#!/usr/bin/env python3
"""Store of facts about the user, kept apart from technical memory.

The file ~/.config/caelestia/user_facts.json is written only by this module.
Every change runs under an exclusive lock, re-reads the file, checks the
revision the caller saw, and replaces the file atomically with mode 0600.
A file that cannot be parsed is never overwritten: writes are refused until
the user runs `recover`, which keeps the damaged copy beside it.

Facts are background data. Nothing here is ever treated as an instruction.
"""

import fcntl
import json
import os
import re
import shutil
import sys
import tempfile
import uuid
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone

SCHEMA_VERSION = 1
CATEGORIES = ("preference", "goal", "skill", "project", "background", "constraint")
# Durable background changes rarely; changing goals carry a review date.
CHANGING_CATEGORIES = ("goal", "project", "constraint")
STATUSES = ("candidate", "approved", "rejected", "archived")
CONFIDENCES = ("high", "medium", "low")
SOURCE_KINDS = ("manual", "import", "chat")
DEFAULT_REVIEW_DAYS = 90
MAX_TEXT = 300
MAX_EVIDENCE = 300
MAX_FACTS = 2000

ALLOWED_TRANSITIONS = {
    "candidate": {"approved", "rejected", "archived"},
    "approved": {"archived", "rejected"},
    "rejected": {"candidate", "approved"},
    "archived": {"approved", "candidate"},
}


class StoreError(Exception):
    def __init__(self, code, message, **extra):
        super().__init__(message)
        self.code = code
        self.message = message
        self.extra = extra

    def as_dict(self):
        out = {"success": False, "error": self.code, "message": self.message}
        out.update(self.extra)
        return out


def config_dir():
    override = os.environ.get("CAELESTIA_CONFIG_DIR", "").strip()
    return override or os.path.expanduser("~/.config/caelestia")


def facts_path():
    return os.path.join(config_dir(), "user_facts.json")


def now_utc():
    return datetime.now(timezone.utc)


def iso(dt):
    return dt.replace(microsecond=0).isoformat()


def parse_time(value):
    if not value or not isinstance(value, str):
        return None
    text = value.strip()
    try:
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", text):
            return datetime.strptime(text, "%Y-%m-%d").replace(tzinfo=timezone.utc)
        dt = datetime.fromisoformat(text.replace("Z", "+00:00"))
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


DEFAULT_SETTINGS = {"include_sensitive_in_replies": False}


def empty_document():
    return {"version": SCHEMA_VERSION, "revision": 0, "settings": dict(DEFAULT_SETTINGS), "facts": []}


def get_settings(doc):
    settings = dict(DEFAULT_SETTINGS)
    raw = doc.get("settings")
    if isinstance(raw, dict):
        for key in DEFAULT_SETTINGS:
            if isinstance(raw.get(key), bool):
                settings[key] = raw[key]
    return settings


def update_settings(doc, changes):
    unknown = set(changes or {}) - set(DEFAULT_SETTINGS)
    if unknown:
        raise StoreError("invalid", f"Unknown settings: {', '.join(sorted(unknown))}.")
    settings = get_settings(doc)
    for key, value in (changes or {}).items():
        if not isinstance(value, bool):
            raise StoreError("invalid", f"{key} must be true or false.")
        settings[key] = value
    doc["settings"] = settings
    return {"settings": settings}


def include_sensitive_setting(path=None):
    doc, state = read_document(path)
    return state != "corrupt" and get_settings(doc)["include_sensitive_in_replies"]


def clean_text(value, limit):
    text = re.sub(r"\s+", " ", str(value or "")).strip()
    # Strip control characters; keep ordinary punctuation and non-Latin letters.
    text = "".join(ch for ch in text if ch == " " or ch.isprintable())
    return text[:limit].strip()


def normalize_key(text):
    words = re.findall(r"[^\W_]+", str(text or "").lower())
    return " ".join(words)


def token_set(text):
    stop = {"the", "a", "an", "and", "or", "to", "of", "in", "on", "for", "with", "is", "are",
            "user", "he", "she", "they", "his", "her", "their", "i", "my", "me", "from", "at", "as", "by"}
    return {w for w in normalize_key(text).split() if w not in stop and len(w) > 1}


def layer_for(category):
    return "changing" if category in CHANGING_CATEGORIES else "durable"


def validate_document(doc):
    if not isinstance(doc, dict) or not isinstance(doc.get("facts"), list):
        raise ValueError("user_facts.json must be an object with a facts list")
    if not isinstance(doc.get("revision", 0), int):
        raise ValueError("revision must be an integer")
    for fact in doc["facts"]:
        if not isinstance(fact, dict) or not fact.get("id") or not isinstance(fact.get("text"), str):
            raise ValueError("every fact needs an id and text")
    return doc


