#!/usr/bin/env python3
import sys
import json
import os
import re
import time
import urllib.request
import urllib.parse
import urllib.error

CONFIG_PATH = os.path.expanduser("~/.config/caelestia/assistant.json")

PROMPTS = {
    "translate": (
        "You are an expert bilingual translator. Translate the following text into natural, accurate, and fluent Arabic. "
        "Keep technical terms clear and provide short context/synonyms if a term has nuances. "
        "Output the Arabic translation directly with brief notes only if strictly necessary."
    ),
    "explain": (
        "You are an expert tutor. Explain the following text simply and clearly (ELIF5 style), "
        "breaking down complex ideas into intuitive parts. Use short bullet points where appropriate."
    ),
    "tldr": (
        "Summarize the following text concisely. Provide key takeaways in 2-4 brief bullet points."
    ),
    "rephrase": (
        "Rewrite the following text in 3 different ways: 1) Professional / Formal, 2) Simple / Casual, 3) More vivid / impactful."
    ),
    "examples": (
        "Provide 3 clear, realistic context examples or sentences showing how this concept, word, or pattern is used in real life."
    ),
    "ask": (
        "You are an expert assistant. Answer the user's question clearly and concisely based on the provided text."
    )
}

def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()

def load_config():
    cfg = {"gemini_key": "", "groq_key": "", "primary": "gemini", "max_chars": 12000}
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, dict):
                    cfg.update(data)
                    # Normalize alternative key names from config schema
                    if "gemini_api_key" in data and not cfg.get("gemini_key"):
                        cfg["gemini_key"] = data["gemini_api_key"]
                    if "groq_api_key" in data and not cfg.get("groq_key"):
                        cfg["groq_key"] = data["groq_api_key"]
                    if "preferred_provider" in data:
                        cfg["primary"] = data["preferred_provider"]
        except Exception:
            pass
    if os.environ.get("GEMINI_API_KEY"):
        cfg["gemini_key"] = os.environ.get("GEMINI_API_KEY")
    if os.environ.get("GROQ_API_KEY"):
        cfg["groq_key"] = os.environ.get("GROQ_API_KEY")
    return cfg

def get_provider_ceiling(primary, gemini_key, groq_key):
    prov = (primary or "").strip().lower()
    has_gemini = bool(gemini_key and gemini_key.strip())
    has_groq = bool(groq_key and groq_key.strip())

    if prov == "gemini":
        return 200000
    if prov == "groq":
        return 100000

    if has_gemini and not has_groq:
        return 200000
    if has_groq and not has_gemini:
        return 100000

    # Both configured and it's auto (or fallback): smaller of the two caps
    return 100000

def save_config(gemini_key, groq_key):
    os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    cfg = load_config()
    cfg["gemini_key"] = gemini_key.strip()
    cfg["groq_key"] = groq_key.strip()
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)
    return {"success": True}

def stream_gemini(api_key, system_instruction, user_text):
    candidate_models = [
        "gemini-3.5-flash-lite",
        "gemini-3.1-flash-lite",
        "gemini-flash-latest"
    ]
    last_err = None
    for model_name in candidate_models:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:streamGenerateContent?alt=sse&key={api_key}"
        payload = {
            "contents": [
                {
                    "parts": [{"text": f"Instructions: {system_instruction}\n\nText:\n{user_text}"}]
                }
            ],
            "generationConfig": {
                "temperature": 0.4,
                "maxOutputTokens": 1024
            }
        }
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        try:
            with urllib.request.urlopen(req, timeout=12) as resp:
                emitted_any = False
                for line in resp:
                    line_str = line.decode("utf-8", errors="replace").strip()
                    if line_str.startswith("data:"):
                        raw_data = line_str[5:].strip()
                        if not raw_data:
                            continue
                        try:
                            parsed = json.loads(raw_data)
                            candidates = parsed.get("candidates", [])
                            if candidates and "content" in candidates[0]:
                                parts = candidates[0]["content"].get("parts", [])
                                for p in parts:
                                    chunk_text = p.get("text", "")
                                    if chunk_text:
                                        emit({"type": "chunk", "text": chunk_text})
                                        emitted_any = True
                        except Exception:
                            continue
                return True
        except urllib.error.HTTPError as e:
            last_err = e
            if e.code in (404, 503):
                continue
            raise e
        except Exception as e:
            last_err = e
            break

    if last_err:
        raise last_err
    return False

