#!/usr/bin/env python3
"""Look up real lyrics for the playing track on LRCLIB.

Used by services/BetterLyrics.qml after the Better Lyrics API has nothing. It never asks an
AI model for lyrics or timing: it returns LRCLIB's own timed lyrics, LRCLIB's plain lyrics
(shown unsynced), or nothing.

Prints one JSON object:
  {"status": "synced" | "plain" | "instrumental" | "none",
   "lines": [{"time": seconds, "text": str}],   # synced only; "" text = instrumental gap
   "plain": str,                                 # plain only
   "source": "LRCLIB", "approximate": bool, "reason": str,
   "match": {"id", "trackName", "artistName", "albumName", "duration", "durationDelta"}}
"""

import argparse
import hashlib
import json
import os
import re
import sys
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

CACHE_VERSION = 2
# New directory on purpose: the old ~/.cache/caelestia/ai_lyrics holds Gemini-generated
# results that must not be shown again.
CACHE_DIR = os.path.expanduser("~/.cache/caelestia/lrclib_lyrics")
API = "https://lrclib.net/api"
USER_AGENT = "caelestia-shell lyrics (https://github.com/mohssine0e/caelestia_shell)"
TIMEOUT = 5
MAX_SEARCHES = 6

# A search result counts as the same recording when its duration is this close. LRCLIB's own
# /api/get uses the same +-2 s window.
EXACT_DURATION_DELTA = 2.0
# Results up to this far off are accepted only when title, artist and version all match, and are
# marked approximate (typically a music video with a longer intro). A fixed offset can fix those.
APPROX_DURATION_DELTA = 15.0

# Labels that change the words or their timing. A result must carry the same set as the track.
VERSION_LABELS = [
    "live", "acoustic", "remix", "unplugged", "instrumental", "demo", "cover", "slowed",
    "sped up", "speed up", "nightcore", "karaoke", "acapella", "a cappella", "orchestral",
    "piano version", "extended", "reverb",
]

# Words that only describe the upload, never the recording.
NOISE_WORDS = [
    "official music video", "official video", "official audio", "official lyric video",
    "official visualizer", "lyric video", "lyrics video", "music video", "visualizer",
    "visualiser", "official", "video", "audio", "lyrics", "lyric", "clip", "hd", "hq", "4k",
    "mv", "exclusive", "remastered", "remaster", "with lyrics", "paroles",
    "\u062d\u0635\u0631\u064a\u0627\u064b", "\u062d\u0635\u0631\u064a\u0627",  # exclusive
    "\u0641\u064a\u062f\u064a\u0648 \u0643\u0644\u064a\u0628", "\u0641\u064a\u062f\u064a\u0648",  # video clip, video
    "\u0643\u0644\u064a\u0628", "\u0643\u0644\u0645\u0627\u062a",  # clip, lyrics
    "\u0623\u063a\u0646\u064a\u0629", "\u0627\u0644\u0631\u0633\u0645\u064a\u0629",  # song, official
    "\u0627\u0644\u0646\u0633\u062e\u0629 \u0627\u0644\u0623\u0635\u0644\u064a\u0629",  # original version
]

BRACKET_RE = re.compile(r"[\(\[\{\uFF08\u3010]([^\)\]\}\uFF09\u3011]*)[\)\]\}\uFF09\u3011]")


# ---------------------------------------------------------------------------------------------
# Text helpers

def _word_re(words):
    alts = sorted((re.escape(w) for w in words), key=len, reverse=True)
    return re.compile(r"(?<![\w])(?:" + "|".join(alts) + r")(?![\w])", re.IGNORECASE)


_NOISE_RE = _word_re(NOISE_WORDS)
_VERSION_RE = _word_re(VERSION_LABELS)


