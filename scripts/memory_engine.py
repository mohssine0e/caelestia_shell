#!/usr/bin/env python3
"""
scripts/memory_engine.py
Caelestia HUD Assistant - Memory, Knowledge Mastery & Trial Engine.
Strictly decoupled: Pure Python 3 standard library.
"""

import sys
import os
import json
import ast
import re
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone

# ---------------------------------------------------------
# Path Constants
# ---------------------------------------------------------
CONFIG_PATH = os.path.expanduser("~/.config/caelestia/assistant.json")
HISTORY_PATH = os.path.expanduser("~/.config/caelestia/assistant_history.json")
MEMORY_PATH = os.path.expanduser("~/.config/caelestia/assistant_memory.json")
PROFILE_PATH = os.path.expanduser("~/.config/caelestia/assistant_profile.json")

GEMINI_CANDIDATE_MODELS = [
    "gemini-flash-lite-latest",
    "gemini-3.5-flash-lite",
    "gemini-3.1-flash-lite",
    "gemini-flash-latest"
]

GROQ_CANDIDATE_MODELS = [
    "openai/gpt-oss-120b",
    "qwen/qwen3.8-27b"
]

STOP_WORDS = {
    "a", "about", "above", "after", "again", "against", "all", "am", "an", "and", "any", "are", "aren't",
    "as", "at", "be", "because", "been", "before", "being", "below", "between", "both", "but", "by",
    "can", "can't", "cannot", "could", "couldn't", "did", "didn't", "do", "does", "doesn't", "doing",
    "don't", "down", "during", "each", "few", "for", "from", "further", "had", "hadn't", "has", "hasn't",
    "have", "haven't", "having", "he", "he'd", "he'll", "he's", "her", "here", "here's", "hers",
    "herself", "him", "himself", "his", "how", "how's", "i", "i'd", "i'll", "i'm", "i've", "if", "in",
    "into", "is", "isn't", "it", "it's", "its", "itself", "let's", "me", "more", "most", "mustn't",
    "my", "myself", "no", "nor", "not", "of", "off", "on", "once", "only", "or", "other", "ought",
    "our", "ours", "ourselves", "out", "over", "own", "same", "shan't", "she", "she'd", "she'll",
    "she's", "should", "shouldn't", "so", "some", "such", "than", "that", "that's", "the", "their",
    "theirs", "them", "themselves", "then", "there", "there's", "these", "they", "they'd", "they'll",
    "they're", "they've", "this", "those", "through", "to", "too", "under", "until", "up", "very",
    "was", "wasn't", "we", "we'd", "we'll", "we're", "we've", "were", "weren't", "what", "what's",
    "when", "when's", "where", "where's", "which", "while", "who", "who's", "whom", "why", "why's",
    "with", "won't", "would", "wouldn't", "you", "you'd", "you'll", "you're", "you've", "your",
    "yours", "yourself", "yourselves"
}

CODE_TOKEN_PATTERN = re.compile(
    r'(?:'
    r'[a-zA-Z0-9_]+(?:\.[a-zA-Z0-9_]+)+'
    r'|[a-zA-Z0-9]+_[a-zA-Z0-9_]+'
    r'|[a-z]+[A-Z][a-zA-Z0-9]*'
    r'|[A-Z][a-z]+[A-Z][a-zA-Z0-9]*'
    r'|--[a-zA-Z0-9_-]+'
    r'|[A-Z]{2,}(?:_[A-Z0-9]+)*'
    r')'
)

WORD_PATTERN = re.compile(r'[a-zA-Z0-9_]+')
JSON_CLEAN_PATTERN = re.compile(r'```(?:json)?\s*(.*?)\s*```', re.DOTALL)
DEMOTION_THRESHOLD_SECONDS = 30 * 86400  # 30-day mastery decay

# ---------------------------------------------------------
# Utilities & I/O
# ---------------------------------------------------------
def emit(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()

def load_config():
    cfg = {"gemini_key": "", "groq_key": "", "primary": "gemini"}
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, dict):
                    cfg.update(data)
                    if "gemini_api_key" in data and not cfg.get("gemini_key"):
                        cfg["gemini_key"] = data["gemini_api_key"]
                    if "groq_api_key" in data and not cfg.get("groq_key"):
                        cfg["groq_key"] = data["groq_api_key"]
                    if "preferred_provider" in data and not cfg.get("primary"):
                        cfg["primary"] = data["preferred_provider"]
        except Exception:
            pass
    if not cfg.get("gemini_key"):
        cfg["gemini_key"] = os.environ.get("GEMINI_API_KEY", "")
    if not cfg.get("groq_key"):
        cfg["groq_key"] = os.environ.get("GROQ_API_KEY", "")
    return cfg

def load_memory(auto_demote=True):
    if not os.path.exists(MEMORY_PATH):
        return []
    try:
        with open(MEMORY_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, list):
                now_epoch = time.time()
                mutated = False
                # Normalize schema fields & evaluate 30-day decay
                for card in data:
                    if not isinstance(card, dict):
                        continue
                    if "status" not in card:
                        card["status"] = "learning"
                    if "archived_lines" not in card:
                        card["archived_lines"] = []
                    if "trials" not in card:
                        card["trials"] = []
                    if "last_fail_feedback" not in card:
                        card["last_fail_feedback"] = ""
                    if "mastery_score" not in card:
                        card["mastery_score"] = 1.0 if card.get("status") == "mastered" else 0.0
                    if "last_reviewed" not in card:
                        card["last_reviewed"] = card.get("updated") or card.get("created") or ""
                    if "personal_traps" not in card or not isinstance(card["personal_traps"], list):
                        card["personal_traps"] = []
                    if "relations" not in card or not isinstance(card["relations"], list):
                        card["relations"] = []

                    # Spaced Repetition: 30-day decay demotion check
                    if auto_demote and card.get("status") == "mastered":
                        lr_str = card.get("last_reviewed") or card.get("updated") or card.get("created") or ""
                        if lr_str:
                            try:
                                lr_dt = datetime.fromisoformat(lr_str.replace("Z", "+00:00"))
                                if (now_epoch - lr_dt.timestamp()) > DEMOTION_THRESHOLD_SECONDS:
                                    card["status"] = "learning"
                                    card["mastery_score"] = 0.65
                                    card["last_fail_feedback"] = "Decay: Unreviewed for over 30 days. Re-test to reaffirm mastery."
                                    mutated = True
                            except Exception:
                                pass

                if mutated and auto_demote:
                    atomic_save_memory(data)

                return data
    except Exception:
        pass
    return []

def atomic_save_memory(cards):
    os.makedirs(os.path.dirname(MEMORY_PATH), exist_ok=True)
    tmp_path = MEMORY_PATH + ".tmp"
    bak_path = MEMORY_PATH + ".bak"

    try:
        # Create backup if original exists
        if os.path.exists(MEMORY_PATH):
            try:
                with open(MEMORY_PATH, "r", encoding="utf-8") as src, open(bak_path, "w", encoding="utf-8") as dst:
                    dst.write(src.read())
            except Exception:
                pass

        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(cards, f, indent=2, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())

        os.replace(tmp_path, MEMORY_PATH)
        try:
            os.chmod(MEMORY_PATH, 0o600)
        except Exception:
            pass
        return True
    except Exception as e:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except Exception:
                pass
        raise e