def stream_groq(api_key, system_instruction, user_text):
    url = "https://api.groq.com/openai/v1/chat/completions"
    payload = {
        "model": "llama-3.3-70b-versatile",
        "messages": [
            {"role": "system", "content": system_instruction},
            {"role": "user", "content": user_text}
        ],
        "temperature": 0.4,
        "max_tokens": 1024,
        "stream": True
    }
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}"
        },
        method="POST"
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        for line in resp:
            line_str = line.decode("utf-8", errors="replace").strip()
            if line_str.startswith("data:"):
                raw = line_str[5:].strip()
                if raw == "[DONE]":
                    break
                try:
                    d = json.loads(raw)
                    delta = d.get("choices", [{}])[0].get("delta", {}).get("content", "")
                    if delta:
                        emit({"type": "chunk", "text": delta})
                except Exception:
                    continue
    return True

def classify_error(err_str, http_code=None):
    if http_code in (400, 401, 403):
        return {
            "error_type": "auth",
            "message": "Invalid API key or authentication failed."
        }
    if http_code == 429 or "rate" in err_str.lower() or "quota" in err_str.lower():
        return {
            "error_type": "rate_limit",
            "message": "API rate limit reached. Please wait a few seconds."
        }
    if "unavailable" in err_str.lower() or "timeout" in err_str.lower() or "connection" in err_str.lower():
        return {
            "error_type": "network",
            "message": "Network error or service unavailable. Check your connection."
        }
    return {
        "error_type": "generic",
        "message": err_str or "An error occurred while generating response."
    }

PROFILE_PATH = os.path.expanduser("~/.config/caelestia/assistant_profile.json")
HISTORY_PATH = os.path.expanduser("~/.config/caelestia/assistant_history.json")

DEFAULT_PROFILE = {
    "os": "Linux (Hyprland)",
    "languages": ["Python", "QML / Qt", "Bash"],
    "style_preference": "Concise, standard library first, minimal dependencies",
    "bilingual": "English for technical terms/code, Arabic for natural translation/explanation",
    "custom_notes": "",
    "last_updated": ""
}

def load_profile():
    if os.path.exists(PROFILE_PATH):
        try:
            with open(PROFILE_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, dict):
                    prof = DEFAULT_PROFILE.copy()
                    prof.update(data)
                    return prof
        except Exception:
            pass
    return DEFAULT_PROFILE.copy()

def save_profile(profile_data):
    os.makedirs(os.path.dirname(PROFILE_PATH), exist_ok=True)
    with open(PROFILE_PATH, "w", encoding="utf-8") as f:
        json.dump(profile_data, f, indent=2)
    return {"success": True}

def get_profile_prompt_prefix():
    profile = load_profile()
    parts = []
    if profile.get("os"):
        parts.append(f"OS: {profile['os']}")
    langs = profile.get("languages", [])
    if isinstance(langs, list) and langs:
        parts.append(f"Tech: {', '.join(langs)}")
    elif isinstance(langs, str) and langs.strip():
        parts.append(f"Tech: {langs.strip()}")
    if profile.get("style_preference"):
        parts.append(f"Style: {profile['style_preference']}")
    if profile.get("bilingual"):
        parts.append(f"Language: {profile['bilingual']}")
    if profile.get("custom_notes"):
        parts.append(f"Notes: {profile['custom_notes']}")

    if not parts:
        return ""
    return f"[Developer Profile Context: {' | '.join(parts)}]\n"

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

def extract_keywords(text):
    if not text:
        return set()
    words = re.findall(r'[a-zA-Z0-9_]+', text.lower())
    return {w for w in words if len(w) >= 3 and w not in STOP_WORDS}

def extract_code_tokens(text):
    if not text:
        return set()
    matches = CODE_TOKEN_PATTERN.findall(text)
    return {m for m in matches if len(m) >= 3}

