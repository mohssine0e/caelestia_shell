#!/usr/bin/env python3
"""Import facts that another AI wrote about the user, as candidates only.

Input is JSON Lines, one object per line:
  {"text": "...", "category": "preference", "confidence": "high",
   "evidence": "...", "date_learned": "2026-11", "source_ai": "chatgpt"}

Every accepted line becomes a *candidate*: nothing is used in a reply until
the user approves it. Approved facts are never overwritten. Lines that read
like instructions to a model, or that hold secrets or contact details, are
rejected and reported. These filters lower the risk; they do not make the
assistant immune to prompt injection, which is why approval stays required.
"""

import json
import os
import re
import uuid

import user_facts as store

MAX_FILE_BYTES = 256 * 1024
MAX_LINES = 500

CATEGORY_ALIASES = {
    "preferences": "preference", "likes": "preference", "style": "preference",
    "goals": "goal", "objective": "goal", "aim": "goal",
    "skills": "skill", "knowledge": "skill", "expertise": "skill",
    "projects": "project", "work": "project",
    "bio": "background", "identity": "background", "education": "background", "history": "background",
    "constraints": "constraint", "limit": "constraint", "limits": "constraint", "availability": "constraint",
}

# Text that tries to steer a model rather than describe the user.
INSTRUCTION_PATTERNS = [
    r"\bignore\b.{0,40}\b(instructions?|rules|above|previous|prior|system)\b",
    r"\bdisregard\b", r"\bforget (all|everything|your|previous)\b",
    r"\b(system|developer) (prompt|message|instructions?)\b",
    r"\byou (must|should|are|will|shall)\b", r"\bact as\b", r"\bpretend\b",
    r"\b(always|never) (respond|reply|answer|say|output|mention|use|call|run|execute|send)\b",
    r"\b(assistant|model|ai|llm)\b.{0,20}\b(must|should|has to|needs to|is required)\b",
    r"\b(run|execute|call|invoke)\b.{0,30}\b(command|tool|function|script|shell)\b",
    r"\b(send|email|upload|post)\b.{0,30}\b(to|at)\b.{0,30}(https?://|@)",
    r"</?\s*(system|instructions?|assistant|user)\s*>", r"^\s*(instructions?|rules?|note to (the )?(ai|assistant))\s*:",
    r"\bnew instructions?\b", r"\boverride\b", r"\bjailbreak\b",
]

SECRET_PATTERNS = [
    r"AIza[0-9A-Za-z_\-]{20,}", r"\bgsk_[0-9A-Za-z]{16,}", r"\bsk-[0-9A-Za-z_\-]{16,}",
    r"\bgh[pousr]_[0-9A-Za-z]{20,}", r"\bxox[abp]-[0-9A-Za-z\-]{10,}",
    r"\b(password|passwd|passcode|pin code|api[ _-]?key|secret key|token)\b\s*[:=]",
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
]

CONTACT_PATTERNS = [
    r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}",
    r"\b(iban|card number|passport|national id|cin)\b",
]

# Topics that are personal enough to stay out of replies unless the user opts in.
SENSITIVE_PATTERNS = [
    r"\b(health|illness|diagnos\w*|medication|therapy|depress\w*|anxiety|sleep\w*|insomnia|mental)\b",
    r"\b(romantic|relationship|girlfriend|boyfriend|crush|dating|love life|sex\w*)\b",
    r"\b(religio\w*|faith|politic\w*|ethnic\w*)\b",
    r"\b(salary|debt|income|bank)\b", r"\b(home address|lives at|street)\b",
    r"\b(feels?|feeling|sad|lonely|guilt\w*)\b",
]


def _matches(patterns, text):
    return any(re.search(p, text, flags=re.IGNORECASE | re.MULTILINE) for p in patterns)


def looks_like_instruction(text):
    return _matches(INSTRUCTION_PATTERNS, text)


def looks_secret(text):
    return _matches(SECRET_PATTERNS, text)


PHONE_CANDIDATE = re.compile(r"\+?\d[\d \-.()]{6,}\d")
DATE_LIKE = re.compile(r"^\d{4}-\d{2}(-\d{2})?$")


def has_contact_detail(text):
    if _matches(CONTACT_PATTERNS, text):
        return True
    for match in PHONE_CANDIDATE.finditer(text or ""):
        chunk = match.group(0).strip()
        if DATE_LIKE.match(chunk):
            continue
        if sum(ch.isdigit() for ch in chunk) >= 9:
            return True
    return False


def looks_sensitive(text):
    return _matches(SENSITIVE_PATTERNS, text)


def _clean_date(value):
    text = str(value or "").strip()
    if re.fullmatch(r"\d{4}(-\d{2}){0,2}", text):
        return text
    return ""