def clean_json_response(raw_text):
    text = (raw_text or "").strip()
    if text.startswith("```"):
        first_newline = text.find("\n")
        if first_newline != -1:
            text = text[first_newline+1:]
        else:
            text = text[3:]
    if text.endswith("```"):
        text = text[:-3].rstrip()

    first_brace = text.find("{")
    last_brace = text.rfind("}")
    if first_brace != -1 and last_brace != -1 and last_brace >= first_brace:
        text = text[first_brace:last_brace+1].strip()

    if not text:
        raise ValueError("Received empty or malformed JSON from model.")
    return text

def parse_json_safely(raw_text):
    text = clean_json_response(raw_text)
    try:
        return json.loads(text, strict=False)
    except Exception as e1:
        # Fallback 1: Python dicts with single quotes
        try:
            val = ast.literal_eval(text)
            if isinstance(val, dict):
                return val
        except Exception:
            pass

        # Fallback 2: Remove trailing commas before closing braces/brackets
        try:
            cleaned = re.sub(r',\s*([\]}])', r'\1', text)
            return json.loads(cleaned, strict=False)
        except Exception:
            pass

        # Fallback 3: Convert unescaped single quotes
        try:
            cleaned = re.sub(r"(?<!\\)'", '"', text)
            return json.loads(cleaned, strict=False)
        except Exception:
            pass

        raise e1

# ---------------------------------------------------------
# AI Calling Helper (Groq / Gemini Hybrid)
# Fast Groq prioritized to save Gemini quota, with rock-solid fallback
# ---------------------------------------------------------
def call_llm(system_instruction, user_payload, expect_json=True, temperature=0.2):
    config = load_config()
    gemini_key = config.get("gemini_key", "").strip()
    groq_key = config.get("groq_key", "").strip()

    # Prioritize Groq for background memory operations to avoid exhausting Gemini quota
    providers = []
    if groq_key:
        providers.append(("groq", groq_key))
    if gemini_key:
        providers.append(("gemini", gemini_key))

    if not providers:
        raise RuntimeError("No API key available. Configure GEMINI_API_KEY or GROQ_API_KEY.")

    last_error = None
    for prov_name, key in providers:
        try:
            if prov_name == "groq":
                for model_name in GROQ_CANDIDATE_MODELS:
                    url = "https://api.groq.com/openai/v1/chat/completions"
                    messages = [
                        {"role": "system", "content": system_instruction},
                        {"role": "user", "content": user_payload}
                    ]
                    req_dict = {
                        "model": model_name,
                        "messages": messages,
                        "temperature": temperature
                    }
                    if expect_json:
                        req_dict["response_format"] = {"type": "json_object"}
                    
                    req_data = json.dumps(req_dict).encode("utf-8")
                    req = urllib.request.Request(url, data=req_data, headers={
                        "Content-Type": "application/json",
                        "Authorization": f"Bearer {key}",
                        "User-Agent": "Mozilla/5.0"
                    }, method="POST")
                    try:
                        with urllib.request.urlopen(req, timeout=25) as resp:
                            data = json.loads(resp.read().decode("utf-8"))
                            choices = data.get("choices", [])
                            if choices:
                                content = (choices[0].get("message", {}).get("content") or "").strip()
                                if content:
                                    return content
                    except Exception as e:
                        last_error = e
                        continue
            elif prov_name == "gemini":
                for model_name in GEMINI_CANDIDATE_MODELS:
                    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:generateContent?key={key}"
                    gen_config = {"temperature": temperature}
                    if expect_json:
                        gen_config["responseMimeType"] = "application/json"
                    
                    req_data = json.dumps({
                        "contents": [{
                            "parts": [{"text": f"SYSTEM INSTRUCTIONS:\n{system_instruction}\n\nUSER DATA / QUERY:\n{user_payload}"}]
                        }],
                        "generationConfig": gen_config
                    }).encode("utf-8")

                    req = urllib.request.Request(url, data=req_data, headers={"Content-Type": "application/json"}, method="POST")
                    try:
                        with urllib.request.urlopen(req, timeout=30) as resp:
                            data = json.loads(resp.read().decode("utf-8"))
                            candidates = data.get("candidates", [])
                            if candidates:
                                parts = candidates[0].get("content", {}).get("parts", [])
                                if parts:
                                    content = (parts[0].get("text") or "").strip()
                                    if content:
                                        return content
                    except Exception as e:
                        last_error = e
                        continue
        except Exception as e:
            last_error = e
            continue

    raise RuntimeError(f"All AI providers failed: {last_error}")

# ---------------------------------------------------------
# Keyword & Token Utilities
# ---------------------------------------------------------
def extract_keywords(text):
    if not text:
        return set()
    words = WORD_PATTERN.findall(text.lower())
    return {w for w in words if len(w) >= 3 and w not in STOP_WORDS}

def extract_code_tokens(text):
    if not text:
        return set()
    matches = CODE_TOKEN_PATTERN.findall(text)
    return {m for m in matches if len(m) >= 3}

# ---------------------------------------------------------
# CLI Command: get_context <query>
# Zero-token local matching against assistant_memory.json
# ---------------------------------------------------------
def get_context(query_text):
    cards = load_memory()
    if not cards or not query_text or len(query_text.strip()) < 3:
        emit({"matched": False, "cards": [], "card_ids": [], "prompt_injection": ""})
        return

    q_clean = query_text.strip()
    q_code = extract_code_tokens(q_clean)
    q_words = extract_keywords(q_clean)

    scored = []
    for card in cards:
        topic = (card.get("topic") or "").strip()
        tags = card.get("tags") or []
        lines = card.get("lines") or []

        topic_words = extract_keywords(topic)
        tag_words = extract_keywords(" ".join(tags))
        lines_words = extract_keywords(" ".join(lines[:4]))
        all_card_words = topic_words.union(tag_words).union(lines_words)

        card_code = extract_code_tokens(f"{topic} {' '.join(lines[:3])}")
        shared_code = q_code.intersection(card_code)
        shared_topic = q_words.intersection(topic_words)
        shared_tags = q_words.intersection(tag_words)
        shared_all = q_words.intersection(all_card_words)
        query_coverage = len(shared_all) / len(q_words) if q_words else 0.0

        score = 0.0
        if len(shared_code) >= 2:
            score += 1.5 + (len(shared_code) * 0.4)
        elif len(shared_code) == 1:
            score += 0.8

        score += len(shared_topic) * 0.7
        score += len(shared_tags) * 0.4
        score += query_coverage * 0.9

        if score >= 0.5:
            scored.append((score, card))

    scored.sort(key=lambda x: x[0], reverse=True)
    matched_cards = [c for _, c in scored[:2]]

    if not matched_cards:
        emit({"matched": False, "cards": [], "card_ids": [], "prompt_injection": ""})
        return

    injection_parts = []
    for c in matched_cards:
        status = c.get("status", "learning").upper()
        topic = c.get("topic", "")
        summary = c.get("lines", [""])[0] if c.get("lines") else ""

        is_code = True
        primer = c.get("primer") or {}
        if primer.get("domain") in ("protocol", "conceptual"):
            is_code = False
        elif c.get("category") in ("general", "health", "lifestyle", "productivity", "translation") and not extract_code_tokens(f"{topic} {summary}"):
            is_code = False

        if status == "MASTERED":
            if is_code:
                injection_parts.append(
                    f"[Mastery Grounding: User has MASTERED '{topic}'. Root principle: '{summary}'. Skip introductory basics; provide concise, advanced code.]"
                )
            else:
                injection_parts.append(
                    f"[Mastery Grounding: User has MASTERED '{topic}'. Root principle: '{summary}'. Skip introductory basics; provide clear, actionable principles and protocols (avoid forcing dummy code snippets).]"
                )
        else:
            if is_code:
                injection_parts.append(
                    f"[Learning Grounding: User is LEARNING '{topic}'. Active concept: '{summary}'. Provide an intuitive breakdown with clear steps and code.]"
                )
            else:
                injection_parts.append(
                    f"[Learning Grounding: User is LEARNING '{topic}'. Active concept: '{summary}'. Provide an intuitive breakdown with clear actionable guidelines.]"
                )

    emit({
        "matched": True,
        "cards": [
            {
                "id": c.get("id"),
                "topic": c.get("topic"),
                "status": c.get("status"),
                "summary": c.get("lines", [""])[0] if c.get("lines") else ""
            } for c in matched_cards
        ],
        "card_ids": [str(c.get("id")) for c in matched_cards if c.get("id")],
        "prompt_injection": " ".join(injection_parts)
    })

