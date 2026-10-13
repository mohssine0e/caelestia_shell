pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components

// Shared behaviour for the floating timer mini pill HUD.
// Tracks expanded state and drag coordinates without idle fades or compositor dependencies.
Item {
    id: root

    // Called when the user explicitly dismisses the mini (close button).
    signal dismissRequested()

    property bool expanded: false
    property bool dragging: false

    property real startMouseX: 0
    property real startMouseY: 0
    property real startTimerX: 0
    property real startTimerY: 0

    function beginDrag(mouseX: real, mouseY: real, currentX: real, currentY: real): void {
        startMouseX = mouseX
        startMouseY = mouseY
        startTimerX = currentX
        startTimerY = currentY
        dragging = true
    }

    function dragTo(mouseX: real, mouseY: real, st: var, screen: ShellScreen, cardW: real, cardH: real): void {
        if (!dragging || !st || !screen)
            return

        const dx = mouseX - startMouseX
        const dy = mouseY - startTimerY // mouse delta
        const deltaX = mouseX - startMouseX
        const deltaY = mouseY - startMouseY

        const edgePad = Tokens.spacing.small
        const maxX = Math.max(edgePad, screen.width - cardW - edgePad)
        const maxY = Math.max(edgePad, screen.height - cardH - edgePad)

        const targetX = Math.max(edgePad, Math.min(maxX, startTimerX + deltaX))
        const targetY = Math.max(edgePad, Math.min(maxY, startTimerY + deltaY))

        st.timerX = Math.round(targetX)
        st.timerY = Math.round(targetY)
    }

    function endDrag(): void {
        dragging = false
    }
}
