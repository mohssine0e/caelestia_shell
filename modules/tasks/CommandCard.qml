pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    property var commandData: ({})
    property int itemIndex: 0
    property bool isSelected: false

    signal toggleStarRequested(string id)

    property bool isExpanded: false

    width: ListView.view ? ListView.view.width : (parent ? parent.width : 0)
    implicitHeight: mainCol.implicitHeight + 24

    radius: Tokens.rounding.medium
    color: root.isSelected ? Colours.tPalette.m3surfaceContainerHigh : Colours.tPalette.m3surfaceContainerLow
    border.width: 1
    border.color: root.isExpanded
        ? Colours.palette.m3tertiary
        : (root.isSelected ? Colours.palette.m3primary : Colours.palette.m3outlineVariant)

    Behavior on border.color { CAnim {} }

    function getCategoryIcon(cat) {
        switch (cat) {
            case "network": return "wifi"
            case "bluetooth": return "bluetooth"
            case "arch": return "terminal"
            case "files": return "folder"
            case "vpn": return "vpn_lock"
            case "display": return "desktop_windows"
            default: return "code"
        }
    }

    ColumnLayout {
        id: mainCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 10

        // ── 1. Header Line ──────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Star / Category Icon
            Item {
                implicitWidth: 24
                implicitHeight: 24

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.commandData.starred ? "star" : root.getCategoryIcon(root.commandData.category)
                    fontStyle: Tokens.font.icon.small
                    color: root.commandData.starred ? "#ffca1b" : "#d0bcff"
                    fill: root.commandData.starred ? 1 : 0
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleStarRequested(root.commandData.id)
                }
            }

            // Command Title
            StyledText {
                text: root.commandData.title || ""
                font: Tokens.font.title.small
                color: Colours.palette.m3onSurface
                Layout.alignment: Qt.AlignVCenter
            }

            // Category Pill (e.g. #arch, #network)
            StyledRect {
                implicitHeight: 20
                implicitWidth: catText.implicitWidth + 12
                radius: Tokens.rounding.full
                color: Colours.tPalette.m3surfaceContainer
                border.width: 1
                border.color: Colours.palette.m3outlineVariant

                StyledText {
                    id: catText
                    anchors.centerIn: parent
                    text: "#" + (root.commandData.category || "general")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3primary
                }
            }

            Item { Layout.fillWidth: true }

            // Expand / Collapse Chevron
            Item {
                implicitWidth: 26
                implicitHeight: 26

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.isExpanded ? "keyboard_arrow_up" : "keyboard_arrow_down"
                    fontStyle: Tokens.font.icon.medium
                    color: Colours.palette.m3onSurfaceVariant
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.isExpanded = !root.isExpanded
                }
            }
        }

        // ── 2. Terminal Code Box ────────────────────────────────────
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: Math.max(38, cmdRow.implicitHeight + 14)
            radius: Tokens.rounding.small
            color: Colours.tPalette.m3surfaceContainerLowest
            border.width: 1
            border.color: Colours.palette.m3outlineVariant

            RowLayout {
                id: cmdRow
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                // Terminal prompt sign
                StyledText {
                    text: ">_"
                    font.family: "monospace"
                    font.pixelSize: 13
                    font.bold: true
                    color: Colours.palette.m3tertiary
                }

                // Golden sudo keyword
                StyledText {
                    text: "sudo"
                    font.family: "monospace"
                    font.pixelSize: 13
                    font.bold: true
                    color: Colours.palette.m3tertiary
                    visible: (root.commandData.cmd || "").startsWith("sudo ")
                }

                // Monospace command string
                StyledText {
                    Layout.fillWidth: true
                    text: (root.commandData.cmd || "").startsWith("sudo ")
                        ? (root.commandData.cmd || "").substring(5)
                        : (root.commandData.cmd || "")
                    font.family: "monospace"
                    font.pixelSize: 13
                    color: Colours.palette.m3onSurface
                    wrapMode: root.isExpanded ? Text.Wrap : Text.NoWrap
                    elide: root.isExpanded ? Text.ElideNone : Text.ElideRight
                }
            }
        }

        // ── 3. Expanded Detail Sections (Visible only when expanded) ─
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.isExpanded

            // Description Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: !!root.commandData.description

                MaterialIcon {
                    text: "info"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.commandData.description || ""
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.Wrap
                }
            }

            // Flags Breakdown Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: root.commandData.flags && root.commandData.flags.length > 0

                RowLayout {
                    spacing: 4
                    MaterialIcon {
                        text: "flag"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3tertiary
                    }
                    StyledText {
                        text: qsTr("Flags:")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }

                // Horizontal Row of Flag Pills
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: root.commandData.flags || []
                        delegate: StyledRect {
                            required property var modelData
                            implicitHeight: 22
                            implicitWidth: flagRow.implicitWidth + 14
                            radius: Tokens.rounding.full
                            color: Colours.tPalette.m3surfaceContainer
                            border.width: 1
                            border.color: Colours.palette.m3outlineVariant

                            RowLayout {
                                id: flagRow
                                anchors.centerIn: parent
                                spacing: 4

                                StyledText {
                                    text: modelData.flag + ":"
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Colours.palette.m3tertiary
                                }

                                StyledText {
                                    text: modelData.desc
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3onSurface
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }

            // Divider
            StyledRect {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Colours.palette.m3outlineVariant
            }

            // Metadata Footer
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                RowLayout {
                    spacing: 4
                    visible: !!root.commandData.folder
                    MaterialIcon {
                        text: "folder"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                    StyledText {
                        text: root.commandData.folder || ""
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }

                StyledText {
                    text: "|"
                    color: Colours.palette.m3outlineVariant
                    visible: !!root.commandData.folder
                }

                RowLayout {
                    spacing: 4
                    visible: !!root.commandData.updated
                    MaterialIcon {
                        text: "schedule"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                    StyledText {
                        text: qsTr("Updated: %1").arg(root.commandData.updated || "")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }

                Item { Layout.fillWidth: true }

                // Collapse prompt
                Item {
                    implicitWidth: collapseRow.implicitWidth
                    implicitHeight: collapseRow.implicitHeight

                    RowLayout {
                        id: collapseRow
                        anchors.fill: parent
                        spacing: 4

                        MaterialIcon {
                            text: "keyboard_arrow_up"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3primary
                        }
                        StyledText {
                            text: qsTr("Press to collapse")
                            font: Tokens.font.label.small
                            color: Colours.palette.m3primary
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.isExpanded = false
                    }
                }
            }
        }
    }
}