# ---------------------------------------------------------
# CLI Command: distill
# Thread-aware, noise-filtered memory card distillation
# ---------------------------------------------------------
DISTILL_PROMPT = """You are the Knowledge Distillation Engine for an advanced developer's Linux HUD Assistant.
Your task is to analyze new interactions from the user's history and curate high-value, deep Knowledge Cards.

KNOWLEDGE HIERARCHY & CONSOLIDATION RULES:
1. DUAL-LAYER ARCHITECTURE:
   - DOMAIN CODE HUBS (type: "code_hub"): Concrete programming language idioms, framework patterns, and code recipes. IMPORTANT: Keep core language patterns and major enterprise frameworks separate (e.g., 'card_java_core_hub' for core Java concurrency/virtual threads/records, and 'card_spring_boot_hub' for Spring Boot JPA/DTO/SSE). Use 'sections' to group related topics.
   - ARCHITECTURAL CONCEPTS (type: "concept"): High-level system design, distributed architectures, and development paradigms (e.g., MVP, PaaS overhead, OCI containers, TCP/IP fundamentals) must remain distinct conceptual cards.
2. CONSOLIDATE, DO NOT FRAGMENT: If incoming interactions discuss code or idioms for an ecosystem that already has a Domain Code Hub in 'current_memory', APPEND or UPDATE the relevant section in that card instead of generating a new isolated card.
3. CONCISE CODE SNIPPETS: Provide short, focused, practical code snippets (under 8-10 lines max). Do NOT provide giant boilerplate classes or package/import scaffolding. Focus cleanly on the core idiom/pattern.
4. IGNORE NOISE: Skip greetings, simple translations, pure arithmetic, short tests, and transient banter.
5. LINE LINEAGE: Each bullet in 'lines' or 'sections' must trace directly to a source interaction ID in 'sources'.
6. GENERAL & CONCISE CARD TITLES (5-7 WORDS MAX): When naming or updating card topics, the title MUST be a clean, broad, general concept (e.g., 'Java Core & Concurrency Hub', 'Spring Boot Engineering Hub', 'Docker Architecture & Linux Kernel Primitives') and strictly 5 to 7 words maximum. Never use hyper-specific multi-clause sentences for card titles.
7. EXTRACT ESSENTIAL GENERAL RULES (NOT SITUATIONAL EXAMPLES): Formulate knowledge as universal technical invariants, patterns, and rules, NOT as task-specific project walk-throughs or history anecdotes. Do NOT mention specific temporary repo names, local file paths, or ephemeral exercise narratives. Extract the enduring, transferable learning point.

OUTPUT FORMAT:
Return a JSON object with a single key 'cards', containing an array of card objects:
{
  "cards": [
    {
      "id": "card_<category>_<slug>",
      "topic": "Clear Descriptive Topic",
      "category": "java|python|linux|architecture|networking|general",
      "type": "code_hub|concept",
      "status": "learning",
      "lines": [
        "Concise high-yield rule or insight 1",
        "Concise high-yield rule or insight 2"
      ],
      "sections": [
        {
          "id": "subtopic_slug",
          "title": "Subtopic Title",
          "rules": ["Actionable rule 1", "Actionable rule 2"],
          "snippet": "```lang\\n// Production code snippet\\n...\\n```",
          "pitfalls": ["Common pitfall or anti-pattern"]
        }
      ],
      "tags": ["relevant", "tags"],
      "sources": ["history_id_1", "history_id_2"]
    }
  ]
}
"""

def distill():
    if not os.path.exists(HISTORY_PATH):
        emit({"success": True, "new_cards": 0, "updated_cards": 0, "total_cards": 0, "message": "No history file found."})
        return

    try:
        with open(HISTORY_PATH, "r", encoding="utf-8") as f:
            raw_history = json.load(f)
            if not isinstance(raw_history, list):
                raw_history = []
    except Exception:
        raw_history = []

    current_memory = load_memory()
    indexed_sources = set()
    for card in current_memory:
        for s in card.get("sources", []):
            if s:
                indexed_sources.add(str(s))

    # Filter unindexed, non-noise entries
    unindexed = []
    for item in raw_history:
        if not isinstance(item, dict):
            continue
        iid = str(item.get("id", ""))
        if not iid or iid in indexed_sources or item.get("context_excluded"):
            continue

        prompt = (item.get("prompt") or "").strip()
        text = (item.get("text") or "").strip()
        ans = (item.get("answer") or "").strip()
        
        # Skip pure noise / greetings / trivial checks
        if len(text) < 12 and len(prompt) < 12 and not extract_code_tokens(text + " " + prompt):
            continue
        if item.get("action") == "translate" and len(text) < 30 and not extract_code_tokens(text):
            continue

        unindexed.append({
            "id": iid,
            "prompt": prompt[:300],
            "text": text[:500],
            "answer": ans[:600],
            "action": item.get("action", "ask"),
            "timestamp": item.get("timestamp", 0)
        })

    if not unindexed:
        emit({
            "success": True,
            "new_cards": 0,
            "updated_cards": 0,
            "total_cards": len(current_memory),
            "message": "All history is already indexed."
        })
        return

    # Take up to 40 most recent unindexed entries to prevent token exhaustion
    batch = unindexed[-40:]

    payload = {
        "current_memory": [
            {
                "id": c.get("id"),
                "topic": c.get("topic"),
                "category": c.get("category"),
                "lines": c.get("lines"),
                "tags": c.get("tags"),
                "sources": c.get("sources", [])
            } for c in current_memory
        ],
        "new_interactions": batch
    }

    try:
        raw_resp = call_llm(DISTILL_PROMPT, json.dumps(payload, ensure_ascii=False), expect_json=True)
        resp_data = parse_json_safely(raw_resp)
        new_cards = resp_data.get("cards", [])
        if not isinstance(new_cards, list):
            new_cards = []
    except Exception as e:
        emit({"success": False, "error": f"Distillation AI call failed: {e}"})
        return

    now_iso = datetime.now(timezone.utc).isoformat()
    existing_map = {c.get("id"): c for c in current_memory}

    created_count = 0
    updated_count = 0

    for nc in new_cards:
        cid = nc.get("id") or f"card_{int(time.time()*1000)}"
        if cid in existing_map:
            # Update existing card
            card = existing_map[cid]
            if nc.get("type"):
                card["type"] = nc.get("type")
            if nc.get("sections"):
                existing_sections = card.get("sections") or []
                sec_map = {s.get("id"): s for s in existing_sections if s.get("id")}
                for s in nc.get("sections"):
                    sid = s.get("id")
                    if sid and sid in sec_map:
                        sec_map[sid].update(s)
                    else:
                        existing_sections.append(s)
                card["sections"] = existing_sections
            card["lines"] = nc.get("lines", card.get("lines", []))
            card["updated"] = now_iso
            card["tags"] = list(set((card.get("tags") or []) + (nc.get("tags") or [])))
            card["sources"] = list(set((card.get("sources") or []) + (nc.get("sources") or [])))
            card["_ts"] = int(time.time() * 1000)
            updated_count += 1
        else:
            # Create new card
            card = {
                "id": cid,
                "topic": nc.get("topic", "Untitled Concept"),
                "category": nc.get("category", "general"),
                "type": nc.get("type", "concept"),
                "status": "learning",
                "mastery_score": 0.0,
                "lines": nc.get("lines", []),
                "sections": nc.get("sections", []),
                "archived_lines": [],
                "tags": nc.get("tags", []),
                "sources": nc.get("sources", []),
                "last_fail_feedback": "",
                "trials": [],
                "created": now_iso,
                "updated": now_iso,
                "last_reviewed": now_iso,
                "_ts": int(time.time() * 1000)
            }
            existing_map[cid] = card
            created_count += 1

    final_cards = list(existing_map.values())
    atomic_save_memory(final_cards)

    emit({
        "success": True,
        "new_cards": created_count,
        "updated_cards": updated_count,
        "total_cards": len(final_cards)
    })

