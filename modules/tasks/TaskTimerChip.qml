pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Per-card time chip with an inline timer dropdown.
// Replaces the static "12m" pill in TaskCard / SubtaskCard / NestedSubtaskCard.
// Click (or the trailing caret) opens the menu; picking a row starts the
// FocusTimer with that duration.
StyledRect {
    id: root

    required property string taskId
    required property string taskTitle
    required property int minutes

    // When a FocusTimer session is linked to this row, highlight the chip.
    readonly property bool linked: FocusTimer.linkedTaskId === root.taskId && root.taskId.length > 0
    readonly property bool running: root.linked && FocusTimer.isRunning

    implicitWidth: chipRow.implicitWidth + Tokens.padding.small * 2
    implicitHeight: 20
    radius: Tokens.rounding.full
    color: root.running ? Colours.palette.m3primaryContainer
        : root.linked ? Colours.palette.m3tertiaryContainer
        : Colours.palette.m3surfaceContainerHighest

    Behavior on color { CAnim {} }

    visible: root.minutes > 0

    StateLayer {
        id: state
        color: root.running || root.linked ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
        onClicked: {
            if (timerMenu.expanded)
                timerMenu.expanded = false
            else
                timerMenu.expanded = true
        }
    }

    RowLayout {
        id: chipRow
        anchors.centerIn: parent
        spacing: 2

        MaterialIcon {
            Layout.alignment: Qt.AlignVCenter
            text: root.running ? "pause_circle" : "schedule"
            fontStyle: Tokens.font.icon.small
            color: root.running || root.linked ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text: `${root.minutes}m`
            font: Tokens.font.label.small
            color: root.running || root.linked ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
        }

        MaterialIcon {
            Layout.alignment: Qt.AlignVCenter
            text: "arrow_drop_down"
            fontStyle: Tokens.font.icon.small
            color: root.running || root.linked ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    Menu {
        id: timerMenu
        attachTo: root
        attachSideY: Menu.Bottom
        thisSideY: Menu.Top
        marginY: Tokens.spacing.extraSmall
        items: timerItems.instances
        onItemSelected: item => {
            const opt = (item as TimerOpt)
            const mins = opt.minutesOverride > 0 ? opt.minutesOverride : root.minutes
            if (opt.action === "toggle" && root.linked) {
                FocusTimer.toggle()
            } else {
                FocusTimer.startForTask(root.taskId, root.taskTitle, mins)
            }
            // Reveal the floating mini.
            const st = ShellState.forActive()
            if (st)
                st.timer = true
        }
    }

    Variants {
        id: timerItems
        model: [
            { kind: "start", label: qsTr("Start %1m focus").arg(root.minutes) },
            { kind: "preset", label: qsTr("25m pomodoro"), mins: 25 },
            { kind: "preset", label: qsTr("5m break"), mins: 5 },
            { kind: "toggle", label: root.linked ? (FocusTimer.isRunning ? qsTr("Pause timer") : qsTr("Resume timer")) : qsTr("Custom… (starts %1m)").arg(root.minutes) }
        ]
        TimerOpt {}
    }

    component TimerOpt: MenuItem {
        required property var modelData
        readonly property string action: modelData.kind === "toggle" ? "toggle" : "start"
        readonly property int minutesOverride: modelData.mins ?? 0
        text: modelData.label ?? ""
        icon: modelData.kind === "toggle" ? (FocusTimer.isRunning ? "pause" : "play_arrow") : "timer"
    }
}
