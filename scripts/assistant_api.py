#!/usr/bin/env python3
import sys
import json
import os
import re
import time
import urllib.request
import urllib.parse
import urllib.error
import subprocess
from datetime import datetime, timezone

from assistant_common import (
    CONFIG_PATH, HISTORY_PATH, MEMORY_PATH, PROFILE_PATH, LEARNER_PROFILE_PATH,
    GEMINI_CANDIDATE_MODELS, GROQ_CANDIDATE_MODELS, STOP_WORDS,
    CODE_TOKEN_PATTERN, WORD_PATTERN,
    emit, load_config, load_profile, save_profile,
    extract_keywords, extract_code_tokens, normalize_concept_key
)

PROMPTS = {
    "translate": (
        "You are an expert translator. Translate the following text accurately and naturally. "
        "If the input text is in English or another foreign language, translate it into clear modern Arabic. "
        "If the input text is in Arabic, translate it into fluent English. "
        "Provide only the direct, accurate translation without conversational preamble or conversational filler."
    ),
    "explain": (
        "You are an expert tutor. Explain the following text simply, clearly, and engagingly in pure English. "
        "Break down complex ideas into intuitive parts using short bullet points. "
        "Do NOT write Arabic sentences; write in pure English. If an advanced or difficult English word is used, "
        "you may add its concise Arabic translation in parentheses (e.g., 'elucidate (يوضّح)')."
    ),
    "fix": (
        "You are an expert software engineer and debugger. Analyze the following error, stack trace, or buggy snippet. "
        "Lead immediately with the solution:\n"
        "1. Direct Fix (minimal, production-ready code or command snippet first)\n"
        "2. Exact Root Cause (1 crisp sentence)\n"
        "3. Prevention Invariants (2 bullet points on how to prevent this in the future)\n"
        "No conversational filler or polite preamble."
    ),
    "tldr": (
        "Summarize the following text concisely in pure English. Provide key takeaways in 2-4 brief bullet points. "
        "Write purely in English, adding a brief Arabic translation in parentheses only for difficult vocabulary."
    ),
    "rephrase": (
        "Rewrite the following text in 3 different ways in pure English: 1) Professional / Formal, 2) Simple / Casual, 3) More vivid / impactful. "
        "Write purely in English, adding a parenthetical Arabic gloss only if an advanced vocabulary word is used."
    ),
    "examples": (
        "Provide 3 clear, realistic context examples or sentences showing how this concept, word, or pattern is used in real life. "
        "Write all explanations and sentences in pure English. If a hard English word appears, place its Arabic translation in parentheses."
    ),
    "ask": (
        "You are an expert assistant. Answer the user's question clearly, directly, and concisely in pure English. "
        "Write purely in English, placing a concise Arabic gloss in parentheses only for difficult or advanced English terms."
    )
}

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

def save_config(gemini_key=None, groq_key=None, provider=None, max_chars=None):
    os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    cfg = load_config()
    if gemini_key is not None and gemini_key.strip():
        cfg["gemini_key"] = gemini_key.strip()
    if groq_key is not None and groq_key.strip():
        cfg["groq_key"] = groq_key.strip()
    if provider:
        cfg["primary"] = provider.strip().lower()
    if max_chars:
        try:
            cfg["max_chars"] = int(max_chars)
        except (ValueError, TypeError):
            pass
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)
    return {"success": True}

GEMINI_CANDIDATE_MODELS = [
    "gemini-3.5-flash-lite",
    "gemini-3.1-flash-lite",
    "gemini-2.5-flash"
]

GROQ_CANDIDATE_MODELS = [
    "qwen/qwen3.8-27b",
    "openai/gpt-oss-120b",
    "openai/gpt-oss-20b"
]

