pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import M3Shapes
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Multimedia
import qs.components
import qs.components.effects
import qs.components.filedialog
import qs.services
import qs.utils

StyledRect {
    id: root

    required property ScreenState screenState
    required property FileDialog facePicker

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.extraLarge
    implicitHeight: 64
    Layout.fillWidth: true

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.large
        anchors.topMargin: Tokens.padding.small
        anchors.bottomMargin: Tokens.padding.small
        spacing: Tokens.spacing.medium

        // Left: Avatar with Uptime Badge
        Item {
            id: avatarContainer
            implicitWidth: 44
            implicitHeight: 44
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                id: avatarMask
                anchors.fill: parent
                radius: width / 2
                color: Colours.palette.m3surfaceContainerHighest
                visible: false
            }

            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: Mask {
                    maskSource: avatarMask
                }

                Visual {
                    id: pfp
                    anchors.fill: parent
                    source: `${Paths.home}/.face`
                }
            }

            // Hover overlay to change avatar
            MouseArea {
                id: pfpMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.screenState.dashboard = false;
                    root.facePicker.open();
                }
            }

            // Mini Badge at Bottom-Right
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.bottomMargin: -2
                anchors.rightMargin: -2
                width: 16
                height: 16
                radius: 8
                color: Colours.palette.m3tertiaryContainer
                border.width: 1.5
                border.color: Colours.palette.m3surface

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "history"
                    color: Colours.palette.m3onTertiaryContainer
                    fontStyle: Tokens.font.icon.builders.small.scale(0.55).build()
                }
            }
        }

        // Center-Left: OS & Window Manager
        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 1

            RowLayout {
                spacing: 6
                ColouredIcon {
                    source: SysInfo.osLogo
                    implicitSize: 16
                    colour: Colours.palette.m3primary
                }

                StyledText {
                    text: SysInfo.osName.replace(" Linux", "")
                    font: Tokens.font.title.small
                    color: Colours.palette.m3onSurface
                }
            }

            RowLayout {
                spacing: 6
                MaterialIcon {
                    text: "select_window"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.builders.small.scale(0.7).build()
                }

                StyledText {
                    text: SysInfo.wm
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }

        Item { Layout.fillWidth: true }

        // Right: Digital Clock & Uptime
        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 1

            StyledText {
                Layout.alignment: Qt.AlignRight
                text: Time.format("hh:mm")
                font: Tokens.font.title.builders.large.weight(Font.Bold).build()
                color: Colours.palette.m3onSurface
            }

            StyledText {
                Layout.alignment: Qt.AlignRight
                text: "UPTIME: " + SysInfo.uptimeShort.toUpperCase()
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }
}