def find_relevant_history(current_text, current_prompt):
    if not os.path.exists(HISTORY_PATH):
        return None
    try:
        with open(HISTORY_PATH, "r", encoding="utf-8") as f:
            history = json.load(f)
    except Exception:
        return None

    if not isinstance(history, list) or not history:
        return None

    query_combined = f"{current_prompt or ''} {current_text or ''}".strip()
    if len(query_combined) < 5:
        return None

    query_code = extract_code_tokens(query_combined)
    query_words = extract_keywords(query_combined)

    best_item = None
    best_score = 0.0

    # Consider up to 100 most recent history items
    for item in history[:100]:
        # Strictly respect 'Forget this' exclusion toggle
        if item.get("context_excluded"):
            continue

        item_text = (item.get("text") or "").strip()
        item_prompt = (item.get("prompt") or "").strip()
        item_answer = (item.get("answer") or "").strip()
        item_combined = f"{item_prompt} {item_text}".strip()

        if not item_combined or not item_answer:
            continue

        # Skip if identical query (avoid self-reference on repeated runs)
        if item_combined == query_combined or (item_text == current_text and item_prompt == current_prompt):
            continue

        item_code = extract_code_tokens(item_combined)
        item_words = extract_keywords(item_combined)

        shared_code = query_code.intersection(item_code)
        shared_words = query_words.intersection(item_words)
        union_words = query_words.union(item_words)
        jaccard = len(shared_words) / len(union_words) if union_words else 0.0

        is_match = False
        score = 0.0

        # Strict Threshold Heuristic:
        # 1. >= 2 shared technical code tokens
        if len(shared_code) >= 2:
            is_match = True
            score = 1.0 + (len(shared_code) * 0.5) + jaccard
        # 2. 1 shared code token + Jaccard similarity >= 0.40
        elif len(shared_code) == 1 and jaccard >= 0.40:
            is_match = True
            score = 0.8 + jaccard
        # 3. Jaccard similarity >= 0.65 with >= 3 shared keywords
        elif jaccard >= 0.65 and len(shared_words) >= 3:
            is_match = True
            score = 0.6 + jaccard

        if is_match and score > best_score:
            best_score = score
            best_item = item

    return best_item