def stream_gemini(api_key, system_instruction, user_text, contents=None):
    last_err = None
    for model_name in GEMINI_CANDIDATE_MODELS:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:streamGenerateContent?alt=sse&key={api_key}"
        gen_config = {
            "temperature": 0.4,
            "maxOutputTokens": 8192
        }
        if "2.5" in model_name or "2.0" in model_name:
            gen_config["thinkingConfig"] = {"thinkingBudget": 0}

        payload = {
            "contents": contents if contents else [
                {
                    "parts": [{"text": f"Instructions: {system_instruction}\n\nText:\n{user_text}"}]
                }
            ],
            "generationConfig": gen_config
        }
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        emitted_any = False
        try:
            with urllib.request.urlopen(req, timeout=12) as resp:
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
            if e.code in (404, 429, 500, 502, 503, 504) and not emitted_any:
                continue
            raise e
        except Exception as e:
            last_err = e
            if not emitted_any:
                continue
            break

    if last_err:
        raise last_err
    return False

def stream_groq(api_key, system_instruction, user_text, messages=None):
    url = "https://api.groq.com/openai/v1/chat/completions"
    last_err = None
    for model_name in GROQ_CANDIDATE_MODELS:
        payload = {
            "model": model_name,
            "messages": messages if messages else [
                {"role": "system", "content": system_instruction},
                {"role": "user", "content": user_text}
            ],
            "temperature": 0.4,
            "max_tokens": 8192,
            "stream": True
        }
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {api_key}",
                "User-Agent": "Mozilla/5.0"
            },
            method="POST"
        )
        emitted_any = False
        try:
            with urllib.request.urlopen(req, timeout=25) as resp:
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
                                emitted_any = True
                        except Exception:
                            continue
            return True
        except urllib.error.HTTPError as e:
            last_err = e
            if e.code in (404, 429, 500, 502, 503, 504) and not emitted_any:
                continue
            raise e
        except Exception as e:
            last_err = e
            if not emitted_any:
                continue
            break
    if last_err:
        raise last_err
    return False

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
MEMORY_PATH = os.path.expanduser("~/.config/caelestia/assistant_memory.json")

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

LEARNER_PROFILE_PATH = os.path.expanduser("~/.config/caelestia/learner_profile.json")

def get_learner_profile_injection():
    if not os.path.exists(LEARNER_PROFILE_PATH):
        return ""
    try:
        with open(LEARNER_PROFILE_PATH, "r", encoding="utf-8") as f:
            prof = json.load(f)
        active_ctx = prof.get("active_context") or "unknown workspace"
        weakest = ", ".join(prof.get("weakest_domains", [])) or "none identified yet"
        blindspots_list = prof.get("blindspots", [])
        blindspots = "; ".join(blindspots_list[:4]) if blindspots_list else "none recorded"
        return (
            f"USER PROFILE: The user is currently working on [{active_ctx}]. "
            f"Their weakest areas are [{weakest}]. "
            f"They frequently fail on [{blindspots}]. "
            f"Tailor your answers to their level. "
            f"If they ask about a known blindspot, explicitly point it out.\n"
        )
    except Exception:
        return ""

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

def get_active_workspace_context():
    try:
        raw_clients = subprocess.check_output(["hyprctl", "-j", "clients"], text=True, stderr=subprocess.DEVNULL)
        clients = json.loads(raw_clients)
        candidates = [c for c in clients if c.get("class") != "org.quickshell" and "Assistant" not in c.get("title", "")]
        candidates.sort(key=lambda x: x.get("focusHistoryID", 999))
        if not candidates:
            return ""

        win = candidates[0]
        title = win.get("title", "").strip()
        cls = win.get("class", "").strip()
        pid = win.get("pid")

        parts = []
        if cls:
            parts.append(f"Editor/App: {cls}")
        if title:
            parts.append(f"Active Window/File: {title}")

        if pid:
            try:
                cwd = os.path.realpath(f"/proc/{pid}/cwd")
                if os.path.exists(cwd):
                    parts.append(f"Project Path: {cwd}")
                    git_dir = os.path.join(cwd, ".git")
                    if os.path.exists(git_dir):
                        branch = subprocess.check_output(
                            ["git", "-C", cwd, "branch", "--show-current"],
                            text=True, stderr=subprocess.DEVNULL
                        ).strip()
                        if branch:
                            parts.append(f"Git Branch: {branch}")
            except Exception:
                pass

        if parts:
            return f"[CURRENT DEVELOPER WORKSPACE: {' | '.join(parts)}]\n(Tailor your answer directly to this project, file, and technology.)\n"
        return ""
    except Exception:
        return ""

