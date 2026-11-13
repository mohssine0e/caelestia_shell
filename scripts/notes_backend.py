#!/usr/bin/env python3
"""Private storage and optional AI organization for Caelestia Quick Notes."""

from __future__ import annotations

import json
import os
import re
import sqlite3
import sys
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 2
TAG_PATTERN = re.compile(r"(?<![\w#])#([\w-]+)", re.UNICODE)
ORGANIZER_PROMPT = (
    "You are a technical note formatter. Format the supplied raw developer note as "
    "concise Markdown. Preserve its meaning and every useful command or fact. Group "
    "related material under short headings. Put CLI commands in fenced code blocks. "
    "Do not invent missing details, explanations, tags, or commands. Output only the "
    "formatted Markdown."
)
TRIAGE_PROMPT = """
You organize a private quick-note inbox. Return one strict JSON object and no
other text:
{
  "keep": true,
  "category": "technical|reference|personal|idea|noise",
  "essential_bullets": ["..."],
  "completion_bullets": ["..."]
}

Rules:
- Personal observations, feelings, preferences, plans, and ideas belong in
  personal or idea. Preserve them verbatim: return empty bullet arrays.
- Technical or reference notes may become at most six short, factual essential
  bullets. Preserve commands exactly and use Markdown backticks where useful.
- If a technical note is incomplete, add at most three completion bullets only
  when the missing fact is well established and directly implied. Never invent
  project-specific details, personal facts, credentials, paths, or intent.
- Use noise and keep=false only for clearly accidental, meaningless input.
  Short but meaningful thoughts must be kept.
- Do not add introductions, headings, filler, advice, or repeated information.
""".strip()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def database_path() -> Path:
    override = os.environ.get("CAELESTIA_NOTES_DB", "").strip()
    if override:
        return Path(override).expanduser()
    data_home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
    return data_home / "caelestia" / "notes" / "notes.sqlite3"


def _secure_path(path: Path) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    if path.exists():
        os.chmod(path, 0o600)


def connect() -> sqlite3.Connection:
    path = database_path()
    _secure_path(path)
    db = sqlite3.connect(path, timeout=5)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA foreign_keys=ON")
    db.execute("PRAGMA busy_timeout=5000")
    db.executescript(
        """
        CREATE TABLE IF NOT EXISTS notes (
            id TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            raw_content TEXT NOT NULL,
            formatted_content TEXT,
            tags_json TEXT NOT NULL DEFAULT '[]',
            status TEXT NOT NULL DEFAULT 'inbox'
                CHECK(status IN ('inbox', 'formatting', 'formatted', 'format_failed')),
            format_error TEXT,
            format_attempts INTEGER NOT NULL DEFAULT 0,
            format_token TEXT,
            provider TEXT,
            deleted_at TEXT,
            schema_version INTEGER NOT NULL DEFAULT 1
        );
        CREATE INDEX IF NOT EXISTS notes_status_updated
            ON notes(status, updated_at DESC);
        CREATE INDEX IF NOT EXISTS notes_deleted_updated
            ON notes(deleted_at, updated_at DESC);
        """
    )
    columns = {row[1] for row in db.execute("PRAGMA table_info(notes)")}
    migrations = {
        "category": "ALTER TABLE notes ADD COLUMN category TEXT NOT NULL DEFAULT 'unclassified'",
        "keep_decision": "ALTER TABLE notes ADD COLUMN keep_decision TEXT NOT NULL DEFAULT 'pending'",
        "triage_error": "ALTER TABLE notes ADD COLUMN triage_error TEXT",
        "triage_attempts": "ALTER TABLE notes ADD COLUMN triage_attempts INTEGER NOT NULL DEFAULT 0",
        "triage_token": "ALTER TABLE notes ADD COLUMN triage_token TEXT",
    }
    for column, statement in migrations.items():
        if column not in columns:
            db.execute(statement)
    db.execute("CREATE INDEX IF NOT EXISTS notes_category_updated ON notes(category, updated_at DESC)")
    db.execute("CREATE INDEX IF NOT EXISTS notes_keep_updated ON notes(keep_decision, updated_at DESC)")
    db.execute(f"PRAGMA user_version={SCHEMA_VERSION}")
    db.commit()
    _secure_path(path)
    for suffix in ("-wal", "-shm"):
        sidecar = Path(str(path) + suffix)
        if sidecar.exists():
            os.chmod(sidecar, 0o600)
    return db


