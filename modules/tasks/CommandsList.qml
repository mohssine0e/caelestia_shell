pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.containers
import qs.services

FocusScope {
    id: root

    property string searchQuery: ""
    property string selectedCategory: "all"
    property int selectedIndex: 0
    property string expandedCommandId: ""
    property var allCommands: []

    onAllCommandsChanged: {
        if (root.allCommands.length > 0 && root.expandedCommandId === "") {
            root.expandedCommandId = root.allCommands[0].id
        }
    }

    readonly property string commandsPath: Quickshell.env("HOME") + "/.config/caelestia/commands.json"

    signal escapePressed()
    signal flagSearchRequested(string query)

    // ── Persistence via FileView ────────────────────────────────
    FileView {
        id: commandsFile
        path: root.commandsPath
        printErrors: false

        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                if (Array.isArray(parsed)) {
                    root.allCommands = parsed
                    if (parsed.length > 0 && root.expandedCommandId === "") {
                        root.expandedCommandId = parsed[0].id
                    }
                }
            } catch (e) {
                root.allCommands = []
            }
        }
    }

    function saveCommands() {
        if (!commandsFile) return
        commandsFile.setText(JSON.stringify(root.allCommands, null, 2))
    }

    function toggleStar(cmdId) {
        const list = root.allCommands.slice()
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === cmdId) {
                list[i].starred = !list[i].starred
                break
            }
        }
        root.allCommands = list
        root.saveCommands()
    }

    // ── Filtered Model ──────────────────────────────────────────
    readonly property var filteredCommands: {
        const q = root.searchQuery.trim().toLowerCase()
        const cat = root.selectedCategory

        return (root.allCommands || []).filter(item => {
            // Category filter
            if (cat === "starred") {
                if (!item.starred) return false
            } else if (cat !== "all") {
                if ((item.category || "").toLowerCase() !== cat) return false
            }

            // Search query filter (matches tool title, subtitle, description, category, or any command/flags/params)
            if (q.length > 0) {
                const titleMatch = (item.title || "").toLowerCase().includes(q)
                const subtitleMatch = (item.subtitle || "").toLowerCase().includes(q)
                const descMatch = (item.description || "").toLowerCase().includes(q)
                const catMatch = (item.category || "").toLowerCase().includes(q)
                const list = item.commands || item.cases || []
                const cmdMatch = list.some(c => {
                    const cTitle = (c.title || c.desc || "").toLowerCase().includes(q)
                    const cCmd = (c.cmd || "").toLowerCase().includes(q)
                    const cFlags = (c.flags || []).some(f => (f.flag + " " + f.desc).toLowerCase().includes(q))
                    const cPlaceholders = (c.placeholders || []).some(p => (p.name + " " + p.desc).toLowerCase().includes(q))
                    const cParams = (c.params || []).some(p => (p.key + " " + p.value).toLowerCase().includes(q))
                    const cNotes = (c.notes || c.warning || c.prereqs || "").toLowerCase().includes(q)
                    return cTitle || cCmd || cFlags || cPlaceholders || cParams || cNotes
                })
                return titleMatch || subtitleMatch || descMatch || catMatch || cmdMatch
            }

            return true
        })
    }

    readonly property int totalCount: (root.allCommands || []).length
    readonly property int starredCount: (root.allCommands || []).filter(c => !!c.starred).length

    // ── Keyboard Navigation ──────────────────────────────────────
    Keys.onUpPressed: {
        if (root.selectedIndex > 0) {
            root.selectedIndex--
            cmdListView.positionViewAtIndex(root.selectedIndex, ListView.Contain)
        }
    }

    Keys.onDownPressed: {
        if (root.selectedIndex < root.filteredCommands.length - 1) {
            root.selectedIndex++
            cmdListView.positionViewAtIndex(root.selectedIndex, ListView.Contain)
        }
    }

    Keys.onReturnPressed: {
        if (root.filteredCommands[root.selectedIndex]) {
            const id = root.filteredCommands[root.selectedIndex].id
            root.expandedCommandId = (root.expandedCommandId === id ? "" : id)
        }
    }

    Keys.onSpacePressed: {
        if (root.filteredCommands[root.selectedIndex]) {
            const id = root.filteredCommands[root.selectedIndex].id
            root.expandedCommandId = (root.expandedCommandId === id ? "" : id)
        }
    }

    Keys.onEscapePressed: {
        root.escapePressed()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // ── Top Category Filter Pills ──────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            // 1. All Pill
            StyledRect {
                implicitHeight: 32
                implicitWidth: allRow.implicitWidth + 18
                radius: Tokens.rounding.full
                color: root.selectedCategory === "all" ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer
                border.width: 1
                border.color: root.selectedCategory === "all" ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

                RowLayout {
                    id: allRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialIcon {
                        text: "apps"
                        fontStyle: Tokens.font.icon.small
                        color: root.selectedCategory === "all" ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        text: qsTr("All")
                        font: Tokens.font.label.medium
                        color: root.selectedCategory === "all" ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.selectedCategory = "all"
                        root.selectedIndex = 0
                    }
                }
            }

            // 2. Starred Pill
            StyledRect {
                implicitHeight: 32
                implicitWidth: starredRow.implicitWidth + 18
                radius: Tokens.rounding.full
                color: root.selectedCategory === "starred" ? Colours.palette.m3tertiary : Colours.tPalette.m3surfaceContainer
                border.width: 1
                border.color: root.selectedCategory === "starred" ? Colours.palette.m3tertiary : Colours.palette.m3outlineVariant

                RowLayout {
                    id: starredRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialIcon {
                        text: "star"
                        fontStyle: Tokens.font.icon.small
                        color: root.selectedCategory === "starred" ? Colours.palette.m3onTertiary : Colours.palette.m3tertiary
                        fill: 1
                    }

                    StyledText {
                        text: qsTr("Starred")
                        font: Tokens.font.label.medium
                        color: root.selectedCategory === "starred" ? Colours.palette.m3onTertiary : Colours.palette.m3tertiary
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.selectedCategory = "starred"
                        root.selectedIndex = 0
                    }
                }
            }

            // 3. Domain Tag Pills (#network, #bluetooth, #arch, #vpn, #files)
            Repeater {
                model: ["network", "bluetooth", "arch", "vpn", "files"]
                delegate: StyledRect {
                    required property string modelData
                    readonly property bool active: root.selectedCategory === modelData

                    implicitHeight: 32
                    implicitWidth: catLabel.implicitWidth + 18
                    radius: Tokens.rounding.full
                    color: active ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer
                    border.width: 1
                    border.color: active ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

                    StyledText {
                        id: catLabel
                        anchors.centerIn: parent
                        text: "#" + modelData
                        font: Tokens.font.label.medium
                        color: active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.selectedCategory = active ? "all" : modelData
                            root.selectedIndex = 0
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }

        // ── Command List ────────────────────────────────────────────
        ListView {
            id: cmdListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: root.filteredCommands

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: cmdListView
            }

            delegate: CommandCard {
                required property var modelData
                required property int index

                width: cmdListView.width
                commandData: modelData
                itemIndex: index
                isSelected: index === root.selectedIndex
                isExpanded: root.expandedCommandId === modelData.id

                onToggleStarRequested: id => root.toggleStar(id)
                onToggleExpandRequested: id => {
                    root.expandedCommandId = (root.expandedCommandId === id ? "" : id)
                }
                onFlagClicked: flag => root.flagSearchRequested(flag)
            }
        }

        // ── Bottom Status Bar ───────────────────────────────────────
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 34
            radius: Tokens.rounding.small
            color: Colours.tPalette.m3surfaceContainerLow
            border.width: 1
            border.color: Colours.palette.m3outlineVariant

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                MaterialIcon {
                    text: "info"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledText {
                    text: qsTr("%1 tools • %2 starred")
                        .arg(root.totalCount)
                        .arg(root.starredCount)
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                // Keyboard hint: [↑↓ to navigate]
                RowLayout {
                    spacing: 6

                    StyledRect {
                        implicitHeight: 20
                        implicitWidth: 32
                        radius: Tokens.rounding.extraSmall
                        color: Colours.tPalette.m3surfaceContainer
                        border.width: 1
                        border.color: Colours.palette.m3outlineVariant

                        StyledText {
                            anchors.centerIn: parent
                            text: "↑↓"
                            font.family: "monospace"
                            font.pixelSize: 11
                            color: Colours.palette.m3onSurface
                        }
                    }

                    StyledText {
                        text: qsTr("to navigate")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }
    }
}
