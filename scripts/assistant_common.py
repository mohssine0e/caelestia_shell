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
import tempfile
import shutil
import subprocess
from datetime import datetime, timezone, timedelta

# ---------------------------------------------------------
# File Paths
# ---------------------------------------------------------
CONFIG_PATH = os.path.expanduser("~/.config/caelestia/assistant.json")
HISTORY_PATH = os.path.expanduser("~/.config/caelestia/assistant_history.json")
MEMORY_PATH = os.path.expanduser("~/.config/caelestia/assistant_memory.json")
PROFILE_PATH = os.path.expanduser("~/.config/caelestia/assistant_profile.json")
LEARNER_PROFILE_PATH = os.path.expanduser("~/.config/caelestia/learner_profile.json")
SECRETS_PATH = os.path.expanduser("~/.config/caelestia/assistant_secrets.json")
SECRET_SERVICE_NAME = "caelestia-assistant"
SECRET_PROVIDERS = ("gemini", "groq")

# ---------------------------------------------------------
# Candidate Models
# ---------------------------------------------------------
GEMINI_CANDIDATE_MODELS = [
    "gemini-3.5-flash-lite",
    "gemini-3.1-flash-lite",
    "gemini-2.5-flash"
]

GROQ_CANDIDATE_MODELS = [
    "qwen/qwen3.8-27b",
    "openai/gpt-oss-120b"
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

def atomic_write_json(path, data):
    """Write private JSON atomically so a crash cannot truncate the prior file."""
    directory = os.path.dirname(path)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as current_file:
                json.load(current_file)
        except Exception:
            stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            backup_path = path + ".corrupt." + stamp
            shutil.copy2(path, backup_path)
            os.chmod(backup_path, 0o600)
    fd, temp_path = tempfile.mkstemp(prefix="." + os.path.basename(path) + ".", dir=directory)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp_path, path)
        os.chmod(path, 0o600)
    except Exception:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.unlink(temp_path)
        except OSError:
            pass
        raise

def load_config_document():
    data = {}
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                parsed = json.load(f)
                if isinstance(parsed, dict):
                    data = parsed
        except Exception:
            pass
    return data

def _secret_tool_enabled():
    return bool(shutil.which("secret-tool") and os.environ.get("DBUS_SESSION_BUS_ADDRESS"))

def _secret_tool_lookup(provider):
    if provider not in SECRET_PROVIDERS or not _secret_tool_enabled():
        return ""
    try:
        result = subprocess.run(
            ["secret-tool", "lookup", "service", SECRET_SERVICE_NAME, "provider", provider],
            capture_output=True, text=True, timeout=4, check=False,
        )
        return result.stdout.strip() if result.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""

def _load_private_file_credentials():
    try:
        with open(SECRETS_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            return {p: str(data.get(p, "")).strip() for p in SECRET_PROVIDERS if str(data.get(p, "")).strip()}
    except (OSError, ValueError):
        pass
    return {}

def credential_status(include_values=False):
    raw = load_config_document()
    private = _load_private_file_credentials()
    values, sources = {}, {}
    for provider, env_name in (("gemini", "GEMINI_API_KEY"), ("groq", "GROQ_API_KEY")):
        legacy = str(raw.get(f"{provider}_key") or raw.get(f"{provider}_api_key") or "").strip()
        candidates = (
            (os.environ.get(env_name, "").strip(), "environment"),
            (_secret_tool_lookup(provider), "secret-service"),
            (private.get(provider, ""), "private-file"),
            (legacy, "legacy-config"),
        )
        values[provider], sources[provider] = next(((v, s) for v, s in candidates if v), ("", "none"))
    active = {s for s in sources.values() if s != "none"}
    backend = next((s for s in ("legacy-config", "private-file", "secret-service", "environment") if s in active),
                   "secret-service" if _secret_tool_enabled() else "private-file")
    status = {
        "backend": backend,
        "gemini_configured": bool(values["gemini"]), "groq_configured": bool(values["groq"]),
        "gemini_source": sources["gemini"], "groq_source": sources["groq"],
        "needs_migration": "legacy-config" in active,
    }
    if include_values:
        status["values"] = values
    return status

def load_config():
    data = load_config_document()
    cfg = {"gemini_key": "", "groq_key": "", "primary": "gemini", "max_chars": 12000}
    cfg.update(data)
    if "preferred_provider" in data and not data.get("primary"):
        cfg["primary"] = data["preferred_provider"]
    credentials = credential_status(include_values=True)
    cfg["gemini_key"] = credentials["values"]["gemini"]
    cfg["groq_key"] = credentials["values"]["groq"]
    cfg["credential_backend"] = credentials["backend"]
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
    atomic_write_json(PROFILE_PATH, profile_data)
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
    atomic_write_json(LEARNER_PROFILE_PATH, profile_data)

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
