pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components

Item {
    id: root

    required property DrawerVisibilities visibilities

    readonly property bool shouldBeActive: visibilities.tasks

    property real offsetScale: shouldBeActive ? 0 : 1

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            implicitHeight = Qt.binding(() => content.implicitHeight);
            // Content may still be alive from the close animation — refocus
            // it so keyboard shortcuts ("/", j/k, Escape) work immediately
            content.item?.forceActiveFocus();
        } else {
            implicitHeight = implicitHeight; // Break binding during close anim
        }
    }

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
        onTriggered: root.visibilities.tasks = false
    }

    Loader {
        id: content

        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter

        active: root.shouldBeActive || root.visible
        // Fresh load on open: grab keyboard focus right away
        onLoaded: item.forceActiveFocus()

        sourceComponent: Tasks {
            onCloseRequested: root.visibilities.tasks = false
        }
    }
}
