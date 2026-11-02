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
    signal flagClicked(string flag)

    width: ListView.view ? ListView.view.width : (parent ? parent.width : 0)
    implicitHeight: mainCol.implicitHeight + 18

    radius: Tokens.rounding.medium
    color: root.isSelected ? Colours.tPalette.m3surfaceContainerHigh : Colours.tPalette.m3surfaceContainerLow
    border.width: 1
    border.color: root.isExpanded
        ? Colours.palette.m3tertiary
        : (root.isSelected ? Colours.palette.m3primary : Colours.palette.m3outlineVariant)

    Behavior on border.color { CAnim {} }

    readonly property var commandsList: {
        if (!root.commandData) return []
        if (root.commandData.commands && root.commandData.commands.length !== undefined)
            return root.commandData.commands
        if (root.commandData.cases && root.commandData.cases.length !== undefined)
            return root.commandData.cases
        return []
    }

    readonly property string previewCommandText: {
        if (root.commandData.previewCmd) return root.commandData.previewCmd
        const list = root.commandsList
        if (list.length > 0 && list[0].cmd) return list[0].cmd
        return root.commandData.cmd || ""
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

    function formatSyntaxHighlight(cmd) {
        if (!cmd) return ""
        let s = cmd.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        // Sudo keyword in amber
        s = s.replace(/\b(sudo)\b/g, '<font color="#ffb74d"><b>$1</b></font>')
        // Executables in violet/primary
        s = s.replace(/\b(pacman|nmcli|systemctl|rfkill|bluetoothctl|warp-cli|curl|sed|ncdu|mount|paccache)\b/g, '<font color="#d0bcff"><b>$1</b></font>')
        // Flags (-Syu, -Rns, --needed, etc.) in light cyan
        s = s.replace(/(\s)(-[a-zA-Z0-9_-]+)/g, '$1<font color="#80d4ff">$2</font>')
        // Placeholders (&lt;package&gt;, &lt;SSID&gt;, &lt;PASSWORD&gt;, etc.) in gold
        s = s.replace(/(&lt;[a-zA-Z0-9_-]+&gt;)/g, '<font color="#fbc02d"><i>$1</i></font>')
        return s
    }

    ColumnLayout {
        id: mainCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        spacing: 8

        // ── 1. Tool Header Line ─────────────────────────────────────
        Item {
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight

            // Click entire header row to expand / collapse
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

                // Tool Title
                StyledText {
                    text: root.commandData.title || ""
                    font: Tokens.font.title.small
                    color: Colours.palette.m3onSurface
                    Layout.alignment: Qt.AlignVCenter
                }

                // Subtitle / Tagline (e.g. Package Manager)
                StyledText {
                    text: root.commandData.subtitle ? ("· " + root.commandData.subtitle) : ""
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onSurfaceVariant
                    Layout.alignment: Qt.AlignVCenter
                    visible: !!root.commandData.subtitle
                }

                // Category Pill
                StyledRect {
                    implicitHeight: 18
                    implicitWidth: catText.implicitWidth + 10
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

                // Available commands count
                StyledText {
                    text: qsTr("%1 commands").arg(root.commandsList.length)
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                    Layout.alignment: Qt.AlignVCenter
                }

                // Expand / Collapse Chevron
                MaterialIcon {
                    text: root.isExpanded ? "expand_less" : "expand_more"
                    fontStyle: Tokens.font.icon.small
                    color: root.isExpanded ? Colours.palette.m3tertiary : Colours.palette.m3onSurfaceVariant
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }

        // ── 2. Collapsed View: 1-line description + Preview Box + [Copy] + [Expand]
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: !root.isExpanded

            // Short one-line description
            StyledText {
                Layout.fillWidth: true
                text: root.commandData.description || ""
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
                visible: !!root.commandData.description
            }

            // Command Preview Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: !!root.previewCommandText

                // Monospace preview code box
                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: Tokens.rounding.small
                    color: "#0a0a0f"
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant

                    TextEdit {
                        id: previewEdit
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.topMargin: 6
                        readOnly: true
                        selectByMouse: true
                        mouseSelectionMode: TextEdit.SelectCharacters
                        activeFocusOnPress: false
                        textFormat: TextEdit.RichText
                        text: root.formatSyntaxHighlight(root.previewCommandText)
                        font.family: "monospace"
                        font.pixelSize: 12
                        color: Colours.palette.m3onSurface
                        selectionColor: Colours.palette.m3primary
                        selectedTextColor: Colours.palette.m3onPrimary
                        wrapMode: TextEdit.NoWrap
                    }
                }

                // Copy Preview Button
                StyledRect {
                    id: previewCopyBtn
                    property bool copied: false
                    implicitHeight: 32
                    implicitWidth: previewCopyRow.implicitWidth + 14
                    radius: Tokens.rounding.small
                    color: copied ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer
                    border.width: 1
                    border.color: copied ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

                    RowLayout {
                        id: previewCopyRow
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            text: previewCopyBtn.copied ? "check" : "content_copy"
                            fontStyle: Tokens.font.icon.small
                            color: previewCopyBtn.copied ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                        }

                        StyledText {
                            text: previewCopyBtn.copied ? qsTr("Copied!") : qsTr("Copy")
                            font: Tokens.font.label.small
                            color: previewCopyBtn.copied ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                        }
                    }

                    Timer {
                        id: previewCopyTimer
                        interval: 1500
                        onTriggered: previewCopyBtn.copied = false
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.clipboardText = root.previewCommandText
                            previewCopyBtn.copied = true
                            previewCopyTimer.restart()
                        }
                    }
                }

                // Expand Button
                StyledRect {
                    implicitHeight: 32
                    implicitWidth: previewExpandRow.implicitWidth + 14
                    radius: Tokens.rounding.small
                    color: Colours.tPalette.m3surfaceContainer
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant

                    RowLayout {
                        id: previewExpandRow
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            text: "expand_more"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3primary
                        }

                        StyledText {
                            text: qsTr("Expand")
                            font: Tokens.font.label.small
                            color: Colours.palette.m3primary
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleExpandRequested(root.commandData.id)
                    }
                }
            }
        }

        // ── 3. Expanded View (Full tool description + all commands with details shown directly)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.isExpanded

            // Tool Full Description
            StyledText {
                Layout.fillWidth: true
                text: root.commandData.description || ""
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.Wrap
                visible: !!root.commandData.description
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Colours.palette.m3outlineVariant
                opacity: 0.3
            }

            // Individual Commands
            Repeater {
                model: root.commandsList
                delegate: ColumnLayout {
                    id: cmdEntry
                    required property var modelData
                    required property int index

                    property bool copied: false

                    Layout.fillWidth: true
                    spacing: 5

                    // Divider between commands (except before first command)
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Colours.palette.m3outlineVariant
                        opacity: 0.2
                        visible: index > 0
                    }

                    // 1. Command Header Line
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        // Number & Title
                        StyledText {
                            text: (index + 1) + ". " + (modelData.title || qsTr("Command %1").arg(index + 1))
                            font: Tokens.font.label.large
                            color: Colours.palette.m3onSurface
                            Layout.alignment: Qt.AlignVCenter
                        }

                        // Sudo Badge if elevated
                        StyledRect {
                            implicitHeight: 18
                            implicitWidth: sudoText.implicitWidth + 8
                            radius: Tokens.rounding.full
                            color: Colours.tPalette.m3surfaceContainer
                            border.width: 1
                            border.color: Colours.palette.m3tertiary
                            visible: !!modelData.sudo || (typeof modelData.cmd === "string" && modelData.cmd.startsWith("sudo"))

                            StyledText {
                                id: sudoText
                                anchors.centerIn: parent
                                text: "sudo"
                                font: Tokens.font.label.small
                                color: Colours.palette.m3tertiary
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Copy Command Button
                        StyledRect {
                            id: cmdCopyBtn
                            implicitHeight: 24
                            implicitWidth: cmdCopyRow.implicitWidth + 12
                            radius: Tokens.rounding.small
                            color: cmdEntry.copied ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer
                            border.width: 1
                            border.color: cmdEntry.copied ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

                            RowLayout {
                                id: cmdCopyRow
                                anchors.centerIn: parent
                                spacing: 4

                                MaterialIcon {
                                    text: cmdEntry.copied ? "check" : "content_copy"
                                    fontStyle: Tokens.font.icon.small
                                    color: cmdEntry.copied ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                }

                                StyledText {
                                    text: cmdEntry.copied ? qsTr("Copied!") : qsTr("Copy")
                                    font: Tokens.font.label.small
                                    color: cmdEntry.copied ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                }
                            }

                            Timer {
                                id: cmdCopyTimer
                                interval: 1500
                                onTriggered: cmdEntry.copied = false
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Quickshell.clipboardText = modelData.cmd || ""
                                    cmdEntry.copied = true
                                    cmdCopyTimer.restart()
                                }
                            }
                        }
                    }

                    // 2. Monospace Code Block
                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: caseEdit.implicitHeight + 12
                        radius: Tokens.rounding.small
                        color: "#0a0a0f"
                        border.width: 1
                        border.color: Colours.palette.m3outlineVariant

                        TextEdit {
                            id: caseEdit
                            anchors.fill: parent
                            anchors.margins: 6
                            readOnly: true
                            selectByMouse: true
                            mouseSelectionMode: TextEdit.SelectCharacters
                            activeFocusOnPress: false
                            textFormat: TextEdit.RichText
                            text: root.formatSyntaxHighlight(modelData.cmd || "")
                            font.family: "monospace"
                            font.pixelSize: 12
                            color: Colours.palette.m3onSurface
                            selectionColor: Colours.palette.m3primary
                            selectedTextColor: Colours.palette.m3onPrimary
                            wrapMode: TextEdit.Wrap
                        }
                    }

                    // 3. Compact Flag / Parameter Pills
                    Flow {
                        Layout.fillWidth: true
                        spacing: 5
                        visible: !!(modelData.flags && modelData.flags.length > 0)

                        Repeater {
                            model: (modelData && modelData.flags) ? modelData.flags : []
                            delegate: StyledRect {
                                required property var modelData
                                implicitHeight: 20
                                implicitWidth: flagRow.implicitWidth + 12
                                radius: Tokens.rounding.full
                                color: Colours.tPalette.m3surfaceContainer
                                border.width: 1
                                border.color: Colours.palette.m3outlineVariant

                                RowLayout {
                                    id: flagRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    StyledText {
                                        text: modelData.flag
                                        font.family: "monospace"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: Colours.palette.m3tertiary
                                    }

                                    StyledText {
                                        text: modelData.desc
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3onSurfaceVariant
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.flagClicked(modelData.flag)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
