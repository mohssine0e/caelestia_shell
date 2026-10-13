pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Per-card time chip with 1-click focus timer start.
// Clicking starts the focus timer with the task's duration and opens the HUD.
// If already linked to this task, clicking toggles play/pause.
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
            if (root.linked) {
                FocusTimer.toggle();
            } else {
                FocusTimer.startForTask(root.taskId, root.taskTitle, root.minutes);
            }
            // Show the floating HUD window
            const st = ShellState.forActive();
            if (st)
                st.timer = true;
        }
    }

    RowLayout {
        id: chipRow
        anchors.centerIn: parent
        spacing: 2

        MaterialIcon {
            Layout.alignment: Qt.AlignVCenter
            text: root.running ? "pause" : root.linked ? "play_arrow" : "schedule"
            fontStyle: Tokens.font.icon.small
            color: root.running || root.linked ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text: `${root.minutes}m`
            font: Tokens.font.label.small
            color: root.running || root.linked ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
}
