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
    property bool isExpanded: false

    signal toggleStarRequested(string id)
    signal toggleExpandRequested(string id)

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

        // ── 1. Clickable Header Line (Expands / Collapses) ───────────
        Item {
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight

            // MouseArea covering the header row to expand / collapse
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleExpandRequested(root.commandData.id)
            }

            RowLayout {
                id: headerRow
                width: parent.width
                spacing: 8

            // Star Button (Clickable independently, z: 2)
            Item {
                implicitWidth: 24
                implicitHeight: 24
                z: 2

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.commandData.starred ? "star" : root.getCategoryIcon(root.commandData.category)
                    fontStyle: Tokens.font.icon.small
                    color: root.commandData.starred ? Colours.palette.m3tertiary : Colours.palette.m3primary
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

            // Category Pill
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

            // Case count badge
            StyledText {
                text: {
                    const cases = root.commandData.cases || []
                    return qsTr("%1 use cases").arg(cases.length)
                }
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

        // ── 2. Collapsed Preview Box (Selectable text, no >_) ───────
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: previewEdit.implicitHeight + 16
            radius: Tokens.rounding.small
            color: Colours.tPalette.m3surfaceContainerLowest
            border.width: 1
            border.color: Colours.palette.m3outlineVariant
            visible: !root.isExpanded

            TextEdit {
                id: previewEdit
                anchors.fill: parent
                anchors.margins: 8
                readOnly: true
                selectByMouse: true
                mouseSelectionMode: TextEdit.SelectCharacters
                activeFocusOnPress: false
                text: {
                    const cases = root.commandData.cases || []
                    return cases.length > 0 ? cases[0].cmd : (root.commandData.cmd || "")
                }
                font.family: "monospace"
                font.pixelSize: 13
                color: Colours.palette.m3onSurface
                selectionColor: Colours.palette.m3primary
                selectedTextColor: Colours.palette.m3onPrimary
                wrapMode: TextEdit.Wrap
            }
        }

        // ── 3. Expanded View (Description + All Use Cases) ──────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            visible: root.isExpanded

            // Tool Description
            StyledText {
                Layout.fillWidth: true
                text: root.commandData.description || ""
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.Wrap
                visible: !!root.commandData.description
            }

            // Use Cases List
            Repeater {
                model: root.commandData.cases || []
                delegate: ColumnLayout {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    spacing: 6

                    // Case Explanation
                    StyledText {
                        Layout.fillWidth: true
                        text: (index + 1) + ". " + (modelData.desc || modelData.title || "")
                        font: Tokens.font.label.large
                        color: Colours.palette.m3onSurface
                        wrapMode: Text.Wrap
                    }

                    // Selectable Code Box (No >_ symbol)
                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: caseEdit.implicitHeight + 16
                        radius: Tokens.rounding.small
                        color: Colours.tPalette.m3surfaceContainerLowest
                        border.width: 1
                        border.color: Colours.palette.m3outlineVariant

                        TextEdit {
                            id: caseEdit
                            anchors.fill: parent
                            anchors.margins: 8
                            readOnly: true
                            selectByMouse: true
                            mouseSelectionMode: TextEdit.SelectCharacters
                            activeFocusOnPress: false
                            text: modelData.cmd || ""
                            font.family: "monospace"
                            font.pixelSize: 13
                            color: Colours.palette.m3onSurface
                            selectionColor: Colours.palette.m3primary
                            selectedTextColor: Colours.palette.m3onPrimary
                            wrapMode: TextEdit.Wrap
                        }
                    }

                    // Direct Flag Explanations (No "Flags:" word or icon)
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: !!(modelData && modelData.flags && modelData.flags.length > 0)

                        Repeater {
                            model: (modelData && modelData.flags) ? modelData.flags : []
                            delegate: StyledRect {
                                required property var modelData
                                implicitHeight: 24
                                implicitWidth: flagRow.implicitWidth + 16
                                radius: Tokens.rounding.full
                                color: Colours.tPalette.m3surfaceContainer
                                border.width: 1
                                border.color: Colours.palette.m3outlineVariant

                                RowLayout {
                                    id: flagRow
                                    anchors.centerIn: parent
                                    spacing: 5

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
                    }
                }
            }
        }
    }
}
