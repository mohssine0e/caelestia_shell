#!/usr/bin/env python3
import os
import sys
import json
import re
import hashlib
import argparse
import urllib.request
import urllib.parse
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import assistant_common
except ImportError:
    assistant_common = None

CACHE_DIR = os.path.expanduser("~/.cache/caelestia/ai_lyrics")
os.makedirs(CACHE_DIR, exist_ok=True)

GEMINI_MODELS = ["gemini-flash-lite-latest", "gemini-2.5-flash-lite"]


def get_cache_path(artist: str, title: str) -> str:
    key = f"{artist.lower().strip()}_{title.lower().strip()}".encode("utf-8")
    h = hashlib.sha256(key).hexdigest()[:16]
    return os.path.join(CACHE_DIR, f"{h}.json")


def should_skip_lyrics(artist: str, title: str, album: str) -> bool:
    t = (title or "").lower().strip()
    a = (artist or "").lower().strip()
    al = (album or "").lower().strip()

    if not t:
        return True

    # 1. Quran / Religious media
    quran_keywords = [
        "quran", "surah", "sura", "juz", "tafsir", "ayah", "ayat",
        "recitation", "tilawat", "adhan", "azan", "nasheed", "ruqyah",
        "dua", "khutbah", "salat"
    ]
    religious_artists = [
        "sheikh", "imam", "mishary", "abdul basit", "abdulbasit",
        "alafasy", "al-afasy", "sudais", "shuraim", "ghamdi", "al-ghamdi",
        "minshawi", "al-minshawi", "hussary", "al-hussary", "maher al-muaiqly",
        "islam sobhi", "yasser al-dosari", "mufti menk", "zakir naik"
    ]
    if any(kw in t or kw in al or kw in a for kw in quran_keywords):
        return True
    if any(ra in a or ra in t for ra in religious_artists):
        return True

    # 2. Movies / TV / Podcasts / Non-music videos
    non_music_keywords = [
        "trailer", "teaser", "episode", "podcast", "interview", "documentary",
        "audiobook", "gameplay", "walkthrough", "livestream", "news",
        "tutorial", "review", "vlog", "stand-up", "ted talk", "full movie"
    ]
    if any(nm in t for nm in non_music_keywords):
        return True

    # "Official Video" without "music", "song", "audio", or "lyric"
    if "official video" in t and not any(k in t for k in ["music video", "official music", "audio", "lyric", "song"]):
        studio_channels = ["marvel", "warner", "paramount", "sony pictures", "netflix", "hbo", "universal pictures", "ign", "movieclips"]
        if any(s in a for s in studio_channels):
            return True

    # 3. Generic / Unknown
    generic_artists = ["youtube", "unknown", "unknown artist", "various artists", "various", "n/a", "none"]
    if (not a or a in generic_artists) and not al:
        return True

    return False


def clean_title(title: str, artist: str = "") -> str:
    t = re.sub(r"\(.*?(official|video|audio|lyric|visualizer|clip|remaster|hd|4k|mv).*?\)", "", title, flags=re.IGNORECASE)
    t = re.sub(r"\[.*?(official|video|audio|lyric|visualizer|clip|remaster|hd|4k|mv).*?\]", "", t, flags=re.IGNORECASE)
    if artist and t.lower().startswith(artist.lower()):
        t = t[len(artist):].lstrip(" -:_|")
    return t.strip() or title.strip()


def parse_lrc(lrc_text: str):
    lines = []
    for line in lrc_text.splitlines():
        match = re.match(r"^\[(\d+):(\d+(?:\.\d+)?)\](.*)", line.strip())
        if match:
            m = int(match.group(1))
            s = float(match.group(2))
            txt = match.group(3).strip()
            if txt:
                lines.append({"time": round(m * 60 + s, 2), "text": txt})
    lines.sort(key=lambda x: x["time"])
    return lines


def fetch_lrclib(artist: str, title: str, duration: float = 0):
    cleaned = clean_title(title, artist)
    queries = [
        f"{artist} {cleaned}".strip(),
        cleaned,
        title
    ]
    seen_queries = set()
    for q in queries:
        if not q or q in seen_queries:
            continue
        seen_queries.add(q)
        try:
            url = "https://lrclib.net/api/search?q=" + urllib.parse.quote(q)
            req = urllib.request.Request(url, headers={"User-Agent": "CaelestiaShell/1.0"})
            with urllib.request.urlopen(req, timeout=4) as r:
                results = json.loads(r.read().decode())
                if not isinstance(results, list) or len(results) == 0:
                    continue

                best = None
                if duration > 0:
                    for item in results:
                        if item.get("syncedLyrics") and abs(item.get("duration", 0) - duration) < 6:
                            best = item
                            break

                if not best:
                    for item in results:
                        if item.get("syncedLyrics"):
                            best = item
                            break

                if best and best.get("syncedLyrics"):
                    parsed = parse_lrc(best["syncedLyrics"])
                    if len(parsed) > 0:
                        return parsed, "lrclib-synced"

                # Plain lyrics fallback for word-level AI alignment
                plain = next((it.get("plainLyrics") for it in results if it.get("plainLyrics")), None)
                if plain:
                    return plain, "lrclib-plain"
        except Exception:
            continue
    return None, None


