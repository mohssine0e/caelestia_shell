
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.Services
import Caelestia.State
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

Item {
    id: root

    required property ShellScreen screen

    readonly property var player: Players.active
    readonly property bool betterEnabled: true
    readonly property bool fallbackEnabled: true
    readonly property bool useBetter: root.betterEnabled && BetterLyrics.hasLyrics
    readonly property bool useShell: !root.useBetter && !BetterLyrics.loading && root.fallbackEnabled && Lyrics.hasLyrics
    readonly property bool activeHasLyrics: root.useBetter || root.useShell
    readonly property var activeTexts: root.useBetter ? BetterLyrics.texts : (root.useShell ? Lyrics.lyrics : [])
    readonly property bool activeLoading: !root.activeHasLyrics && (BetterLyrics.loading || (root.fallbackEnabled && Lyrics.loading))

    readonly property bool shouldHide: {
        const mon = root.screen ? Hypr.monitorFor(root.screen) : null;
        if (!mon || !mon.activeWorkspace || !mon.activeWorkspace.toplevels)
            return false;
        const toplevels = mon.activeWorkspace.toplevels.values;
        if (!toplevels || toplevels.length === 0)
            return false;
        return toplevels.some(t => {
            const ipc = t.lastIpcObject;
            return ipc && ((ipc.fullscreen ?? 0) !== 0 || !ipc.floating);
        });
    }

    property int currentIndex: -1
    property string displayedLyric: ""
    property string previousLyricText: ""
    property string nextLyricText: ""
    property real userOffset: 0.0

    function isArabic(text: string): bool {
        return /[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]/.test(text || "");
    }

    function isInstrumental(str: string): bool {
        if (!str) return false;
        const s = str.trim().toLowerCase();
        if (s === "♪" || s === "♪ ♪" || s === "♪ ♪ ♪" || s === "♫" || s === "..." || s === ". . .")
            return true;
        return s.includes("instrumental") || s.includes("intro") || s.includes("solo") ||
               s.includes("interlude") || s.includes("outro") || s.includes("break");
    }

    function formatLine(str: string): string {
        if (!str) return "";
        if (root.isInstrumental(str))
            return "♪  ♫  ♪";
        return str;
    }

    readonly property bool isCurrentInstrumental: !root.activeLoading && (root.isInstrumental(root.displayedLyric) || (root.activeHasLyrics && root.displayedLyric.length === 0))
    readonly property bool hasText: root.displayedLyric.trim() !== "" || root.previousLyricText.trim() !== "" || root.nextLyricText.trim() !== "" || root.activeHasLyrics
    readonly property bool shown: !!root.player && !root.shouldHide && ((root.activeHasLyrics && root.hasText) || root.activeLoading)

    implicitWidth: Math.min(650, root.screen.width * 0.7)
    implicitHeight: 120

    function syncTrack(): void {
        root.userOffset = 0.0;
        const active = root.player;
        if (active && (active.trackTitle ?? "").length > 0) {
            const artist = active.trackArtist ?? "";
            const title = active.trackTitle ?? "";
            const album = active.trackAlbum ?? "";
            const duration = active.length ?? 0;
            if (root.betterEnabled)
                BetterLyrics.setTrack(artist, title, album, duration);
            if (root.fallbackEnabled)
                Lyrics.setTrack(artist, title, album, duration);
        } else if (!active) {
            BetterLyrics.clearTrack();
        }
    }

    onPlayerChanged: root.syncTrack()

    Connections {
        target: root.player
        ignoreUnknownSignals: true

        function onTrackTitleChanged() {
            root.syncTrack();
        }
        function onTrackArtistChanged() {
            root.syncTrack();
        }
        function onTrackAlbumChanged() {
            root.syncTrack();
        }
        function onLengthChanged() {
            root.syncTrack();
        }
    }

    function refreshLyrics(): void {
        const texts = root.activeTexts;
        if (!root.activeHasLyrics || !texts || texts.length === 0) {
            root.displayedLyric = "";
            root.previousLyricText = "";
            root.nextLyricText = "";
            return;
        }

        if (root.currentIndex >= 0) {
            root.displayedLyric = String(texts[root.currentIndex] ?? "").replace(/\u00A0/g, " ");
            root.previousLyricText = root.currentIndex > 0 ? String(texts[root.currentIndex - 1] ?? "").replace(/\u00A0/g, " ") : "";
            root.nextLyricText = root.currentIndex < texts.length - 1 ? String(texts[root.currentIndex + 1] ?? "").replace(/\u00A0/g, " ") : "";
        } else {
            root.displayedLyric = "";
            root.previousLyricText = "";
            root.nextLyricText = String(texts[0] ?? "").replace(/\u00A0/g, " ");
        }
    }

    function activeIndexForTime(time: real): int {
        const t = time - root.userOffset;
        if (root.useBetter)
            return BetterLyrics.indexForTime(t);
        if (root.useShell)
            return Lyrics.indexForTime(t);
        return -1;
    }

    function forceUpdate(): void {
        const pos = root.player ? root.player.position : 0;
        const nextIndex = root.activeHasLyrics ? root.activeIndexForTime(pos) : -1;
        if (nextIndex === root.currentIndex) {
            root.refreshLyrics();
            return;
        }
        root.currentIndex = nextIndex;
    }

    onCurrentIndexChanged: {
        root.refreshLyrics();
    }

    Component.onCompleted: {
        root.syncTrack();
        root.forceUpdate();
    }

    Timer {
        running: root.player ? root.player.isPlaying : false
        interval: 200
        triggeredOnStart: true
        repeat: true
        onTriggered: root.forceUpdate()
    }

    Connections {
        target: BetterLyrics
        function onLinesChanged() {
            root.forceUpdate();
        }
        function onHasLyricsChanged() {
            root.forceUpdate();
        }
    }

    Connections {
        target: Lyrics
        function onLyricsChanged() {
            root.forceUpdate();
        }
        function onHasLyricsChanged() {
            root.forceUpdate();
        }
    }

    opacity: root.shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    Item {
        id: lyricsWrapper

        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall
        clip: false

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.alpha("black", 0.8)
            shadowOpacity: 0.85
            shadowBlur: 0.45
            shadowVerticalOffset: 1
        }

        ColumnLayout {
            id: lyricsCol
            anchors.centerIn: parent
            width: parent.width
            spacing: Tokens.spacing.extraSmall

            // Previous Lyric Line
            StyledText {
                Layout.fillWidth: true
                text: root.formatLine(root.previousLyricText)
                font.family: "Rubik, Noto Kufi Arabic, sans-serif"
                font.pixelSize: root.isArabic(text) ? 20 : 16
                font.weight: Font.Medium
                color: Colours.palette.m3onSurfaceVariant
                opacity: 0.55
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 1
                elide: Text.ElideRight
                visible: text.length > 0

                Behavior on opacity {
                    Anim { type: Anim.FastEffects }
                }
            }

            // Dancing Notes when Instrumental / Intro / Solo
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                visible: root.isCurrentInstrumental

                DancingNotes {
                    anchors.centerIn: parent
                    running: root.isCurrentInstrumental && root.shown
                    noteColor: Colours.palette.m3primary
                    noteSize: 26
                }
            }

            // Active Lyric Line (Highlighted Vocal Text)
            StyledText {
                Layout.fillWidth: true
                visible: !root.isCurrentInstrumental
                text: root.activeLoading ? qsTr("Loading lyrics...") : root.displayedLyric
                font.family: "Rubik, Noto Kufi Arabic, sans-serif"
                font.pixelSize: root.isArabic(text) ? 30 : 25
                font.weight: Font.Bold
                lineHeight: root.isArabic(text) ? 1.4 : 1.2
                color: Colours.palette.m3primary
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight

                Behavior on color {
                    CAnim { duration: Tokens.anim.durations.expressiveFastEffects }
                }
            }

            // Next Lyric Line
            StyledText {
                Layout.fillWidth: true
                text: root.formatLine(root.nextLyricText)
                font.family: "Rubik, Noto Kufi Arabic, sans-serif"
                font.pixelSize: root.isArabic(text) ? 20 : 16
                font.weight: Font.Medium
                color: Colours.palette.m3onSurfaceVariant
                opacity: 0.55
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 1
                elide: Text.ElideRight
                visible: text.length > 0

                Behavior on opacity {
                    Anim { type: Anim.FastEffects }
                }
            }
        }
    }
}
