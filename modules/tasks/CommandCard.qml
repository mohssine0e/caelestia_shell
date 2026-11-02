pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls

StyledRect {
    id: root

    property var commandData: ({})
    property int itemIndex: 0
    property bool isSelected: false

    signal toggleStarRequested(string id)
    signal runRequested(string cmd)
    signal copyRequested(string cmd)

    property bool isExpanded: false
    property bool copied: false

    width: ListView.view ? ListView.view.width : (parent ? parent.width : 0)
    implicitHeight: mainCol.implicitHeight + 24

    radius: Tokens.rounding.medium
    color: "#16141a"
    border.width: 1
    border.color: root.isExpanded
        ? Qt.alpha("#ffca1b", 0.6)
        : (root.isSelected ? Qt.alpha("#d0bcff", 0.4) : Qt.alpha("#353140", 0.6))

    Behavior on border.color { CAnim {} }

    Timer {
        id: copyResetTimer
        interval: 1800
        onTriggered: root.copied = false
    }

    function doCopy() {
        Quickshell.clipboardText = root.commandData.cmd
        root.copied = true
        copyResetTimer.restart()
        root.copyRequested(root.commandData.cmd)
    }

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
                color: "#ede6df"
                Layout.alignment: Qt.AlignVCenter
            }

            // Category Pill (e.g. #arch, #network)
            StyledRect {
                implicitHeight: 20
                implicitWidth: catText.implicitWidth + 12
                radius: Tokens.rounding.full
                color: "#282433"

                StyledText {
                    id: catText
                    anchors.centerIn: parent
                    text: "#" + (root.commandData.category || "general")
                    font: Tokens.font.label.small
                    color: "#d0bcff"
                }
            }

            Item { Layout.fillWidth: true }

            // Shortcut Badge / Copy Button (when expanded shows Ctrl+C, when collapsed shows Copy)
            StyledRect {
                implicitHeight: 26
                implicitWidth: copyBtnRow.implicitWidth + 14
                radius: Tokens.rounding.small
                color: root.copied ? Qt.alpha("#4CAF50", 0.25) : "#25212e"
                border.width: 1
                border.color: root.copied ? "#4CAF50" : Qt.alpha("#d0bcff", 0.2)

                RowLayout {
                    id: copyBtnRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialIcon {
                        text: root.copied ? "check" : "content_copy"
                        fontStyle: Tokens.font.icon.small
                        color: root.copied ? "#4CAF50" : "#ede6df"
                    }

                    StyledText {
                        text: root.copied ? qsTr("Copied") : (root.isExpanded ? "Ctrl+C" : qsTr("Copy"))
                        font: Tokens.font.label.small
                        color: root.copied ? "#4CAF50" : "#ede6df"
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.doCopy()
                }
            }

            // Run Button
            StyledRect {
                implicitHeight: 26
                implicitWidth: runBtnRow.implicitWidth + 14
                radius: Tokens.rounding.small
                color: "#302b3d"
                border.width: 1
                border.color: Qt.alpha("#d0bcff", 0.3)

                RowLayout {
                    id: runBtnRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialIcon {
                        text: "play_arrow"
                        fontStyle: Tokens.font.icon.small
                        color: "#d0bcff"
                    }

                    StyledText {
                        text: qsTr("Run")
                        font: Tokens.font.label.small
                        color: "#d0bcff"
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runRequested(root.commandData.cmd)
                }
            }

            // Expand / Collapse Chevron
            Item {
                implicitWidth: 26
                implicitHeight: 26

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.isExpanded ? "keyboard_arrow_up" : "keyboard_arrow_down"
                    fontStyle: Tokens.font.icon.medium
                    color: Qt.alpha("#ede6df", 0.6)
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
            color: "#0d0c10"
            border.width: 1
            border.color: "#232128"

            RowLayout {
                id: cmdRow
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                spacing: 8

                // Terminal prompt sign
                StyledText {
                    text: ">_"
                    font.family: "monospace"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#ffca1b"
                }

                // Monospace command string with sudo highlight
                StyledText {
                    Layout.fillWidth: true
                    text: {
                        let raw = root.commandData.cmd || ""
                        raw = raw.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
                        if (raw.startsWith("sudo ")) {
                            return '<font color="#ffca1b">sudo</font> ' + raw.substring(5)
                        }
                        return raw
                    }
                    textFormat: Text.RichText
                    font.family: "monospace"
                    font.pixelSize: 13
                    color: "#f0ece9"
                    wrapMode: root.isExpanded ? Text.Wrap : Text.NoWrap
                    elide: root.isExpanded ? Text.ElideNone : Text.ElideRight
                }

                // Inner copy icon button
                StyledRect {
                    implicitWidth: innerCopyRow.implicitWidth + 12
                    implicitHeight: 24
                    radius: Tokens.rounding.small
                    color: root.copied ? Qt.alpha("#4CAF50", 0.25) : "#1f1c26"
                    border.width: 1
                    border.color: root.copied ? "#4CAF50" : Qt.alpha("#ede6df", 0.15)
                    visible: !root.isExpanded

                    RowLayout {
                        id: innerCopyRow
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            text: root.copied ? "check" : "content_copy"
                            fontStyle: Tokens.font.icon.small
                            color: root.copied ? "#4CAF50" : "#ede6df"
                        }

                        StyledText {
                            text: root.copied ? qsTr("Copied") : qsTr("Copy")
                            font: Tokens.font.label.small
                            color: root.copied ? "#4CAF50" : "#ede6df"
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.doCopy()
                    }
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
                    color: Qt.alpha("#ede6df", 0.5)
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.commandData.description || ""
                    font: Tokens.font.body.small
                    color: Qt.alpha("#ede6df", 0.75)
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
                        color: "#ffca1b"
                    }
                    StyledText {
                        text: qsTr("Flags:")
                        font: Tokens.font.label.small
                        color: Qt.alpha("#ede6df", 0.6)
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
                            color: "#211e29"
                            border.width: 1
                            border.color: "#353042"

                            RowLayout {
                                id: flagRow
                                anchors.centerIn: parent
                                spacing: 4

                                StyledText {
                                    text: modelData.flag + ":"
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: "#ffca1b"
                                }

                                StyledText {
                                    text: modelData.desc
                                    font: Tokens.font.label.small
                                    color: "#ede6df"
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
                color: Qt.alpha("#ede6df", 0.08)
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
                        color: Qt.alpha("#ede6df", 0.4)
                    }
                    StyledText {
                        text: root.commandData.folder || ""
                        font: Tokens.font.label.small
                        color: Qt.alpha("#ede6df", 0.5)
                    }
                }

                StyledText {
                    text: "|"
                    color: Qt.alpha("#ede6df", 0.2)
                    visible: !!root.commandData.folder
                }

                RowLayout {
                    spacing: 4
                    visible: !!root.commandData.updated
                    MaterialIcon {
                        text: "schedule"
                        fontStyle: Tokens.font.icon.small
                        color: Qt.alpha("#ede6df", 0.4)
                    }
                    StyledText {
                        text: qsTr("Updated: %1").arg(root.commandData.updated || "")
                        font: Tokens.font.label.small
                        color: Qt.alpha("#ede6df", 0.5)
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
                            color: Qt.alpha("#d0bcff", 0.7)
                        }
                        StyledText {
                            text: qsTr("Press to collapse")
                            font: Tokens.font.label.small
                            color: Qt.alpha("#d0bcff", 0.7)
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