def organize_history():
    if not os.path.exists(HISTORY_PATH):
        emit({"type": "organize_done", "tags": [], "mapping": {}})
        return

    try:
        with open(HISTORY_PATH, "r", encoding="utf-8") as f:
            history = json.load(f)
    except Exception as e:
        emit({"type": "error", "message": f"Could not read history: {e}"})
        return

    if not history or not isinstance(history, list):
        emit({"type": "organize_done", "tags": [], "mapping": {}})
        return

    items_to_tag = []
    for item in history[:100]:
        snippet = (item.get("text") or item.get("prompt") or "")[:80].replace("\n", " ").strip()
        if snippet:
            items_to_tag.append({
                "id": str(item.get("id")),
                "action": item.get("action", ""),
                "snippet": snippet
            })

    if not items_to_tag:
        emit({"type": "organize_done", "tags": [], "mapping": {}})
        return

    config = load_config()
    gemini_key = config.get("gemini_key", "").strip()
    groq_key = config.get("groq_key", "").strip()
    primary = config.get("primary", "gemini").lower()

    providers = []
    if primary == "groq":
        if groq_key: providers.append(("groq", groq_key))
        if gemini_key: providers.append(("gemini", gemini_key))
    else:
        if gemini_key: providers.append(("gemini", gemini_key))
        if groq_key: providers.append(("groq", groq_key))

    if not providers:
        emit({"type": "error", "error_type": "auth", "message": "No API key configured."})
        return

    system_instruction = (
        "You are an expert knowledge organizer and developer mentor. Analyze the provided list of reading/learning queries.\n"
        "1. Generate 3 to 7 concise, high-level topical lowercase tags (e.g. 'python', 'regex', 'vocabulary', 'linux', 'science', 'math') "
        "and assign 1 or 2 relevant tags to each item ID.\n"
        "2. Based on the queries, PROPOSE (do NOT force) an updated developer profile reflecting their tools, languages, and style.\n"
        "Respond ONLY with valid, raw JSON matching this schema without markdown codeblocks:\n"
        "{\n"
        "  \"tags\": [\"tag1\", \"tag2\"],\n"
        "  \"mapping\": {\"id1\": [\"tag1\"], \"id2\": [\"tag2\"]},\n"
        "  \"proposed_profile\": {\n"
        "    \"os\": \"...\",\n"
        "    \"languages\": [\"...\"],\n"
        "    \"style_preference\": \"...\",\n"
        "    \"bilingual\": \"...\",\n"
        "    \"custom_notes\": \"...\"\n"
        "  }\n"
        "}"
    )
    user_payload = json.dumps({
        "current_profile": load_profile(),
        "items": items_to_tag
    })

    response_text = ""
    for prov_name, key in providers:
        try:
            if prov_name == "gemini":
                candidate_models = ["gemini-2.5-flash-lite", "gemini-2.0-flash", "gemini-flash-latest"]
                for model_name in candidate_models:
                    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:generateContent?key={key}"
                    req_data = json.dumps({
                        "contents": [{"parts": [{"text": f"{system_instruction}\n\nItems and Current Profile:\n{user_payload}"}]}],
                        "generationConfig": {"temperature": 0.2, "responseMimeType": "application/json"}
                    }).encode("utf-8")
                    req = urllib.request.Request(url, data=req_data, headers={"Content-Type": "application/json"}, method="POST")
                    try:
                        with urllib.request.urlopen(req, timeout=15) as resp:
                            resp_json = json.loads(resp.read().decode("utf-8"))
                            candidates = resp_json.get("candidates", [])
                            if candidates:
                                parts = candidates[0].get("content", {}).get("parts", [])
                                if parts:
                                    response_text = parts[0].get("text", "")
                                    break
                    except Exception:
                        continue
            elif prov_name == "groq":
                url = "https://api.groq.com/openai/v1/chat/completions"
                req_data = json.dumps({
                    "model": "llama-3.3-70b-versatile",
                    "messages": [
                        {"role": "system", "content": system_instruction},
                        {"role": "user", "content": f"Items and Current Profile:\n{user_payload}"}
                    ],
                    "temperature": 0.2,
                    "response_format": {"type": "json_object"}
                }).encode("utf-8")
                req = urllib.request.Request(url, data=req_data, headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {key}"
                }, method="POST")
                with urllib.request.urlopen(req, timeout=15) as resp:
                    resp_json = json.loads(resp.read().decode("utf-8"))
                    choices = resp_json.get("choices", [])
                    if choices:
                        response_text = choices[0].get("message", {}).get("content", "")

            if response_text:
                break
        except Exception:
            continue

    if not response_text:
        emit({"type": "error", "message": "Failed to organize history with AI."})
        return

    try:
        clean_text = response_text.strip()
        if clean_text.startswith("```"):
            clean_text = clean_text.split("\n", 1)[1].rsplit("```", 1)[0].strip()
        parsed = json.loads(clean_text)
        tags = parsed.get("tags", [])
        mapping = parsed.get("mapping", {})
        proposed_profile = parsed.get("proposed_profile")

        for item in history:
            item_id = str(item.get("id"))
            if item_id in mapping:
                item["tags"] = mapping[item_id]

        with open(HISTORY_PATH, "w", encoding="utf-8") as f:
            json.dump(history, f, indent=2)

        emit({
            "type": "organize_done",
            "tags": tags,
            "mapping": mapping,
            "proposed_profile": proposed_profile
        })
    except Exception as e:
        emit({"type": "error", "message": f"Failed to parse organization tags: {e}"})