def normalize(text: str) -> str:
    """Lowercase, strip accents, Arabic diacritics and tatweel, punctuation and extra spaces."""
    t = unicodedata.normalize("NFKD", text or "")
    t = "".join(ch for ch in t if not unicodedata.combining(ch))
    t = re.sub(r"[\u064B-\u065F\u0670\u0640]", "", t)  # harakat, superscript alef, tatweel
    t = t.replace("\u0623", "\u0627").replace("\u0625", "\u0627").replace("\u0622", "\u0627")
    t = t.casefold()
    t = re.sub(r"[^\w\s]", " ", t)
    return " ".join(t.split())


def _clean_group(content: str) -> str:
    """Remove noise words from one bracket's content; what is left is kept."""
    rest = _NOISE_RE.sub(" ", content)
    rest = re.sub(r"\b(19|20)\d{2}\b", " ", rest) if not _VERSION_RE.search(rest) else rest
    rest = re.sub(r"\s+", " ", rest).strip(" -:_|/,.")
    return rest


def version_labels(title: str) -> frozenset:
    """Version labels found in brackets or after a ' - ' separator. A bare word in the title
    itself ("Live Forever") is part of the song name, not a label."""
    found = set()
    zones = [m.group(1) for m in BRACKET_RE.finditer(title or "")]
    parts = re.split(r"\s+[-\u2013\u2014]\s+", BRACKET_RE.sub(" ", title or ""))
    zones.extend(parts[1:])
    for z in zones:
        for m in _VERSION_RE.finditer(z):
            label = m.group(0).lower()
            label = {"speed up": "sped up", "a cappella": "acapella"}.get(label, label)
            found.add(label)
    return frozenset(found)


def clean_title(title: str, artist: str = "") -> str:
    """Drop upload noise but keep version labels: "Song (Live Acoustic Video)" -> "Song (Live Acoustic)"."""
    def repl(m):
        kept = _clean_group(m.group(1))
        return f" ({kept})" if kept else " "

    t = BRACKET_RE.sub(repl, title or "")
    t = re.sub(r"\s+", " ", t).strip(" -:_|")
    if artist:
        for a in split_artists(artist):
            if len(a) >= 2 and t.lower().startswith(a.lower()):
                stripped = t[len(a):].lstrip(" -:_|\u2013\u2014")
                if stripped:
                    t = stripped
                break
    return t.strip() or (title or "").strip()


def base_title(title: str) -> str:
    """Song name only: no brackets at all, no ' - suffix'."""
    t = BRACKET_RE.sub(" ", title or "")
    t = re.split(r"\s+[-\u2013\u2014]\s+", t)[0] if " - " in t or "\u2013" in t or "\u2014" in t else t
    return " ".join(t.split()).strip(" -:_|")


def split_artists(artist: str):
    parts = re.split(r"\s*(?:[|/,&;\u060C]|\bfeat\.?|\bft\.?|\bx\b|\u00D7)\s*", artist or "", flags=re.IGNORECASE)
    return [p.strip() for p in parts if p and p.strip()]


def should_skip_lyrics(artist: str, title: str, album: str) -> bool:
    """Recitations, podcasts, trailers and similar uploads have no song lyrics to look up.
    Keywords match whole words only, so "Dua Lipa" or "Good News" are not skipped."""
    t = (title or "").lower().strip()
    a = (artist or "").lower().strip()
    al = (album or "").lower().strip()
    if not t:
        return True

    religious_title_words = [
        "quran", "qur'an", "surah", "sura", "juz", "tafsir", "ayah", "ayat", "recitation",
        "tilawat", "tilawa", "adhan", "azan", "ruqyah", "khutbah",
    ]
    reciters = [
        "mishary", "abdul basit", "abdulbasit", "alafasy", "al-afasy", "sudais", "shuraim",
        "al-ghamdi", "minshawi", "al-minshawi", "hussary", "al-hussary", "maher al-muaiqly",
        "islam sobhi", "yasser al-dosari", "mufti menk", "zakir naik",
    ]
    if _word_re(religious_title_words).search(t) or _word_re(religious_title_words).search(al):
        return True
    if _word_re(reciters).search(a) or _word_re(reciters).search(t):
        return True

    non_music = [
        "trailer", "teaser", "episode", "podcast", "interview", "documentary", "audiobook",
        "gameplay", "walkthrough", "livestream", "tutorial", "vlog", "stand-up", "ted talk",
        "full movie",
    ]
    if _word_re(non_music).search(t):
        return True

    generic_artists = ["youtube", "unknown", "unknown artist", "various artists", "various", "n/a", "none"]
    if (not a or a in generic_artists) and not al:
        return True
    return False