# ---------------------------------------------------------
# CLI Command: challenge <card_id>
# Adaptive mastery assessment suite scaled to domain & complexity
# ---------------------------------------------------------
CHALLENGE_PROMPT = """You are a senior technical examiner and developer mentor.
Generate an adaptive mastery assessment suite tailored specifically to the card's domain and complexity.

ADAPTIVE ASSESSMENT RULES:
1. COMPLEXITY & QUESTION COUNT:
   - "small" complexity: Return EXACTLY 1 to 2 questions (e.g. 1 focused QCM + 1 quick scenario check). Do NOT overwhelm small concepts with unnecessary questions.
   - "medium" complexity: Return EXACTLY 2 to 3 questions (e.g. 1 QCM + 1 bug hunt/scenario check + 1 edge case).
   - "deep" complexity: Return 3 to 4 questions (e.g. 1 QCM + 1-2 diagnosis/bug hunts + 1 edge case / trade-off).

2. DOMAIN-SPECIFIC QUESTION TYPES:
   - For "code" domain:
     - 'qcm': Multiple choice on syntax invariants, lifecycle, or timing. 4 options (A, B, C, D) with one unambiguous answer.
     - 'bug_hunt': Markdown code snippet or shell pipeline containing a subtle bug, race condition, or memory leak. Ask where the bug is and how to fix it.
     - 'edge_case': Architectural or boundary failure scenario under extreme conditions.
   - For "protocol" / non-code domain:
     - 'qcm': Multiple choice on core principles, trade-offs, or physiological/operational mechanisms.
     - 'bug_hunt' (or scenario diagnosis): A realistic real-world protocol execution scenario where someone applied the concept incorrectly or under suboptimal conditions. Ask to identify what went wrong and how to correct the protocol. DO NOT USE FAKE CODE SNIPPETS.
     - 'edge_case': What fails under extreme conditions (e.g. severe sleep deficit, high stress, boundary constraints) and why.

3. TARGETED WEAKNESS & PERSONAL TRAP FOCUS:
   - If 'personal_traps' contains items, AT LEAST ONE question (e.g. q1 or a diagnosis scenario) MUST specifically target and test whether the user has overcome their documented personal traps: {personal_traps}. Probe them deliberately on their past mistakes!
   - If 'last_fail_feedback' is present and non-empty, directly probe and diagnose the exact pitfall or misconception described to verify that the user has corrected their understanding.

FORMAT REQUIREMENT:
Return valid JSON with:
{
  "card_id": "<card_id>",
  "topic": "<topic>",
  "domain": "code" | "protocol",
  "complexity": "small" | "medium" | "deep",
  "questions": [
    {
      "id": "q1",
      "type": "qcm",
      "title": "Conceptual Check",
      "question": "Clear multiple choice question...",
      "options": [
        "A) First option",
        "B) Second option",
        "C) Third option",
        "D) Fourth option"
      ],
      "correct_option": "B",
      "explanation": "Why B is correct"
    }
  ]
}
"""

def challenge(card_id, is_daily=False):
    cards = load_memory()
    card = next((c for c in cards if c.get("id") == card_id), None)
    if not card:
        emit({"success": False, "error": f"Card '{card_id}' not found."})
        return

    primer = card.get("primer") or {}
    domain = primer.get("domain") or ("code" if extract_code_tokens(card.get("topic", "") + " " + " ".join(card.get("lines", []))) else "protocol")
    complexity = primer.get("complexity") or ("small" if len(card.get("lines", [])) <= 1 else "medium")

    payload = {
        "card_id": card.get("id"),
        "topic": card.get("topic"),
        "category": card.get("category"),
        "domain": domain,
        "complexity": complexity,
        "lines": card.get("lines"),
        "archived_lines": card.get("archived_lines", []),
        "last_fail_feedback": card.get("last_fail_feedback", ""),
        "personal_traps": card.get("personal_traps", []),
        "primer": primer
    }

    try:
        raw_resp = call_llm(CHALLENGE_PROMPT, json.dumps(payload, ensure_ascii=False), expect_json=True)
        resp_data = parse_json_safely(raw_resp)
        resp_data["card_id"] = card_id
        resp_data["success"] = True
        if is_daily:
            resp_data["is_daily_gauntlet"] = True

        questions = resp_data.get("questions", [])
        if not questions:
            raise ValueError("No questions returned by examiner.")

        # Store the active trial criteria in the card for subsequent grading
        card["active_trial"] = {
            "timestamp": int(time.time()),
            "domain": resp_data.get("domain", domain),
            "complexity": resp_data.get("complexity", complexity),
            "questions": questions
        }
        atomic_save_memory(cards)

        emit(resp_data)
    except Exception as e:
        emit({"success": False, "error": f"Challenge generation failed: {e}"})

