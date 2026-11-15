"""Edit an existing local calendar event without replacing it with a new one."""

import json
import os
from pathlib import Path
import sys
import tempfile
from datetime import datetime, timezone


def read_object(path, default=None):
    if not path.exists() and default is not None:
        return default
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise ValueError("Invalid calendar data")
    return data


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".")
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(data, stream, indent=2)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def edit_event(payload, config_dir, cache_dir):
    day = payload["date"]
    title = payload["title"].strip()
    time = payload.get("time", "").strip() or "All day"
    if not title:
        raise ValueError("Event title is required")

    local_path = config_dir / "local_events.json"
    completed_path = config_dir / "calendar_completed.json"
    cache_path = cache_dir / "gcal.json"
    # Parse all existing files before writing: unreadable data must survive.
    local = read_object(local_path)
    completed = read_object(completed_path, {})
    cache = read_object(cache_path, {"configured": False, "events": {}})
    events = local["events"].get(day, [])
    matches = [event for event in events if event.get("id") == payload.get("id") and event.get("id")]
    if not matches:
        # Legacy events may have no persisted ID. Only accept a unique match.
        matches = [event for event in events if not event.get("id")
                   and event.get("title") == payload.get("original_title")
                   and event.get("time", "All day") == payload.get("original_time")]
    if len(matches) != 1:
        raise ValueError("Event changed or could not be identified uniquely")
    event = matches[0]
    old_title = event.get("title", "")
    if old_title != payload.get("original_title") or event.get("time", "All day") != payload.get("original_time"):
        raise ValueError("Event changed while being edited")
    old_id = event.get("id")
    if not old_id:
        import uuid
        event["id"] = "local_" + str(uuid.uuid4())
    event.update(title=title, time=time, all_day=time.lower() in ("all day", "allday"), is_local=True)
    events.sort(key=lambda item: (not item.get("all_day", False), item.get("time", "")))

    # The existing syncer keys completion by day/title. Preserve it on rename.
    old_key, new_key = day + "_" + old_title, day + "_" + title
    if old_key != new_key and old_key in completed:
        completed[new_key] = completed[old_key]
        if not any(item.get("title") == old_title for item in events):
            del completed[old_key]

    # Keep remote rows intact and rebuild only this day's local rows.
    cached = cache.setdefault("events", {}).get(day, [])
    remote = [item for item in cached if not item.get("is_local", False)]
    cache["events"][day] = sorted(remote + events, key=lambda item: (not item.get("all_day", False), item.get("time", "")))
    now = datetime.now(timezone.utc).isoformat()
    local["last_updated"] = now
    cache["last_updated"] = now
    atomic_write(local_path, local)
    atomic_write(completed_path, completed)
    atomic_write(cache_path, cache)


if __name__ == "__main__":
    try:
        edit_event(json.loads(sys.argv[1]), Path.home() / ".config/caelestia", Path.home() / ".cache/caelestia")
    except Exception as error:
        print(f"Calendar edit failed: {error}", file=sys.stderr)
        sys.exit(1)
