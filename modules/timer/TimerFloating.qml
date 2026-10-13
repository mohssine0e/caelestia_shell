pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services

// Floating timer window: a real Wayland toplevel (FloatingWindow).
// Hyprland owns move/resize. Size is driven by content. Focus state drives dimming.
Scope {
    id: root

    Variants {
        model: Screens.screens

        LazyLoader {
            id: loader
            required property ShellScreen modelData

            activeAsync: true

            FloatingWindow {
                id: win

                screen: loader.modelData
                readonly property ScreenState st: ShellState.forScreen(loader.modelData)

                visible: win.st?.timer ?? false
                onClosed: {
                    if (win.st)
                        win.st.timer = false
                }
                onVisibleChanged: {
                    if (!visible && win.st && win.st.timer)
                        win.st.timer = false
                }
                title: FocusTimer.linkedTaskTitle.length > 0
                    ? `Timer — ${FocusTimer.linkedTaskTitle} (${FocusTimer.formattedTime})`
                    : `Timer (${FocusTimer.formattedTime})`

                color: "transparent"
                surfaceFormat.opaque: false

                implicitWidth: miniCard.implicitWidth
                implicitHeight: miniCard.implicitHeight

                minimumSize.width: miniCard.implicitWidth
                minimumSize.height: miniCard.implicitHeight
                maximumSize.width: miniCard.implicitWidth
                maximumSize.height: miniCard.implicitHeight

                contentItem.Config.screen: loader.modelData.name
                contentItem.Tokens.screen: loader.modelData.name

                FloatingMini {
                    id: behaviour
                    expanded: win.st?.timerExpanded ?? false
                    onExpandedChanged: {
                        if (win.st && win.st.timerExpanded !== expanded)
                            win.st.timerExpanded = expanded
                    }
                    onDismissRequested: {
                        if (win.st)
                            win.st.timer = false
                    }
                }

                TimerMini {
                    id: miniCard
                    mini: behaviour
                    windowRef: win
                    focused: win.activeFocus
                }
            }
        }
    }
}