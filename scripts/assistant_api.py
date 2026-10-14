#!/usr/bin/env python3
import sys
import json
import os
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
    cfg = {"gemini_key": "", "groq_key": "", "primary": "gemini"}
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                cfg.update(json.load(f))
        except Exception:
            pass
    if os.environ.get("GEMINI_API_KEY"):
        cfg["gemini_key"] = os.environ.get("GEMINI_API_KEY")
    if os.environ.get("GROQ_API_KEY"):
        cfg["groq_key"] = os.environ.get("GROQ_API_KEY")
    return cfg

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

    user_payload = text
    if action == "ask":
        if custom_prompt and text.strip():
            system_instruction = (
                "You are an expert reading assistant. Answer the user's question clearly and concisely "
                "using the provided context text as reference when relevant."
            )
            user_payload = f"Context text:\n{text}\n\nUser Question: {custom_prompt}"
        elif custom_prompt:
            system_instruction = (
                "You are a helpful, knowledgeable, and concise AI assistant. "
                "Directly and accurately answer the user's question."
            )
            user_payload = custom_prompt
        elif text.strip():
            system_instruction = (
                "You are an expert assistant. Explain or answer regarding the provided text clearly and concisely."
            )
            user_payload = text
    else:
        system_instruction = PROMPTS.get(action, PROMPTS["explain"])

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
            emit({"type": "start", "provider": prov_label})
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
            "latency_ms": elapsed_ms
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