FOLLOWUP_TRIGGERS = {
    "it", "this", "that", "these", "those", "they", "them", "why", "how", "what", "which",
    "instead", "more", "example", "examples", "explain", "expand", "clarify",
    "difference", "versus", "vs", "better", "worse", "and", "but", "so",
    "can", "could", "would", "should", "does", "do", "is", "are"
}

def is_topic_shift(new_question, thread, topic_anchor=""):
    if not thread or len(thread) == 0:
        return False
    words = re.findall(r'[a-zA-Z0-9_\-\.]+', (new_question or "").lower())
    if len(words) <= 4:
        return False
    early_words = set(words[:3])
    if any(w in {"it", "this", "that", "these", "those", "they", "them"} for w in early_words):
        return False
    thread_text = topic_anchor or ""
    for t in thread:
        thread_text += " " + (t.get("content", "") if isinstance(t, dict) else str(t))
    thread_tokens = set(re.findall(r'[a-zA-Z0-9_\-\.]{3,}', thread_text.lower()))
    content_tokens = [w for w in words if len(w) >= 3 and w not in FOLLOWUP_TRIGGERS]
    if len(content_tokens) < 3:
        return False
    overlap = sum(1 for w in content_tokens if w in thread_tokens)
    ratio = overlap / len(content_tokens)
    return ratio < 0.12 and len(content_tokens) >= 3

def touch_matching_knowledge_cards(query):
    """Chat-to-Card Exposure: update last_touched date when user asks a question matching KnowledgeNode."""
    if not query or len(str(query).strip()) < 3:
        return
    words = [w.lower() for w in re.findall(r"[a-zA-Z0-9_]{3,}", str(query)) if w.lower() not in STOP_WORDS]
    if not words:
        return
    try:
        if not os.path.exists(MEMORY_PATH):
            return
        with open(MEMORY_PATH, "r", encoding="utf-8") as f:
            cards = json.load(f)
        if not isinstance(cards, list):
            return
        touched = False
        now_iso = datetime.now(timezone.utc).isoformat()
        for c in cards:
            if isinstance(c, dict) and c.get("type") == "knowledge":
                title_words = (c.get("title") or c.get("topic") or "").lower()
                tags_str = " ".join(c.get("tags") or []).lower()
                if any(w in title_words or w in tags_str for w in words):
                    c["last_touched"] = now_iso
                    touched = True
        if touched:
            tmp = MEMORY_PATH + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(cards, f, indent=2, ensure_ascii=False)
            os.replace(tmp, MEMORY_PATH)
    except Exception:
        pass

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

