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

                Timer {
                    id: contentResizeTimer
                    interval: 80
                    repeat: false
                    onTriggered: {
                        if (!win.visible) return
                        // FloatingWindow applies implicit sizes when hidden; update the live
                        // window after its content settles so view changes resize in place.
                        const targetWidth = Math.round(hudCard.implicitWidth)
                        const targetHeight = Math.round(hudCard.implicitHeight)
                        if (Math.abs(win.width - targetWidth) > 1) win.width = targetWidth
                        if (Math.abs(win.height - targetHeight) > 1) win.height = targetHeight
                    }
                }

                Connections {
                    target: hudCard
                    function onImplicitWidthChanged() { contentResizeTimer.restart() }
                    function onImplicitHeightChanged() { contentResizeTimer.restart() }
                }

                screen: loader.modelData
                readonly property ScreenState st: ShellState.forScreen(loader.modelData)

                visible: win.st?.assistant ?? false
                onClosed: {
                    if (win.st) win.st.assistant = false
                    Assistant.isWatching = false
                    Assistant.isWindowActive = false
                    Assistant.cancelCurrentRequest()
                }
                onVisibleChanged: {
                    if (!visible) {
                        if (win.st && win.st.assistant)
                            win.st.assistant = false
                        Assistant.cancelCurrentRequest()
                        Assistant.isWindowActive = false
                    } else {
                        hudCard.forceActiveFocus()
                        contentResizeTimer.restart()
                    }
                    Assistant.isWatching = visible
                }

                title: "Assistant HUD"

                color: "transparent"
                surfaceFormat.opaque: false

                implicitWidth: hudCard.implicitWidth
                implicitHeight: hudCard.implicitHeight
                minimumSize.width: Math.min(520, Math.round(loader.modelData.width * 0.94))
                minimumSize.height: hudCard.minimumHudHeight
                maximumSize.width: Math.max(minimumSize.width, Math.round(loader.modelData.width * 0.94))
                maximumSize.height: Math.max(minimumSize.height, Math.round(loader.modelData.height * 0.9))

                contentItem.Config.screen: loader.modelData.name
                contentItem.Tokens.screen: loader.modelData.name

                AssistantHUD {
                    id: hudCard
                    anchors.fill: parent
                    maximumHudWidth: win.maximumSize.width
                    maximumHudHeight: win.maximumSize.height
                    windowRef: win
                    onCloseRequested: {
                        if (win.st) win.st.assistant = false
                    }
                }
            }
        }
    }
}