def clean_json_text(text: str) -> str:
    text = text.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text, flags=re.IGNORECASE)
        text = re.sub(r"\s*```$", "", text)
    match = re.search(r"\[\s*\{.*\}\s*\]", text, re.DOTALL)
    if match:
        return match.group(0)
    return text


def is_valid_lyrics(parsed) -> bool:
    if not isinstance(parsed, list) or len(parsed) == 0:
        return False
    refusal_words = ["cannot provide", "not provided", "i am sorry", "i'm sorry", "copyright", "unable to provide", "as an ai"]
    combined = " ".join([str(item.get("text", "")).lower() for item in parsed[:5]])
    if any(w in combined for w in refusal_words):
        return False
    valid_lines = [item for item in parsed if isinstance(item, dict) and str(item.get("text", "")).strip()]
    if len(valid_lines) == 0:
        return False
    return True


def query_gemini_with_real_lyrics(api_key: str, artist: str, title: str, real_lyrics: str, duration: float):
    prompt = (
        "You are a precision audio-lyric synchronizer.\n"
        f"Track: \"{clean_title(title, artist)}\" by \"{artist}\"\n"
        f"Duration: {int(duration)} seconds\n\n"
        f"Verified lyrics:\n\"\"\"\n{real_lyrics}\n\"\"\"\n\n"
        "Output ONLY a raw valid JSON array. Each item represents a line.\n"
        "Format exactly like this:\n"
        "[{\"time\": 12.5, \"text\": \"Hello world\", \"words\": [{\"w\": \"Hello\", \"t\": 12.5}, {\"w\": \"world\", \"t\": 13.2}]}]\n\n"
        "Instructions:\n"
        "1. For EVERY line, break the text into individual words in the words array.\n"
        "2. Calculate the exact start time t for EVERY word based on the natural singing pace.\n"
        "3. If there is an instrumental intro/solo, output: {\"time\": 0.0, \"text\": \"♪\", \"words\": []}.\n"
        "4. Do not hallucinate lyrics. If unsure, output []."
    )
    for model in GEMINI_MODELS:
        try:
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
            req = urllib.request.Request(
                url,
                data=json.dumps({"contents": [{"parts": [{"text": prompt}]}]}).encode("utf-8"),
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=12) as resp:
                data = json.loads(resp.read().decode())
                content = data["candidates"][0]["content"]["parts"][0]["text"]
                cleaned = clean_json_text(content)
                parsed = json.loads(cleaned)
                if is_valid_lyrics(parsed):
                    return parsed
        except Exception:
            continue
    return None


def query_gemini(api_key: str, artist: str, title: str, album: str, duration: float):
    clean_t = clean_title(title, artist)
    prompt = (
        "You are a precision audio-lyric synchronizer.\n"
        f"Track: \"{clean_t}\" by \"{artist}\"\n"
        f"Duration: {int(duration)} seconds\n\n"
        "Output ONLY a raw valid JSON array. Each item represents a line.\n"
        "Format exactly like this:\n"
        "[{\"time\": 12.5, \"text\": \"Hello world\", \"words\": [{\"w\": \"Hello\", \"t\": 12.5}, {\"w\": \"world\", \"t\": 13.2}]}]\n\n"
        "Instructions:\n"
        "1. For EVERY line, break the text into individual words in the words array.\n"
        "2. Calculate the exact start time t for EVERY word based on the natural singing pace.\n"
        "3. If there is an instrumental intro/solo, output: {\"time\": 0.0, \"text\": \"♪\", \"words\": []}.\n"
        "4. Do not hallucinate lyrics. If unsure, output []."
    )
    for model in GEMINI_MODELS:
        try:
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
            req = urllib.request.Request(
                url,
                data=json.dumps({"contents": [{"parts": [{"text": prompt}]}]}).encode("utf-8"),
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=12) as resp:
                data = json.loads(resp.read().decode())
                content = data["candidates"][0]["content"]["parts"][0]["text"]
                cleaned = clean_json_text(content)
                parsed = json.loads(cleaned)
                if is_valid_lyrics(parsed):
                    return parsed
        except Exception:
            continue
    return None


