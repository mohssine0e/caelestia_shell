.pragma library

// Pure lyrics helpers shared by BetterLyrics, LyricsSource and the desktop overlay.
// No QML types are used here, so tests/lyrics_logic.test.js can run this file under node.

// Same lead the C++ Lyrics service uses (k_indexFudge): a line becomes current 100 ms
// before its timestamp, so both lyric sources switch lines at the same moment.
var LEAD_SECONDS = 0.1;

// A silence of at least this long between two timed lines becomes an instrumental gap.
var GAP_MIN_SECONDS = 4.0;

// Before the first line, the overlay shows notes only for an intro of at least this long.
var INTRO_NOTES_MIN_SECONDS = 3.0;

// Whole-line markers that mean "no vocals here". Matched against the entire line only, so
// "Don't break my heart" or "Let me introduce myself" stay lyrics.
var MARKER_WORDS = [
    "instrumental", "instrumental break", "intro", "outro", "interlude", "solo",
    "guitar solo", "piano solo", "bridge instrumental", "break", "music", "musical break"
];

function cleanText(text) {
    return String(text === undefined || text === null ? "" : text).replace(/\u00A0/g, " ").replace(/\s+/g, " ").trim();
}

function isInstrumentalMarker(text) {
    var s = cleanText(text);
    if (s.length === 0)
        return true;
    // Only music symbols, dots, ellipses and spaces.
    if (/^[\s\u266A-\u266F\u2669.\u2026\-_*~]+$/.test(s))
        return true;
    // The whole line is one bracketed or bare marker word, e.g. "[Instrumental]", "(Guitar Solo)".
    var inner = s.toLowerCase().replace(/^[\[(\{<\s*]+/, "").replace(/[\])\}>\s*.:]+$/, "").trim();
    inner = inner.replace(/^[\u266A-\u266F\u2669\s]+|[\u266A-\u266F\u2669\s]+$/g, "");
    return MARKER_WORDS.indexOf(inner) !== -1;
}

function isArabic(text) {
    return /[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]/.test(text || "");
}

// True when at least 40% of the non-empty lines contain Arabic script. Decided once per track
// so font size and row height do not change from line to line.
function isMostlyArabic(lines) {
    var total = 0;
    var arabic = 0;
    for (var i = 0; i < (lines ? lines.length : 0); i++) {
        var t = typeof lines[i] === "string" ? lines[i] : (lines[i] ? lines[i].text : "");
        if (!t)
            continue;
        total++;
        if (isArabic(t))
            arabic++;
    }
    return total > 0 && arabic / total >= 0.4;
}

// TTML time expressions: "27.395", "00:00:27.395", "1:02.5", "1250ms", "12s".
function parseTime(value) {
    if (value === undefined || value === null)
        return NaN;
    var s = String(value).trim();
    if (s === "")
        return NaN;
    if (/ms$/i.test(s))
        return parseFloat(s) / 1000;
    if (/s$/i.test(s))
        return parseFloat(s);
    var parts = s.split(":");
    var sec = NaN;
    if (parts.length === 3)
        sec = parseInt(parts[0], 10) * 3600 + parseInt(parts[1], 10) * 60 + parseFloat(parts[2].replace(",", "."));
    else if (parts.length === 2)
        sec = parseInt(parts[0], 10) * 60 + parseFloat(parts[1].replace(",", "."));
    else
        sec = parseFloat(s.replace(",", "."));
    return isFinite(sec) ? sec : NaN;
}

// LRC parser. Handles several timestamps on one line ([00:12.00][01:30.50]Chorus), [mm:ss],
// [mm:ss.x], [mm:ss.xxx] and [mm:ss:xx], ignores metadata tags, and applies the [offset:] tag.
// LRC offset is in milliseconds and a positive value shows lyrics earlier, so it is subtracted.
// Empty timed lines are kept as "" (instrumental gaps).
// Returns { lines: [{ time, text }], offsetMs }.
function parseLrc(text) {
    var out = [];
    var offsetMs = 0;
    if (!text)
        return { lines: out, offsetMs: 0 };

    var rows = String(text).split(/\r?\n/);
    var stampRe = /\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g;
    var order = 0;
    for (var r = 0; r < rows.length; r++) {
        var row = rows[r];
        var off = /^\s*\[offset:\s*([+-]?\d+(?:\.\d+)?)\s*\]\s*$/i.exec(row);
        if (off) {
            offsetMs = parseFloat(off[1]) || 0;
            continue;
        }

        // Collect the run of timestamps at the start of the row.
        var times = [];
        var rest = row.replace(/^\s+/, "");
        var lead;
        while ((lead = /^\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/.exec(rest)) !== null) {
            var frac = lead[3] ? parseFloat("0." + lead[3]) : 0;
            times.push(parseInt(lead[1], 10) * 60 + parseInt(lead[2], 10) + frac);
            rest = rest.slice(lead[0].length);
        }
        if (times.length === 0)
            continue;

        // Word-level tags (<00:12.34>) are not used for display.
        var lyric = cleanText(rest.replace(/<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>/g, "").replace(stampRe, ""));
        for (var i = 0; i < times.length; i++)
            out.push({ time: times[i], text: lyric, order: order++ });
    }

    var shift = offsetMs / 1000;
    for (var j = 0; j < out.length; j++)
        out[j].time = Math.max(0, Math.round((out[j].time - shift) * 1000) / 1000);

    out.sort(function (a, b) {
        return a.time - b.time || a.order - b.order;
    });
    var lines = [];
    for (var k = 0; k < out.length; k++)
        lines.push({ time: out[k].time, text: out[k].text });
    return { lines: lines, offsetMs: offsetMs };
}

