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

                visible: win.st?.assistant ?? false
                onClosed: {
                    if (win.st) win.st.assistant = false
                    Assistant.isWatching = false
                }
                onVisibleChanged: {
                    if (!visible && win.st && win.st.assistant)
                        win.st.assistant = false
                    Assistant.isWatching = visible
                }

                title: "Assistant HUD"

                color: "transparent"
                surfaceFormat.opaque: false

                implicitWidth: hudCard.implicitWidth
                implicitHeight: hudCard.implicitHeight
                minimumSize.width: hudCard.implicitWidth
                minimumSize.height: hudCard.implicitHeight
                maximumSize.width: hudCard.implicitWidth
                maximumSize.height: hudCard.implicitHeight

                contentItem.Config.screen: loader.modelData.name
                contentItem.Tokens.screen: loader.modelData.name

                AssistantHUD {
                    id: hudCard
                    windowRef: win
                    onCloseRequested: {
                        if (win.st) win.st.assistant = false
                    }
                }
            }
        }
    }
}