def main():
    parser = argparse.ArgumentParser(description="Fetch accurate lyrics using LRCLIB with Gemini fallback and word-level timestamps")
    parser.add_argument("--artist", default="", help="Track artist")
    parser.add_argument("--title", required=True, help="Track title")
    parser.add_argument("--album", default="", help="Track album")
    parser.add_argument("--duration", type=float, default=180.0, help="Track duration in seconds")
    parser.add_argument("--offset", type=float, default=0.0, help="Manual timing offset in seconds")
    parser.add_argument("--force", action="store_true", help="Bypass cache")
    args = parser.parse_args()

    # Part 1: Strict Non-Music Filter
    if should_skip_lyrics(args.artist, args.title, args.album):
        print(json.dumps([{"time": 0.0, "text": "♪", "words": []}]))
        return

    cache_file = get_cache_path(args.artist, args.title)
    if not args.force and os.path.exists(cache_file):
        try:
            with open(cache_file, "r") as f:
                cached = json.load(f)
                if isinstance(cached, list) and len(cached) > 0:
                    # Apply offset if specified on cached results
                    if args.offset != 0.0:
                        for item in cached:
                            item["time"] = max(0.0, round(item.get("time", 0.0) + args.offset, 2))
                            for w in item.get("words", []):
                                w["t"] = max(0.0, round(w.get("t", 0.0) + args.offset, 2))
                    print(json.dumps(cached))
                    return
        except Exception:
            pass

    gemini_key = ""
    if assistant_common:
        cfg = assistant_common.load_config()
        gemini_key = cfg.get("gemini_key", "")
    if not gemini_key:
        gemini_key = os.environ.get("GEMINI_API_KEY", "")

    lyrics = None
    source = ""

    # 1. Primary: LRCLIB (10M+ verified human synced tracks, ~150ms)
    lrclib_res, lrclib_type = fetch_lrclib(args.artist, args.title, args.duration)
    if lrclib_type == "lrclib-synced":
        lyrics = lrclib_res
        source = "lrclib"
    elif lrclib_type == "lrclib-plain" and gemini_key:
        # Word-level alignment of genuine lyrics with Gemini
        lyrics = query_gemini_with_real_lyrics(gemini_key, args.artist, args.title, lrclib_res, args.duration)
        if lyrics:
            source = "lrclib-gemini-aligned"

    # 2. Secondary: Gemini AI direct lookup (with strict anti-hallucination check)
    if not lyrics and gemini_key:
        lyrics = query_gemini(gemini_key, args.artist, args.title, args.album, args.duration)
        if lyrics:
            source = "ai-gemini"

    if not lyrics:
        lyrics = [{"time": 0.0, "text": "♪", "words": []}]
        source = "none"

    # Part 3: JSON Parsing and Normalization with word-level timing
    normalized = []
    for item in lyrics:
        try:
            t = float(item.get("time", 0.0))
        except (ValueError, TypeError):
            continue
        txt = str(item.get("text", "")).strip()
        if not txt:
            continue

        lower_txt = txt.lower()
        if any(k in lower_txt for k in ["instrumental", "intro", "interlude", "solo", "outro", "break"]):
            txt = "♪"

        words_array = []
        if txt == "♪":
            words_array = []
        elif "words" in item and isinstance(item["words"], list) and len(item["words"]) > 0:
            for w in item["words"]:
                if isinstance(w, dict):
                    try:
                        wt = float(w.get("t", t)) if "t" in w else t
                        word_str = str(w.get("w", "")).strip()
                        if word_str:
                            words_array.append({"w": word_str, "t": round(wt, 2)})
                    except (ValueError, TypeError):
                        pass
        else:
            # Word-level interpolation for line-level sources (e.g. LRCLIB)
            line_words = txt.split()
            if line_words:
                est_span = 3.2
                step = est_span / max(1, len(line_words))
                words_array = [{"w": w, "t": round(max(0.0, t + i * step), 2)} for i, w in enumerate(line_words)]

        normalized.append({
            "time": max(0.0, t),
            "text": txt,
            "words": words_array
        })

    normalized.sort(key=lambda x: x["time"])

    # Deduplicate consecutive ♪ markers
    deduped = []
    for line in normalized:
        if line["text"] == "♪" and deduped and deduped[-1]["text"] == "♪":
            continue
        deduped.append(line)
    normalized = deduped

    # Ensure intro indicator if singing begins after 3 seconds
    if normalized and normalized[0]["time"] > 3.0:
        normalized.insert(0, {"time": 0.0, "text": "♪", "words": []})
    elif not normalized:
        normalized.append({"time": 0.0, "text": "♪", "words": []})

    # Part 4: Apply Manual Timing Offset
    offset = args.offset
    if offset != 0.0:
        for item in normalized:
            item["time"] = max(0.0, round(item["time"] + offset, 2))
            for w in item.get("words", []):
                w["t"] = max(0.0, round(w["t"] + offset, 2))

    # Cache successful lyrics
    if source in ("lrclib", "lrclib-gemini-aligned", "ai-gemini") and len(normalized) > 0:
        try:
            with open(cache_file, "w") as f:
                json.dump(normalized, f)
        except Exception:
            pass

    print(json.dumps(normalized))


if __name__ == "__main__":
    main()
