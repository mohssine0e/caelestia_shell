pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../utils/scripts/lyrics.js" as Logic

// Real-lyrics provider for the desktop overlay and the dashboard media tab (through LyricsSource).
//
// Order: Better Lyrics TTML, Better Lyrics QQ (QRC), then LRCLIB through scripts/lrclib_lyrics.py.
// An AI metadata helper may suggest an artist/title when catalog searches miss; it never supplies
// lyrics or timing. When only plain lyrics exist they are exposed as
// plain text (status "plain") and never given invented timestamps; when nothing matches, status is
// "none".
//
// Every request carries the serial of the track it was made for. A result that arrives after the
// track changed is dropped before it can be shown or cached, so an old song's lyrics never appear
// on, or get saved under, the next song.
//
// API: https://api.betterlyrics.org/getLyrics (TTML) and /qq/getLyrics (QRC fallback). Both are
// keyless for cache hits; BETTER_LYRICS_API_KEY unlocks uncached queries.
Singleton {
    id: root

    property bool enabled: true
    property string apiKey: ""

    property string trackKey: ""
    property string trackArtist: ""
    property string trackTitle: ""
    property string trackAlbum: ""
    property real trackDuration: 0

    // "idle" | "loading" | "synced" | "plain" | "instrumental" | "none"
    property string status: "idle"

    // [{ time: <seconds>, text: <line> }, ...] sorted by time. Text "" marks an instrumental gap.
    property var lines: []
    property var texts: []
    // Plain (unsynced) lyrics when no timed lyrics matched this recording.
    property string plainText: ""
    // True when the match is the same song and version but its length differs by more than 2 s
    // (for example a music video with a longer intro). The per-recording offset can correct it.
    property bool approximate: false
    property var matchInfo: null
    property string error: ""
    property string source: ""

    property int requestSerial: 0
    property var activeXhr: null
    property bool betterLyricsAuthDenied: false

    readonly property bool loading: status === "loading"
    readonly property bool hasLyrics: status === "synced" && lines.length > 0
    readonly property string effectiveApiKey: apiKey.length > 0 ? apiKey : (Quickshell.env("BETTER_LYRICS_API_KEY") || "")
    onEffectiveApiKeyChanged: betterLyricsAuthDenied = false

    // Results are kept for the session so skipping back to a track does not refetch it. Only real
    // answers are cached; misses and network errors are retried on the next play.
    property var cache: ({})

    // XMLHttpRequest.timeout covers Qt builds that honour it; this is the backstop for the ones
    // that do not.
    Timer {
        id: requestTimeout

        interval: 25000
        repeat: false

        onTriggered: {
            if (root.activeXhr)
                root.activeXhr.abort();
        }
    }

    function makeKey(artist: string, title: string, album: string, duration: real): string {
        return artist + "\u0001" + title + "\u0001" + album + "\u0001" + Math.round(duration);
    }

    function setTrack(artist: string, title: string, album: string, duration: real): void {
        if (!root.enabled) {
            root.clearTrack();
            return;
        }

        const a = String(artist ?? "");
        const t = String(title ?? "");
        const al = String(album ?? "");
        const d = Number(duration ?? 0);
        const key = root.makeKey(a, t, al, d);

        if (key === root.trackKey && root.status !== "idle")
            return;

        // Anything still running belongs to the previous track.
        root.cancelRequests();
        root.requestSerial += 1;

        root.trackArtist = a;
        root.trackTitle = t;
        root.trackAlbum = al;
        root.trackDuration = d;
        root.trackKey = key;
        root.error = "";

        const cached = root.cache[key];
        if (cached) {
            root.applyState(cached);
            return;
        }

        root.applyState({
            "status": t.length > 0 ? "loading" : "none",
            "lines": [],
            "plain": "",
            "source": "",
            "approximate": false,
            "match": null
        });
        if (t.length > 0) {
            if (root.betterLyricsAuthDenied)
                root.startLrclib(root.requestSerial);
            else
                root.fetchTtml(root.requestSerial, a, t, al, d);
        }
    }

    function clearTrack(): void {
        root.cancelRequests();
        root.requestSerial += 1;
        root.trackKey = "";
        root.trackArtist = "";
        root.trackTitle = "";
        root.trackAlbum = "";
        root.trackDuration = 0;
        root.error = "";
        root.applyState({
            "status": "idle",
            "lines": [],
            "plain": "",
            "source": "",
            "approximate": false,
            "match": null
        });
    }

    function cancelRequests(): void {
        requestTimeout.stop();
        if (root.activeXhr) {
            const xhr = root.activeXhr;
            root.activeXhr = null;
            try {
                xhr.abort();
            } catch (e) {}
        }
        lrclibProc.pendingSerial = -1;
        if (lrclibProc.running)
            lrclibProc.running = false;
    }

    function applyState(state: var): void {
        const lines = state.lines || [];
        const texts = [];
        for (let i = 0; i < lines.length; i++)
            texts.push(lines[i].text);
        root.lines = lines;
        root.texts = texts;
        root.plainText = state.plain || "";
        root.source = state.source || "";
        root.approximate = !!state.approximate;
        root.matchInfo = state.match || null;
        root.status = state.status || "idle";
    }

    // Index of the current line at player position `time`, with `offset` seconds (positive delays
    // the lyrics). Same 100 ms lead as the C++ Lyrics service.
    function indexForTime(time: real, offset: real): int {
        return Logic.indexForTime(root.lines, time, offset || 0);
    }

    function buildUrl(endpoint: string, artist: string, title: string, album: string, duration: real): string {
        let url = endpoint + "?s=" + encodeURIComponent(title) + "&a=" + encodeURIComponent(artist) + "&al=" + encodeURIComponent(album);
        if (isFinite(duration) && duration > 0)
            url += "&d=" + Math.round(duration);
        return url;
    }

    function getJson(url: string, serial: int, done: var): void {
        const xhr = new XMLHttpRequest();
        let finished = false;

        function finish(err, text) {
            if (finished)
                return;
            finished = true;
            if (root.activeXhr === xhr) {
                requestTimeout.stop();
                root.activeXhr = null;
            }
            done(err, text);
        }

        xhr.open("GET", url);
        if (root.effectiveApiKey.length > 0)
            xhr.setRequestHeader("X-API-Key", root.effectiveApiKey);
        xhr.timeout = 20000;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (serial !== root.requestSerial) {
                finish("stale", null);
                return;
            }
            if (xhr.status >= 200 && xhr.status < 300)
                finish(null, xhr.responseText);
            else
                finish("HTTP " + xhr.status, null);
        };
        xhr.ontimeout = function () {
            finish("timeout", null);
        };
        xhr.onerror = function () {
            finish("network error", null);
        };
        root.activeXhr = xhr;
        requestTimeout.restart();
        try {
            xhr.send();
        } catch (e) {
            finish("send failed", null);
        }
    }

    function fetchTtml(serial: int, artist: string, title: string, album: string, duration: real): void {
        const url = root.buildUrl("https://api.betterlyrics.org/getLyrics", artist, title, album, duration);
        root.getJson(url, serial, function (err, text) {
            if (serial !== root.requestSerial)
                return;
            if (err === "HTTP 401" || err === "HTTP 403") {
                root.betterLyricsAuthDenied = true;
                root.startLrclib(serial);
                return;
            }
            if (!err) {
                try {
                    const obj = JSON.parse(text);
                    const ttml = obj && obj.ttml ? String(obj.ttml) : "";
                    if (ttml.length > 0 && root.applyTimed(serial, root.parseTtml(ttml), "Better Lyrics (TTML)"))
                        return;
                } catch (e) {
                    // Fall through to the QRC endpoint.
                }
            }
            root.fetchQq(serial, artist, title, album, duration);
        });
    }

    function fetchQq(serial: int, artist: string, title: string, album: string, duration: real): void {
        const url = root.buildUrl("https://api.betterlyrics.org/qq/getLyrics", artist, title, album, duration);
        root.getJson(url, serial, function (err, text) {
            if (serial !== root.requestSerial)
                return;
            if (err === "HTTP 401" || err === "HTTP 403")
                root.betterLyricsAuthDenied = true;
            if (!err) {
                try {
                    const obj = JSON.parse(text);
                    const qrc = obj && obj.lyrics ? String(obj.lyrics) : "";
                    if (root.applyTimed(serial, root.cleanQrc(root.parseQrc(qrc), title, artist), "Better Lyrics (QQ)"))
                        return;
                } catch (e) {
                    // Fall through to LRCLIB.
                }
            }
            root.startLrclib(serial);
        });
    }

    // Normalises timed lines (markers become gaps, long silences become gaps) and applies them.
    // Returns false when nothing sung is left, so the caller can try the next source.
    function applyTimed(serial: int, parsed: var, src: string): bool {
        if (serial !== root.requestSerial)
            return true; // stale: stop the chain without touching the current track
        const lines = Logic.normalizeLines(parsed, root.trackDuration);
        if (!Logic.hasVocalLines(lines))
            return false;
        root.finish(serial, {
            "status": "synced",
            "lines": lines,
            "plain": "",
            "source": src,
            "approximate": false,
            "match": null
        });
        return true;
    }

    function finish(serial: int, state: var): void {
        if (serial !== root.requestSerial)
            return;
        root.applyState(state);
        root.error = state.status === "none" ? (state.reason || "No lyrics found") : "";
        if (state.status === "synced" || state.status === "plain" || state.status === "instrumental") {
            const cached = root.cache;
            cached[root.trackKey] = state;
            root.cache = cached;
        }
        console.info("Lyrics:", state.status, state.source || "", (state.lines || []).length, "lines for", root.trackArtist, "-", root.trackTitle);
    }

    function startLrclib(serial: int): void {
        if (serial !== root.requestSerial)
            return;
        if (root.trackTitle.length === 0) {
            root.finish(serial, {
                "status": "none",
                "reason": "No track title"
            });
            return;
        }
        lrclibProc.raw = "";
        lrclibProc.serial = serial;
        lrclibProc.command = ["python3", Quickshell.shellPath("scripts/lrclib_lyrics.py"), "--artist", root.trackArtist, "--title", root.trackTitle, "--album", root.trackAlbum, "--duration", String(root.trackDuration)];
        if (lrclibProc.running) {
            // An older run is still exiting; start this one when it has.
            lrclibProc.pendingSerial = serial;
            lrclibProc.running = false;
            return;
        }
        lrclibProc.running = true;
    }

    Process {
        id: lrclibProc

        property string raw: ""
        property int serial: -1
        property int pendingSerial: -1

        stdout: SplitParser {
            onRead: data => lrclibProc.raw += data
        }

        onExited: exitCode => {
            const out = lrclibProc.raw.trim();
            const serial = lrclibProc.serial;
            lrclibProc.raw = "";

            if (lrclibProc.pendingSerial >= 0) {
                const next = lrclibProc.pendingSerial;
                lrclibProc.pendingSerial = -1;
                if (next === root.requestSerial) {
                    lrclibProc.serial = next;
                    Qt.callLater(() => {
                        if (lrclibProc.serial === root.requestSerial && !lrclibProc.running)
                            lrclibProc.running = true;
                    });
                }
                return;
            }

            // Result for a track that is no longer playing: never shown, never cached.
            if (serial !== root.requestSerial)
                return;

            let result = null;
            if (exitCode === 0 && out.length > 0) {
                try {
                    result = JSON.parse(out);
                } catch (e) {
                    console.warn("Lyrics: LRCLIB output parse error", e);
                }
            }
            if (!result || typeof result !== "object") {
                root.finish(serial, {
                    "status": "none",
                    "reason": "LRCLIB lookup failed"
                });
                return;
            }

            if (result.status === "synced") {
                const lines = Logic.normalizeLines(result.lines || [], root.trackDuration);
                if (Logic.hasVocalLines(lines)) {
                    root.finish(serial, {
                        "status": "synced",
                        "lines": lines,
                        "plain": "",
                        "source": result.approximate ? "LRCLIB (approximate match)" : "LRCLIB",
                        "approximate": !!result.approximate,
                        "match": result.match || null
                    });
                    return;
                }
            }
            if (result.status === "plain" && result.plain) {
                root.finish(serial, {
                    "status": "plain",
                    "lines": [],
                    "plain": String(result.plain),
                    "source": "LRCLIB (not synced)",
                    "approximate": !!result.approximate,
                    "match": result.match || null
                });
                return;
            }
            if (result.status === "instrumental") {
                root.finish(serial, {
                    "status": "instrumental",
                    "lines": [],
                    "plain": "",
                    "source": "LRCLIB",
                    "approximate": false,
                    "match": result.match || null
                });
                return;
            }
            root.finish(serial, {
                "status": "none",
                "reason": result.reason || "No lyrics found"
            });
        }
    }

    // QRC files start with title/credit rows before the actual lyrics.
    function cleanQrc(parsed, title, artist) {
        const out = [];
        for (let i = 0; i < parsed.length; i++) {
            const item = parsed[i];
            const text = item.text;
            if (/^(lyrics|composed|written|produced|arranged)\s+by\s*[:：]/i.test(text))
                continue;
            if (/^(作词|作曲|编曲|制作人|监制)\s*[:：]/.test(text))
                continue;
            if (title && artist && text === title + " - " + artist)
                continue;
            if (title && text === title && item.time < 5)
                continue;
            out.push(item);
        }
        return out;
    }

    function fromCodePoint(cp) {
        if (String.fromCodePoint)
            return String.fromCodePoint(cp);
        if (cp <= 0xFFFF)
            return String.fromCharCode(cp);
        cp -= 0x10000;
        return String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF));
    }

    function decodeEntities(s) {
        if (s === undefined || s === null)
            return "";
        return String(s).replace(/&#x([0-9a-fA-F]+);/g, function (_, h) {
            return root.fromCodePoint(parseInt(h, 16));
        }).replace(/&#([0-9]+);/g, function (_, d) {
            return root.fromCodePoint(parseInt(d, 10));
        }).replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
    }

    // Text of one <p> block. Background-vocal spans (ttm:role="x-bg") are skipped, matching the
    // midnight-shell parser; everything else contributes its text.
    function paragraphText(body) {
        const tokenRe = /<[^>]*>|[^<]+/g;
        const stack = [];
        let out = "";
        let m;
        while ((m = tokenRe.exec(body)) !== null) {
            const tok = m[0];
            if (tok.charAt(0) === "<") {
                const isClose = /^<\s*\//.test(tok);
                const selfClosing = /\/\s*>$/.test(tok);
                const nameMatch = /^<\s*\/?\s*([A-Za-z0-9:_-]+)/.exec(tok);
                const name = nameMatch ? nameMatch[1].toLowerCase() : "";
                if (name === "br") {
                    if (stack.indexOf(true) === -1)
                        out += " ";
                    continue;
                }
                if (name !== "span")
                    continue;
                if (isClose) {
                    if (stack.length > 0)
                        stack.pop();
                } else if (!selfClosing) {
                    stack.push(/(?:ttm:)?role\s*=\s*["']x-bg["']/i.test(tok));
                }
            } else if (stack.indexOf(true) === -1) {
                out += tok;
            }
        }
        return root.decodeEntities(out).replace(/\u00A0/g, " ").replace(/\s+/g, " ").trim();
    }

    function parseTime(value) {
        return Logic.parseTime(value);
    }

    function parseTtml(ttml) {
        const out = [];
        if (!ttml)
            return out;
        const pRe = /<p\b([^>]*)>([\s\S]*?)<\/p>/g;
        let m;
        while ((m = pRe.exec(ttml)) !== null) {
            const attrs = m[1] || "";
            const body = m[2] || "";
            const beginMatch = /\bbegin\s*=\s*["']([^"']*)["']/i.exec(attrs);
            const time = beginMatch ? root.parseTime(beginMatch[1]) : NaN;
            if (!isFinite(time))
                continue;
            const endMatch = /\bend\s*=\s*["']([^"']*)["']/i.exec(attrs);
            const durMatch = /\bdur\s*=\s*["']([^"']*)["']/i.exec(attrs);
            let end = endMatch ? root.parseTime(endMatch[1]) : NaN;
            if (!isFinite(end) && durMatch)
                end = time + root.parseTime(durMatch[1]);
            const text = root.paragraphText(body);
            if (text.length === 0)
                continue;
            out.push({
                "time": time,
                "end": end,
                "text": text
            });
        }
        return out;
    }

    // QRC payload from /qq/getLyrics: either the QrcInfos XML wrapper or bare QRC content.
    // Line entries look like "[startMs,durationMs]text(wordStart,wordDur) ...". LRC rows are
    // accepted too, with the same rules as LRCLIB (several timestamps per row, [offset:]).
    function parseQrc(payload) {
        const out = [];
        if (!payload)
            return out;
        let content = String(payload);

        // QRC attributes are not XML-escaped, so a lyric that contains a quote would cut a
        // non-greedy match short. The value is the last quoted part of the tag, so match
        // greedily up to the tag close instead.
        const attr = /LyricContent\s*=\s*"([\s\S]*)"\s*\/>/.exec(content);
        if (attr) {
            content = attr[1];
        } else {
            const attr2 = /LyricContent\s*=\s*"([\s\S]*)"\s*>/.exec(content);
            if (attr2)
                content = attr2[1];
        }

        content = root.decodeEntities(content);
        const rows = content.split(/\r?\n/);
        const lrcRows = [];
        for (let i = 0; i < rows.length; i++) {
            const raw = rows[i];
            const qrc = /^\s*\[(\d+),(\d+)\]\s*(.*)$/.exec(raw);
            if (qrc) {
                const time = parseInt(qrc[1], 10) / 1000;
                const dur = parseInt(qrc[2], 10) / 1000;
                let text = qrc[3].replace(/\(\d+,\d+\)/g, "").replace(/<\d+,\d+>/g, "");
                text = root.decodeEntities(text).replace(/\s+/g, " ").trim();
                if (text.length > 0)
                    out.push({
                        "time": time,
                        "end": dur > 0 ? time + dur : NaN,
                        "text": text
                    });
                continue;
            }
            if (/^\s*\[(\d+:\d+|offset:)/i.test(raw))
                lrcRows.push(raw);
        }

        // Plain LRC lines are also accepted as a last resort.
        if (lrcRows.length > 0) {
            const lrc = Logic.parseLrc(lrcRows.join("\n")).lines;
            for (let j = 0; j < lrc.length; j++)
                out.push(lrc[j]);
        }
        return out;
    }
}