# ---------------------------------------------------------
# CLI Command: grade <card_id> "<answer>"
# Multi-question grading with voice tolerance & line compression
# ---------------------------------------------------------
MULTI_GRADE_PROMPT = """You are a rigorous, fair technical code & conceptual examiner.
Grade the user's answers across all questions presented in the trial gauntlet.

VOICE-TO-TEXT TRANSCRIPTION TOLERANCE:
The user may have spoken their answers using Whisper dictation (Super+Alt+V).
Forgive minor phonetic transcription artifacts (e.g. 'pipe wire' instead of 'pipewire', 'dash capital S' instead of '-S', 'equals equals' instead of '==').
Focus strictly on whether their causal understanding, logic, and technical insight are correct.

GRADING CRITERIA:
- Evaluate each question fairly against its criteria.
- In 'q_results', provide an entry for every question present in 'questions' (e.g. q1, q2, ...).
- Calculate an overall score from 0.0 to 1.0 (Mastery graduation requires score >= 0.85).
- ALWAYS provide the canonical, authoritative 'correct_solution' for every question so the user can study what the exact model answer or code fix was, especially if they were wrong!
- If passed with score >= 0.85, provide a crisp 1-sentence 'compressed_summary' capturing the master-level lesson.
- ADAPTIVE PERSONAL TRAP EXTRACTION:
  If the user made any errors, had blindspots, or scored < 0.85, formulate EXACTLY ONE crisp, actionable 'personal_trap' sentence diagnosing the exact mistake or misconception they made (e.g. 'Assumed Promise callbacks run before the current synchronous block', or 'Confused sleep latency with caffeine absorption timing'). If user answered flawlessly, set 'personal_trap' to "".

OUTPUT JSON:
{
  "verdict": "pass" | "fail",
  "score": 0.0 to 1.0,
  "q_results": {
    "q1": {
      "verdict": "pass" | "fail",
      "comment": "Specific feedback on user's answer",
      "correct_solution": "The exact correct answer or option (e.g., 'Option B: ... because ...')"
    }
  },
  "strengths": "Summary of what they understood well",
  "blindspots": "Summary of what was missing, imprecise, or misunderstood",
  "personal_trap": "Concise 1-sentence personal trap or caveat that tripped them up, or empty string if perfect",
  "explanation": "Master-level clarification of the core concepts",
  "compressed_summary": "1-sentence distillation of the rule (only if pass)"
}
"""

def grade(card_id, user_answer_raw):
    cards = load_memory()
    card = next((c for c in cards if c.get("id") == card_id), None)
    if not card:
        emit({"success": False, "error": f"Card '{card_id}' not found."})
        return

    active_trial = card.get("active_trial") or {}
    questions = active_trial.get("questions") or []

    # Parse user answers (may be JSON string of {"q1": "...", "q2": "..."} or raw text)
    user_answers = {}
    try:
        parsed = json.loads(user_answer_raw)
        if isinstance(parsed, dict):
            user_answers = parsed
        else:
            user_answers = {"q1": str(user_answer_raw)}
    except Exception:
        user_answers = {"q1": str(user_answer_raw)}

    payload = {
        "topic": card.get("topic"),
        "core_rules": card.get("lines"),
        "questions": questions,
        "user_answers": user_answers
    }

    try:
        raw_resp = call_llm(MULTI_GRADE_PROMPT, json.dumps(payload, ensure_ascii=False), expect_json=True)
        resp_data = parse_json_safely(raw_resp)

        verdict = resp_data.get("verdict", "fail").lower()
        score = float(resp_data.get("score", 0.0))
        now_iso = datetime.now(timezone.utc).isoformat()

        trial_record = {
            "timestamp": int(time.time()),
            "questions_count": len(questions),
            "user_answers": user_answers,
            "verdict": verdict,
            "score": score,
            "q_results": resp_data.get("q_results", {}),
            "feedback": resp_data.get("blindspots") or resp_data.get("explanation", ""),
            "personal_trap": resp_data.get("personal_trap", "")
        }

        if "trials" not in card:
            card["trials"] = []
        card["trials"].append(trial_record)
        card["last_reviewed"] = now_iso
        card["updated"] = now_iso

        # Adaptive Weakness Tracking: Auto-append personal trap if score < 0.85 or verdict != pass
        trap = (resp_data.get("personal_trap") or "").strip()
        if trap and trap.lower() not in ["none", "n/a", "no trap", "empty", "\"\"", "''"]:
            if "personal_traps" not in card or not isinstance(card["personal_traps"], list):
                card["personal_traps"] = []
            if not any(trap.lower() == existing.lower() for existing in card["personal_traps"]):
                card["personal_traps"].insert(0, trap)
                card["personal_traps"] = card["personal_traps"][:5]

        # Enforce score >= 0.85 for true mastery graduation
        if verdict == "pass" and score >= 0.85:
            card["status"] = "mastered"
            card["mastery_score"] = score
            card["last_fail_feedback"] = ""
            # Compress lines on mastery
            compressed = resp_data.get("compressed_summary", "").strip()
            if compressed:
                card["archived_lines"] = list(card.get("lines") or [])
                card["lines"] = [f"Mastered Rule: {compressed}"]
        else:
            card["status"] = "learning"
            card["mastery_score"] = score
            if verdict == "pass" and score < 0.85:
                card["last_fail_feedback"] = f"Passing score was {int(score*100)}%, but mastery graduation requires >= 85%. Review the edge cases and re-test to graduate."
            else:
                card["last_fail_feedback"] = resp_data.get("blindspots") or resp_data.get("explanation", "")

        # Clear the active trial
        card.pop("active_trial", None)
        atomic_save_memory(cards)

        resp_data["card_id"] = card_id
        resp_data["status"] = card["status"]
        resp_data["success"] = True
        emit(resp_data)
    except Exception as e:
        emit({"success": False, "error": f"Grading failed: {e}"})

# ---------------------------------------------------------
# CLI Command: suggest_profile
# Analyzes history without writing to disk
# ---------------------------------------------------------
PROFILE_PROMPT = """Analyze the user's recent interactions and memory cards to suggest updates to their developer profile.
Detect newly recurring technologies, active stacks, or explicit preferences.

OUTPUT JSON:
{
  "suggested_additions": ["item1", "item2"],
  "suggested_removals": [],
  "detected_preference": "Concise summary of observed style preferences",
  "reasoning": "Brief rationale"
}
"""

def suggest_profile():
    cards = load_memory()
    history = []
    if os.path.exists(HISTORY_PATH):
        try:
            with open(HISTORY_PATH, "r", encoding="utf-8") as f:
                d = json.load(f)
                if isinstance(d, list):
                    history = d[-30:]
        except Exception:
            pass

    profile = {}
    if os.path.exists(PROFILE_PATH):
        try:
            with open(PROFILE_PATH, "r", encoding="utf-8") as f:
                profile = json.load(f)
        except Exception:
            pass

    payload = {
        "current_profile": profile,
        "sample_interactions": [
            {
                "prompt": h.get("prompt", "")[:200],
                "text": h.get("text", "")[:300]
            } for h in history
        ],
        "mastered_topics": [c.get("topic") for c in cards if c.get("status") == "mastered"]
    }

    try:
        raw_resp = call_llm(PROFILE_PROMPT, json.dumps(payload, ensure_ascii=False), expect_json=True)
        resp_data = parse_json_safely(raw_resp)
        resp_data["success"] = True
        emit(resp_data)
    except Exception as e:
        emit({"success": False, "error": f"Profile suggestion failed: {e}"})

