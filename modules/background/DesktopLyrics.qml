pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.State
import qs.components
import qs.services

// Desktop lyrics overlay: previous, current and next line under the visualiser.
//
// Lines, timing and the per-track offset come from LyricsSource, the same source as the
// dashboard media tab. Visibility follows playback like the visualiser: hidden at once on stop,
// faded out 1.5 s after a pause (a quick pause does not flicker), cleared when the player closes.
// The decision itself is LyricsSource.overlayState(), covered by tests/lyrics_logic.test.js.
Item {
    id: root

    required property ShellScreen screen

    readonly property var player: LyricsSource.player
    readonly property string playback: LyricsSource.playback
    readonly property string status: LyricsSource.status

    // Same rule as before: a tiled or fullscreen window on this monitor covers the desktop.
    readonly property bool covered: {
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

    // Horizontal shift that centres the lyrics on the visualiser bars, which start after the bar's
    // exclusive zone (see Visualiser.qml) instead of at the screen edge.
    // Visualiser.qml: margins of Config.border.thickness, left margin = bar zone + spacing.
    readonly property real visualiserCentreOffset: ((ShellState.componentsFor(root.screen)?.bar?.exclusiveZone ?? 0) + Tokens.spacing.small * Config.background.visualiser.spacing - Config.border.thickness) / 2

    property bool pauseGrace: false
    property bool loadingDelayPassed: false
    property bool noticeActive: false
    property string noticeKey: ""
    property int currentIndex: -1

    readonly property var overlay: LyricsSource.overlayState({
        "hasPlayer": !!root.player,
        "covered": root.covered,
        "playback": root.playback,
        "pauseGrace": root.pauseGrace,
        "status": root.status,
        "loadingDelayPassed": root.loadingDelayPassed,
        "noticeActive": root.noticeActive,
        "lines": LyricsSource.lines,
        "index": root.currentIndex
    })
    readonly property bool shown: root.overlay.visible
    readonly property string mode: root.overlay.mode

    readonly property var rows: LyricsSource.rowsForIndex(root.currentIndex)
    readonly property string currentText: {
        if (root.mode === "loading")
            return qsTr("Loading lyrics…");
        if (root.mode === "notice")
            return root.status === "plain" ? qsTr("Lyrics for this track are not synced") : qsTr("No lyrics found for this track");
        if (root.mode === "lyrics")
            return root.currentIndex < 0 ? "" : root.rows.current;
        return "";
    }
    readonly property string previousText: root.mode === "lyrics" || root.mode === "notes" ? root.rows.previous : ""
    readonly property string nextText: root.mode === "lyrics" || root.mode === "notes" ? root.rows.next : ""

    // Font sizes are chosen once per track, so a single Arabic line does not resize the block.
    readonly property bool arabic: LyricsSource.arabic
    readonly property string fontFamily: "Rubik, Noto Kufi Arabic, sans-serif"
    readonly property int sidePixelSize: root.arabic ? 20 : 16
    readonly property int mainPixelSize: root.arabic ? 30 : 25
    readonly property real mainLineHeight: root.arabic ? 1.4 : 1.2

    implicitWidth: Math.min(650, root.screen.width * 0.7)
    implicitHeight: column.implicitHeight + Tokens.padding.extraSmall * 2

    function updateIndex(): void {
        const p = root.player;
        root.currentIndex = p && LyricsSource.status === "synced" ? LyricsSource.indexForTime(p.position) : -1;
    }

    // Wakes up right when the next line is due (at most every 250 ms, so a seek is caught quickly)
    // instead of polling every 200 ms and switching up to 200 ms late.
    function scheduleTick(): void {
        if (root.playback !== "playing" || root.status !== "synced" || !root.player) {
            ticker.stop();
            return;
        }
        const ms = LyricsSource.msUntilNextLine(root.player.position);
        ticker.interval = ms < 0 ? 250 : Math.max(16, Math.min(250, Math.ceil(ms) + 5));
        ticker.restart();
    }

    function refresh(): void {
        root.updateIndex();
        root.scheduleTick();
    }

    Timer {
        id: ticker

        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: pauseGraceTimer

        interval: 1500
        onTriggered: root.pauseGrace = false
    }

    Timer {
        id: loadingDelay

        interval: 400
        onTriggered: root.loadingDelayPassed = true
    }

    Timer {
        id: noticeTimer

        interval: 3000
        onTriggered: root.noticeActive = false
    }

    onPlaybackChanged: {
        if (root.playback === "paused") {
            root.pauseGrace = true;
            pauseGraceTimer.restart();
        } else {
            pauseGraceTimer.stop();
            root.pauseGrace = false;
        }
        root.refresh();
    }

    onStatusChanged: {
        if (root.status === "loading") {
            root.loadingDelayPassed = false;
            loadingDelay.restart();
        } else {
            loadingDelay.stop();
            root.loadingDelayPassed = false;
        }

        // Say once per track that there is nothing to sync, then get out of the way.
        if ((root.status === "plain" || root.status === "none") && LyricsSource.syncedKey !== root.noticeKey) {
            root.noticeKey = LyricsSource.syncedKey;
            root.noticeActive = true;
            noticeTimer.restart();
        } else if (root.status !== "plain" && root.status !== "none") {
            noticeTimer.stop();
            root.noticeActive = false;
        }
        root.refresh();
    }

    Connections {
        target: LyricsSource

        function onLinesChanged() {
            root.refresh();
        }
        function onOffsetChanged() {
            root.refresh();
        }
    }

    // Seeks do not notify; the dashboard calls positionChanged() on its own timers, which lands here.
    Connections {
        target: root.player
        ignoreUnknownSignals: true

        function onPositionChanged() {
            if (!ticker.running)
                root.refresh();
        }
    }

    Component.onCompleted: root.refresh()

    opacity: root.shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    FontMetrics {
        id: sideMetrics

        font.family: root.fontFamily
        font.pixelSize: root.sidePixelSize
        font.weight: Font.Medium
    }

    FontMetrics {
        id: mainMetrics

        font.family: root.fontFamily
        font.pixelSize: root.mainPixelSize
        font.weight: Font.Bold
    }

    component SideRow: Item {
        id: sideRow

        property alias text: sideLabel.text

        width: parent.width
        height: Math.ceil(sideMetrics.lineSpacing)
        opacity: 0.55

        StyledText {
            id: sideLabel

            anchors.fill: parent
            animate: true
            font.family: root.fontFamily
            font.pixelSize: root.sidePixelSize
            font.weight: Font.Medium
            color: Colours.palette.m3onSurfaceVariant
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            maximumLineCount: 1
            elide: Text.ElideRight
        }
    }

    Item {
        id: lyricsWrapper

        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.alpha("black", 0.8)
            shadowOpacity: 0.85
            shadowBlur: 0.45
            shadowVerticalOffset: 1
        }

        // Fixed rows, anchored at the bottom: the block keeps its place on the first and last
        // line, on wrapping lines and in instrumental gaps.
        Column {
            id: column

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: Tokens.spacing.extraSmall

            SideRow {
                text: root.previousText
            }

            // Current line: room for two lines at the current font, Arabic included.
            Item {
                width: parent.width
                height: Math.ceil(mainMetrics.lineSpacing * root.mainLineHeight * 2)

                StyledText {
                    anchors.fill: parent
                    animate: true
                    text: root.currentText
                    font.family: root.fontFamily
                    font.pixelSize: root.mainPixelSize
                    font.weight: Font.Bold
                    lineHeight: root.mainLineHeight
                    color: root.mode === "notice" || root.mode === "loading" ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3primary
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                DancingNotes {
                    anchors.centerIn: parent
                    opacity: root.mode === "notes" ? 1 : 0
                    visible: opacity > 0
                    running: root.mode === "notes" && root.shown && root.playback === "playing"
                    noteColor: Colours.palette.m3primary
                    noteSize: 26

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }
            }

            SideRow {
                text: root.nextText
            }
        }
    }
}