// Sorts timed lines, turns marker lines into "" gaps, inserts gaps where an end time leaves a
// long silence before the next line (or before the end of the track), and merges repeated gaps.
// Input items: { time, text, end? }. Output items: { time, text }.
function normalizeLines(parsed, duration) {
    var items = [];
    for (var i = 0; i < (parsed ? parsed.length : 0); i++) {
        var it = parsed[i];
        if (!it || !isFinite(it.time))
            continue;
        items.push({ time: Number(it.time), end: isFinite(it.end) ? Number(it.end) : NaN, text: cleanText(it.text), order: i });
    }
    items.sort(function (a, b) {
        return a.time - b.time || a.order - b.order;
    });

    var out = [];
    function push(time, text) {
        var gap = text.length === 0;
        if (gap && out.length > 0 && out[out.length - 1].text.length === 0)
            return; // already in a gap
        if (gap && out.length === 0)
            return; // the intro before the first line is handled separately
        out.push({ time: time, text: text });
    }

    for (var j = 0; j < items.length; j++) {
        var cur = items[j];
        push(cur.time, isInstrumentalMarker(cur.text) ? "" : cur.text);
        if (isFinite(cur.end) && cur.end > cur.time) {
            var nextTime = j + 1 < items.length ? items[j + 1].time : (duration > 0 ? duration : NaN);
            if (isFinite(nextTime) && nextTime - cur.end >= GAP_MIN_SECONDS)
                push(cur.end, "");
        }
    }

    // A trailing gap with nothing after it is kept: it clears the last line during an outro.
    return out;
}

function hasVocalLines(lines) {
    for (var i = 0; i < (lines ? lines.length : 0); i++) {
        if (lines[i] && lines[i].text && lines[i].text.length > 0)
            return true;
    }
    return false;
}

// Last line whose start is <= position - offset + lead, or -1 before the first line.
// offset is in seconds; a positive offset delays the lyrics.
function indexForTime(lines, position, offset) {
    if (!lines || lines.length === 0)
        return -1;
    var target = Number(position) - (Number(offset) || 0) + LEAD_SECONDS;
    var lo = 0;
    var hi = lines.length - 1;
    var ans = -1;
    while (lo <= hi) {
        var mid = (lo + hi) >> 1;
        if (lines[mid].time <= target) {
            ans = mid;
            lo = mid + 1;
        } else {
            hi = mid - 1;
        }
    }
    return ans;
}

// Player position at which line `index` starts, including the offset.
function timeForIndex(lines, index, offset) {
    if (!lines || index < 0 || index >= lines.length)
        return -1;
    return Math.max(0, lines[index].time + (Number(offset) || 0));
}

// Milliseconds until the next line becomes current at playback `rate`, or -1 after the last.
function msUntilNextLine(lines, position, offset, rate) {
    var idx = indexForTime(lines, position, offset);
    if (!lines || idx + 1 >= lines.length)
        return -1;
    var r = rate > 0 ? rate : 1;
    var target = Number(position) - (Number(offset) || 0) + LEAD_SECONDS;
    return Math.max(0, (lines[idx + 1].time - target) * 1000 / r);
}

// Rows for the overlay: previous, current, next. Gaps are returned as "".
function rowsForIndex(lines, index) {
    var n = lines ? lines.length : 0;
    function at(i) {
        return i >= 0 && i < n ? lines[i].text : "";
    }
    if (index < 0)
        return { previous: "", current: "", next: at(0) };
    return { previous: at(index - 1), current: at(index), next: at(index + 1) };
}

// Decides what the desktop overlay shows. Input fields:
//   hasPlayer, covered      - a player exists; a tiled/fullscreen window covers the desktop
//   playback                - "playing" | "paused" | "stopped"
//   pauseGrace              - true for ~1.5 s after a pause, so a quick pause does not flicker
//   status                  - "idle" | "loading" | "synced" | "plain" | "instrumental" | "none"
//   loadingDelayPassed      - loading has lasted long enough (~400 ms) to be worth showing
//   noticeActive            - the short "no synced lyrics" notice is still within its time
//   lines, index            - timed lines and the current index (synced only)
// Returns { visible, mode } where mode is "hidden" | "loading" | "lyrics" | "notes" | "notice".
function overlayState(s) {
    var hidden = { visible: false, mode: "hidden" };
    if (!s || !s.hasPlayer || s.covered)
        return hidden;
    var playback = s.playback || "stopped";
    if (playback === "stopped")
        return hidden;
    var playing = playback === "playing";
    if (!playing && !s.pauseGrace)
        return hidden;

    switch (s.status) {
    case "loading":
        return playing && s.loadingDelayPassed ? { visible: true, mode: "loading" } : hidden;
    case "instrumental":
        return { visible: true, mode: "notes" };
    case "plain":
    case "none":
        return playing && s.noticeActive ? { visible: true, mode: "notice" } : hidden;
    case "synced": {
        var lines = s.lines || [];
        if (lines.length === 0)
            return hidden;
        var idx = typeof s.index === "number" ? s.index : -1;
        if (idx < 0)
            return lines[0].time >= INTRO_NOTES_MIN_SECONDS ? { visible: true, mode: "notes" } : { visible: true, mode: "lyrics" };
        if (idx >= lines.length)
            return hidden;
        if (!lines[idx].text)
            return { visible: true, mode: "notes" };
        return { visible: true, mode: "lyrics" };
    }
    default:
        return hidden;
    }
}