# ---------------------------------------------------------
# CLI Command: enrich <card_id>
# Adaptive high-density Technical / Conceptual Primer
# ---------------------------------------------------------
ENRICH_PROMPT = """You are an expert technical educator and knowledge architect.
Enrich this knowledge card into an authoritative, high-density primer tailored to its domain.

DOMAIN & SCOPE ADAPTATION:
1. Determine the domain:
   - "code": software development, programming languages, CLI commands, scripts, APIs, system configs.
   - "protocol": conceptual, methodologies, productivity, health/biology, translation, general reasoning.
2. Determine complexity:
   - "small": a single flag, simple lookup, or short isolated concept.
   - "medium": a standard concept with multiple rules or edge cases.
   - "deep": an intricate, multifaceted architectural or conceptual system.
3. AUDIT EXISTING NOTES FIRST:
   - If the card already has accurate, comprehensive lines from previous interactions, PRESERVE and distill their core substance. DO NOT replace them with generic hallucinated filler!
   - Remove only noise, irrelevant chit-chat, or duplicated trivialities.
4. CONTENT STRUCTURE:
   - 'mental_model': 2-3 dense sentences explaining the underlying cause-and-effect mechanics/principles and WHY it works this way.
   - 'rules': 2-4 actionable, definitive golden rules or invariants.
   - 'pitfall': 1 critical real-world edge case, race condition, or common failure mode.
   - 'snippet':
     - If domain is "code": 3-8 lines of clean, copy-pasteable canonical code, shell pipeline, or config.
     - If domain is "protocol": leave EMPTY string (""). DO NOT invent fake code or dummy bash commands!
   - 'protocol_flow':
     - If domain is "protocol": 2-4 concise, sequential steps or practical execution protocol.
     - If domain is "code": empty list ([]).

OUTPUT JSON:
{
  "domain": "code" | "protocol",
  "complexity": "small" | "medium" | "deep",
  "mental_model": "...",
  "rules": ["Rule 1", "Rule 2"],
  "pitfall": "...",
  "snippet": "...",
  "protocol_flow": ["Step 1", "Step 2"]
}
"""

def enrich(card_id):
    cards = load_memory()
    card = next((c for c in cards if c.get("id") == card_id), None)
    if not card:
        emit({"success": False, "error": f"Card '{card_id}' not found."})
        return

    # Gather user context from lines and history sources
    sources_text = []
    if os.path.exists(HISTORY_PATH):
        try:
            with open(HISTORY_PATH, "r", encoding="utf-8") as f:
                hist = json.load(f)
                if isinstance(hist, list):
                    source_ids = set(str(s) for s in card.get("sources", []))
                    for item in hist:
                        if str(item.get("id")) in source_ids:
                            prompt = item.get("prompt") or ""
                            text = item.get("text") or ""
                            ans = item.get("answer") or ""
                            sources_text.append(f"User Query: {prompt} {text[:200]} -> Answer: {ans[:250]}")
        except Exception:
            pass

    payload = {
        "card_id": card.get("id"),
        "topic": card.get("topic"),
        "category": card.get("category", "general"),
        "current_notes": card.get("lines"),
        "archived_lines": card.get("archived_lines", []),
        "user_sources": sources_text[:3]
    }

    try:
        raw_resp = call_llm(ENRICH_PROMPT, json.dumps(payload, ensure_ascii=False), expect_json=True)
        resp_data = parse_json_safely(raw_resp)

        now_iso = datetime.now(timezone.utc).isoformat()
        domain = resp_data.get("domain", "code" if extract_code_tokens(card.get("topic", "") + " " + " ".join(card.get("lines", []))) else "protocol")
        complexity = resp_data.get("complexity", "small" if len(card.get("lines", [])) <= 1 else "medium")

        card["primer"] = {
            "domain": domain,
            "complexity": complexity,
            "mental_model": resp_data.get("mental_model", ""),
            "rules": resp_data.get("rules", []),
            "pitfall": resp_data.get("pitfall", ""),
            "snippet": resp_data.get("snippet", "") if domain == "code" else "",
            "protocol_flow": resp_data.get("protocol_flow", []) if domain != "code" else [],
            "updated_at": now_iso
        }
        card["updated"] = now_iso
        atomic_save_memory(cards)

        emit({
            "success": True,
            "card_id": card_id,
            "topic": card.get("topic"),
            "primer": card["primer"]
        })
    except Exception as e:
        emit({"success": False, "error": f"Enrichment failed: {e}"})

# ---------------------------------------------------------
# CLI Command: merge <id1> <id2>
# Deduplication & merging of cards (card2 into card1)
# ---------------------------------------------------------
def merge_cards(id1, id2):
    cards = load_memory(auto_demote=False)
    card1 = next((c for c in cards if str(c.get("id")) == str(id1)), None)
    card2 = next((c for c in cards if str(c.get("id")) == str(id2)), None)
    if not card1 or not card2:
        emit({"success": False, "error": f"One or both cards not found: '{id1}', '{id2}'"})
        return
    if id1 == id2:
        emit({"success": False, "error": "Cannot merge a card into itself."})
        return

    now_iso = datetime.now(timezone.utc).isoformat()

    # Merge lines
    existing_lines = list(card1.get("lines") or [])
    for line in (card2.get("lines") or []):
        if line and line not in existing_lines:
            existing_lines.append(line)
    card1["lines"] = existing_lines

    # Merge archived lines
    existing_archived = list(card1.get("archived_lines") or [])
    for line in (card2.get("archived_lines") or []):
        if line and line not in existing_archived:
            existing_archived.append(line)
    card1["archived_lines"] = existing_archived

    # Union tags & sources
    card1["tags"] = list(set((card1.get("tags") or []) + (card2.get("tags") or [])))
    card1["sources"] = list(set((card1.get("sources") or []) + (card2.get("sources") or [])))

    # Combine trials chronologically
    combined_trials = (card1.get("trials") or []) + (card2.get("trials") or [])
    combined_trials.sort(key=lambda t: t.get("timestamp", 0))
    card1["trials"] = combined_trials

    # Inherit primer if card1 lacks one
    if not card1.get("primer") and card2.get("primer"):
        card1["primer"] = card2["primer"]

    # Status & score
    if card1.get("status") != "mastered" and card2.get("status") == "mastered":
        card1["status"] = "mastered"
        card1["mastery_score"] = card2.get("mastery_score", 1.0)
    else:
        card1["mastery_score"] = max(float(card1.get("mastery_score", 0.0)), float(card2.get("mastery_score", 0.0)))

    card1["updated"] = now_iso

    # Remove card2
    remaining_cards = [c for c in cards if str(c.get("id")) != str(id2)]
    atomic_save_memory(remaining_cards)

    emit({
        "success": True,
        "merged_into": id1,
        "deleted_id": id2,
        "total_cards": len(remaining_cards)
    })

