#!/usr/bin/env python3
import sys
import json
import os
import urllib.request
import urllib.parse
import urllib.error
import subprocess

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

def call_gemini(api_key, system_instruction, user_text):
    # Verified working models in current environment
    candidate_models = [
        "gemini-3.5-flash-lite",
        "gemini-3.1-flash-lite",
        "gemini-flash-latest"
    ]
    last_err = None
    for model_name in candidate_models:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:generateContent"
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
            headers={
                "Content-Type": "application/json",
                "x-goog-api-key": api_key
            },
            method="POST"
        )
        try:
            with urllib.request.urlopen(req, timeout=12) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                candidates = data.get("candidates", [])
                if candidates and "content" in candidates[0]:
                    parts = candidates[0]["content"].get("parts", [])
                    if parts:
                        return "".join(p.get("text", "") for p in parts)
        except urllib.error.HTTPError as e:
            last_err = e
            # Only retry next model if 404 (not found) or 503 (transient overload)
            if e.code in (404, 503):
                continue
            # If 400, 401, 403 (Invalid key or quota issue), re-raise immediately
            raise e
        except Exception as e:
            last_err = e
            break

    if last_err:
        raise last_err
    return "No response generated."

def call_groq(api_key, system_instruction, user_text):
    url = "https://api.groq.com/openai/v1/chat/completions"
    payload = {
        "model": "llama-3.3-70b-versatile",
        "messages": [
            {"role": "system", "content": system_instruction},
            {"role": "user", "content": user_text}
        ],
        "temperature": 0.4,
        "max_tokens": 1024
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
        data = json.loads(resp.read().decode("utf-8"))
        choices = data.get("choices", [])
        if choices and "message" in choices[0]:
            return choices[0]["message"].get("content", "")
    return "No response generated."

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "Usage: assistant_api.py <action> [args...]"}))
        sys.exit(1)

    cmd = sys.argv[1]

    # Subcommand: secure config save via argv
    if cmd == "save_config":
        gemini_key = sys.argv[2] if len(sys.argv) > 2 else ""
        groq_key = sys.argv[3] if len(sys.argv) > 3 else ""
        print(json.dumps(save_config(gemini_key, groq_key)))
        sys.exit(0)

    action = cmd
    text = sys.argv[2] if len(sys.argv) > 2 else ""
    custom_prompt = sys.argv[3] if len(sys.argv) > 3 else ""

    config = load_config()
    gemini_key = config.get("gemini_key", "").strip()
    groq_key = config.get("groq_key", "").strip()
    primary = config.get("primary", "gemini").lower()

    if not gemini_key and not groq_key:
        print(json.dumps({
            "error": "NO_API_KEY",
            "message": "Please configure your Gemini or Groq API key in ~/.config/caelestia/assistant.json"
        }))
        sys.exit(0)

    system_instruction = PROMPTS.get(action, PROMPTS["explain"])
    user_payload = text
    if action == "ask" and custom_prompt:
        user_payload = f"Context text:\n{text}\n\nUser Question: {custom_prompt}"

    result = None
    used_provider = ""
    error_msg = ""
    is_auth_error = False

    # Determine execution order based on config primary
    providers = []
    if primary == "groq":
        if groq_key: providers.append(("groq", groq_key))
        if gemini_key: providers.append(("gemini", gemini_key))
    else:
        if gemini_key: providers.append(("gemini", gemini_key))
        if groq_key: providers.append(("groq", groq_key))

    for prov_name, key in providers:
        if prov_name == "gemini":
            try:
                result = call_gemini(key, system_instruction, user_payload)
                used_provider = "Gemini Flash"
                break
            except urllib.error.HTTPError as e:
                if e.code in (400, 401, 403):
                    is_auth_error = True
                error_msg = f"Gemini error: {e}"
            except Exception as e:
                error_msg = f"Gemini error: {e}"
        elif prov_name == "groq":
            try:
                result = call_groq(key, system_instruction, user_payload)
                used_provider = "Groq Llama 3.3"
                break
            except urllib.error.HTTPError as e:
                if e.code in (400, 401, 403):
                    is_auth_error = True
                error_msg += f" | Groq error: {e}"
            except Exception as e:
                error_msg += f" | Groq error: {e}"

    if result:
        print(json.dumps({
            "success": True,
            "provider": used_provider,
            "content": result.strip()
        }))
    else:
        err_type = "AUTH_ERROR" if is_auth_error else "API_CALL_FAILED"
        print(json.dumps({
            "error": err_type,
            "message": error_msg or "Failed to connect to AI providers."
        }))

if __name__ == "__main__":
    main()
