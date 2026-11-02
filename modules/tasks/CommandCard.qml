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
    implicitHeight: mainCol.implicitHeight + 24

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
        anchors.margins: 12
        spacing: 10

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
                    implicitWidth: 26
                    implicitHeight: 26
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
            spacing: 8
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
                spacing: 8
                visible: !!root.previewCommandText

                // Monospace preview code box
                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: Tokens.rounding.small
                    color: "#0a0a0f"
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant

                    TextEdit {
                        id: previewEdit
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.topMargin: 8
                        readOnly: true
                        selectByMouse: true
                        mouseSelectionMode: TextEdit.SelectCharacters
                        activeFocusOnPress: false
                        textFormat: TextEdit.RichText
                        text: root.formatSyntaxHighlight(root.previewCommandText)
                        font.family: "monospace"
                        font.pixelSize: 13
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
                    implicitHeight: 36
                    implicitWidth: previewCopyRow.implicitWidth + 18
                    radius: Tokens.rounding.small
                    color: copied ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer
                    border.width: 1
                    border.color: copied ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

                    RowLayout {
                        id: previewCopyRow
                        anchors.centerIn: parent
                        spacing: 5

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
                    implicitHeight: 36
                    implicitWidth: previewExpandRow.implicitWidth + 18
                    radius: Tokens.rounding.small
                    color: Colours.tPalette.m3surfaceContainer
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant

                    RowLayout {
                        id: previewExpandRow
                        anchors.centerIn: parent
                        spacing: 5

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

        // ── 3. Expanded View (Full tool description + individual command entries)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
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
                opacity: 0.35
            }

            // Individual Commands
            Repeater {
                model: root.commandsList
                delegate: StyledRect {
                    id: cmdEntry
                    required property var modelData
                    required property int index

                    property bool showDetails: false
                    property bool copied: false

                    readonly property bool hasDetails: !!(modelData.flags && modelData.flags.length > 0)
                                                    || !!(modelData.placeholders && modelData.placeholders.length > 0)
                                                    || !!(modelData.params && modelData.params.length > 0)
                                                    || !!modelData.warning
                                                    || !!modelData.prereqs
                                                    || !!modelData.notes

                    Layout.fillWidth: true
                    implicitHeight: cmdEntryCol.implicitHeight + 20
                    radius: Tokens.rounding.small
                    color: Colours.tPalette.m3surfaceContainerLowest
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant

                    ColumnLayout {
                        id: cmdEntryCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 8

                        // 1. Command Header Line
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            // Command Title & Sudo Badge (Clickable to toggle details)
                            Item {
                                implicitHeight: 26
                                implicitWidth: titleRow.implicitWidth

                                RowLayout {
                                    id: titleRow
                                    anchors.fill: parent
                                    spacing: 8

                                    StyledText {
                                        text: modelData.title || (qsTr("Command %1").arg(index + 1))
                                        font: Tokens.font.title.small
                                        color: Colours.palette.m3onSurface
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    // Sudo Badge if elevated
                                    StyledRect {
                                        implicitHeight: 20
                                        implicitWidth: sudoText.implicitWidth + 10
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
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: cmdEntry.hasDetails ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (cmdEntry.hasDetails) cmdEntry.showDetails = !cmdEntry.showDetails
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // Copy Command Button
                            StyledRect {
                                id: cmdCopyBtn
                                implicitHeight: 28
                                implicitWidth: cmdCopyRow.implicitWidth + 16
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

                            // Details Toggle Button
                            StyledRect {
                                implicitHeight: 28
                                implicitWidth: detailsRow.implicitWidth + 16
                                radius: Tokens.rounding.small
                                color: cmdEntry.showDetails ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer
                                border.width: 1
                                border.color: cmdEntry.showDetails ? Colours.palette.m3secondary : Colours.palette.m3outlineVariant
                                visible: !!(modelData.flags && modelData.flags.length > 0)
                                      || !!(modelData.placeholders && modelData.placeholders.length > 0)
                                      || !!(modelData.params && modelData.params.length > 0)
                                      || !!modelData.warning
                                      || !!modelData.prereqs
                                      || !!modelData.notes

                                RowLayout {
                                    id: detailsRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    StyledText {
                                        text: qsTr("Details")
                                        font: Tokens.font.label.small
                                        color: cmdEntry.showDetails ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                                    }

                                    MaterialIcon {
                                        text: cmdEntry.showDetails ? "expand_less" : "expand_more"
                                        fontStyle: Tokens.font.icon.small
                                        color: cmdEntry.showDetails ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: cmdEntry.showDetails = !cmdEntry.showDetails
                                }
                            }
                        }

                        // 2. Command Explanation
                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.desc || ""
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                            wrapMode: Text.Wrap
                            visible: !!modelData.desc
                        }

                        // 3. Monospace Code Block
                        StyledRect {
                            Layout.fillWidth: true
                            implicitHeight: caseEdit.implicitHeight + 16
                            radius: Tokens.rounding.small
                            color: "#0a0a0f"
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
                                textFormat: TextEdit.RichText
                                text: root.formatSyntaxHighlight(modelData.cmd || "")
                                font.family: "monospace"
                                font.pixelSize: 13
                                color: Colours.palette.m3onSurface
                                selectionColor: Colours.palette.m3primary
                                selectedTextColor: Colours.palette.m3onPrimary
                                wrapMode: TextEdit.Wrap
                            }
                        }

                        // 4. Details Section (Level 3 - flags, warnings, params, placeholders)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: cmdEntry.showDetails

                            // Warning Alert Box
                            StyledRect {
                                Layout.fillWidth: true
                                implicitHeight: warnRow.implicitHeight + 14
                                radius: Tokens.rounding.small
                                color: "#251a05"
                                border.width: 1
                                border.color: Colours.palette.m3tertiary
                                visible: !!modelData.warning

                                RowLayout {
                                    id: warnRow
                                    anchors.fill: parent
                                    anchors.margins: 7
                                    spacing: 8

                                    MaterialIcon {
                                        text: "warning"
                                        fontStyle: Tokens.font.icon.small
                                        color: Colours.palette.m3tertiary
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.warning || ""
                                        font: Tokens.font.body.small
                                        color: Colours.palette.m3onSurface
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }

                            // Prerequisites line
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                visible: !!modelData.prereqs

                                MaterialIcon {
                                    text: "lock"
                                    fontStyle: Tokens.font.icon.small
                                    color: Colours.palette.m3secondary
                                }

                                StyledText {
                                    text: qsTr("Prerequisites: %1").arg(modelData.prereqs || "")
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3secondary
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }

                            // Flag Chips (Clickable to search)
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                visible: !!(modelData.flags && modelData.flags.length > 0)

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

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.flagClicked(modelData.flag)
                                        }
                                    }
                                }
                            }

                            // Placeholders Definition
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                visible: !!(modelData.placeholders && modelData.placeholders.length > 0)

                                Repeater {
                                    model: (modelData && modelData.placeholders) ? modelData.placeholders : []
                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 8

                                        StyledText {
                                            text: modelData.name + ":"
                                            font.family: "monospace"
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: Colours.palette.m3primary
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.desc
                                            font: Tokens.font.body.small
                                            color: Colours.palette.m3onSurfaceVariant
                                            wrapMode: Text.Wrap
                                        }
                                    }
                                }
                            }

                            // Structured Technical Parameters (NetworkManager 802.1x EAP/Inner/MAC)
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                visible: !!(modelData.params && modelData.params.length > 0)

                                Repeater {
                                    model: (modelData && modelData.params) ? modelData.params : []
                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 12

                                        StyledText {
                                            text: modelData.key
                                            font: Tokens.font.label.medium
                                            color: Colours.palette.m3tertiary
                                            Layout.preferredWidth: 110
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.value
                                            font: Tokens.font.body.small
                                            color: Colours.palette.m3onSurface
                                            wrapMode: Text.Wrap
                                        }
                                    }
                                }
                            }

                            // Notes / Tips
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                visible: !!modelData.notes

                                MaterialIcon {
                                    text: "lightbulb"
                                    fontStyle: Tokens.font.icon.small
                                    color: Colours.palette.m3secondary
                                }

                                StyledText {
                                    text: modelData.notes || ""
                                    font: Tokens.font.body.small
                                    color: Colours.palette.m3onSurfaceVariant
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