# ---------------------------------------------------------
# CLI Command: consolidate <domain>
# Synthesizes fragmented micro-cards into an authoritative Domain Code Hub
# ---------------------------------------------------------
CONSOLIDATE_PROMPT = """You are a Principal Software Engineer and Technical Knowledge Architect.
Your task is to consolidate multiple fragmented cards from the same technical domain into ONE authoritative, cohesive Master Domain Code Hub.

CONSOLIDATION PRINCIPLES:
1. TECHNICAL DEPTH: Do NOT compress into 2 superficial bullet points. Preserve and synthesize all technical nuance, exact idioms, edge cases, and code patterns from the original cards.
2. MODULAR SECTIONS: Organize the knowledge into 2-4 logical, well-structured sections.
3. CONCISE CODE SNIPPETS: Each section must provide a short, focused, practical code snippet (under 8-10 lines max). Do NOT provide full boilerplate classes, endless imports, or package headers. Show only the clean, essential pattern.
4. PITFALLS & BLINDSPOTS: Retain and clearly list deadly traps, gotchas, and concurrency/memory pitfalls.
5. CLEAN DISTINCT TOPIC (5-7 WORDS MAX): Keep core languages and large frameworks separate. Ensure card topics are general, clean, and strictly 5 to 7 words maximum (e.g. 'Java Core & Concurrency Hub', 'Spring Boot Engineering Hub'). Never use long hyper-specific sentences for card titles.
6. EXTRACT ESSENTIAL GENERAL RULES (NOT SITUATIONAL EXAMPLES): Synthesize universal engineering principles, invariants, and syntax gotchas. Eliminate all situational project names, temporary filenames, and conversational history narratives.

OUTPUT FORMAT:
Return a JSON object with a single key 'card':
{
  "card": {
    "id": "card_<domain>_engineering_hub",
    "topic": "Domain & Framework Engineering Hub",
    "category": "<domain>",
    "type": "code_hub",
    "summary": "1-2 sentence high-level overview of the engineering domain.",
    "lines": [
      "Top synthesized high-yield rule 1 across the domain",
      "Top synthesized high-yield rule 2 across the domain"
    ],
    "sections": [
      {
        "id": "section_slug",
        "title": "Section Title",
        "rules": [
          "Actionable technical rule 1",
          "Actionable technical rule 2"
        ],
        "snippet": "```lang\\n// Production code snippet\\n...\\n```",
        "pitfalls": [
          "Deadly trap or common misstep"
        ]
      }
    ],
    "tags": ["domain", "tag1", "tag2"],
    "personal_traps": [
      "Personal traps gathered from user feedback"
    ]
  }
}
"""

def consolidate_domain(domain_query="java"):
    cards = load_memory(auto_demote=False)
    if not cards:
        emit({"success": False, "error": "No memory cards found."})
        return

    domain = (domain_query or "java").lower().strip()

    # Identify candidate cards matching this domain
    matched = []
    for c in cards:
        tags = [str(t).lower() for t in c.get("tags", [])]
        topic = (c.get("topic") or "").lower()
        cid = (c.get("id") or "").lower()
        if domain in tags or domain in topic or domain in cid:
            matched.append(c)

    if len(matched) < 2:
        emit({"success": False, "error": f"Found only {len(matched)} card(s) matching '{domain}'. At least 2 cards are needed to consolidate."})
        return

    payload = {
        "domain": domain,
        "cards_to_consolidate": [
            {
                "id": c.get("id"),
                "topic": c.get("topic"),
                "lines": c.get("lines", []),
                "tags": c.get("tags", []),
                "primer": c.get("primer"),
                "personal_traps": c.get("personal_traps", []),
                "last_fail_feedback": c.get("last_fail_feedback", "")
            }
            for c in matched
        ]
    }

    try:
        raw_resp = call_llm(CONSOLIDATE_PROMPT, json.dumps(payload, ensure_ascii=False), expect_json=True)
        resp_data = parse_json_safely(raw_resp)
        new_card_data = resp_data.get("card")
        if not new_card_data or not isinstance(new_card_data, dict):
            emit({"success": False, "error": "LLM failed to return a valid consolidated card structure."})
            return
    except Exception as e:
        emit({"success": False, "error": f"Consolidation LLM call failed: {e}"})
        return

    now_iso = datetime.now(timezone.utc).isoformat()
    matched_ids = {str(c.get("id")) for c in matched}

    all_sources = set()
    all_trials = []
    all_traps = list(new_card_data.get("personal_traps", []))
    all_relations = []
    max_score = 0.0
    any_mastered = False

    for c in matched:
        for s in c.get("sources", []):
            if s:
                all_sources.add(str(s))
        for t in c.get("trials", []):
            all_trials.append(t)
        for trap in c.get("personal_traps", []):
            if trap and trap not in all_traps:
                all_traps.append(trap)
        if c.get("last_fail_feedback") and c["last_fail_feedback"] not in all_traps:
            all_traps.append(c["last_fail_feedback"])
        for rel in c.get("relations", []):
            if str(rel.get("target_id")) not in matched_ids:
                all_relations.append(rel)
        if c.get("status") == "mastered":
            any_mastered = True
        try:
            score = float(c.get("mastery_score", 0.0))
            if score > max_score:
                max_score = score
        except Exception:
            pass

    all_trials.sort(key=lambda t: t.get("timestamp", 0))

    consolidated_id = new_card_data.get("id") or f"card_{domain}_engineering_hub"
    consolidated_card = {
        "id": consolidated_id,
        "topic": new_card_data.get("topic") or f"{domain.capitalize()} Engineering Hub",
        "category": domain,
        "type": "code_hub",
        "status": "mastered" if any_mastered else "learning",
        "mastery_score": max_score,
        "summary": new_card_data.get("summary", ""),
        "lines": new_card_data.get("lines", []),
        "sections": new_card_data.get("sections", []),
        "tags": list(set(new_card_data.get("tags", [domain]) + [domain])),
        "sources": list(all_sources),
        "trials": all_trials,
        "personal_traps": all_traps,
        "relations": all_relations,
        "created": now_iso,
        "updated": now_iso,
        "last_reviewed": now_iso,
        "_ts": int(time.time() * 1000)
    }

    # Replace matched cards with the new consolidated card
    remaining_cards = [c for c in cards if str(c.get("id")) not in matched_ids]
    remaining_cards.insert(0, consolidated_card)
    atomic_save_memory(remaining_cards)

    emit({
        "success": True,
        "consolidated_id": consolidated_id,
        "topic": consolidated_card["topic"],
        "sections_count": len(consolidated_card.get("sections", [])),
        "merged_card_count": len(matched),
        "deleted_ids": list(matched_ids),
        "total_cards": len(remaining_cards)
    })


# ---------------------------------------------------------
# CLI Command: daily_challenge
# Spaced repetition gauntlet prioritizing due & blindspot cards
# ---------------------------------------------------------
def daily_challenge():
    cards = load_memory()
    if not cards:
        emit({"success": False, "error": "No memory cards found to generate daily gauntlet."})
        return

    now_epoch = time.time()
    FOURTEEN_DAYS = 14 * 86400

    def card_priority(c):
        score = 100
        # Priority 1: Unresolved blindspots
        if c.get("status") != "mastered" and c.get("last_fail_feedback"):
            score = 10
        # Priority 2: Unmastered concepts
        elif c.get("status") != "mastered":
            score = 20
        else:
            # Priority 3: Mastered cards due for review (> 14 days)
            lr_str = c.get("last_reviewed") or c.get("updated") or c.get("created") or ""
            try:
                lr_dt = datetime.fromisoformat(lr_str.replace("Z", "+00:00"))
                age = now_epoch - lr_dt.timestamp()
                if age > FOURTEEN_DAYS:
                    score = 30 - min(10, int(age / (30 * 86400) * 10))
                else:
                    score = 50 + int(age / 86400)
            except Exception:
                score = 60
        return score

    sorted_candidates = sorted(cards, key=card_priority)
    chosen_card = sorted_candidates[0]
    challenge(chosen_card.get("id"), is_daily=True)
