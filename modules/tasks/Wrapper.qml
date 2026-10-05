pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components

Item {
    id: root

    required property ScreenState screenState

    readonly property bool shouldBeActive: screenState.tasks

    // The Loader loads once at startup while the popout is invisible, so the
    // onLoaded focus grab is silently dropped (Qt ignores focus requests on
    // hidden items). Re-grab here every time the popout opens, otherwise Q,
    // / and the list shortcuts do nothing until the user clicks inside first.
    onShouldBeActiveChanged: {
        if (root.shouldBeActive)
            Qt.callLater(() => content.item?.forceActiveFocus())
    }

    property real offsetScale: shouldBeActive ? 0 : 1

    visible: offsetScale < 1
    anchors.bottomMargin: (-implicitHeight - 5) * offsetScale
    width: content.item?.width ?? 1040
    implicitHeight: content.implicitHeight || 720
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
        // Keep the content cached between opens so the popout appears immediately.
        active: true
        onLoaded: Qt.callLater(() => item?.forceActiveFocus())

        sourceComponent: Tasks {
            onCloseRequested: root.screenState.tasks = false
        }
    }
}