def read_document(path=None):
    """Return (document, state). state is 'missing', 'healthy' or 'corrupt'."""
    path = path or facts_path()
    if not os.path.exists(path):
        return empty_document(), "missing"
    try:
        with open(path, "r", encoding="utf-8") as handle:
            doc = validate_document(json.load(handle))
        doc.setdefault("version", SCHEMA_VERSION)
        doc.setdefault("revision", 0)
        return doc, "healthy"
    except (OSError, ValueError):
        return empty_document(), "corrupt"


def _write_atomic(path, doc):
    directory = os.path.dirname(path)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    fd, temp_path = tempfile.mkstemp(prefix=".user_facts.", dir=directory)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(doc, handle, indent=2, ensure_ascii=False)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_path, path)
        os.chmod(path, 0o600)
    except Exception:
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        raise


@contextmanager
def _locked(path):
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    lock_path = path + ".lock"
    fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def mutate(change, expected_revision=None, path=None):
    """Run change(doc) under the lock and save. change returns a result dict."""
    path = path or facts_path()
    with _locked(path):
        doc, state = read_document(path)
        if state == "corrupt":
            raise StoreError("store_corrupt", "user_facts.json could not be read. Nothing was changed; run recover to keep a copy and start a new file.")
        if expected_revision is not None and int(expected_revision) != int(doc.get("revision", 0)):
            raise StoreError("stale_revision", "The facts changed since this view was loaded. Reload and try again.",
                             revision=doc.get("revision", 0))
        result = change(doc) or {}
        if len(doc["facts"]) > MAX_FACTS:
            raise StoreError("too_many_facts", f"The store holds at most {MAX_FACTS} facts.")
        doc["version"] = SCHEMA_VERSION
        doc["revision"] = int(doc.get("revision", 0)) + 1
        _write_atomic(path, doc)
        result.setdefault("success", True)
        result["revision"] = doc["revision"]
        return result


def recover(path=None):
    path = path or facts_path()
    with _locked(path):
        doc, state = read_document(path)
        if state != "corrupt":
            return {"success": True, "recovered": False, "state": state}
        stamp = now_utc().strftime("%Y%m%dT%H%M%SZ")
        backup = f"{path}.corrupt.{stamp}"
        shutil.copy2(path, backup)
        os.chmod(backup, 0o600)
        _write_atomic(path, empty_document())
        return {"success": True, "recovered": True, "backup_path": backup}


def _find(doc, fact_id):
    for fact in doc["facts"]:
        if fact.get("id") == fact_id:
            return fact
    raise StoreError("not_found", f"No fact with id {fact_id}.")


def _clean_review_after(value, category, created):
    if value in (None, ""):
        if category in CHANGING_CATEGORIES:
            return (created + timedelta(days=DEFAULT_REVIEW_DAYS)).date().isoformat()
        return ""
    parsed = parse_time(value)
    if parsed is None:
        raise StoreError("invalid", "review_after must be a date like 2027-02-01.")
    return parsed.date().isoformat()


def build_fact(data, source_kind="manual", status=None, now=None):
    """Validate user-supplied fields and return a new fact dict."""
    now = now or now_utc()
    text = clean_text(data.get("text"), MAX_TEXT)
    if len(text) < 3:
        raise StoreError("invalid", "A fact needs at least 3 characters of text.")
    category = str(data.get("category") or "background").strip().lower()
    if category not in CATEGORIES:
        raise StoreError("invalid", f"category must be one of: {', '.join(CATEGORIES)}.")
    confidence = str(data.get("confidence") or ("high" if source_kind == "manual" else "low")).strip().lower()
    if confidence not in CONFIDENCES:
        raise StoreError("invalid", "confidence must be high, medium or low.")
    if source_kind not in SOURCE_KINDS:
        raise StoreError("invalid", "unknown source kind")
    if status is None:
        status = "approved" if source_kind == "manual" else "candidate"
    stamp = iso(now)
    fact = {
        "id": "fact_" + uuid.uuid4().hex[:12],
        "text": text,
        "category": category,
        "layer": layer_for(category),
        "status": status,
        "confidence": confidence,
        "source": {
            "kind": source_kind,
            "ai": clean_text(data.get("source_ai"), 40).lower() if source_kind != "manual" else "",
            "date_learned": clean_text(data.get("date_learned"), 10),
            "batch_id": clean_text(data.get("batch_id"), 40),
        },
        "evidence": clean_text(data.get("evidence"), MAX_EVIDENCE),
        "created_at": stamp,
        "updated_at": stamp,
        "last_confirmed": stamp if status == "approved" else "",
        "review_after": _clean_review_after(data.get("review_after"), category, now),
        "supersedes": [],
        "conflicts_with": [],
        "sensitive": bool(data.get("sensitive", False)),
        "pinned": bool(data.get("pinned", False)) and category == "preference",
        "use_in_replies": data.get("use_in_replies", True) is not False,
    }
    return fact


