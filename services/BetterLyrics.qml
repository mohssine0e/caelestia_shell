pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Better Lyrics provider for the desktop overlay.
//
// The shell's Lyrics service is compiled C++ with a fixed backend enum, so a plugin cannot add a
// backend to it. This singleton therefore fetches and parses lyrics itself, and the desktop
// overlay reads from it first, falling back to the shell's Lyrics singleton when there is no
// Better Lyrics match.
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

    // [{ time: <seconds>, text: <line> }, ...] sorted by time, and the same lines as plain text
    // for the surface.
    property var lines: []
    property var texts: []
    property bool loading: false
    property string error: ""
    property string source: ""

    property int requestSerial: 0
    property string failedKey: ""
    property var activeXhr: null

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

    readonly property bool hasLyrics: lines.length > 0
    readonly property string effectiveApiKey: apiKey.length > 0 ? apiKey : (Quickshell.env("BETTER_LYRICS_API_KEY") || "")

    // Results are kept for the session so skipping back to a track does not refetch it.
    property var cache: ({})

    function setTrack(artist, title, album, duration) {
        if (!root.enabled) {
            root.clearTrack();
            return;
        }

        const a = String(artist ?? "");
        const t = String(title ?? "");
        const al = String(album ?? "");
        const d = Number(duration ?? 0);
        const key = a + "\u0001" + t + "\u0001" + al + "\u0001" + Math.round(d);

        if (key === root.trackKey && (root.loading || root.lines.length > 0 || root.failedKey === key))
            return;

        root.trackArtist = a;
        root.trackTitle = t;
        root.trackAlbum = al;
        root.trackDuration = d;
        root.trackKey = key;

        const cached = root.cache[key];
        if (cached) {
            root.lines = cached.lines;
            root.texts = cached.texts;
            root.source = cached.source;
            root.loading = false;
            root.error = "";
            root.failedKey = "";
            return;
        }

        root.lines = [];
        root.texts = [];
        root.source = "";
        root.error = "";
        root.loading = true;
        root.failedKey = "";

        root.requestSerial += 1;
        root.fetchTtml(root.requestSerial, a, t, al, d);
    }

    function clearTrack() {
        if (aiProc.running)
            aiProc.running = false;
        root.requestSerial += 1;
        root.trackKey = "";
        root.trackArtist = "";
        root.trackTitle = "";
        root.trackAlbum = "";
        root.trackDuration = 0;
        root.lines = [];
        root.texts = [];
        root.loading = false;
        root.error = "";
        root.source = "";
        root.failedKey = "";
    }

    // Last line whose start time is <= time, or -1 before the first line.
    function indexForTime(time) {
        const arr = root.lines;
        if (!arr || arr.length === 0)
            return -1;
        let lo = 0;
        let hi = arr.length - 1;
        let ans = -1;
        while (lo <= hi) {
            const mid = (lo + hi) >> 1;
            if (arr[mid].time <= time) {
                ans = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
        return ans;
    }

    function buildUrl(endpoint, artist, title, album, duration) {
        let url = endpoint + "?s=" + encodeURIComponent(title) + "&a=" + encodeURIComponent(artist) + "&al=" + encodeURIComponent(album);
        if (isFinite(duration) && duration > 0)
            url += "&d=" + Math.round(duration);
        return url;
    }

    function getJson(url, serial, done) {
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

    function fetchTtml(serial, artist, title, album, duration) {
        const url = root.buildUrl("https://api.betterlyrics.org/getLyrics", artist, title, album, duration);
        root.getJson(url, serial, function (err, text) {
            if (serial !== root.requestSerial)
                return;
            if (!err) {
                try {
                    const obj = JSON.parse(text);
                    const ttml = obj && obj.ttml ? String(obj.ttml) : "";
                    if (ttml.length > 0) {
                        const parsed = root.parseTtml(ttml);
                        if (parsed.length > 0) {
                            root.apply(serial, parsed, "Better Lyrics (TTML)");
                            return;
                        }
                    }
                } catch (e) {
                    // Fall through to the QRC endpoint.
                }
            }
            root.fetchQq(serial, artist, title, album, duration);
        });
    }

    function fetchQq(serial, artist, title, album, duration) {
        const url = root.buildUrl("https://api.betterlyrics.org/qq/getLyrics", artist, title, album, duration);
        root.getJson(url, serial, function (err, text) {
            if (serial !== root.requestSerial)
                return;
            if (err) {
                root.fail(serial, err);
                return;
            }
            try {
                const obj = JSON.parse(text);
                const qrc = obj && obj.lyrics ? String(obj.lyrics) : "";
                const parsed = root.cleanQrc(root.parseQrc(qrc), title, artist);
                if (parsed.length > 0) {
                    root.apply(serial, parsed, "Better Lyrics (QQ)");
                    return;
                }
            } catch (e) {
                // Fall through to the failure below.
            }
            root.fail(serial, "No lyrics found");
        });
    }

    function apply(serial, parsed, src) {
        if (serial !== root.requestSerial)
            return;

        parsed.sort(function (a, b) {
            return a.time - b.time;
        });

        const kept = [];
        const textList = [];
        for (let i = 0; i < parsed.length; i++) {
            const item = parsed[i];
            if (!isFinite(item.time))
                continue;
            const text = String(item.text ?? "").replace(/\u00A0/g, " ").trim();
            if (text.length === 0)
                continue;
            kept.push({
                "time": item.time,
                "text": text,
                "words": item.words || []
            });
            textList.push(text);
        }

        if (kept.length === 0) {
            root.fail(serial, "No lyrics found");
            return;
        }

        root.lines = kept;
        root.texts = textList;
        root.source = src;
        root.loading = false;
        root.error = "";
        root.failedKey = "";

        const cached = root.cache;
        cached[root.trackKey] = {
            "lines": kept,
            "texts": textList,
            "source": src
        };
        root.cache = cached;
        console.info("BetterLyrics:", src, kept.length, "lines for", root.trackArtist, "-", root.trackTitle);
    }

    Process {
        id: aiProc

        property string raw: ""

        command: [
            "python3",
            Quickshell.shellPath("scripts/ai_lyrics.py"),
            "--artist", root.trackArtist,
            "--title", root.trackTitle,
            "--album", root.trackAlbum,
            "--duration", String(root.trackDuration)
        ]

        stdout: SplitParser {
            onRead: data => aiProc.raw += data
        }

        onExited: exitCode => {
            const out = aiProc.raw.trim();
            aiProc.raw = "";
            if (exitCode === 0 && out.length > 0) {
                try {
                    const parsed = JSON.parse(out);
                    if (Array.isArray(parsed) && parsed.length > 0) {
                        root.apply(root.requestSerial, parsed, "ai-provider");
                        return;
                    }
                } catch (e) {
                    console.warn("BetterLyrics: AI parse error", e);
                }
            }
            root.finalFail(root.requestSerial, "No lyrics found from API or AI");
        }
    }

    function fail(serial, message) {
        if (serial !== root.requestSerial)
            return;
        if (!aiProc.running && root.trackTitle.length > 0) {
            console.info("BetterLyrics: Falling back to AI lyrics for", root.trackArtist, "-", root.trackTitle);
            aiProc.running = true;
            return;
        }
        root.finalFail(serial, message);
    }

    function finalFail(serial, message) {
        if (serial !== root.requestSerial)
            return;
        root.loading = false;
        root.error = message;
        root.lines = [];
        root.texts = [];
        root.source = "";
        root.failedKey = root.trackKey;
        console.warn("BetterLyrics:", message, "for", root.trackArtist, "-", root.trackTitle);
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

    // TTML time expressions: "27.395", "00:00:27.395", "1:02.5", "1250ms", "12s".
    function parseTime(value) {
        if (value === undefined || value === null)
            return NaN;
        const s = String(value).trim();
        if (s === "")
            return NaN;
        if (/ms$/i.test(s))
            return parseFloat(s) / 1000;
        if (/s$/i.test(s))
            return parseFloat(s);
        const parts = s.split(":");
        let sec = NaN;
        if (parts.length === 3)
            sec = parseInt(parts[0], 10) * 3600 + parseInt(parts[1], 10) * 60 + parseFloat(parts[2].replace(",", "."));
        else if (parts.length === 2)
            sec = parseInt(parts[0], 10) * 60 + parseFloat(parts[1].replace(",", "."));
        else
            sec = parseFloat(s.replace(",", "."));
        return isFinite(sec) ? sec : NaN;
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
            const text = root.paragraphText(body);
            if (text.length === 0)
                continue;
            out.push({
                "time": time,
                "text": text
            });
        }
        return out;
    }

    // QRC payload from /qq/getLyrics: either the QrcInfos XML wrapper or bare QRC content.
    // Line entries look like "[startMs,durationMs]text(wordStart,wordDur) ...".
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
        for (let i = 0; i < rows.length; i++) {
            const raw = rows[i];
            const qrc = /^\s*\[(\d+),(\d+)\]\s*(.*)$/.exec(raw);
            if (qrc) {
                const time = parseInt(qrc[1], 10) / 1000;
                let text = qrc[3].replace(/\(\d+,\d+\)/g, "").replace(/<\d+,\d+>/g, "");
                text = root.decodeEntities(text).replace(/\s+/g, " ").trim();
                if (text.length > 0)
                    out.push({
                        "time": time,
                        "text": text
                    });
                continue;
            }

            // Plain LRC lines are also accepted as a last resort.
            const lrc = /^\s*\[(\d+):(\d+)(?:[.:](\d+))?\]\s*(.*)$/.exec(raw);
            if (lrc) {
                const frac = lrc[3] ? parseFloat("0." + lrc[3]) : 0;
                const time = parseInt(lrc[1], 10) * 60 + parseInt(lrc[2], 10) + frac;
                const text = root.decodeEntities(lrc[4]).replace(/\s+/g, " ").trim();
                if (text.length > 0)
                    out.push({
                        "time": time,
                        "text": text
                    });
            }
        }
        return out;
    }
}
