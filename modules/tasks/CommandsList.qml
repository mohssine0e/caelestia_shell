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

FocusScope {
    id: root

    property string searchQuery: ""
    property string selectedCategory: "all"
    property int selectedIndex: 0
    property var allCommands: []

    readonly property string commandsPath: Quickshell.env("HOME") + "/.config/caelestia/commands.json"

    signal escapePressed()

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

    function recordUsage(cmdStr) {
        const list = root.allCommands.slice()
        for (let i = 0; i < list.length; i++) {
            if (list[i].cmd === cmdStr) {
                list[i].use_count = (list[i].use_count || 0) + 1
                list[i].updated = "Just now"
                break
            }
        }
        root.allCommands = list
        root.saveCommands()
    }

    function runCommandInTerminal(cmdStr) {
        root.recordUsage(cmdStr)
        // Spawn Kitty terminal executing command with an exit pause so output is visible
        const p = Qt.createQmlObject('import Quickshell.Io; Process { running: false }', root, "runnerProc")
        p.command = ["kitty", "--hold", "sh", "-c", cmdStr]
        p.running = true
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

            // Search query filter (matches title, cmd, description, or flags)
            if (q.length > 0) {
                const titleMatch = (item.title || "").toLowerCase().includes(q)
                const cmdMatch = (item.cmd || "").toLowerCase().includes(q)
                const descMatch = (item.description || "").toLowerCase().includes(q)
                const catMatch = (item.category || "").toLowerCase().includes(q)
                const flagMatch = (item.flags || []).some(f => (f.flag + " " + f.desc).toLowerCase().includes(q))
                return titleMatch || cmdMatch || descMatch || catMatch || flagMatch
            }

            return true
        })
    }

    readonly property int totalCount: (root.allCommands || []).length
    readonly property int starredCount: (root.allCommands || []).filter(c => !!c.starred).length
    readonly property int recentlyUsedCount: (root.allCommands || []).filter(c => (c.use_count || 0) > 0).length

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
        const item = root.filteredCommands[root.selectedIndex]
        if (item) {
            root.runCommandInTerminal(item.cmd)
        }
    }

    Keys.onSpacePressed: {
        const item = root.filteredCommands[root.selectedIndex]
        if (item) {
            Quickshell.clipboardText = item.cmd
            root.recordUsage(item.cmd)
        }
    }

    Keys.onEscapePressed: {
        root.escapePressed()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // ── Top Search & Filter Bar ─────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // Search Bar
            StyledTextField {
                id: searchInput
                Layout.preferredWidth: 370
                implicitHeight: 38
                leadingIcon: "search"
                placeholderText: qsTr("Search runbooks, commands, or flags (/)...")
                text: root.searchQuery
                onTextChanged: {
                    root.searchQuery = text
                    root.selectedIndex = 0
                }
                Keys.onEscapePressed: {
                    clear()
                    focus = false
                    root.forceActiveFocus()
                }
            }

            // Category Filter Pills
            RowLayout {
                spacing: 6

                // 1. All Pill
                StyledRect {
                    implicitHeight: 32
                    implicitWidth: allRow.implicitWidth + 16
                    radius: Tokens.rounding.full
                    color: root.selectedCategory === "all" ? "#d0bcff" : "#1d1a24"
                    border.width: 1
                    border.color: root.selectedCategory === "all" ? "#d0bcff" : "#2f2b3b"

                    RowLayout {
                        id: allRow
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            text: "apps"
                            fontStyle: Tokens.font.icon.small
                            color: root.selectedCategory === "all" ? "#16141a" : "#ede6df"
                        }

                        StyledText {
                            text: qsTr("All")
                            font: Tokens.font.label.medium
                            color: root.selectedCategory === "all" ? "#16141a" : "#ede6df"
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
                    implicitWidth: starredRow.implicitWidth + 16
                    radius: Tokens.rounding.full
                    color: root.selectedCategory === "starred" ? Qt.alpha("#ffca1b", 0.25) : "#1d1a24"
                    border.width: 1
                    border.color: root.selectedCategory === "starred" ? "#ffca1b" : "#2f2b3b"

                    RowLayout {
                        id: starredRow
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            text: "star"
                            fontStyle: Tokens.font.icon.small
                            color: "#ffca1b"
                            fill: 1
                        }

                        StyledText {
                            text: qsTr("Starred")
                            font: Tokens.font.label.medium
                            color: root.selectedCategory === "starred" ? "#ffca1b" : "#ede6df"
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
                        color: active ? "#38314a" : "#1d1a24"
                        border.width: 1
                        border.color: active ? "#d0bcff" : "#2f2b3b"

                        StyledText {
                            id: catLabel
                            anchors.centerIn: parent
                            text: "#" + modelData
                            font: Tokens.font.label.medium
                            color: active ? "#d0bcff" : Qt.alpha("#ede6df", 0.7)
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
            }

            Item { Layout.fillWidth: true }
        }

        // ── Command List ────────────────────────────────────────────
        ListView {
            id: cmdListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 10
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

                Component.onCompleted: {
                    if (index === 0) {
                        isExpanded = true
                    }
                }

                onToggleStarRequested: id => root.toggleStar(id)
                onRunRequested: cmd => root.runCommandInTerminal(cmd)
                onCopyRequested: cmd => root.recordUsage(cmd)
            }
        }

        // ── Bottom Status Bar (Metadata & Keyboard shortcuts) ───────
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 34
            radius: Tokens.rounding.small
            color: "#121016"
            border.width: 1
            border.color: "#23202c"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                MaterialIcon {
                    text: "info"
                    fontStyle: Tokens.font.icon.small
                    color: Qt.alpha("#ede6df", 0.4)
                }

                StyledText {
                    text: qsTr("%1 commands • %2 starred • %3 recently used")
                        .arg(root.totalCount)
                        .arg(root.starredCount)
                        .arg(root.recentlyUsedCount)
                    font: Tokens.font.label.small
                    color: Qt.alpha("#ede6df", 0.5)
                }

                Item { Layout.fillWidth: true }

                // Keyboard hints: [↑↓ to navigate]  [Enter to run]
                RowLayout {
                    spacing: 6

                    StyledRect {
                        implicitHeight: 20
                        implicitWidth: 32
                        radius: 4
                        color: "#211e29"
                        StyledText {
                            anchors.centerIn: parent
                            text: "↑↓"
                            font.family: "monospace"
                            font.pixelSize: 11
                            color: Qt.alpha("#ede6df", 0.7)
                        }
                    }

                    StyledText {
                        text: qsTr("to navigate")
                        font: Tokens.font.label.small
                        color: Qt.alpha("#ede6df", 0.4)
                    }

                    StyledRect {
                        implicitHeight: 20
                        implicitWidth: 44
                        radius: 4
                        color: "#211e29"
                        StyledText {
                            anchors.centerIn: parent
                            text: "Enter"
                            font.family: "monospace"
                            font.pixelSize: 11
                            color: "#d0bcff"
                        }
                    }

                    StyledText {
                        text: qsTr("to run")
                        font: Tokens.font.label.small
                        color: Qt.alpha("#ede6df", 0.4)
                    }
                }
            }
        }
    }
}
