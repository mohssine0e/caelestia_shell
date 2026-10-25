pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.Multimedia
import Caelestia.Services
import Caelestia.State
import qs.components
import qs.components.controls
import qs.services

WlSessionLockSurface {
    id: root

    required property WlSessionLock lock
    required property Pam pam

    readonly property alias unlocking: unlockAnim.running
    readonly property int cardWidth: Math.round(Math.min(480, (root.screen?.width ?? 1920) * 0.35))
    readonly property int cardHeight: Math.round(Math.min(750, (root.screen?.height ?? 1080) * 0.77))

    contentItem.Config.screen: screen.name
    contentItem.Tokens.screen: screen.name

    color: "transparent"

    Connections {
        function onUnlock(): void {
            unlockAnim.start();
        }

        target: root.lock
    }

    SequentialAnimation {
        id: unlockAnim

        ParallelAnimation {
            Anim {
                target: lockContent
                properties: "implicitWidth,implicitHeight"
                to: lockContent.size
            }
            Anim {
                target: lockBg
                property: "radius"
                to: lockContent.radius
            }
            Anim {
                target: content
                property: "scale"
                to: 0
            }
            Anim {
                target: content
                property: "opacity"
                to: 0
                type: Anim.StandardSmall
            }
            Anim {
                target: lockIcon
                property: "opacity"
                to: 1
                type: Anim.StandardLarge
            }
            Anim {
                target: background
                property: "opacity"
                to: 0
                type: Anim.StandardLarge
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: Tokens.anim.durations.small
                }
                Anim {
                    type: Anim.Standard
                    target: lockContent
                    property: "opacity"
                    to: 0
                }
            }
        }
        PropertyAction {
            target: root.lock
            property: "locked"
            value: false
        }
    }

    ParallelAnimation {
        id: initAnim

        running: true

        Anim {
            target: background
            property: "opacity"
            to: 1
            type: Anim.StandardLarge
        }
        SequentialAnimation {
            ParallelAnimation {
                Anim {
                    target: lockContent
                    property: "scale"
                    to: 1
                    type: Anim.FastSpatial
                }
                Anim {
                    target: lockContent
                    property: "rotation"
                    to: 360
                    duration: Tokens.anim.durations.expressiveFastSpatial
                    easing: Tokens.anim.standardAccel
                }
            }
            ParallelAnimation {
                Anim {
                    target: lockIcon
                    property: "rotation"
                    to: 360
                    easing: Tokens.anim.standardDecel
                }
                Anim {
                    type: Anim.DefaultEffects
                    target: lockIcon
                    property: "opacity"
                    to: 0
                }
                Anim {
                    type: Anim.DefaultEffects
                    target: content
                    property: "opacity"
                    to: 1
                }
                Anim {
                    target: content
                    property: "scale"
                    to: 1
                }
                Anim {
                    target: lockBg
                    property: "radius"
                    to: lockContent.Tokens.rounding.extraExtraLarge * 1.5
                }
                Anim {
                    target: lockContent
                    property: "implicitWidth"
                    to: root.cardWidth
                }
                Anim {
                    target: lockContent
                    property: "implicitHeight"
                    to: root.cardHeight
                }
            }
        }
    }

    Item {
        id: background

        anchors.fill: parent
        opacity: 0

        layer.enabled: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1
            blurMax: 64
            blurMultiplier: 1
        }

        Loader {
            anchors.fill: parent
            sourceComponent: Config.lock.useWallpaper ? wallpaperBackground : screencopyBackground
        }
    }

    Component {
        id: screencopyBackground

        ScreencopyView {
            captureSource: root.screen
        }
    }

    Component {
        id: wallpaperBackground

        Visual {
            source: Wallpapers.current
            playing: PersistentState.wallpaperPlaying
        }
    }

    Item {
        id: lockContent

        readonly property int size: lockIcon.implicitHeight + Tokens.padding.large * 4
        readonly property int radius: size / 4 * Tokens.rounding.scale

        anchors.centerIn: parent
        implicitWidth: size
        implicitHeight: size

        visible: Config.lock.enabled
        rotation: 180
        scale: 0

        StyledRect {
            id: lockBg

            anchors.fill: parent
            color: Colours.palette.m3surface
            radius: parent.radius
            opacity: Colours.transparency.enabled ? Colours.transparency.base : 1
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.25)

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                blurMax: 20
                shadowVerticalOffset: 4
                shadowColor: Qt.alpha(Colours.palette.m3shadow, 0.6)
            }
        }

        MaterialIcon {
            id: lockIcon

            anchors.centerIn: parent
            text: "lock"
            fontStyle: Tokens.font.icon.builders.extraLarge.scale(4).weight(Font.Bold).build()
            rotation: 180
        }

        Content {
            id: content

            anchors.centerIn: parent
            width: root.cardWidth - Tokens.padding.large * 2
            height: root.cardHeight - Tokens.padding.large * 2

            lock: root
            opacity: 0
            scale: 0
        }
    }

    RowLayout {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.extraLarge
        spacing: Tokens.spacing.small
        opacity: root.pam.pendingShutdown ? 1.0 : (hoverCorner.hovered ? 1.0 : 0.45)

        Behavior on opacity {
            Anim { type: Anim.DefaultEffects }
        }

        HoverHandler {
            id: hoverCorner
        }

        StyledRect {
            id: shutdownBtn
            implicitWidth: 42
            implicitHeight: 42
            radius: Tokens.rounding.full
            color: root.pam.pendingShutdown 
                ? Colours.palette.m3error 
                : (shutMouse.containsMouse ? Colours.layer(Colours.tPalette.m3surfaceContainerHigh, 2) : Colours.tPalette.m3surfaceContainerHigh)
            border.color: root.pam.pendingShutdown ? Colours.palette.m3error : Qt.alpha(Colours.palette.m3outlineVariant, 0.3)
            border.width: root.pam.pendingShutdown ? 2 : 1

            scale: shutMouse.pressed ? 0.92 : (shutMouse.containsMouse ? 1.08 : 1.0)

            Behavior on scale {
                Anim { type: Anim.FastSpatial }
            }
            Behavior on color {
                Anim { type: Anim.FastEffects }
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: Config.session.icons.shutdown
                color: root.pam.pendingShutdown ? Colours.palette.m3onError : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.builders.small.scale(1.1).build()
            }

            MouseArea {
                id: shutMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.pam.pendingShutdown = !root.pam.pendingShutdown;
                }
            }
        }
    }
}