def generate_chat_title_and_tags(prompt_text, answer_text):
    prompt_snippet = (prompt_text or "").strip()[:500]
    answer_snippet = (answer_text or "").strip()[:500]

    config = load_config()
    gemini_key = config.get("gemini_key", "").strip()

    title_prompt = (
        f"User: {prompt_snippet}\n"
        f"Assistant: {answer_snippet}"
    )

    if gemini_key:
        try:
            url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={gemini_key}"
            body = json.dumps({
                "contents": [{"parts": [{"text": title_prompt}]}],
                "generationConfig": {
                    "temperature": 0.2,
                    "maxOutputTokens": 150,
                    "thinkingConfig": {"thinkingBudget": 0},
                    "responseMimeType": "application/json",
                    "responseSchema": {
                        "type": "OBJECT",
                        "properties": {
                            "title": {"type": "STRING", "description": "3 to 5 word topic title"},
                            "tags": {"type": "ARRAY", "items": {"type": "STRING"}, "description": "1 to 3 lowercase topic tags"}
                        },
                        "required": ["title", "tags"]
                    }
                }
            }).encode("utf-8")
            req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                content = data["candidates"][0]["content"]["parts"][0]["text"]
                parsed = json.loads(content)
                if isinstance(parsed, dict) and "title" in parsed:
                    clean_title = str(parsed.get("title", "")).strip().strip('"').strip("'")
                    raw_tags = parsed.get("tags", [])
                    clean_tags = [str(t).strip().lower() for t in raw_tags if str(t).strip()] if isinstance(raw_tags, list) else []
                    if clean_title:
                        return {"title": clean_title, "tags": clean_tags}
        except Exception:
            pass

    # Fallback heuristic
    words = re.sub(r'[\n\r`#*]+', ' ', prompt_snippet).strip().split()
    fallback = " ".join(words[:5]) if len(words) > 5 else " ".join(words)
    return {"title": (fallback.capitalize() or "New Chat"), "tags": ["general"]}