# ---------------------------------------------------------------------------------------------
# LRC parsing (same rules as utils/scripts/lyrics.js parseLrc)

_STAMP = re.compile(r"^\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]")
_ANY_STAMP = re.compile(r"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]")
_WORD_STAMP = re.compile(r"<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>")
_OFFSET = re.compile(r"^\s*\[offset:\s*([+-]?\d+(?:\.\d+)?)\s*\]\s*$", re.IGNORECASE)


def parse_lrc(lrc_text: str):
    """Every timestamp on a line becomes its own entry; [offset:+ms] shifts lyrics earlier.
    Empty timed lines are kept with text "" (instrumental gaps)."""
    entries = []
    offset_ms = 0.0
    order = 0
    for row in (lrc_text or "").splitlines():
        off = _OFFSET.match(row)
        if off:
            offset_ms = float(off.group(1))
            continue
        rest = row.lstrip()
        times = []
        while True:
            m = _STAMP.match(rest)
            if not m:
                break
            frac = float("0." + m.group(3)) if m.group(3) else 0.0
            times.append(int(m.group(1)) * 60 + int(m.group(2)) + frac)
            rest = rest[m.end():]
        if not times:
            continue
        text = _ANY_STAMP.sub("", _WORD_STAMP.sub("", rest))
        text = " ".join(text.replace("\u00A0", " ").split())
        for t in times:
            entries.append((t, order, text))
            order += 1

    shift = offset_ms / 1000.0
    entries = [(max(0.0, round(t - shift, 3)), o, txt) for t, o, txt in entries]
    entries.sort(key=lambda e: (e[0], e[1]))
    return [{"time": t, "text": txt} for t, _, txt in entries]


# ---------------------------------------------------------------------------------------------
# Matching

class Track:
    def __init__(self, artist: str, title: str, album: str, duration: float):
        self.artist = artist or ""
        self.title = title or ""
        self.album = album or ""
        self.duration = float(duration or 0)
        self.labels = version_labels(self.title)
        self.artists = split_artists(self.artist)
        self.titles = self._title_variants()

    def _title_variants(self):
        out = []
        # Bilingual uploads: "Arabic title | Latin title".
        for seg in re.split(r"\s*[|/]\s*", self.title):
            if not seg.strip():
                continue
            for v in (base_title(clean_title(seg, self.artist)), base_title(seg)):
                n = normalize(v)
                if len(n) >= 2 and n not in out:
                    out.append(n)
        for m in re.findall(r"[\u0600-\u06FF][\u0600-\u06FF\s]{2,}", self.title):
            n = normalize(_NOISE_RE.sub(" ", m))
            if len(n) >= 3 and n not in out:
                out.append(n)
        return out


def _title_matches(track: Track, name: str) -> bool:
    cand = normalize(base_title(name))
    if not cand:
        return False
    for t in track.titles:
        if cand == t:
            return True
        if min(len(cand), len(t)) >= 4 and (cand in t or t in cand):
            return True
    return False


def _artist_matches(track: Track, name: str) -> bool:
    cand = normalize(name)
    if not cand:
        return False
    for a in track.artists:
        n = normalize(a)
        if n and (n == cand or (min(len(n), len(cand)) >= 3 and (n in cand or cand in n))):
            return True
    return False


