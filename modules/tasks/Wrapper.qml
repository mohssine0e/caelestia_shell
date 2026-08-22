pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components

Item {
    id: root

    required property ScreenState screenState

    readonly property bool shouldBeActive: screenState.tasks

    property real offsetScale: shouldBeActive ? 0 : 1

    visible: offsetScale < 1
    anchors.bottomMargin: (-implicitHeight - 5) * offsetScale
    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth || 1040 // Hard coded fallback for first open
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {}
    }

    // Auto-close 5s after the mouse leaves the popout (resets if it comes
    // back before the timer fires). Suspended while a text field inside
    // has focus — closing mid-typing loses the user's input.
    HoverHandler {
        id: hover
    }

    Timer {
        id: idleTimer
        interval: 5000
        running: root.shouldBeActive && !hover.hovered && !(content.item?.inputActive ?? false)
        onTriggered: if (root.shouldBeActive) root.screenState.tasks = false
    }

    Loader {
        id: content

        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter

        asynchronous: true
        active: true
        // Fresh load on open: grab keyboard focus right away
        onLoaded: Qt.callLater(() => item?.forceActiveFocus())

        sourceComponent: Tasks {
            onCloseRequested: root.screenState.tasks = false
        }
    }
}
