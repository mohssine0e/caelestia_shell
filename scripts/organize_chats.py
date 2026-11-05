#!/usr/bin/env python3
import json
import os
import sys
import urllib.request
import urllib.error
from datetime import datetime

CHATS_PATH = os.path.expanduser("~/.config/caelestia/chats.json")
BACKUP_PATH = os.path.expanduser("~/.config/caelestia/chats.json.bak_organize")
CONFIG_PATH = os.path.expanduser("~/.config/caelestia/assistant.json")

def load_data():
    if not os.path.exists(CHATS_PATH):
        print(f"Error: {CHATS_PATH} does not exist.")
        sys.exit(1)
    with open(CHATS_PATH, "r", encoding="utf-8") as f:
        chats = json.load(f)

    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        cfg = json.load(f)
        key = cfg.get("gemini_key") or cfg.get("gemini_api_key")

    if not key:
        print("Error: No Gemini API key found in assistant.json.")
        sys.exit(1)

    return chats, key

def backup_data(chats):
    with open(BACKUP_PATH, "w", encoding="utf-8") as f:
        json.dump(chats, f, indent=2, ensure_ascii=False)
    print(f"Backup saved to {BACKUP_PATH} ({len(chats)} chats).")

def organize_with_gemini(chats, key):
    chat_summaries = []
    for c in chats:
        cid = c.get("id")
        created = (c.get("createdAt") or "")[:10]
        title = c.get("title") or ""
        tags = c.get("tags") or []
        msgs = c.get("messages") or []
        first_q = ""
        for m in msgs:
            if m.get("role") == "user":
                first_q = m.get("text", "").replace("\n", " ")[:140]
                break
        chat_summaries.append({
            "id": cid,
            "date": created,
            "title": title,
            "tags": tags,
            "query": first_q
        })

    prompt = (
        "You are an expert AI knowledge organizer for an engineer's technical assistant.\n"
        "Below is a list of historical chat interactions asked by a software and DevOps engineer.\n"
        "Many of these questions were asked about the same overarching project, concept, or learning topic "
        "(e.g., Linux namespaces & cgroups, SSH key configuration & daemons, Docker container setup and debugging, "
        "Python HTTP service, Linux user/permission management, crontab automation, DevStack OVN networking bugfix, "
        "Arabic translations & glossary, bash scripting & background jobs, etc.).\n\n"
        "Your task:\n"
        "Group these items into cohesive, topic-based conversation sessions based on related concepts and temporal relevance.\n"
        "Guidelines:\n"
        "1. Group closely related questions and follow-ups into single coherent chat sessions.\n"
        "2. For each group, provide:\n"
        "   - 'title': A crisp, descriptive, professional title (3 to 6 words) clearly summarizing the topic.\n"
        "   - 'tags': 2 to 4 accurate lowercase tags (e.g. ['docker', 'python', 'devops'], ['linux', 'sysadmin', 'permissions']).\n"
        "   - 'chat_ids': Array of original chat IDs belonging to this group.\n"
        "3. Every single chat ID in the input list must appear in exactly one group. Do not omit any ID.\n"
        "4. If an item is distinct or standalone, keep it in its own group with a polished title and tags.\n"
        "5. Return valid JSON only with the schema:\n"
        "{\n"
        "  \"groups\": [\n"
        "    {\"title\": \"...\", \"tags\": [\"...\"], \"chat_ids\": [\"...\"]}\n"
        "  ]\n"
        "}\n\n"
        f"Input Chats ({len(chat_summaries)} items):\n"
        f"{json.dumps(chat_summaries, ensure_ascii=False)}"
    )

    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={key}"
    body = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "responseMimeType": "application/json"
        }
    }

    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )

    print("Requesting AI concept clustering from Gemini 2.5 Flash...")
    with urllib.request.urlopen(req, timeout=60) as resp:
        result = json.loads(resp.read().decode("utf-8"))

    raw_text = result["candidates"][0]["content"]["parts"][0]["text"].strip()
    return json.loads(raw_text)

def merge_chats(original_chats, clusters):
    chat_by_id = {c["id"]: c for c in original_chats if "id" in c}
    assigned_ids = set()
    new_chats = []

    groups = clusters.get("groups", [])
    print(f"Gemini proposed {len(groups)} cohesive chat groups.")

    for g in groups:
        title = g.get("title", "").strip()
        tags = [t.strip().lower() for t in g.get("tags", []) if t.strip()]
        cids = g.get("chat_ids", [])

        # Filter valid IDs
        valid_items = [chat_by_id[cid] for cid in cids if cid in chat_by_id]
        if not valid_items:
            continue

        for cid in cids:
            assigned_ids.add(cid)

        # Sort items chronologically
        valid_items.sort(key=lambda x: x.get("createdAt", ""))

        # Merge messages
        merged_messages = []
        is_pinned = False
        is_starred = False

        for it in valid_items:
            if it.get("pinned"):
                is_pinned = True
            if it.get("starred"):
                is_starred = True
            msgs = it.get("messages") or []
            merged_messages.extend(msgs)

        if not merged_messages:
            continue

        first_created = valid_items[0].get("createdAt", datetime.utcnow().isoformat())
        last_updated = valid_items[-1].get("updatedAt", valid_items[-1].get("createdAt", datetime.utcnow().isoformat()))
        primary_id = valid_items[-1].get("id") # Keep latest ID so active references work

        new_chats.append({
            "id": primary_id,
            "title": title or valid_items[0].get("title", "Chat"),
            "createdAt": first_created,
            "updatedAt": last_updated,
            "pinned": is_pinned,
            "starred": is_starred,
            "tags": tags or valid_items[0].get("tags", []),
            "messages": merged_messages
        })

    # Catch any missed chat IDs (safety guarantee)
    unassigned = [c for c in original_chats if c.get("id") not in assigned_ids]
    if unassigned:
        print(f"Preserving {len(unassigned)} unassigned chats to ensure zero data loss.")
        new_chats.extend(unassigned)

    # Sort final list by updatedAt descending (newest conversations first)
    new_chats.sort(key=lambda x: x.get("updatedAt", x.get("createdAt", "")), reverse=True)
    return new_chats

def main():
    chats, key = load_data()
    backup_data(chats)
    clusters = organize_with_gemini(chats, key)
    merged = merge_chats(chats, clusters)

    with open(CHATS_PATH, "w", encoding="utf-8") as f:
        json.dump(merged, f, indent=2, ensure_ascii=False)

    print(f"Successfully organized {len(chats)} raw items into {len(merged)} cohesive topic chats!")

if __name__ == "__main__":
    main()

