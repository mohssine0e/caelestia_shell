#!/usr/bin/env python3
import json
import os
import re
from datetime import datetime, timezone

history_path = os.path.expanduser("~/.config/caelestia/assistant_history.json")
chats_path = os.path.expanduser("~/.config/caelestia/chats.json")

def migrate():
    if not os.path.exists(history_path):
        print("No assistant_history.json found.")
        return

    with open(history_path, "r", encoding="utf-8") as f:
        try:
            history = json.load(f)
        except Exception as e:
            print("Failed to parse assistant_history.json:", e)
            return

    if not isinstance(history, list) or len(history) == 0:
        print("No history items to migrate.")
        return

    def to_iso(ts):
        if not ts:
            return ""
        if isinstance(ts, (int, float)):
            try:
                # Handle milliseconds or seconds
                sec = ts / 1000.0 if ts > 1e11 else ts
                return datetime.fromtimestamp(sec, timezone.utc).isoformat()
            except Exception:
                return str(ts)
        return str(ts)

    # Sort chronological
    history.sort(key=lambda x: to_iso(x.get("timestamp", "")))

    threads = {}
    standalone_count = 0

    for item in history:
        tid = item.get("thread_id")
        if not tid:
            tid = f"chat_{item.get('id', standalone_count)}"
            standalone_count += 1

        if tid not in threads:
            threads[tid] = []
        threads[tid].append(item)

    chats = []
    for tid, items in threads.items():
        first = items[0]
        last = items[-1]

        raw_prompt = (first.get("prompt") or first.get("original") or first.get("text") or "Chat").strip()
        # Clean title
        clean_title = re.sub(r"[\n\r`#*]+", " ", raw_prompt).strip()
        clean_title = re.sub(r"\s+", " ", clean_title)
        if len(clean_title) > 45:
            clean_title = clean_title[:42] + "..."
        if not clean_title:
            clean_title = first.get("action", "Chat").capitalize()

        all_tags = set()
        for it in items:
            for t in it.get("tags", []):
                if t:
                    all_tags.add(t.strip().lower())

        is_starred = any(bool(it.get("starred")) for it in items)

        msgs = []
        for it in items:
            u_text = (it.get("prompt") or it.get("original") or it.get("text") or "").strip()
            a_text = (it.get("answer") or "").strip()
            ts = it.get("timestamp", "")
            time_str = ""
            if ts:
                try:
                    iso = to_iso(ts)
                    dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
                    time_str = dt.strftime("%H:%M")
                except Exception:
                    time_str = ""

            if u_text:
                msgs.append({
                    "id": "u_" + str(it.get("id", len(msgs))),
                    "role": "user",
                    "action": it.get("action", "ask"),
                    "text": u_text,
                    "timestamp": time_str
                })
            if a_text:
                msgs.append({
                    "id": "a_" + str(it.get("id", len(msgs))),
                    "role": "assistant",
                    "action": it.get("action", "ask"),
                    "text": a_text,
                    "timestamp": time_str
                })

        chats.append({
            "id": tid if tid.startswith("t_") or tid.startswith("chat_") else f"chat_{tid}",
            "title": clean_title,
            "createdAt": to_iso(first.get("timestamp", "")),
            "updatedAt": to_iso(last.get("timestamp", "")),
            "pinned": is_starred,
            "starred": is_starred,
            "tags": sorted(list(all_tags)),
            "messages": msgs
        })

    # Sort chats by updatedAt descending
    chats.sort(key=lambda c: to_iso(c.get("updatedAt", "")), reverse=True)

    with open(chats_path, "w", encoding="utf-8") as f:
        json.dump(chats, f, indent=2, ensure_ascii=False)

    print(f"Successfully migrated {len(history)} items into {len(chats)} chats at {chats_path}")

if __name__ == "__main__":
    migrate()