@contextmanager
def database():
    db = connect()
    try:
        with db:
            yield db
    finally:
        db.close()


def extract_tags(text: str) -> list[str]:
    seen: set[str] = set()
    tags: list[str] = []
    for match in TAG_PATTERN.finditer(text):
        tag = "#" + match.group(1).lower()
        if tag not in seen:
            seen.add(tag)
            tags.append(tag)
    return tags


def _normalise_tags(value: Any, raw_content: str = "") -> list[str]:
    source = value if isinstance(value, list) else extract_tags(raw_content)
    tags: list[str] = []
    seen: set[str] = set()
    for item in source:
        tag = str(item).strip().lower()
        if not tag:
            continue
        if not tag.startswith("#"):
            tag = "#" + tag
        if not re.fullmatch(r"#[\w-]+", tag, re.UNICODE) or tag in seen:
            continue
        seen.add(tag)
        tags.append(tag)
    return tags[:24]


def _row_to_note(row: sqlite3.Row) -> dict[str, Any]:
    note = dict(row)
    try:
        note["tags"] = json.loads(note.pop("tags_json"))
    except (TypeError, ValueError):
        note["tags"] = []
        note.pop("tags_json", None)
    note["formatted_content"] = note.get("formatted_content") or ""
    note["format_error"] = note.get("format_error") or ""
    note["triage_error"] = note.get("triage_error") or ""
    note["category"] = note.get("category") or "unclassified"
    note["keep_decision"] = note.get("keep_decision") or "pending"
    note["provider"] = note.get("provider") or ""
    note["deleted"] = bool(note.get("deleted_at"))
    note.pop("format_token", None)
    note.pop("triage_token", None)
    return note


def create_note(payload: dict[str, Any]) -> dict[str, Any]:
    raw = str(payload.get("raw_content", "")).strip()
    if not raw:
        raise ValueError("The note is empty.")
    if len(raw) > 200_000:
        raise ValueError("The note is too large (maximum 200,000 characters).")
    note_id = str(uuid.uuid4())
    now = utc_now()
    tags = _normalise_tags(payload.get("tags"), raw)
    with database() as db:
        db.execute(
            """INSERT INTO notes
               (id, created_at, updated_at, raw_content, tags_json, status,
                category, keep_decision, schema_version)
               VALUES (?, ?, ?, ?, ?, 'inbox', 'unclassified', 'pending', ?)""",
            (note_id, now, now, raw, json.dumps(tags, ensure_ascii=False), SCHEMA_VERSION),
        )
        row = db.execute("SELECT * FROM notes WHERE id = ?", (note_id,)).fetchone()
    return {"success": True, "note": _row_to_note(row)}


def list_notes(payload: dict[str, Any]) -> dict[str, Any]:
    query = str(payload.get("query", "")).strip().lower()
    status = str(payload.get("status", "")).strip()
    include_deleted = payload.get("include_deleted") is True
    clauses = ["1=1" if include_deleted else "deleted_at IS NULL"]
    params: list[Any] = []
    if status:
        allowed = {"inbox", "formatting", "formatted", "format_failed"}
        if status not in allowed:
            raise ValueError("Unknown note status.")
        clauses.append("status = ?")
        params.append(status)
    if query:
        clauses.append(
            "(lower(raw_content) LIKE ? OR lower(COALESCE(formatted_content, '')) LIKE ? "
            "OR lower(tags_json) LIKE ?)"
        )
        needle = f"%{query}%"
        params.extend((needle, needle, needle))
    limit = max(1, min(int(payload.get("limit", 500)), 1000))
    sql = f"SELECT * FROM notes WHERE {' AND '.join(clauses)} ORDER BY updated_at DESC LIMIT ?"
    params.append(limit)
    with database() as db:
        rows = db.execute(sql, params).fetchall()
    return {"success": True, "notes": [_row_to_note(row) for row in rows]}