def _apply_approval(doc, fact, now):
    """Approving a fact archives the approved facts it replaces or conflicts with."""
    archived = []
    replaced = set(fact.get("supersedes") or []) | set(fact.get("conflicts_with") or [])
    for other in doc["facts"]:
        if other is fact or other.get("id") not in replaced:
            continue
        if other.get("status") == "approved":
            other["status"] = "archived"
            other["updated_at"] = iso(now)
            archived.append(other["id"])
    fact["supersedes"] = sorted(set(fact.get("supersedes") or []) | set(archived))
    fact["conflicts_with"] = []
    fact["last_confirmed"] = iso(now)
    return archived


def set_status(doc, fact_id, status, now=None):
    now = now or now_utc()
    if status not in STATUSES:
        raise StoreError("invalid", f"status must be one of: {', '.join(STATUSES)}.")
    fact = _find(doc, fact_id)
    current = fact.get("status", "candidate")
    if status == current:
        return {"id": fact_id, "status": status, "archived": []}
    if status not in ALLOWED_TRANSITIONS.get(current, set()):
        raise StoreError("invalid_transition", f"A {current} fact cannot become {status}.")
    fact["status"] = status
    fact["updated_at"] = iso(now)
    archived = _apply_approval(doc, fact, now) if status == "approved" else []
    return {"id": fact_id, "status": status, "archived": archived}


EDITABLE_FIELDS = ("text", "category", "confidence", "review_after", "sensitive", "pinned", "use_in_replies")


def edit_fact(doc, fact_id, changes, now=None):
    now = now or now_utc()
    fact = _find(doc, fact_id)
    unknown = set(changes) - set(EDITABLE_FIELDS)
    if unknown:
        raise StoreError("invalid", f"These fields cannot be edited: {', '.join(sorted(unknown))}.")
    merged = {
        "text": changes.get("text", fact["text"]),
        "category": changes.get("category", fact["category"]),
        "confidence": changes.get("confidence", fact["confidence"]),
        "review_after": changes.get("review_after", fact.get("review_after") or ""),
        "sensitive": changes.get("sensitive", fact.get("sensitive", False)),
        "pinned": changes.get("pinned", fact.get("pinned", False)),
        "use_in_replies": changes.get("use_in_replies", fact.get("use_in_replies", True)),
    }
    probe = build_fact(merged, source_kind="manual", status=fact["status"], now=parse_time(fact.get("created_at")) or now)
    if probe["text"] != fact["text"]:
        fact.setdefault("previous_texts", []).append(fact["text"])
        fact["previous_texts"] = fact["previous_texts"][-5:]
    for key in ("text", "category", "layer", "confidence", "review_after", "sensitive", "pinned", "use_in_replies"):
        fact[key] = probe[key]
    if "review_after" in changes and not changes.get("review_after"):
        fact["review_after"] = ""
    fact["updated_at"] = iso(now)
    if fact["status"] == "approved":
        fact["last_confirmed"] = iso(now)
    return {"id": fact_id, "fact": fact}


def confirm_fact(doc, fact_id, now=None):
    """The user says an approved fact is still true: move its review date on."""
    now = now or now_utc()
    fact = _find(doc, fact_id)
    if fact.get("status") != "approved":
        raise StoreError("invalid_transition", "Only approved facts can be confirmed.")
    fact["last_confirmed"] = iso(now)
    fact["updated_at"] = iso(now)
    if fact.get("category") in CHANGING_CATEGORIES:
        fact["review_after"] = (now + timedelta(days=DEFAULT_REVIEW_DAYS)).date().isoformat()
    return {"id": fact_id, "fact": fact}


def delete_facts(doc, ids=None, source_ai=None, batch_id=None):
    ids = set(ids or [])
    source_ai = (source_ai or "").strip().lower()
    batch_id = (batch_id or "").strip()
    if not ids and not source_ai and not batch_id:
        raise StoreError("invalid", "Say which facts to delete: ids, a source or an import batch.")

    def matches(fact):
        src = fact.get("source") or {}
        if fact.get("id") in ids:
            return True
        if source_ai and src.get("ai") == source_ai:
            return True
        if batch_id and src.get("batch_id") == batch_id:
            return True
        return False

    removed = [f["id"] for f in doc["facts"] if matches(f)]
    doc["facts"] = [f for f in doc["facts"] if not matches(f)]
    gone = set(removed)
    for fact in doc["facts"]:
        fact["conflicts_with"] = [i for i in fact.get("conflicts_with") or [] if i not in gone]
    return {"deleted": removed}


