pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import Caelestia.I18n
import Caelestia.State
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root

    required property Props props
    required property ScreenState screenState
    readonly property int notifCount: Notifs.list.reduce((acc, n) => n.closed ? acc : acc + 1, 0)

    Component.onCompleted: Notifs.list.forEach(n => n.popup = false)

    StyledRect {
        id: title

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right

        implicitHeight: Math.max(count.implicitHeight, titleText.implicitHeight, clearBtn.implicitHeight) + Tokens.padding.extraSmall
        radius: Tokens.rounding.full
        color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.7)

        StyledText {
            id: count

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: root.notifCount > 0 ? Tokens.padding.medium : Tokens.padding.medium - width - titleText.anchors.leftMargin
            opacity: root.notifCount > 0 ? 1 : 0

            text: root.notifCount
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.medium

            Behavior on anchors.leftMargin {
                Anim {}
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        StyledText {
            id: titleText

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: count.right
            anchors.right: dndBtn.left
            anchors.leftMargin: Tokens.spacing.extraSmall
            anchors.rightMargin: Tokens.spacing.extraSmall

            // TRANSLATORS: the count itself is rendered separately, immediately to the left
            text: root.notifCount > 0 ? Tr.trCtxN("notification", "notifications", root.notifCount, "notification count label, number shown separately") : Tr.tr("Notifications")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.medium
            elide: Text.ElideRight
        }

        IconButton {
            id: dndBtn

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: clearBtn.visible ? clearBtn.left : parent.right
            anchors.rightMargin: clearBtn.visible ? Tokens.spacing.extraSmall : Tokens.padding.extraSmall
            isToggle: true
            checked: PersistentState.doNotDisturb
            icon: PersistentState.doNotDisturb ? "notifications_off" : "notifications"
            font: Tokens.font.icon.medium
            padding: Tokens.padding.extraSmall
            inactiveColour: "transparent"
            inactiveOnColour: Colours.palette.m3onSurfaceVariant
            activeColour: Qt.alpha(Colours.palette.m3secondaryContainer, 0.85)
            activeOnColour: Colours.palette.m3onSecondaryContainer
            onClicked: PersistentState.doNotDisturb = !PersistentState.doNotDisturb
        }

        IconButton {
            id: clearBtn

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: Tokens.padding.extraSmall
            visible: root.notifCount > 0
            icon: clearConfirmTimer.running ? "delete_forever" : "delete_sweep"
            font: Tokens.font.icon.medium
            padding: Tokens.padding.extraSmall
            inactiveColour: clearConfirmTimer.running ? Qt.alpha(Colours.palette.m3errorContainer, 0.85) : "transparent"
            inactiveOnColour: clearConfirmTimer.running ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSurfaceVariant
            onClicked: {
                if (clearConfirmTimer.running) {
                    clearConfirmTimer.stop();
                    clearTimer.start();
                } else {
                    clearConfirmTimer.restart();
                }
            }

            Timer {
                id: clearConfirmTimer

                interval: 3000
            }
        }
    }

    ClipRect {
        id: clipRect

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: title.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: Tokens.spacing.small

        radius: Tokens.rounding.medium
        color: "transparent"

        Loader {
            asynchronous: true
            anchors.centerIn: parent
            active: opacity > 0
            opacity: root.notifCount > 0 ? 0 : 1

            sourceComponent: ColumnLayout {
                spacing: Tokens.spacing.extraLarge

                Image {
                    asynchronous: true
                    source: Paths.absolutePath(Config.paths.noNotifsPic)
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: clipRect.width * 0.8 * ((QsWindow.window as QsWindow)?.devicePixelRatio ?? 1)

                    layer.enabled: true
                    layer.effect: Colouriser {
                        colorizationColor: Colours.palette.m3outlineVariant
                        brightness: 1
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Tr.tr("All up to date!")
                    color: Colours.palette.m3outlineVariant
                    font: Tokens.font.headline.builders.small.width(90).build()
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.StandardExtraLarge
                }
            }
        }

        StyledFlickable {
            id: view

            anchors.fill: parent

            flickableDirection: Flickable.VerticalFlick
            contentWidth: width
            contentHeight: notifList.implicitHeight

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: view
            }

            NotifDockList {
                id: notifList

                props: root.props
                screenState: root.screenState
                container: view
            }
        }
    }

    Timer {
        id: clearTimer

        repeat: true
        triggeredOnStart: true
        interval: Math.max(15, Math.min(80, 69.8 - 12.3 * Math.log(Notifs.notClosed.length)))
        onTriggered: {
            const first = Notifs.notClosed[0];
            if (!first) {
                stop();
                return;
            }

            const appName = first.appName;
            let cleared = 0;
            for (const n of Notifs.notClosed.filter(n => n.appName === appName)) {
                n.close();
                cleared++;
                if (cleared > 30) {
                    interval = 5;
                    return;
                }
            }
        }
    }


}