def get_note(payload: dict[str, Any]) -> dict[str, Any]:
    note_id = str(payload.get("id", "")).strip()
    with database() as db:
        row = db.execute("SELECT * FROM notes WHERE id = ?", (note_id,)).fetchone()
    if row is None:
        raise ValueError("Note not found.")
    return {"success": True, "note": _row_to_note(row)}


def update_note(payload: dict[str, Any]) -> dict[str, Any]:
    note_id = str(payload.get("id", "")).strip()
    with database() as db:
        row = db.execute("SELECT * FROM notes WHERE id = ? AND deleted_at IS NULL", (note_id,)).fetchone()
        if row is None:
            raise ValueError("Note not found.")
        raw = str(payload.get("raw_content", row["raw_content"])).strip()
        if not raw:
            raise ValueError("The note is empty.")
        existing_tags = json.loads(row["tags_json"] or "[]")
        tags = _normalise_tags(payload.get("tags", existing_tags), raw)
        now = utc_now()
        raw_changed = raw != row["raw_content"]
        db.execute(
            """UPDATE notes SET raw_content = ?, tags_json = ?, updated_at = ?,
               status = CASE WHEN ? THEN 'inbox' ELSE status END,
               formatted_content = CASE WHEN ? THEN NULL ELSE formatted_content END,
               format_error = CASE WHEN ? THEN NULL ELSE format_error END,
               format_token = CASE WHEN ? THEN NULL ELSE format_token END,
               triage_token = CASE WHEN ? THEN NULL ELSE triage_token END,
               triage_error = CASE WHEN ? THEN NULL ELSE triage_error END,
               category = CASE WHEN ? THEN 'unclassified' ELSE category END,
               keep_decision = CASE WHEN ? THEN 'pending' ELSE keep_decision END,
               provider = CASE WHEN ? THEN NULL ELSE provider END,
               schema_version = ?
               WHERE id = ?""",
            (raw, json.dumps(tags, ensure_ascii=False), now,
             raw_changed, raw_changed, raw_changed, raw_changed,
             raw_changed, raw_changed, raw_changed, raw_changed, raw_changed,
             SCHEMA_VERSION, note_id),
        )
        updated = db.execute("SELECT * FROM notes WHERE id = ?", (note_id,)).fetchone()
    return {"success": True, "note": _row_to_note(updated)}


def delete_note(payload: dict[str, Any]) -> dict[str, Any]:
    note_id = str(payload.get("id", "")).strip()
    now = utc_now()
    with database() as db:
        cursor = db.execute(
            "UPDATE notes SET deleted_at = ?, updated_at = ?, format_token = NULL WHERE id = ? AND deleted_at IS NULL",
            (now, now, note_id),
        )
    if cursor.rowcount != 1:
        raise ValueError("Note not found.")
    return {"success": True, "id": note_id}


def restore_note(payload: dict[str, Any]) -> dict[str, Any]:
    note_id = str(payload.get("id", "")).strip()
    now = utc_now()
    with database() as db:
        cursor = db.execute(
            "UPDATE notes SET deleted_at = NULL, updated_at = ? WHERE id = ? AND deleted_at IS NOT NULL",
            (now, note_id),
        )
    if cursor.rowcount != 1:
        raise ValueError("Deleted note not found.")
    return get_note({"id": note_id})


def provider_status(_: dict[str, Any]) -> dict[str, Any]:
    from assistant_common import load_config

    config = load_config()
    primary = str(config.get("primary", "gemini")).lower()
    available = []
    if str(config.get("gemini_key", "")).strip():
        available.append("gemini")
    if str(config.get("groq_key", "")).strip():
        available.append("groq")
    selected = primary if primary in available else (available[0] if available else "")
    ordered = ([selected] if selected else []) + [name for name in available if name != selected]
    return {
        "success": True,
        "configured": bool(ordered),
        "provider": selected,
        "fallback": ordered[1] if len(ordered) > 1 else "",
        "providers": ordered,
    }