def main():
    if len(sys.argv) < 2:
        emit({"type": "error", "error_type": "generic", "message": "Usage: assistant_api.py <action> [args...]"})
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "save_config":
        gemini_key = sys.argv[2] if len(sys.argv) > 2 else ""
        groq_key = sys.argv[3] if len(sys.argv) > 3 else ""
        provider = sys.argv[4] if len(sys.argv) > 4 else None
        max_chars = sys.argv[5] if len(sys.argv) > 5 else None
        emit(save_config(gemini_key, groq_key, provider, max_chars))
        sys.exit(0)

    if cmd == "save_profile":
        profile_json_str = sys.argv[2] if len(sys.argv) > 2 else "{}"
        try:
            profile_data = json.loads(profile_json_str)
            emit(save_profile(profile_data))
        except Exception as e:
            emit({"type": "error", "message": f"Failed to save profile: {e}"})
        sys.exit(0)

    if cmd == "title_chat":
        prompt_text = sys.argv[2] if len(sys.argv) > 2 else ""
        answer_text = sys.argv[3] if len(sys.argv) > 3 else ""
        res = generate_chat_title_and_tags(prompt_text, answer_text)
        print(json.dumps(res), flush=True)
        sys.exit(0)

    action = cmd
    mode = "auto"
    thread_raw = "[]"
    topic_anchor = ""
    extra_context = ""
    positional = []
    i = 2
    while i < len(sys.argv):
        arg = sys.argv[i]
        if arg == "--mode" and i + 1 < len(sys.argv):
            mode = sys.argv[i + 1]
            i += 2
        elif arg == "--thread" and i + 1 < len(sys.argv):
            thread_raw = sys.argv[i + 1]
            i += 2
        elif arg == "--anchor" and i + 1 < len(sys.argv):
            topic_anchor = sys.argv[i + 1]
            i += 2
        elif arg == "--context" and i + 1 < len(sys.argv):
            extra_context = sys.argv[i + 1]
            i += 2
        else:
            positional.append(arg)
            i += 1

    text = positional[0] if len(positional) > 0 else ""
    custom_prompt = positional[1] if len(positional) > 1 else ""

    thread = []
    try:
        parsed_thread = json.loads(thread_raw)
        if isinstance(parsed_thread, list):
            thread = parsed_thread
    except Exception:
        thread = []

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

    if action == "ask" and len(thread) > 0 and mode != "standalone":
        if is_topic_shift(custom_prompt, thread, topic_anchor):
            mode = "standalone"
            thread = []
            topic_anchor = ""
            print(json.dumps({"type": "topic_shift", "topic": (custom_prompt or "")[:60]}), flush=True)

    # Trim thread to last 6 message pairs (12 turns) to prevent token bloat
    MAX_THREAD_TURNS = 12
    if len(thread) > MAX_THREAD_TURNS:
        thread = thread[-MAX_THREAD_TURNS:]

    is_followup = (action == "ask" and mode == "followup" and len(thread) > 0)
    user_payload = text_to_process

    if action == "ask":
        if is_followup:
            anchor_text = topic_anchor.strip() if topic_anchor else (text_to_process[:350].strip() if text_to_process else "")
            anchor_context = f"[Originating Topic & Reference Material: {anchor_text}]\n" if anchor_text else ""
            system_instruction = (
                f"You are an expert technical reading assistant continuing an active inquiry with the user.\n"
                f"{anchor_context}"
                f"Directly and concisely answer the user's follow-up question based on the whole discussion and reference material. "
                f"Synthesize the prior discussion without re-explaining settled definitions unless requested. "
                f"Focus specifically on the new aspect requested (e.g., concrete examples, edge cases, deeper breakdown)."
            )
            user_payload = custom_prompt if custom_prompt else text_to_process
        elif custom_prompt and text_to_process.strip():
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

    if action == "ask":
        touch_matching_knowledge_cards(custom_prompt or text_to_process)

    learner_injection = get_learner_profile_injection()
    if learner_injection:
        system_instruction = f"{learner_injection}\n{system_instruction}"

    profile_prefix = get_profile_prompt_prefix()
    if profile_prefix:
        system_instruction = f"{profile_prefix}\n{system_instruction}"

    workspace_context = get_active_workspace_context()
    if workspace_context:
        system_instruction = f"{workspace_context}\n{system_instruction}"

    if extra_context:
        system_instruction = f"{extra_context}\n{system_instruction}"

    latex_symbol_rule = (
        "Formatting rules: Always output standard Unicode characters directly for symbols and arrows "
        "(e.g., →, ←, ↔, ⇒, ⇐, ⇔, ≈, ≠, ≤, ≥, ×, ·) instead of LaTeX math syntax like $\\rightarrow$ or \\rightarrow. "
        "Never use raw LaTeX delimiters ($...$) or macros for arrows or basic symbols in plain text."
    )
    system_instruction = f"{system_instruction}\n{latex_symbol_rule}"

    recalled_item = find_relevant_history(text_to_process, custom_prompt) if not is_followup else None
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

    gemini_contents = None
    groq_messages = None

    if is_followup:
        # Groq: OpenAI-style messages array as-is
        groq_messages = [{"role": "system", "content": system_instruction}]
        for turn in thread:
            t_role = "assistant" if turn.get("role") == "assistant" else "user"
            groq_messages.append({"role": t_role, "content": turn.get("content", "")})
        groq_messages.append({"role": "user", "content": user_payload})

        # Gemini: convert to contents format (user/model, parts[{text}])
        gemini_contents = []
        first_user = True
        for turn in thread:
            g_role = "model" if turn.get("role") == "assistant" else "user"
            t_content = turn.get("content", "")
            if first_user and g_role == "user":
                t_content = f"Instructions: {system_instruction}\n\n{t_content}"
                first_user = False
            gemini_contents.append({"role": g_role, "parts": [{"text": t_content}]})

        final_user_text = user_payload
        if first_user:
            final_user_text = f"Instructions: {system_instruction}\n\n{final_user_text}"
        gemini_contents.append({"role": "user", "parts": [{"text": final_user_text}]})

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
                stream_gemini(key, system_instruction, user_payload, gemini_contents)
            elif prov_name == "groq":
                stream_groq(key, system_instruction, user_payload, groq_messages)

            success = True
            break
        except urllib.error.HTTPError as e:
            last_http_code = e.code
            last_err_str = str(e)
            continue
        except Exception as e:
            last_err_str = str(e)
            continue

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