def validate_line(raw, default_source=""):
    """Return (clean dict, None) or (None, reason)."""
    if not isinstance(raw, dict):
        return None, "not_an_object"
    text_raw = raw.get("text")
    if not isinstance(text_raw, str):
        return None, "missing_text"
    for field in ("text", "evidence"):
        value = str(raw.get(field) or "")
        if looks_secret(value):
            return None, "secret_or_credential"
        if has_contact_detail(value):
            return None, "contact_detail"
        if looks_like_instruction(value):
            return None, "instruction_like"
    text = store.clean_text(text_raw, store.MAX_TEXT + 1)
    if len(text) < 3:
        return None, "text_too_short"
    if len(text) > store.MAX_TEXT:
        return None, "text_too_long"
    category = str(raw.get("category") or "").strip().lower()
    category = CATEGORY_ALIASES.get(category, category)
    if category not in store.CATEGORIES:
        return None, "unknown_category"
    confidence = str(raw.get("confidence") or "low").strip().lower()
    if confidence not in store.CONFIDENCES:
        confidence = "low"
    source_ai = re.sub(r"[^a-z0-9 _\-]", "", str(raw.get("source_ai") or default_source or "unknown").lower()).strip()[:40]
    return {
        "text": text,
        "category": category,
        "confidence": confidence,
        "evidence": store.clean_text(raw.get("evidence"), store.MAX_EVIDENCE),
        "date_learned": _clean_date(raw.get("date_learned")),
        "source_ai": source_ai or "unknown",
        "sensitive": bool(raw.get("sensitive")) or looks_sensitive(text),
        "review_after": raw.get("review_after") if store.parse_time(raw.get("review_after")) else "",
    }, None


def _similar(a, b):
    ta, tb = store.token_set(a), store.token_set(b)
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


def plan_import(doc, lines, default_source="", now=None):
    """Work out what an import would do without changing doc."""
    report = {"accepted": [], "duplicates": [], "conflicts": [], "rejected": []}
    seen = {store.normalize_key(f.get("text")): f for f in doc["facts"]}
    batch_keys = set()
    for number, line in enumerate(lines, start=1):
        stripped = line.strip()
        if not stripped:
            continue
        try:
            raw = json.loads(stripped)
        except ValueError:
            report["rejected"].append({"line": number, "reason": "invalid_json"})
            continue
        clean, reason = validate_line(raw, default_source)
        if reason:
            report["rejected"].append({"line": number, "reason": reason})
            continue
        key = store.normalize_key(clean["text"])
        if key in batch_keys:
            report["duplicates"].append({"line": number, "text": clean["text"], "existing_id": "", "existing_status": "same_file"})
            continue
        if key in seen:
            existing = seen[key]
            report["duplicates"].append({"line": number, "text": clean["text"],
                                         "existing_id": existing.get("id"), "existing_status": existing.get("status")})
            continue
        batch_keys.add(key)
        conflicts = [f["id"] for f in doc["facts"]
                     if f.get("status") == "approved" and f.get("category") == clean["category"]
                     and _similar(f.get("text"), clean["text"]) >= 0.5]
        entry = {"line": number, "fact": clean, "conflicts_with": conflicts}
        report["accepted"].append(entry)
        if conflicts:
            report["conflicts"].append({"line": number, "text": clean["text"], "conflicts_with": conflicts})
    return report


def read_lines(path):
    if not path:
        raise store.StoreError("invalid", "Give the path of a .jsonl file to import.")
    path = os.path.expanduser(path)
    if not os.path.isfile(path):
        raise store.StoreError("not_found", f"No file at {path}.")
    if os.path.getsize(path) > MAX_FILE_BYTES:
        raise store.StoreError("too_large", f"Import files are limited to {MAX_FILE_BYTES // 1024} KB.")
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        lines = handle.read().splitlines()
    if len([l for l in lines if l.strip()]) > MAX_LINES:
        raise store.StoreError("too_large", f"Import files are limited to {MAX_LINES} facts.")
    return lines


def _summary(report, dry_run, batch_id=""):
    return {
        "success": True,
        "dry_run": dry_run,
        "batch_id": batch_id,
        "accepted": len(report["accepted"]),
        "duplicates": report["duplicates"],
        "conflicts": report["conflicts"],
        "rejected": report["rejected"],
        "preview": [{"line": e["line"], "text": e["fact"]["text"], "category": e["fact"]["category"],
                     "sensitive": e["fact"]["sensitive"], "conflicts_with": e["conflicts_with"]}
                    for e in report["accepted"]],
    }


def import_lines(lines, source_ai="", dry_run=True, path=None, now=None):
    if dry_run:
        doc, state = store.read_document(path)
        if state == "corrupt":
            raise store.StoreError("store_corrupt", "user_facts.json could not be read; run recover first.")
        return _summary(plan_import(doc, lines, source_ai, now), True)

    batch_id = "import_" + uuid.uuid4().hex[:10]
    holder = {}

    def change(doc):
        report = plan_import(doc, lines, source_ai, now)
        for entry in report["accepted"]:
            data = dict(entry["fact"])
            data["batch_id"] = batch_id
            fact = store.build_fact(data, source_kind="import", status="candidate", now=now)
            fact["conflicts_with"] = entry["conflicts_with"]
            doc["facts"].append(fact)
        holder["report"] = report
        return {}

    result = store.mutate(change, path=path)
    out = _summary(holder["report"], False, batch_id)
    out["revision"] = result["revision"]
    return out


def import_file(file_path, source_ai="", dry_run=True, path=None, now=None):
    return import_lines(read_lines(file_path), source_ai=source_ai, dry_run=dry_run, path=path, now=now)
