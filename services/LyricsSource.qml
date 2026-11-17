pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Caelestia.Services
import "../utils/scripts/lyrics.js" as Logic

// One lyrics source for the desktop overlay and the dashboard media tab, so both show the same
// lines at the same moment.
//
// It keeps BetterLyrics (Better Lyrics TTML/QQ, then LRCLIB, never AI) and the shell's C++
// Lyrics service in step with the active player, then picks one provider:
//   1. BetterLyrics when it has timed lyrics for this recording;
//   2. otherwise the C++ Lyrics service's timed lyrics (its own backends and the candidate picker
//      in the media tab), once BetterLyrics has finished;
//   3. otherwise plain lyrics (shown unsynced), an instrumental track, or nothing.
//
// The timing offset is the C++ service's per-track offset (Lyrics.offset, saved per
// "artist - title" in its lyrics map), so an adjustment made for one recording is kept for it and
// applies to whichever provider is showing. A positive offset delays the lyrics.
Singleton {
    id: root

    readonly property MprisPlayer player: Players.active

    // "playing" | "paused" | "stopped". A player with no track counts as stopped.
    readonly property string playback: {
        const p = root.player;
        if (!p || (p.trackTitle ?? "").length === 0)
            return "stopped";
        if (p.playbackState === MprisPlaybackState.Playing || p.isPlaying)
            return "playing";
        if (p.playbackState === MprisPlaybackState.Paused)
            return "paused";
        return "stopped";
    }

    readonly property bool betterDone: BetterLyrics.status !== "loading" && BetterLyrics.status !== "idle"
    readonly property string provider: {
        if (BetterLyrics.hasLyrics)
            return "better";
        if (root.betterDone && Lyrics.hasLyrics)
            return "shell";
        return "";
    }

    // "idle" | "loading" | "synced" | "plain" | "instrumental" | "none"
    readonly property string status: {
        if (!root.player || (root.player.trackTitle ?? "").length === 0)
            return "idle";
        if (root.provider.length > 0)
            return "synced";
        if (!root.betterDone || Lyrics.loading)
            return "loading";
        if (BetterLyrics.status === "plain")
            return "plain";
        if (BetterLyrics.status === "instrumental")
            return "instrumental";
        return "none";
    }

    // [{ time, text }] for the chosen provider; "" text marks an instrumental gap.
    readonly property var lines: {
        if (root.provider === "better")
            return BetterLyrics.lines;
        if (root.provider === "shell") {
            const texts = Lyrics.lyrics;
            const off = Lyrics.offset;
            const out = [];
            for (let i = 0; i < texts.length; i++) {
                const text = Logic.isInstrumentalMarker(texts[i]) ? "" : String(texts[i]).replace(/\u00A0/g, " ").trim();
                out.push({
                    "time": Lyrics.timeForIndex(i) - off,
                    "text": text
                });
            }
            return out;
        }
        return [];
    }
    readonly property var texts: root.lines.map(l => l.text)
    readonly property string plainText: root.status === "plain" ? BetterLyrics.plainText : ""
    readonly property bool approximate: root.provider === "better" && BetterLyrics.approximate
    readonly property string sourceLabel: root.provider === "better" ? BetterLyrics.source : (root.provider === "shell" ? "Shell lyrics" : (root.status === "plain" ? BetterLyrics.source : ""))
    readonly property bool arabic: Logic.isMostlyArabic(root.lines.length > 0 ? root.lines : root.plainText.split("\n"))

    // Seconds; positive delays the lyrics. Saved per track by the C++ service.
    readonly property real offset: Lyrics.offset
    readonly property real offsetStep: 0.25

    function indexForTime(position: real): int {
        return Logic.indexForTime(root.lines, position, root.offset);
    }

    function currentIndex(): int {
        return root.player ? root.indexForTime(root.player.position) : -1;
    }

    function timeForIndex(index: int): real {
        return Logic.timeForIndex(root.lines, index, root.offset);
    }

    function msUntilNextLine(position: real): real {
        return Logic.msUntilNextLine(root.lines, position, root.offset, root.player ? (root.player.rate || 1) : 1);
    }

    function rowsForIndex(index: int): var {
        return Logic.rowsForIndex(root.lines, index);
    }

    function overlayState(state: var): var {
        return Logic.overlayState(state);
    }

    function isInstrumentalMarker(text: string): bool {
        return Logic.isInstrumentalMarker(text);
    }

    function seekToLine(index: int): void {
        const p = root.player;
        const t = root.timeForIndex(index);
        if (p && p.canSeek && t >= 0)
            p.position = t;
    }

    function nudgeOffset(delta: real): void {
        Lyrics.offset = Math.round((Lyrics.offset + delta) * 1000) / 1000;
    }

    function resetOffset(): void {
        Lyrics.offset = 0;
    }

    // --- Track sync: the only place that tells the providers what is playing. ---

    property string syncedKey: ""

    function syncTrack(): void {
        const p = root.player;
        const title = p ? String(p.trackTitle ?? "") : "";
        if (!p || title.length === 0) {
            if (root.syncedKey !== "") {
                root.syncedKey = "";
                BetterLyrics.clearTrack();
                Lyrics.clearTrack();
            }
            return;
        }
        const artist = String(p.trackArtist ?? "");
        const album = String(p.trackAlbum ?? "");
        const duration = Number(p.length ?? 0);
        const key = BetterLyrics.makeKey(artist, title, album, duration);
        if (key === root.syncedKey)
            return;
        root.syncedKey = key;
        BetterLyrics.setTrack(artist, title, album, duration);
        Lyrics.setTrack(artist, title, album, duration);
    }

    // Metadata often arrives field by field (title, then artist, then length); wait a moment so
    // one track change makes one request instead of three.
    Timer {
        id: syncDebounce

        interval: 150
        onTriggered: root.syncTrack()
    }

    onPlayerChanged: syncDebounce.restart()
    Component.onCompleted: root.syncTrack()

    Connections {
        target: root.player
        ignoreUnknownSignals: true

        function onTrackTitleChanged() {
            syncDebounce.restart();
        }
        function onTrackArtistChanged() {
            syncDebounce.restart();
        }
        function onTrackAlbumChanged() {
            syncDebounce.restart();
        }
        function onLengthChanged() {
            syncDebounce.restart();
        }
    }
}