def _run_provider(system_prompt: str, raw: str) -> tuple[str, str]:
    import assistant_api
    from assistant_common import load_config

    config = load_config()
    primary = str(config.get("primary", "gemini")).lower()
    gemini_key = str(config.get("gemini_key", "")).strip()
    groq_key = str(config.get("groq_key", "")).strip()
    providers: list[tuple[str, str]] = []
    if primary == "groq":
        if groq_key:
            providers.append(("groq", groq_key))
        if gemini_key:
            providers.append(("gemini", gemini_key))
    else:
        if gemini_key:
            providers.append(("gemini", gemini_key))
        if groq_key:
            providers.append(("groq", groq_key))
    if not providers:
        raise RuntimeError("Configure a Gemini or Groq API key before formatting notes.")

    chunks: list[str] = []
    original_emit = assistant_api.emit
    assistant_api.emit = lambda item: chunks.append(str(item.get("text", ""))) if item.get("type") == "chunk" else None
    last_error: Exception | None = None
    try:
        for provider, key in providers:
            chunks.clear()
            try:
                if provider == "gemini":
                    assistant_api.stream_gemini(key, system_prompt, raw)
                else:
                    assistant_api.stream_groq(key, system_prompt, raw)
                result = "".join(chunks).strip()
                if not result:
                    raise RuntimeError("The AI provider returned an empty note.")
                if result.startswith("```markdown") and result.endswith("```"):
                    result = result[len("```markdown"): -3].strip()
                return result, provider
            except Exception as exc:  # provider fallback is intentional
                last_error = exc
        raise RuntimeError(f"Formatting failed: {last_error}")
    finally:
        assistant_api.emit = original_emit


def _format_with_provider(raw: str) -> tuple[str, str]:
    return _run_provider(ORGANIZER_PROMPT, raw)


def _clean_bullets(value: Any, limit: int) -> list[str]:
    if not isinstance(value, list):
        return []
    bullets: list[str] = []
    for item in value:
        text = re.sub(r"^\s*[-*•]\s*", "", str(item)).strip()
        if text and text not in bullets:
            bullets.append(text[:500])
        if len(bullets) >= limit:
            break
    return bullets


def _parse_triage_response(text: str) -> dict[str, Any]:
    cleaned = text.strip()
    fence = re.fullmatch(r"```(?:json)?\s*(.*?)\s*```", cleaned, re.DOTALL | re.IGNORECASE)
    if fence:
        cleaned = fence.group(1)
    try:
        result = json.loads(cleaned)
    except (TypeError, ValueError) as exc:
        raise RuntimeError("The AI returned invalid note classification data.") from exc
    if not isinstance(result, dict):
        raise RuntimeError("The AI returned invalid note classification data.")
    category = str(result.get("category", "")).strip().lower()
    allowed = {"technical", "reference", "personal", "idea", "noise"}
    if category not in allowed:
        raise RuntimeError("The AI returned an unknown note category.")
    keep = result.get("keep") is not False and category != "noise"
    essentials = _clean_bullets(result.get("essential_bullets"), 6)
    completions = _clean_bullets(result.get("completion_bullets"), 3)
    if category in {"personal", "idea", "noise"}:
        essentials = []
        completions = []
    return {
        "keep": keep,
        "category": category,
        "essential_bullets": essentials,
        "completion_bullets": completions,
    }


