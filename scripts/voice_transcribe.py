#!/usr/bin/env python3
import sys
import os
import json
import base64
import urllib.request
import urllib.parse
import urllib.error
import subprocess

CONFIG_PATH = os.path.expanduser("~/.config/caelestia/assistant.json")

def load_keys():
    groq_key = ""
    gemini_key = ""
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                groq_key = (data.get("groq_key") or "").strip()
                gemini_key = (data.get("gemini_key") or "").strip()
        except Exception:
            pass
    return groq_key, gemini_key

def transcribe_groq(audio_path, api_key):
    url = "https://api.groq.com/openai/v1/audio/transcriptions"
    boundary = "----WebKitFormBoundary" + os.urandom(16).hex()
    
    with open(audio_path, "rb") as f:
        file_bytes = f.read()
        
    parts = []
    
    # Model: full whisper-large-v3 (32 layers, significantly stronger multilingual discrimination)
    parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-large-v3\r\n".encode("utf-8"))
    
    # Response format
    parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"response_format\"\r\n\r\njson\r\n".encode("utf-8"))
    
    # Strict greedy decoding (temperature 0.0 prevents speculative translation and hallucination)
    parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"temperature\"\r\n\r\n0.0\r\n".encode("utf-8"))
    
    # Multilingual vocabulary seed: primes Whisper to accept English, French, and Arabic/Darija verbatim
    prompt_seed = "English, Français, العربية, Darija."
    parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"prompt\"\r\n\r\n{prompt_seed}\r\n".encode("utf-8"))
    
    # File part
    filename = os.path.basename(audio_path)
    file_header = (
        f"--{boundary}\r\n"
        f"Content-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\n"
        f"Content-Type: audio/wav\r\n\r\n"
    ).encode("utf-8")
    parts.append(file_header + file_bytes + b"\r\n")
    
    parts.append(f"--{boundary}--\r\n".encode("utf-8"))
    body = b"".join(parts)
    
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Authorization", f"Bearer {api_key}")
    req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    req.add_header("User-Agent", "Mozilla/5.0 (X11; Linux x86_64)")
    
    with urllib.request.urlopen(req, timeout=12) as resp:
        res = json.loads(resp.read().decode("utf-8"))
        raw_text = res.get("text", "").strip()
        
        # Filter out common Whisper silence hallucinations
        cleaned = raw_text.lower().rstrip(".?! ")
        if cleaned in {"thank you", "thanks for watching", "subtitles by", "you", "merci"}:
            return ""
        return raw_text

def transcribe_gemini(audio_path, api_key):
    # Fallback online multimodal transcription via Gemini
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={api_key}"
    
    with open(audio_path, "rb") as f:
        audio_b64 = base64.b64encode(f.read()).decode("utf-8")
        
    payload = {
        "contents": [{
            "parts": [
                {"inlineData": {"mimeType": "audio/wav", "data": audio_b64}},
                {"text": "Transcribe the spoken audio verbatim in the exact language spoken (English, Français, or العربية/Darija). Never translate between languages. Output ONLY the plain transcription text with no commentary or markdown quotes."}
            ]
        }],
        "generationConfig": {
            "temperature": 0.0,
            "maxOutputTokens": 1024
        }
    }
    
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    
    with urllib.request.urlopen(req, timeout=12) as resp:
        res = json.loads(resp.read().decode("utf-8"))
        candidates = res.get("candidates", [])
        if candidates:
            parts = candidates[0].get("content", {}).get("parts", [])
            if parts:
                return parts[0].get("text", "").strip()
    return ""

def transcribe_offline(audio_path):
    # Check for whisper-cli (from whisper-cpp package)
    whisper_bin = None
    for b in ["whisper-cli", "whisper-cpp", "whisper"]:
        which = subprocess.run(["which", b], capture_output=True, text=True)
        if which.returncode == 0:
            whisper_bin = which.stdout.strip()
            break
            
    if not whisper_bin:
        return None
        
    cmd = [whisper_bin, "-f", audio_path, "--no-timestamps", "-nt"]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode == 0:
        return proc.stdout.strip()
    return None

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
        
    audio_file = sys.argv[1]
    if not os.path.exists(audio_file) or os.path.getsize(audio_file) < 500:
        sys.exit(0)
        
    groq_key, gemini_key = load_keys()
    text = ""
    
    # 1. Primary: Groq Whisper (ultra-fast, ~180ms)
    if groq_key:
        try:
            text = transcribe_groq(audio_file, groq_key)
        except Exception:
            text = ""
            
    # 2. Secondary online: Gemini (multimodal audio transcription)
    if not text and gemini_key:
        try:
            text = transcribe_gemini(audio_file, gemini_key)
        except Exception:
            text = ""
            
    # 3. Offline fallback: local whisper
    if not text:
        try:
            local_text = transcribe_offline(audio_file)
            if local_text:
                text = local_text
        except Exception:
            pass
            
    if text:
        text = text.strip()
        if (text.startswith('"') and text.endswith('"')) or (text.startswith("'") and text.endswith("'")):
            text = text[1:-1].strip()
        print(text)

if __name__ == "__main__":
    main()
