#!/usr/bin/env python3
"""Apply local calendar edits and refresh the dashboard cache."""

import json
import os
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path


CONFIG = Path.home() / ".config/caelestia/local_events.json"
CACHE = Path.home() / ".cache/caelestia/gcal.json"


def read_json(path: Path, default: dict) -> dict:
    if not path.exists():
        return default
    data = json.loads(path.read_text())
    if not isinstance(data, dict) or not isinstance(data.get("events", {}), dict):
        raise ValueError(f"Invalid calendar data in {path}")
    return data


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    try:
        temp.write_text(json.dumps(data, ensure_ascii=False, indent=2))
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def event_time(value: str) -> str:
    text = value.strip()
    if not text or text.casefold() == "all day":
        return "All day"
    import re
    if not re.fullmatch(r"(?:[01]?\d|2[0-3]):[0-5]\d", text):
        raise ValueError("Enter a time like 14:00, or select All day.")
    return text.zfill(5)


def mutate(action: str, payload: dict) -> dict:
    from datetime import date

    day = str(payload.get("date", ""))
    try:
        date.fromisoformat(day)
    except ValueError as exc:
        raise ValueError("Choose a valid date.") from exc

    local_data = read_json(CONFIG, {"events": {}})
    cache_data = read_json(CACHE, {"configured": False, "events": {}})
    local = local_data["events"]
    cached = cache_data["events"]
    local_day = list(local.get(day, []))
    cache_day = list(cached.get(day, []))
    event_id = str(payload.get("id", ""))

    if action in {"update", "delete"}:
        original = next((item for item in local_day if item.get("id") == event_id), None)
        if not original:
            raise ValueError("This local event no longer exists. Refresh the calendar.")
        local_day = [item for item in local_day if item.get("id") != event_id]
        cache_day = [item for item in cache_day if not (item.get("is_local") and item.get("id") == event_id)]
    elif action != "add":
        raise ValueError("Unknown calendar action.")

    if action in {"add", "update"}:
        title = str(payload.get("title", "")).strip()
        if not title or len(title) > 300:
            raise ValueError("Enter an event title under 300 characters.")
        time = event_time(str(payload.get("time", "")))
        item = {
            "id": event_id if action == "update" else f"local_{uuid.uuid4().hex}",
            "title": title,
            "time": time,
            "all_day": time == "All day",
            "location": original.get("location", "") if action == "update" else "",
            "is_local": True,
        }
        local_day.append(item)
        cache_day.append(item)
    else:
        item = original

    if local_day:
        local[day] = local_day
    else:
        local.pop(day, None)
    if cache_day:
        cached[day] = cache_day
    else:
        cached.pop(day, None)

    now = datetime.now(timezone.utc).isoformat()
    local_data["last_updated"] = now
    cache_data["last_updated"] = now
    write_json(CONFIG, local_data)
    write_json(CACHE, cache_data)
    return {"success": True, "action": action, "event": item}


if __name__ == "__main__":
    try:
        print(json.dumps(mutate(sys.argv[1], json.loads(sys.argv[2]))))
    except (IndexError, ValueError, OSError, json.JSONDecodeError) as exc:
        print(json.dumps({"success": False, "error": str(exc)}))
        sys.exit(1)