def generate_challenge(item_json_str):
    try:
        item = json.loads(item_json_str)
    except Exception as e:
        emit({"type": "error", "message": f"Invalid item JSON: {e}"})
        return

    config = load_config()
    gemini_key = config.get("gemini_key", "").strip()
    groq_key = config.get("groq_key", "").strip()
    primary = config.get("primary", "gemini").lower()

    providers = []
    if primary == "groq":
        if groq_key: providers.append(("groq", groq_key))
        if gemini_key: providers.append(("gemini", gemini_key))
    else:
        if gemini_key: providers.append(("gemini", gemini_key))
        if groq_key: providers.append(("groq", groq_key))

    if not providers:
        emit({"type": "error", "error_type": "auth", "message": "No API key configured."})
        return

    snippet = (item.get("text") or "")[:400].strip()
    prompt = (item.get("prompt") or "")[:200].strip()
    answer = (item.get("answer") or "")[:800].strip()

    system_instruction = (
        "You are an expert tutor creating a practical concept-check challenge for active recall.\n"
        "Given the past query, context, and answer:\n"
        "Generate ONE new, concise conceptual question testing the user's understanding of the underlying principle or edge case.\n"
        "Do NOT quiz trivial phrasing from the past answer; test actual conceptual mastery.\n"
        "Respond ONLY with valid, raw JSON matching this schema without markdown codeblocks:\n"
        "{\n"
        "  \"question\": \"The test question...\",\n"
        "  \"hint\": \"A brief 1-sentence hint...\",\n"
        "  \"solution\": \"The direct answer and explanation...\"\n"
        "}"
    )

    user_payload = json.dumps({
        "context_snippet": snippet,
        "query_prompt": prompt,
        "reference_answer": answer
    })

    response_text = ""
    for prov_name, key in providers:
        try:
            if prov_name == "gemini":
                candidate_models = ["gemini-2.5-flash-lite", "gemini-2.0-flash", "gemini-flash-latest"]
                for model_name in candidate_models:
                    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:generateContent?key={key}"
                    req_data = json.dumps({
                        "contents": [{"parts": [{"text": f"{system_instruction}\n\nTarget Material:\n{user_payload}"}]}],
                        "generationConfig": {"temperature": 0.3, "responseMimeType": "application/json"}
                    }).encode("utf-8")
                    req = urllib.request.Request(url, data=req_data, headers={"Content-Type": "application/json"}, method="POST")
                    try:
                        with urllib.request.urlopen(req, timeout=15) as resp:
                            resp_json = json.loads(resp.read().decode("utf-8"))
                            candidates = resp_json.get("candidates", [])
                            if candidates:
                                parts = candidates[0].get("content", {}).get("parts", [])
                                if parts:
                                    response_text = parts[0].get("text", "")
                                    break
                    except Exception:
                        continue
            elif prov_name == "groq":
                url = "https://api.groq.com/openai/v1/chat/completions"
                req_data = json.dumps({
                    "model": "llama-3.3-70b-versatile",
                    "messages": [
                        {"role": "system", "content": system_instruction},
                        {"role": "user", "content": f"Target Material:\n{user_payload}"}
                    ],
                    "temperature": 0.3,
                    "response_format": {"type": "json_object"}
                }).encode("utf-8")
                req = urllib.request.Request(url, data=req_data, headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {key}"
                }, method="POST")
                with urllib.request.urlopen(req, timeout=15) as resp:
                    resp_json = json.loads(resp.read().decode("utf-8"))
                    choices = resp_json.get("choices", [])
                    if choices:
                        response_text = choices[0].get("message", {}).get("content", "")

            if response_text:
                break
        except Exception:
            continue

    if not response_text:
        emit({"type": "error", "message": "Failed to generate concept challenge."})
        return

    try:
        clean_text = response_text.strip()
        if clean_text.startswith("```"):
            clean_text = clean_text.split("\n", 1)[1].rsplit("```", 1)[0].strip()
        parsed = json.loads(clean_text)
        emit({
            "type": "challenge_done",
            "item_id": str(item.get("id")),
            "question": parsed.get("question", ""),
            "hint": parsed.get("hint", ""),
            "solution": parsed.get("solution", "")
        })
    except Exception as e:
        emit({"type": "error", "message": f"Failed to parse challenge question: {e}"})

