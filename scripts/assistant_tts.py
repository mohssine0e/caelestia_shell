#!/home/mohssine/piper-venv/bin/python3
"""
Caelestia Neural Text-to-Speech (TTS)
Replaces espeak-ng with natural, studio-quality neural voices
via Edge-TTS with streaming playback and offline fallback.
"""

import sys
import os
import re
import json
import signal
import asyncio
import subprocess

CONFIG_PATH = os.path.expanduser("~/.config/caelestia/assistant.json")
DEFAULT_VOICE_EN = "en-US-AriaNeural"
DEFAULT_VOICE_AR = "ar-SA-HamedNeural"
DEFAULT_VOICE_FR = "fr-FR-VivienneNeural"

player_proc = None

def signal_handler(sig, frame):
    global player_proc
    if player_proc and player_proc.poll() is None:
        try:
            player_proc.terminate()
            player_proc.kill()
        except Exception:
            pass
    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

def load_voices():
    en = DEFAULT_VOICE_EN
    ar = DEFAULT_VOICE_AR
    fr = DEFAULT_VOICE_FR
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                en = data.get("tts_voice_en", en)
                ar = data.get("tts_voice_ar", ar)
                fr = data.get("tts_voice_fr", fr)
        except Exception:
            pass
    return en, ar, fr

def detect_voice(text, voice_en, voice_ar, voice_fr):
    # Check Arabic characters
    if re.search(r"[\u0600-\u06FF]", text):
        return voice_ar, "ar"
    
    # Check French characters or common French markers
    if re.search(r"[éàèùâêîôûçëïüœæ]", text, re.IGNORECASE) or re.search(r"\b(bonjour|merci|s'il|vous|nous|dans|pour|avec|c'est)\b", text, re.IGNORECASE):
        return voice_fr, "fr"
        
    return voice_en, "en-us"

def clean_markdown(text):
    # Remove code blocks
    text = re.sub(r"```[\s\S]*?```", " ", text)
    text = re.sub(r"`[^`]*`", " ", text)
    # Remove markdown links [text](url) -> text
    text = re.sub(r"\[([^\]]+)\]\([^\)]+\)", r"\1", text)
    # Remove header markers, bullets, bold/italic symbols
    text = re.sub(r"[#*_~>|]", " ", text)
    # Collapse multiple whitespaces
    text = re.sub(r"\s+", " ", text).strip()
    return text

async def speak_edge(text, voice):
    global player_proc
    import edge_tts
    
    communicate = edge_tts.Communicate(text, voice)
    
    # Check if mpv is available for zero-latency direct streaming
    has_mpv = subprocess.run(["which", "mpv"], capture_output=True).returncode == 0
    
    if has_mpv:
        player_proc = subprocess.Popen(
            ["mpv", "--no-video", "--really-quiet", "-"],
            stdin=subprocess.PIPE
        )
        try:
            async for chunk in communicate.stream():
                if chunk["type"] == "audio" and player_proc.stdin:
                    player_proc.stdin.write(chunk["data"])
                    player_proc.stdin.flush()
            if player_proc.stdin:
                player_proc.stdin.close()
            player_proc.wait()
            return True
        except Exception as e:
            if player_proc:
                try:
                    player_proc.kill()
                except Exception:
                    pass
            return False
    else:
        # Fallback: save to temp file and play with pw-play
        temp_audio = "/tmp/caelestia_tts.mp3"
        await communicate.save(temp_audio)
        player_proc = subprocess.Popen(["pw-play", temp_audio])
        player_proc.wait()
        return True

def fallback_espeak(text, espeak_lang):
    global player_proc
    try:
        player_proc = subprocess.Popen(["espeak-ng", "-v", espeak_lang, text[:500]])
        player_proc.wait()
    except Exception:
        pass

def main():
    if len(sys.argv) < 2:
        return
        
    raw_text = " ".join(sys.argv[1:])
    clean_text = clean_markdown(raw_text)
    if not clean_text:
        return
        
    # Cap maximum characters for a single spoken answer (e.g. 1500 chars)
    if len(clean_text) > 1500:
        clean_text = clean_text[:1500] + "..."
        
    voice_en, voice_ar, voice_fr = load_voices()
    selected_voice, espeak_lang = detect_voice(clean_text, voice_en, voice_ar, voice_fr)
    
    try:
        success = asyncio.run(speak_edge(clean_text, selected_voice))
        if not success:
            fallback_espeak(clean_text, espeak_lang)
    except Exception as e:
        # Offline or network issue -> fall back to espeak-ng
        fallback_espeak(clean_text, espeak_lang)

if __name__ == "__main__":
    main()

