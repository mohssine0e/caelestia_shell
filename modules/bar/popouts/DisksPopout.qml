pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

ColumnLayout {
    id: root

    required property PopoutState popouts

    width: 290
    spacing: Tokens.spacing.small

    // ── Header Row ──────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.padding.small
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: Disks.primaryIcon
            fontStyle: Tokens.font.icon.medium
            color: Colours.palette.m3primary
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            StyledText {
                text: qsTr("Removable Drives")
                font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                color: Colours.palette.m3onSurface
            }

            StyledText {
                text: {
                    if (Disks.count === 0) return qsTr("No drives connected");
                    return qsTr("%n drive(s) connected", "", Disks.count);
                }
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }

        IconButton {
            type: IconButton.Tonal
            icon: "refresh"
            font: Tokens.font.icon.small
            implicitWidth: 32
            implicitHeight: 32
            onClicked: Disks.refresh()
        }
    }

    // ── Ejecting in progress indicator ──────────────────────
    RowLayout {
        Layout.fillWidth: true
        visible: Disks.isEjecting
        spacing: Tokens.spacing.small
        Layout.topMargin: 4
        Layout.bottomMargin: 4

        CircularIndicator {
            implicitSize: 18
            running: Disks.isEjecting
        }

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Flushing & safely removing...")
            font: Tokens.font.body.small
            color: Colours.palette.m3primary
        }
    }

    // ── Drives List ─────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall
        visible: Disks.count > 0

        Repeater {
            model: Disks.drives

            delegate: StyledRect {
                id: driveCard
                required property var modelData

                Layout.fillWidth: true
                implicitHeight: cardRow.implicitHeight + Tokens.padding.small * 2
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

                RowLayout {
                    id: cardRow
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: driveCard.modelData.icon || "usb"
                        fontStyle: Tokens.font.icon.medium
                        color: driveCard.modelData.is_mounted ? Colours.palette.m3primary : Colours.palette.m3outline
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: driveCard.modelData.name || qsTr("USB Drive")
                            font: Tokens.font.label.medium
                            color: Colours.palette.m3onSurface
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                const sizeStr = driveCard.modelData.size ? (driveCard.modelData.size + " • ") : "";
                                const statusStr = driveCard.modelData.is_mounted ? qsTr("Mounted") : qsTr("Ready to unplug");
                                return sizeStr + statusStr;
                            }
                            font: Tokens.font.label.small
                            color: driveCard.modelData.is_mounted ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3outline
                            elide: Text.ElideRight
                        }
                    }

                    // Eject / Safely Remove button
                    IconButton {
                        type: IconButton.Filled
                        icon: "eject"
                        font: Tokens.font.icon.small
                        implicitWidth: 34
                        implicitHeight: 34
                        enabled: !Disks.isEjecting
                        onClicked: Disks.eject(driveCard.modelData)
                    }
                }
            }
        }
    }

    // ── Eject All Button (when multiple) ────────────────────
    TextButton {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.extraSmall
        visible: Disks.count > 1
        text: qsTr("Safely Remove All")
        enabled: !Disks.isEjecting
        onClicked: Disks.ejectAll()
    }
}