def batch_status(doc, status, ids=None, source_ai=None, only_status=None, now=None):
    ids = list(ids or [])
    source_ai = (source_ai or "").strip().lower()
    if not ids and source_ai:
        ids = [f["id"] for f in doc["facts"]
               if (f.get("source") or {}).get("ai") == source_ai
               and (only_status is None or f.get("status") == only_status)]
    if not ids:
        raise StoreError("invalid", "No facts were selected.")
    changed, skipped = [], []
    for fact_id in ids:
        try:
            res = set_status(doc, fact_id, status, now=now)
            changed.append(res["id"])
        except StoreError as err:
            skipped.append({"id": fact_id, "reason": err.code})
    return {"changed": changed, "skipped": skipped}


def add_fact(doc, data, now=None):
    fact = build_fact(data, source_kind="manual", now=now)
    key = normalize_key(fact["text"])
    for other in doc["facts"]:
        if normalize_key(other.get("text")) == key and other.get("status") in ("approved", "candidate"):
            raise StoreError("duplicate", "That fact is already saved.", id=other["id"])
    doc["facts"].append(fact)
    return {"id": fact["id"], "fact": fact}


def is_stale(fact, now=None):
    now = now or now_utc()
    due = parse_time(fact.get("review_after"))
    return bool(due and due <= now)


def list_facts(path=None, now=None):
    doc, state = read_document(path)
    now = now or now_utc()
    facts = []
    for fact in doc["facts"]:
        item = dict(fact)
        item["stale"] = is_stale(fact, now)
        facts.append(item)
    sources = sorted({(f.get("source") or {}).get("ai") for f in doc["facts"] if (f.get("source") or {}).get("ai")})
    counts = {s: sum(1 for f in doc["facts"] if f.get("status") == s) for s in STATUSES}
    return {"success": state != "corrupt", "state": state, "revision": doc.get("revision", 0),
            "settings": get_settings(doc), "facts": facts, "sources": sources, "counts": counts,
            "stale_count": sum(1 for f in facts if f["stale"] and f.get("status") == "approved")}


def approved_facts(path=None):
    doc, state = read_document(path)
    if state == "corrupt":
        return []
    return [f for f in doc["facts"] if f.get("status") == "approved"]


# ── CLI ────────────────────────────────────────────────────────────────────

def run_command(cmd, payload):
    expected = payload.get("revision")
    if cmd == "list":
        return list_facts()
    if cmd == "recover":
        return recover()
    if cmd == "add":
        return mutate(lambda d: add_fact(d, payload.get("fact") or {}), expected)
    if cmd == "edit":
        return mutate(lambda d: edit_fact(d, payload.get("id"), payload.get("changes") or {}), expected)
    if cmd == "status":
        return mutate(lambda d: set_status(d, payload.get("id"), payload.get("status")), expected)
    if cmd == "confirm":
        return mutate(lambda d: confirm_fact(d, payload.get("id")), expected)
    if cmd == "batch_status":
        return mutate(lambda d: batch_status(d, payload.get("status"), payload.get("ids"),
                                             payload.get("source_ai"), payload.get("only_status")), expected)
    if cmd == "delete":
        return mutate(lambda d: delete_facts(d, payload.get("ids"), payload.get("source_ai"),
                                             payload.get("batch_id")), expected)
    if cmd == "settings":
        return mutate(lambda d: update_settings(d, payload.get("changes") or {}), expected)
    if cmd == "import":
        from facts_import import import_file
        return import_file(payload.get("path", ""), source_ai=payload.get("source_ai", ""),
                           dry_run=payload.get("dry_run", True) is not False)
    raise StoreError("unknown_command", f"Unknown command: {cmd}")


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        print(json.dumps({"success": False, "error": "usage",
                          "message": "usage: user_facts.py <list|add|edit|status|confirm|batch_status|delete|settings|import|recover> [--stdin-json]"}))
        return 2
    cmd = argv[0]
    payload = {}
    if "--stdin-json" in argv[1:]:
        try:
            # One JSON line: the shell keeps stdin open, so never read to EOF.
            payload = json.loads(sys.stdin.readline() or "{}")
        except ValueError:
            payload = {}
    if cmd == "import" and not payload and len(argv) > 1 and argv[1] != "--stdin-json":
        payload = {"path": argv[1], "dry_run": "--apply" not in argv,
                   "source_ai": next((a.split("=", 1)[1] for a in argv if a.startswith("--source=")), "")}
    if not isinstance(payload, dict):
        payload = {}
    try:
        result = run_command(cmd, payload)
    except StoreError as err:
        result = err.as_dict()
    except Exception as err:  # noqa: BLE001 - report, never crash the UI
        result = {"success": False, "error": "internal", "message": str(err)}
    print(json.dumps(result, ensure_ascii=False), flush=True)
    return 0 if result.get("success", False) else 1


if __name__ == "__main__":
    sys.exit(main())