def triage_note(payload: dict[str, Any]) -> dict[str, Any]:
    note_id = str(payload.get("id", "")).strip()
    token = str(uuid.uuid4())
    with database() as db:
        row = db.execute("SELECT * FROM notes WHERE id = ? AND deleted_at IS NULL", (note_id,)).fetchone()
        if row is None:
            raise ValueError("Note not found.")
        db.execute(
            """UPDATE notes SET status = 'formatting', triage_error = NULL,
               triage_attempts = triage_attempts + 1, triage_token = ?, updated_at = ?
               WHERE id = ?""",
            (token, utc_now(), note_id),
        )
        raw = row["raw_content"]

    try:
        response, provider = _run_provider(TRIAGE_PROMPT, raw)
        triage = _parse_triage_response(response)
    except Exception as exc:
        message = str(exc).strip() or "Note analysis failed."
        with database() as db:
            cursor = db.execute(
                """UPDATE notes SET status = 'format_failed', triage_error = ?,
                   triage_token = NULL, updated_at = ? WHERE id = ? AND triage_token = ?""",
                (message[:500], utc_now(), note_id, token),
            )
        if cursor.rowcount != 1:
            return {"success": False, "stale": True, "id": note_id}
        return {"success": False, "id": note_id, "error": message[:500]}

    essentials = triage["essential_bullets"]
    completions = triage["completion_bullets"]
    markdown_parts = ["\n".join(f"- {item}" for item in essentials)] if essentials else []
    if completions:
        markdown_parts.append("**AI-added context**\n" + "\n".join(f"- {item}" for item in completions))
    formatted = "\n\n".join(markdown_parts)
    decision = "keep" if triage["keep"] else "skip"
    with database() as db:
        cursor = db.execute(
            """UPDATE notes SET formatted_content = ?, status = 'formatted',
               category = ?, keep_decision = ?, triage_error = NULL,
               triage_token = NULL, provider = ?, updated_at = ?, schema_version = ?
               WHERE id = ? AND triage_token = ? AND deleted_at IS NULL""",
            (formatted or None, triage["category"], decision, provider, utc_now(),
             SCHEMA_VERSION, note_id, token),
        )
    if cursor.rowcount != 1:
        return {"success": False, "stale": True, "id": note_id}
    return get_note({"id": note_id})


def organize_note(payload: dict[str, Any]) -> dict[str, Any]:
    note_id = str(payload.get("id", "")).strip()
    token = str(uuid.uuid4())
    now = utc_now()
    with database() as db:
        row = db.execute("SELECT * FROM notes WHERE id = ? AND deleted_at IS NULL", (note_id,)).fetchone()
        if row is None:
            raise ValueError("Note not found.")
        db.execute(
            """UPDATE notes SET status = 'formatting', format_error = NULL,
               format_attempts = format_attempts + 1, format_token = ?, updated_at = ?
               WHERE id = ?""",
            (token, now, note_id),
        )
        raw = row["raw_content"]

    try:
        formatted, provider = _format_with_provider(raw)
    except Exception as exc:
        message = str(exc).strip() or "Formatting failed."
        with database() as db:
            cursor = db.execute(
                """UPDATE notes SET status = 'format_failed', format_error = ?,
                   format_token = NULL, updated_at = ? WHERE id = ? AND format_token = ?""",
                (message[:500], utc_now(), note_id, token),
            )
        if cursor.rowcount != 1:
            return {"success": False, "stale": True, "id": note_id}
        return {"success": False, "id": note_id, "error": message[:500]}

    with database() as db:
        cursor = db.execute(
            """UPDATE notes SET formatted_content = ?, status = 'formatted',
               format_error = NULL, format_token = NULL, provider = ?, updated_at = ?
               WHERE id = ? AND format_token = ? AND deleted_at IS NULL""",
            (formatted, provider, utc_now(), note_id, token),
        )
    if cursor.rowcount != 1:
        return {"success": False, "stale": True, "id": note_id}
    result = get_note({"id": note_id})
    result["provider"] = provider
    return result


COMMANDS = {
    "create": create_note,
    "list": list_notes,
    "get": get_note,
    "update": update_note,
    "delete": delete_note,
    "restore": restore_note,
    "organize": organize_note,
    "triage": triage_note,
    "retry": organize_note,
    "provider-status": provider_status,
}


def read_payload() -> dict[str, Any]:
    try:
        value = json.loads(sys.stdin.readline() or "{}")
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(json.dumps({"success": False, "error": "Unknown notes command."}), flush=True)
        return 2
    try:
        result = COMMANDS[sys.argv[1]](read_payload())
    except (ValueError, OSError, sqlite3.Error) as exc:
        result = {"success": False, "error": str(exc)}
    except Exception as exc:  # keep the QML protocol valid without leaking note content
        result = {"success": False, "error": str(exc) or "Unexpected notes backend error."}
    print(json.dumps(result, ensure_ascii=False), flush=True)
    return 0 if result.get("success") else 1


if __name__ == "__main__":
    raise SystemExit(main())
