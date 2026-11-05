#!/usr/bin/env python3
"""
scripts/assistant_common.py
Shared core constants, parsing utilities, and persistence for Caelestia HUD Assistant.
Strictly decoupled: Pure Python 3 standard library.
"""

import sys
import os
import json
import ast
import re
from datetime import datetime, timezone, timedelta

# ---------------------------------------------------------
# File Paths
# ---------------------------------------------------------
CONFIG_PATH = os.path.expanduser("~/.config/caelestia/assistant.json")
HISTORY_PATH = os.path.expanduser("~/.config/caelestia/assistant_history.json")
MEMORY_PATH = os.path.expanduser("~/.config/caelestia/assistant_memory.json")
PROFILE_PATH = os.path.expanduser("~/.config/caelestia/assistant_profile.json")
LEARNER_PROFILE_PATH = os.path.expanduser("~/.config/caelestia/learner_profile.json")

# ---------------------------------------------------------
# Candidate Models
# ---------------------------------------------------------
GEMINI_CANDIDATE_MODELS = [
    "gemini-2.5-flash",
    "gemini-flash-latest"
]

GROQ_CANDIDATE_MODELS = [
    "openai/gpt-oss-120b",
    "qwen/qwen3.8-27b"
]

# ---------------------------------------------------------
# Regex & Stop Words
# ---------------------------------------------------------
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

# ---------------------------------------------------------
# Standard IPC & I/O
# ---------------------------------------------------------
def emit(obj):
    try:
        sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        pass

def load_config():
    cfg = {"gemini_key": "", "groq_key": "", "primary": "gemini", "max_chars": 12000}
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
                    if "preferred_provider" in data and not data.get("primary"):
                        cfg["primary"] = data["preferred_provider"]
        except Exception:
            pass
    if not cfg.get("gemini_key"):
        cfg["gemini_key"] = os.environ.get("GEMINI_API_KEY", "")
    if not cfg.get("groq_key"):
        cfg["groq_key"] = os.environ.get("GROQ_API_KEY", "")
    return cfg

def load_profile():
    if not os.path.exists(PROFILE_PATH):
        return None
    try:
        with open(PROFILE_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, dict):
                return data
    except Exception:
        pass
    return None

def save_profile(profile_data):
    os.makedirs(os.path.dirname(PROFILE_PATH), exist_ok=True)
    with open(PROFILE_PATH, "w", encoding="utf-8") as f:
        json.dump(profile_data, f, indent=2, ensure_ascii=False)
    return {"type": "success", "message": "Profile saved."}

def load_learner_profile():
    if os.path.exists(LEARNER_PROFILE_PATH):
        try:
            with open(LEARNER_PROFILE_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, dict):
                    return data
        except Exception:
            pass
    return {
        "active_context": "unknown workspace",
        "strongest_domains": [],
        "weakest_domains": [],
        "blindspots": [],
        "domain_scores": {},
        "last_updated": datetime.now(timezone.utc).isoformat()
    }

def save_learner_profile(profile_data):
    os.makedirs(os.path.dirname(LEARNER_PROFILE_PATH), exist_ok=True)
    temp_path = f"{LEARNER_PROFILE_PATH}.tmp.{os.getpid()}"
    with open(temp_path, "w", encoding="utf-8") as f:
        json.dump(profile_data, f, indent=2, ensure_ascii=False)
    os.replace(temp_path, LEARNER_PROFILE_PATH)

# ---------------------------------------------------------
# Token & Keyword Extraction
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

def normalize_concept_key(text):
    if not text:
        return ""
    t = re.sub(r"\([^)]*\)", "", str(text))
    t = re.sub(r"[\u2010-\u2015\u2212\-]+", " ", t)
    return re.sub(r"[^a-z0-9]+", "", t.lower())

# ---------------------------------------------------------
# Robust JSON Parsing
# ---------------------------------------------------------
def clean_json_response(raw_text):
    if not raw_text:
        return ""
    match = JSON_CLEAN_PATTERN.search(raw_text)
    if match:
        return match.group(1).strip()
    return raw_text.strip()

def parse_json_safely(raw_text):
    cleaned = clean_json_response(raw_text)
    try:
        return json.loads(cleaned)
    except Exception:
        pass
    first_bracket = min(
        [pos for pos in [cleaned.find('{'), cleaned.find('[')] if pos != -1] or [-1]
    )
    last_bracket = max(cleaned.rfind('}'), cleaned.rfind(']'))
    if first_bracket != -1 and last_bracket != -1 and last_bracket > first_bracket:
        bracketed = cleaned[first_bracket:last_bracket+1]
        try:
            return json.loads(bracketed)
        except Exception:
            pass
        try:
            return ast.literal_eval(bracketed)
        except Exception:
            pass
    try:
        return ast.literal_eval(cleaned)
    except Exception:
        pass
    raise ValueError(f"Could not parse valid JSON from LLM output: {raw_text[:200]}")