def assess(track: Track, item: dict):
    """Returns (accepted, approximate, delta, score) for one LRCLIB record."""
    name = str(item.get("trackName") or item.get("name") or "")
    artist = str(item.get("artistName") or "")
    labels = set(version_labels(name))
    if item.get("instrumental"):
        labels.discard("instrumental")
    track_labels = set(track.labels) - {"instrumental"}
    if labels != track_labels:
        return False, False, None, 0

    title_ok = _title_matches(track, name)
    artist_ok = _artist_matches(track, artist)
    try:
        cand_duration = float(item.get("duration") or 0)
    except (TypeError, ValueError):
        cand_duration = 0.0

    if track.duration > 0 and cand_duration > 0:
        delta = abs(cand_duration - track.duration)
        if delta <= EXACT_DURATION_DELTA and (title_ok or artist_ok):
            score = 100 - delta * 5 + (10 if title_ok else 0) + (10 if artist_ok else 0)
            return True, False, round(delta, 2), score
        if delta <= APPROX_DURATION_DELTA and title_ok and artist_ok:
            return True, True, round(delta, 2), 50 - delta
        return False, False, round(delta, 2), 0

    # Duration unknown on either side: title and artist must both match.
    if title_ok and artist_ok:
        return True, True, None, 40
    return False, False, None, 0


def choose_best(track: Track, results):
    """Best acceptable record, preferring timed lyrics, then exact duration, then score."""
    best = None
    best_key = None
    for item in results or []:
        if not isinstance(item, dict):
            continue
        has_synced = bool(item.get("syncedLyrics"))
        has_plain = bool(item.get("plainLyrics"))
        if not (has_synced or has_plain or item.get("instrumental")):
            continue
        ok, approx, delta, score = assess(track, item)
        if not ok:
            continue
        key = (1 if has_synced else 0, 0 if approx else 1, score)
        if best_key is None or key > best_key:
            best, best_key = (item, approx, delta), key
    return best


def build_result(track: Track, chosen, reason: str = ""):
    if not chosen:
        return {"status": "none", "source": "LRCLIB", "lines": [], "plain": "", "approximate": False, "reason": reason or "no matching recording"}
    item, approx, delta = chosen
    match = {
        "id": item.get("id"),
        "trackName": item.get("trackName") or item.get("name") or "",
        "artistName": item.get("artistName") or "",
        "albumName": item.get("albumName") or "",
        "duration": item.get("duration"),
        "durationDelta": delta,
    }
    base = {"source": "LRCLIB", "match": match, "approximate": bool(approx), "reason": reason}
    if item.get("syncedLyrics"):
        lines = parse_lrc(item["syncedLyrics"])
        if any(line["text"] for line in lines):
            return dict(base, status="synced", lines=lines, plain="")
    if item.get("plainLyrics"):
        return dict(base, status="plain", lines=[], plain=str(item["plainLyrics"]))
    if item.get("instrumental"):
        return dict(base, status="instrumental", lines=[], plain="")
    return {"status": "none", "source": "LRCLIB", "lines": [], "plain": "", "approximate": False, "reason": "match has no lyrics"}


# ---------------------------------------------------------------------------------------------
# Network

def http_get_json(path: str, params: dict):
    url = f"{API}/{path}?" + urllib.parse.urlencode({k: v for k, v in params.items() if v not in (None, "")})
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def search_queries(track: Track):
    """Structured searches first, then free-text ones for bilingual or decorated titles."""
    out = []
    primary_artist = track.artists[0] if track.artists else track.artist
    cleaned = clean_title(track.title, track.artist)
    out.append({"track_name": cleaned, "artist_name": primary_artist})
    if base_title(cleaned) != cleaned:
        out.append({"track_name": base_title(cleaned), "artist_name": primary_artist})
    for seg in re.split(r"\s*[|/]\s*", track.title):
        seg_clean = base_title(clean_title(seg, track.artist))
        if seg_clean:
            out.append({"q": f"{primary_artist} {seg_clean}".strip()})
    for m in re.findall(r"[\u0600-\u06FF][\u0600-\u06FF\s]{2,}", track.title):
        n = " ".join(_NOISE_RE.sub(" ", m).split())
        if len(n) >= 3:
            out.append({"q": n})
    seen = set()
    unique = []
    for q in out:
        key = json.dumps(q, sort_keys=True, ensure_ascii=False)
        if key not in seen and any(v.strip() for v in q.values()):
            seen.add(key)
            unique.append(q)
    return unique[:MAX_SEARCHES]