def main():
    if len(sys.argv) < 2:
        emit({"type": "error", "error_type": "generic", "message": "Usage: assistant_api.py <action> [args...]"})
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "save_config":
        gemini_key = sys.argv[2] if len(sys.argv) > 2 else ""
        groq_key = sys.argv[3] if len(sys.argv) > 3 else ""
        emit(save_config(gemini_key, groq_key))
        sys.exit(0)

    if cmd == "save_profile":
        profile_json_str = sys.argv[2] if len(sys.argv) > 2 else "{}"
        try:
            profile_data = json.loads(profile_json_str)
            emit(save_profile(profile_data))
        except Exception as e:
            emit({"type": "error", "message": f"Failed to save profile: {e}"})
        sys.exit(0)

    if cmd == "organize":
        organize_history()
        sys.exit(0)

    if cmd == "challenge":
        item_json = sys.argv[2] if len(sys.argv) > 2 else "{}"
        generate_challenge(item_json)
        sys.exit(0)

    action = cmd
    text = sys.argv[2] if len(sys.argv) > 2 else ""
    custom_prompt = sys.argv[3] if len(sys.argv) > 3 else ""

    config = load_config()
    gemini_key = config.get("gemini_key", "").strip()
    groq_key = config.get("groq_key", "").strip()
    primary = config.get("primary", "gemini").lower()

    if not gemini_key and not groq_key:
        emit({
            "type": "error",
            "error_type": "auth",
            "message": "Please configure your Gemini or Groq API key."
        })
        sys.exit(0)

    # Determine truncation limit and apply provider ceiling
    raw_max_chars = config.get("max_chars")
    try:
        max_chars = int(raw_max_chars)
        if max_chars <= 0:
            max_chars = 12000
    except (TypeError, ValueError):
        max_chars = 12000

    ceiling = get_provider_ceiling(primary, gemini_key, groq_key)
    effective_limit = min(max_chars, ceiling)

    is_truncated = False
    if text and len(text) > effective_limit:
        text_to_process = text[:effective_limit]
        is_truncated = True
    else:
        text_to_process = text

    user_payload = text_to_process
    if action == "ask":
        if custom_prompt and text_to_process.strip():
            system_instruction = (
                "You are an expert reading assistant. Answer the user's question clearly and concisely "
                "using the provided context text as reference when relevant."
            )
            user_payload = f"Context text:\n{text_to_process}\n\nUser Question: {custom_prompt}"
        elif custom_prompt:
            system_instruction = (
                "You are a helpful, knowledgeable, and concise AI assistant. "
                "Directly and accurately answer the user's question."
            )
            user_payload = custom_prompt
        elif text_to_process.strip():
            system_instruction = (
                "You are an expert assistant. Explain or answer regarding the provided text clearly and concisely."
            )
            user_payload = text_to_process
    else:
        system_instruction = PROMPTS.get(action, PROMPTS["explain"])
        user_payload = text_to_process

    profile_prefix = get_profile_prompt_prefix()
    if profile_prefix:
        system_instruction = f"{profile_prefix}\n{system_instruction}"

    recalled_item = find_relevant_history(text_to_process, custom_prompt)
    recalled_meta = None
    if recalled_item:
        prior_title = (recalled_item.get("prompt") or recalled_item.get("text") or "")[:80].replace("\n", " ").strip()
        prior_ans = (recalled_item.get("answer") or "")[:280].replace("\n", " ").strip()
        context_injection = f"[Relevant Prior Context: User previously worked on \"{prior_title}\". Prior resolution: \"{prior_ans}\"]\n"
        system_instruction = f"{context_injection}{system_instruction}"
        recalled_meta = {
            "id": str(recalled_item.get("id")),
            "title": prior_title,
            "timestamp": recalled_item.get("timestamp", 0)
        }

    providers = []
    if primary == "groq":
        if groq_key: providers.append(("groq", groq_key, "Groq Llama 3.3"))
        if gemini_key: providers.append(("gemini", gemini_key, "Gemini Flash"))
    else:
        if gemini_key: providers.append(("gemini", gemini_key, "Gemini Flash"))
        if groq_key: providers.append(("groq", groq_key, "Groq Llama 3.3"))

    start_time = time.perf_counter()
    success = False
    last_err_str = ""
    last_http_code = None
    chosen_provider = ""

    for prov_name, key, prov_label in providers:
        try:
            # Emit start header so UI immediately knows provider
            emit({
                "type": "start",
                "provider": prov_label,
                "truncated": is_truncated,
                "truncated_at": effective_limit,
                "recalled_from": recalled_meta
            })
            chosen_provider = prov_label

            if prov_name == "gemini":
                stream_gemini(key, system_instruction, user_payload)
            elif prov_name == "groq":
                stream_groq(key, system_instruction, user_payload)

            success = True
            break
        except urllib.error.HTTPError as e:
            last_http_code = e.code
            last_err_str = str(e)
            if e.code in (400, 401, 403):
                break  # Don't fallback on bad auth
        except Exception as e:
            last_err_str = str(e)

    elapsed_ms = int((time.perf_counter() - start_time) * 1000)

    if success:
        emit({
            "type": "done",
            "provider": chosen_provider,
            "latency_ms": elapsed_ms,
            "truncated": is_truncated,
            "truncated_at": effective_limit,
            "recalled_from": recalled_meta
        })
    else:
        err_info = classify_error(last_err_str, last_http_code)
        emit({
            "type": "error",
            "error_type": err_info["error_type"],
            "latency_ms": elapsed_ms,
            "message": err_info["message"]
        })

if __name__ == "__main__":
    main()
