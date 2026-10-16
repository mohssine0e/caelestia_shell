pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services

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
                    if (win.st) win.st.timer = false
                }
                onVisibleChanged: {
                    if (!visible && win.st && win.st.timer)
                        win.st.timer = false
                }

                title: FocusTimer.linkedTaskTitle.length > 0
                    ? `Timer — ${FocusTimer.linkedTaskTitle} [${FocusTimer.taskPhaseString}] (${FocusTimer.formattedSeconds})`
                    : `Timer (${FocusTimer.formattedSeconds})`

                color: "transparent"
                surfaceFormat.opaque: false

                // Window follows content size. Hyprland owns position and resize.
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
                    expanded: false
                    onExpandedChanged: {
                        if (win.st && win.st.timerExpanded !== expanded)
                            win.st.timerExpanded = expanded
                    }
                    onDismissRequested: {
                        if (win.st) win.st.timer = false
                    }
                }

                TimerMini {
                    id: miniCard
                    mini: behaviour
                    windowRef: win
                }
            }
        }
    }
}