def lookup(track: Track, get_json=http_get_json):
    errors = 0
    # 1. Exact lookups: the player's own metadata, then the cleaned title (version labels kept).
    gets = [(track.title, track.artist)]
    cleaned = clean_title(track.title, track.artist)
    primary = track.artists[0] if track.artists else track.artist
    if (cleaned, primary) not in gets:
        gets.append((cleaned, primary))
    for title, artist in gets:
        if not title or not artist:
            continue
        params = {"track_name": title, "artist_name": artist, "album_name": track.album or None}
        if track.duration > 0:
            params["duration"] = int(round(track.duration))
        try:
            item = get_json("get", params)
        except Exception:
            errors += 1
            continue
        chosen = choose_best(track, [item] if isinstance(item, dict) else [])
        if chosen and chosen[0].get("syncedLyrics") and not chosen[1]:
            return build_result(track, chosen, "exact")

    # 2. Searches, filtered strictly: same version labels, duration within the window.
    pool = []
    for q in search_queries(track):
        try:
            res = get_json("search", q)
        except Exception:
            errors += 1
            continue
        if isinstance(res, list):
            pool.extend(res)
            chosen = choose_best(track, pool)
            if chosen and chosen[0].get("syncedLyrics") and not chosen[1]:
                return build_result(track, chosen, "search")
    chosen = choose_best(track, pool)
    if chosen:
        return build_result(track, chosen, "search")
    reason = "network error" if errors and not pool else "no matching recording"
    return build_result(track, None, reason)


# ---------------------------------------------------------------------------------------------
# Cache

def cache_path(track: Track) -> str:
    key = json.dumps([CACHE_VERSION, track.artist.strip().lower(), track.title.strip().lower(), track.album.strip().lower(), int(round(track.duration))], ensure_ascii=False)
    return os.path.join(CACHE_DIR, hashlib.sha256(key.encode("utf-8")).hexdigest()[:24] + ".json")


def read_cache(track: Track):
    try:
        with open(cache_path(track), "r", encoding="utf-8") as f:
            data = json.load(f)
        if data.get("version") == CACHE_VERSION and data.get("result", {}).get("status") in ("synced", "plain", "instrumental"):
            return data["result"]
    except (OSError, ValueError, AttributeError):
        pass
    return None


def write_cache(track: Track, result: dict) -> None:
    if result.get("status") not in ("synced", "plain", "instrumental"):
        return  # misses and network errors are retried next time
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        path = cache_path(track)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"version": CACHE_VERSION, "result": result}, f, ensure_ascii=False)
        os.replace(tmp, path)
    except OSError:
        pass


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Find real timed or plain lyrics on LRCLIB (no AI).")
    parser.add_argument("--artist", default="")
    parser.add_argument("--title", required=True)
    parser.add_argument("--album", default="")
    parser.add_argument("--duration", type=float, default=0.0, help="Track length in seconds (0 if unknown)")
    parser.add_argument("--force", action="store_true", help="Ignore the cache")
    args = parser.parse_args(argv)

    track = Track(args.artist, args.title, args.album, args.duration)
    if should_skip_lyrics(args.artist, args.title, args.album):
        result = build_result(track, None, "not a song")
    else:
        result = None if args.force else read_cache(track)
        if result is None:
            result = lookup(track)
            write_cache(track, result)
    sys.stdout.write(json.dumps(result, ensure_ascii=False))
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
