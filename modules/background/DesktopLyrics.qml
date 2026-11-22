pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import qs.components
import qs.services

// Desktop lyrics overlay: previous, current and next line under the visualiser.
//
// Lines, timing and the per-track offset come from LyricsSource, the same source as the
// dashboard media tab. Visibility follows playback like the visualiser: hidden at once on stop,
// faded out 1.5 s after a pause (a quick pause does not flicker), cleared when the player closes.
//
// On forward line advancement, a smooth vertical conveyor roll-up glides lines upward
// without flickering or blank intervals: the active line glides into the center expanding to
// primary prominence, the outgoing line glides to the top row fading to secondary, and the
// incoming line rolls in smoothly from below.
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

    property bool pauseGrace: false
    property bool loadingDelayPassed: false
    property int currentIndex: -1
    property int displayIndex: -1

    readonly property var overlay: LyricsSource.overlayState({
        "hasPlayer": !!root.player,
        "covered": root.covered,
        "playback": root.playback,
        "pauseGrace": root.pauseGrace,
        "status": root.status,
        "loadingDelayPassed": root.loadingDelayPassed,
        "lines": LyricsSource.lines,
        "index": root.currentIndex
    })
    readonly property bool shown: root.overlay.visible
    readonly property string mode: root.overlay.mode

    // Lyrics conveyor strings:
    // Item 0: Previous line (at yPrev in steady state)
    // Item 1: Current line (at yCenter in steady state)
    // Item 2: Next line (at yNext in steady state)
    // Item 3: Incoming next line (at yNext + rowStep in steady state)
    property string textPrev: ""
    property string textCurr: ""
    property string textNext: ""
    property string textIn: ""

    property real rollProgress: 0.0

    // Font sizes are chosen once per track, so a single Arabic line does not resize the block.
    readonly property bool arabic: LyricsSource.arabic
    readonly property string fontFamily: root.arabic ? "Noto Kufi Arabic" : "Adwaita Sans"
    readonly property int sidePixelSize: 13
    readonly property int mainPixelSize: 19
    readonly property real mainLineHeight: root.arabic ? 1.35 : 1.18
    readonly property real scaleSide: root.sidePixelSize / root.mainPixelSize

    FontMetrics {
        id: sideMetrics

        font.family: root.fontFamily
        font.pixelSize: root.sidePixelSize
        font.weight: Font.Normal
    }

    FontMetrics {
        id: mainMetrics

        font.family: root.fontFamily
        font.pixelSize: root.mainPixelSize
        font.weight: Font.Medium
    }

    // Geometry calculations for conveyor roll
    readonly property real sideHeight: Math.ceil(sideMetrics.lineSpacing)
    readonly property real mainHeight: Math.max(Math.ceil(mainMetrics.lineSpacing * root.mainLineHeight), mainTextMeasure.implicitHeight)
    readonly property real rowSpacing: 4
    readonly property real rowStep: (sideHeight + mainHeight) / 2 + rowSpacing

    readonly property real yPrev: sideHeight / 2
    readonly property real yCenter: sideHeight + rowSpacing + mainHeight / 2
    readonly property real yNext: yCenter + rowStep
    readonly property real shiftY: root.rollProgress * root.rowStep

    implicitWidth: Math.min(650, root.screen.width * 0.7)
    implicitHeight: Math.ceil(sideHeight * 2 + mainHeight + rowSpacing * 2)

    function lerpColor(c1: color, c2: color, p: real): color {
        return Qt.rgba(
            c1.r + (c2.r - c1.r) * p,
            c1.g + (c2.g - c1.g) * p,
            c1.b + (c2.b - c1.b) * p,
            c1.a + (c2.a - c1.a) * p
        );
    }

    function syncImmediate(): void {
        rollAnim.stop();
        root.rollProgress = 0.0;
        root.displayIndex = root.currentIndex;

        if (root.mode === "loading") {
            root.textPrev = "";
            root.textCurr = qsTr("Loading lyrics…");
            root.textNext = "";
            root.textIn = "";
            return;
        }

        if (root.mode !== "lyrics" && root.mode !== "notes") {
            root.textPrev = "";
            root.textCurr = "";
            root.textNext = "";
            root.textIn = "";
            return;
        }

        const r = LyricsSource.rowsForIndex(root.currentIndex);
        root.textPrev = r.previous;
        root.textCurr = root.currentIndex < 0 ? "" : r.current;
        root.textNext = r.next;
        root.textIn = "";
    }

    function startRoll(oldIdx: int, newIdx: int): void {
        rollAnim.stop();
        root.rollProgress = 0.0;

        const rOld = LyricsSource.rowsForIndex(oldIdx);
        const rNew = LyricsSource.rowsForIndex(newIdx);

        root.textPrev = rOld.previous;
        root.textCurr = oldIdx < 0 ? "" : rOld.current;
        root.textNext = rNew.current;
        root.textIn = rNew.next;
        root.displayIndex = newIdx;

        rollAnim.restart();
    }

    function updateIndex(): void {
        const p = root.player;
        const newIdx = p && LyricsSource.status === "synced" ? LyricsSource.indexForTime(p.position) : -1;
        if (newIdx === root.currentIndex)
            return;

        const oldIdx = root.currentIndex;
        root.currentIndex = newIdx;

        if (root.mode === "lyrics" || root.mode === "notes") {
            if (newIdx === oldIdx + 1 && root.shown) {
                root.startRoll(oldIdx, newIdx);
            } else {
                root.syncImmediate();
            }
        } else {
            root.syncImmediate();
        }
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

        root.refresh();
    }

    onModeChanged: root.syncImmediate()

    Connections {
        target: LyricsSource

        function onLinesChanged() {
            root.syncImmediate();
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

    Component.onCompleted: {
        root.syncImmediate();
        root.refresh();
    }

    opacity: root.shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    Anim {
        id: rollAnim

        target: root
        property: "rollProgress"
        from: 0.0
        to: 1.0
        type: Anim.Emphasized
        onFinished: {
            root.textPrev = root.textCurr;
            root.textCurr = root.textNext;
            root.textNext = root.textIn;
            root.textIn = "";
            root.rollProgress = 0.0;
        }
    }

    // Invisible text meter to determine dynamic center row height for 1 or 2 lines
    Text {
        id: mainTextMeasure

        visible: false
        width: lyricsViewport.width
        font.family: root.fontFamily
        font.pixelSize: root.mainPixelSize
        font.weight: Font.Medium
        lineHeight: root.mainLineHeight
        wrapMode: Text.Wrap
        maximumLineCount: 2
        text: root.textCurr
    }

    component LyricRow: Item {
        id: rowItem

        property alias text: label.text
        property real targetCenterY: 0
        property real scaleFactor: 1.0
        property color textColor: Colours.palette.m3onSurfaceVariant

        width: parent.width
        height: root.mainHeight
        y: Math.round(targetCenterY - height / 2)

        StyledText {
            id: label

            anchors.centerIn: parent
            width: parent.width
            scale: rowItem.scaleFactor
            color: rowItem.textColor
            font.family: root.fontFamily
            font.pixelSize: root.mainPixelSize
            font.weight: Font.Medium
            lineHeight: root.mainLineHeight
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }

    Item {
        id: lyricsViewport

        anchors.fill: parent
        clip: true

        // Item 0: Outgoing previous line (glides up and fades out)
        LyricRow {
            text: root.textPrev
            targetCenterY: root.yPrev - root.shiftY
            scaleFactor: root.scaleSide
            opacity: (1.0 - root.rollProgress) * 0.55
            textColor: Colours.palette.m3onSurfaceVariant
            visible: opacity > 0 && text.length > 0
        }

        // Item 1: Outgoing current -> previous (glides up, scales down to 13px, turns secondary)
        LyricRow {
            text: root.textCurr
            targetCenterY: root.yCenter - root.shiftY
            scaleFactor: 1.0 - root.rollProgress * (1.0 - root.scaleSide)
            opacity: 1.0 - root.rollProgress * (1.0 - 0.55)
            textColor: root.lerpColor(Colours.palette.m3primary, Colours.palette.m3onSurfaceVariant, root.rollProgress)
            visible: opacity > 0 && text.length > 0
        }

        // Item 2: Incoming next -> current (glides up to center, scales up to 19px, turns primary)
        LyricRow {
            text: root.textNext
            targetCenterY: root.yNext - root.shiftY
            scaleFactor: root.scaleSide + root.rollProgress * (1.0 - root.scaleSide)
            opacity: 0.55 + root.rollProgress * (1.0 - 0.55)
            textColor: root.mode === "loading"
                ? Colours.palette.m3onSurfaceVariant
                : root.lerpColor(Colours.palette.m3onSurfaceVariant, Colours.palette.m3primary, root.rollProgress)
            visible: opacity > 0 && text.length > 0
        }

        // Item 3: Incoming next line (rolls in smoothly from below)
        LyricRow {
            text: root.textIn
            targetCenterY: (root.yNext + root.rowStep) - root.shiftY
            scaleFactor: root.scaleSide
            opacity: root.rollProgress * 0.55
            textColor: Colours.palette.m3onSurfaceVariant
            visible: opacity > 0 && text.length > 0
        }

        DancingNotes {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(root.yCenter - height / 2)
            opacity: root.mode === "notes" ? 1 : 0
            visible: opacity > 0
            running: root.mode === "notes" && root.shown && root.playback === "playing"
            noteColor: Colours.palette.m3primary
            noteSize: 22

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }
    }
}