# ---------------------------------------------------------
# CLI Command: sync_graph
# Constructs Knowledge Graph relationships (prerequisites, evolutions, related)
# ---------------------------------------------------------
GRAPH_PROMPT = """You are an expert software knowledge graph architect and mentor.
Analyze the provided developer memory cards and map ALL high-value knowledge graph connections between them across all domains (Java, Concurrency, Networking, Linux, Architecture, System Design).

CONNECTION TYPES:
1. "prerequisite": Target card is foundational or required to understand or implement the source card (e.g., OSI Model / TCP is a prerequisite for HTTP SSE Streaming; basic Java Concurrency is a prerequisite for ConcurrentHashMap internals).
2. "evolution": Source card evolved from, modernizes, or solves advanced/edge-case problems of the target card (e.g., CopyOnWriteArrayList evolves from basic Java Collections; OCI ADR Containers evolves from general Docker primitives).
3. "related": Sibling concepts that frequently co-occur in architectures or solve adjacent facets of the same problem (e.g., Docker Architecture and OCI Containers, URI vs URL and Networking Protocols, Spring Boot Config and Thymeleaf Integration).

RULES:
- Review the entire list of cards thoroughly. Create genuine, high-value connections wherever conceptual linkage exists.
- Aim to link related cards into cohesive topic clusters so the developer can navigate between connected concepts.
- 'reason' MUST be a crisp, informative 1-sentence explanation of why they are linked.

OUTPUT JSON FORMAT:
{
  "connections": [
    {
      "source_id": "<card_id_1>",
      "target_id": "<card_id_2>",
      "type": "prerequisite" | "evolution" | "related",
      "reason": "Clear 1-sentence explanation of the conceptual link"
    }
  ]
}
"""

def sync_graph():
    cards = load_memory()
    if len(cards) < 2:
        emit({"success": True, "connections_count": 0, "message": "Need at least 2 cards to form a knowledge graph."})
        return

    manifest = []
    card_map = {c["id"]: c for c in cards}
    for c in cards:
        lines = c.get("lines") or []
        summary = lines[0] if lines else ""
        manifest.append({
            "id": c["id"],
            "topic": c.get("topic", "Untitled"),
            "summary": summary[:120]
        })

    try:
        raw_resp = call_llm(GRAPH_PROMPT, json.dumps({"cards": manifest}, ensure_ascii=False), expect_json=True)
        resp_data = parse_json_safely(raw_resp)
        connections = resp_data.get("connections", [])

        # Reset existing relations
        for c in cards:
            c["relations"] = []

        valid_count = 0
        for conn in connections:
            s_id = conn.get("source_id")
            t_id = conn.get("target_id")
            rel_type = conn.get("type", "related")
            reason = conn.get("reason", "")

            if s_id in card_map and t_id in card_map and s_id != t_id:
                s_card = card_map[s_id]
                t_card = card_map[t_id]

                # Check duplicate on source
                if not any(r.get("target_id") == t_id for r in s_card["relations"]):
                    s_card["relations"].append({
                        "target_id": t_id,
                        "target_topic": t_card.get("topic", "Untitled"),
                        "type": rel_type,
                        "reason": reason
                    })
                    valid_count += 1

                # Add reciprocal link if not already present
                rev_type = "prerequisite_for" if rel_type == "prerequisite" else ("evolved_to" if rel_type == "evolution" else "related")
                if not any(r.get("target_id") == s_id for r in t_card["relations"]):
                    t_card["relations"].append({
                        "target_id": s_id,
                        "target_topic": s_card.get("topic", "Untitled"),
                        "type": rev_type,
                        "reason": reason
                    })

        atomic_save_memory(cards)
        emit({
            "success": True,
            "connections_count": valid_count,
            "cards_count": len(cards),
            "message": f"Successfully mapped {valid_count} graph connections across {len(cards)} cards."
        })
    except Exception as e:
        emit({"success": False, "error": f"Knowledge graph sync failed: {e}"})

def remove_trap(card_id, trap_text):
    cards = load_memory()
    card = next((c for c in cards if c.get("id") == card_id), None)
    if not card:
        emit({"success": False, "error": f"Card '{card_id}' not found."})
        return
    traps = card.get("personal_traps", [])
    card["personal_traps"] = [t for t in traps if t.strip() != trap_text.strip()]
    atomic_save_memory(cards)
    emit({"success": True, "personal_traps": card["personal_traps"]})

# ---------------------------------------------------------
# Main CLI Dispatcher
# ---------------------------------------------------------
def main():
    if len(sys.argv) < 2:
        emit({
            "error": "USAGE",
            "message": "Usage: memory_engine.py <distill|get_context|challenge|grade|suggest_profile|enrich|merge|daily_challenge|sync_graph|remove_trap> [args...]"
        })
        sys.exit(1)

    cmd = sys.argv[1].lower()

    if cmd == "distill":
        distill()
    elif cmd == "get_context":
        query = sys.argv[2] if len(sys.argv) > 2 else ""
        get_context(query)
    elif cmd == "challenge":
        if len(sys.argv) < 3:
            emit({"error": "MISSING_ARG", "message": "Usage: memory_engine.py challenge <card_id>"})
            sys.exit(1)
        challenge(sys.argv[2])
    elif cmd == "daily_challenge":
        daily_challenge()
    elif cmd == "grade":
        if len(sys.argv) < 4:
            emit({"error": "MISSING_ARG", "message": "Usage: memory_engine.py grade <card_id> \"<answer>\""})
            sys.exit(1)
        grade(sys.argv[2], sys.argv[3])
    elif cmd == "enrich":
        if len(sys.argv) < 3:
            emit({"error": "MISSING_ARG", "message": "Usage: memory_engine.py enrich <card_id>"})
            sys.exit(1)
        enrich(sys.argv[2])
    elif cmd == "merge":
        if len(sys.argv) < 4:
            emit({"error": "MISSING_ARG", "message": "Usage: memory_engine.py merge <card_id1> <card_id2>"})
            sys.exit(1)
        merge_cards(sys.argv[2], sys.argv[3])
    elif cmd == "sync_graph":
        sync_graph()
    elif cmd == "consolidate":
        domain = sys.argv[2] if len(sys.argv) > 2 else "java"
        consolidate_domain(domain)
    elif cmd == "remove_trap":
        if len(sys.argv) < 4:
            emit({"error": "MISSING_ARG", "message": "Usage: memory_engine.py remove_trap <card_id> \"<trap_text>\""})
            sys.exit(1)
        remove_trap(sys.argv[2], sys.argv[3])
    elif cmd == "suggest_profile":
        suggest_profile()
    else:
        emit({"error": "UNKNOWN_COMMAND", "command": cmd})
        sys.exit(1)

if __name__ == "__main__":
    main()

