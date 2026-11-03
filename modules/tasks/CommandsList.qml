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
    property string selectedCategory: "files" // Match photo default #files
    property int selectedIndex: 0
    property string activeSubTab: "commands" // "commands" | "favorites"
    property var allCommands: []

    readonly property string commandsPath: Quickshell.env("HOME") + "/.config/caelestia/commands.json"

    signal escapePressed()
    signal flagSearchRequested(string query)

    // ── Persistence via FileView ────────────────────────────────
    function loadCommands() {
        if (!commandsFile) return
        try {
            const raw = commandsFile.text()
            if (raw && raw.length > 2) {
                const parsed = JSON.parse(raw)
                if (Array.isArray(parsed) && parsed.length > 0) {
                    root.allCommands = parsed
                }
            }
        } catch (e) {
            // silent fallback
        }
    }

    FileView {
        id: commandsFile
        path: root.commandsPath
        printErrors: false

        onLoaded: root.loadCommands()
    }

    Component.onCompleted: {
        root.loadCommands()
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

    function getCategoryIcon(cat) {
        switch (cat) {
            case "network": return "wifi"
            case "bluetooth": return "bluetooth"
            case "arch": return "terminal"
            case "files": return "folder"
            case "vpn": return "vpn_lock"
            case "nav": return "explore"
            case "text": return "text_fields"
            case "system": return "dns"
            case "process": return "memory"
            case "perms": return "lock"
            case "archive": return "archive"
            case "binary": return "data_object"
            case "advanced": return "construction"
            case "security": return "security"
            case "cron": return "schedule"
            case "git": return "source_environment"
            default: return "code"
        }
    }

    function getCategoryTitle(cat) {
        switch (cat) {
            case "files": return "Disk & Filesystem · Mount & Storage"
            case "nav": return "Core Navigation · Paths & Traversal"
            case "text": return "Text Processing · Grep, AWK & Sed"
            case "network": return "Networking Mastery · Sockets & SSH"
            case "process": return "Process Control · Daemons & Signals"
            case "perms": return "Permissions & Ownership · SUID & Mode Bits"
            case "arch": return "Arch Linux · Pacman, AUR & Systemd"
            case "git": return "Git Workflow · Commits, Branches & Reflog"
            case "security": return "Offensive Cheatsheet · TTY & Exploits"
            case "cron": return "Cron & Automation · Scheduled Jobs"
            case "archive": return "Archives & Compression · Tar & Streams"
            case "binary": return "Binary Analysis · Strings & Tracing"
            case "system": return "System Architecture · FHS & Kernel RAM"
            case "advanced": return "Advanced Shell Techniques · Redirection & Subshells"
            default: return qsTr("Linux Command Catalog")
        }
    }

    function getCategoryDesc(cat) {
        switch (cat) {
            case "files": return "Mount foreign drives, read NTFS partitions, and analyze disk visually."
            case "nav": return "Traverse directory trees, resolve symlinks, and search paths."
            case "text": return "Search with extended regex, slice columns, and stream edit in-place."
            case "network": return "Configure SSH tunnels, monitor sockets, and catch reverse listeners."
            case "process": return "Monitor background daemons, track open files, and handle signals."
            case "perms": return "Audit SUID privilege vectors, lock private keys, and set immutable bits."
            case "arch": return "Perform rolling updates, clean orphan packages, and build from AUR."
            case "git": return "Stage commits, visualize commit trees, and rescue resets with reflog."
            case "security": return "Upgrade reverse shells, inspect permissions, and bypass jail restrictions."
            case "cron": return "Automate recurring maintenance tasks and inspect systemd timers."
            case "archive": return "Package tarballs, inspect magic bytes, and stream nested archives."
            case "binary": return "Inspect ELF headers, extract readable strings, and trace syscalls."
            case "system": return "Inspect hardware, audit virtual /proc filesystems, and analyze disk."
            case "advanced": return "Master I/O streams 2>&1, subshells, xargs parallelization, and loops."
            default: return qsTr("Comprehensive command reference and runbooks.")
        }
    }

    // ── Filtered Model ──────────────────────────────────────────
    readonly property var filteredCommands: {
        const q = root.searchQuery.trim().toLowerCase()
        const cat = root.selectedCategory
        const favOnly = (root.activeSubTab === "favorites" || cat === "starred")

        return (root.allCommands || []).filter(item => {
            if (favOnly && !item.starred) return false

            if (cat !== "all" && cat !== "starred") {
                if ((item.category || "").toLowerCase() !== cat) return false
            }

            if (q.length > 0) {
                const nameMatch = (item.name || item.title || "").toLowerCase().includes(q)
                const descMatch = (item.desc || item.subtitle || "").toLowerCase().includes(q)
                const purposeMatch = (item.purpose || item.description || "").toLowerCase().includes(q)
                const catMatch = (item.category || "").toLowerCase().includes(q)
                const tagsMatch = (item.tags || []).some(t => t.toLowerCase().includes(q))
                const flagsMatch = (item.flags || []).some(f => (f.flag + " " + f.desc).toLowerCase().includes(q))
                const exs = item.examples || item.commands || []
                const exMatch = exs.some(e => ((e.cmd || "") + " " + (e.desc || e.title || "")).toLowerCase().includes(q))
                return nameMatch || descMatch || purposeMatch || catMatch || tagsMatch || flagsMatch || exMatch
            }

            return true
        })
    }

    onFilteredCommandsChanged: {
        if (root.selectedIndex >= root.filteredCommands.length) {
            root.selectedIndex = 0
        }
    }

    readonly property var currentCommand: (root.filteredCommands.length > 0 && root.selectedIndex >= 0 && root.selectedIndex < root.filteredCommands.length)
        ? root.filteredCommands[root.selectedIndex]
        : null

    readonly property int totalCount: (root.allCommands || []).length
    readonly property int starredCount: (root.allCommands || []).filter(c => !!c.starred).length
    readonly property var availableCategories: {
        const set = new Set()
        for (let i = 0; i < (root.allCommands || []).length; i++) {
            const cat = root.allCommands[i].category
            if (cat && cat.length > 0) set.add(cat.toLowerCase())
        }
        return Array.from(set).sort()
    }

    // ── Keyboard Navigation ──────────────────────────────────────
    Keys.onUpPressed: {
        if (root.selectedIndex > 0) {
            root.selectedIndex--
            commandListView.positionViewAtIndex(root.selectedIndex, ListView.Contain)
        }
    }

    Keys.onDownPressed: {
        if (root.selectedIndex < root.filteredCommands.length - 1) {
            root.selectedIndex++
            commandListView.positionViewAtIndex(root.selectedIndex, ListView.Contain)
        }
    }

    Keys.onEscapePressed: {
        root.escapePressed()
    }

    Timer {
        id: copyAllTimer
        interval: 1800
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // ── Top Category Filter Pills ──────────────────────────────
        Flickable {
            id: catFlick
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            contentWidth: catRow.implicitWidth
            contentHeight: 34
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds

            WheelHandler {
                target: catFlick
                orientation: Qt.Horizontal
            }

            WheelHandler {
                target: catFlick
                orientation: Qt.Vertical
                onWheel: event => {
                    catFlick.contentX = Math.max(0, Math.min(catFlick.contentWidth - catFlick.width, catFlick.contentX - event.angleDelta.y))
                }
            }

            RowLayout {
                id: catRow
                height: 32
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
                            root.activeSubTab = "commands"
                            root.selectedIndex = 0
                        }
                    }
                }

                // 2. Starred Pill
                StyledRect {
                    implicitHeight: 32
                    implicitWidth: starredRow.implicitWidth + 18
                    radius: Tokens.rounding.full
                    color: (root.selectedCategory === "starred" || root.activeSubTab === "favorites") ? Colours.palette.m3tertiary : Colours.tPalette.m3surfaceContainer
                    border.width: 1
                    border.color: (root.selectedCategory === "starred" || root.activeSubTab === "favorites") ? Colours.palette.m3tertiary : Colours.palette.m3outlineVariant

                    RowLayout {
                        id: starredRow
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            text: "star"
                            fontStyle: Tokens.font.icon.small
                            color: (root.selectedCategory === "starred" || root.activeSubTab === "favorites") ? Colours.palette.m3onTertiary : Colours.palette.m3tertiary
                            fill: 1
                        }

                        StyledText {
                            text: qsTr("Starred")
                            font: Tokens.font.label.medium
                            color: (root.selectedCategory === "starred" || root.activeSubTab === "favorites") ? Colours.palette.m3onTertiary : Colours.palette.m3tertiary
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.selectedCategory = "starred"
                            root.activeSubTab = "favorites"
                            root.selectedIndex = 0
                        }
                    }
                }

                // 3. Domain Tag Pills
                Repeater {
                    model: root.availableCategories
                    delegate: StyledRect {
                        required property string modelData
                        readonly property bool active: root.selectedCategory === modelData && root.activeSubTab !== "favorites"

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
                                root.activeSubTab = "commands"
                                root.selectedIndex = 0
                            }
                        }
                    }
                }
            }
        }

        // ── Active Category Overview Banner (From Reference Photo) ──
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: bannerCol.implicitHeight + 18
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainerLow
            border.width: 1
            border.color: Colours.palette.m3outlineVariant

            ColumnLayout {
                id: bannerCol
                anchors.fill: parent
                anchors.margins: 12
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialIcon {
                        text: root.getCategoryIcon(root.selectedCategory)
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3primary
                    }

                    StyledText {
                        text: root.getCategoryTitle(root.selectedCategory)
                        font: Tokens.font.title.small
                        color: Colours.palette.m3onSurface
                    }

                    StyledRect {
                        implicitHeight: 20
                        implicitWidth: catTag.implicitWidth + 10
                        radius: Tokens.rounding.full
                        color: Colours.tPalette.m3surfaceContainer
                        border.width: 1
                        border.color: Colours.palette.m3outlineVariant

                        StyledText {
                            id: catTag
                            anchors.centerIn: parent
                            text: "#" + root.selectedCategory
                            font: Tokens.font.label.small
                            color: Colours.palette.m3primary
                        }
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: qsTr("%1 commands ∨").arg(root.filteredCommands.length)
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.getCategoryDesc(root.selectedCategory)
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                    elide: Text.ElideRight
                }
            }
        }

        // ── Main Master-Detail Split Pane (Matching Photo) ───────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 0
            spacing: 12

            // ── Left Column: Commands Sidebar ───────────────────────
            StyledRect {
                Layout.preferredWidth: 280
                Layout.fillHeight: true
                radius: Tokens.rounding.medium
                color: Colours.tPalette.m3surfaceContainerLow
                border.width: 1
                border.color: Colours.palette.m3outlineVariant

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    // Sub-Tabs Header: [ >_ Commands ] [ ☆ Favorites ]
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        // Commands Tab
                        ColumnLayout {
                            spacing: 4
                            RowLayout {
                                spacing: 4
                                StyledText {
                                    text: ">_"
                                    font.family: "monospace"
                                    font.pixelSize: 13
                                    color: root.activeSubTab === "commands" ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                }
                                StyledText {
                                    text: qsTr("Commands")
                                    font: root.activeSubTab === "commands" ? Tokens.font.title.small : Tokens.font.label.large
                                    color: root.activeSubTab === "commands" ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                }
                            }
                            StyledRect {
                                Layout.fillWidth: true
                                implicitHeight: 2
                                radius: 1
                                color: root.activeSubTab === "commands" ? Colours.palette.m3primary : "transparent"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.activeSubTab = "commands"
                                    if (root.selectedCategory === "starred") root.selectedCategory = "all"
                                    root.selectedIndex = 0
                                }
                            }
                        }

                        // Favorites Tab
                        ColumnLayout {
                            spacing: 4
                            RowLayout {
                                spacing: 4
                                MaterialIcon {
                                    text: root.activeSubTab === "favorites" ? "star" : "star_outline"
                                    fontStyle: Tokens.font.icon.small
                                    color: root.activeSubTab === "favorites" ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                }
                                StyledText {
                                    text: qsTr("Favorites")
                                    font: root.activeSubTab === "favorites" ? Tokens.font.title.small : Tokens.font.label.large
                                    color: root.activeSubTab === "favorites" ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                }
                            }
                            StyledRect {
                                Layout.fillWidth: true
                                implicitHeight: 2
                                radius: 1
                                color: root.activeSubTab === "favorites" ? Colours.palette.m3primary : "transparent"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.activeSubTab = "favorites"
                                    root.selectedIndex = 0
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    // Command List
                    ListView {
                        id: commandListView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 0
                        clip: true
                        spacing: 4
                        model: root.filteredCommands

                        StyledScrollBar.vertical: StyledScrollBar {
                            flickable: commandListView
                        }

                        delegate: StyledRect {
                            id: cmdRowItem
                            required property var modelData
                            required property int index
                            readonly property bool isSelected: index === root.selectedIndex

                            width: commandListView.width - 6
                            implicitHeight: 52
                            radius: Tokens.rounding.small
                            color: isSelected ? Qt.alpha(Colours.palette.m3primary, 0.12) : (rowHover.hovered ? Colours.tPalette.m3surfaceContainer : "transparent")
                            border.width: isSelected ? 1.5 : 0
                            border.color: Colours.palette.m3primary

                            Behavior on color { CAnim {} }

                            HoverHandler { id: rowHover }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                MaterialIcon {
                                    text: cmdRowItem.modelData.icon || root.getCategoryIcon(cmdRowItem.modelData.category)
                                    fontStyle: Tokens.font.icon.medium
                                    color: cmdRowItem.isSelected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: cmdRowItem.modelData.name || cmdRowItem.modelData.title || ""
                                        font: Tokens.font.title.small
                                        color: cmdRowItem.isSelected ? Colours.palette.m3primary : Colours.palette.m3onSurface
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: cmdRowItem.modelData.desc || cmdRowItem.modelData.subtitle || ""
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3onSurfaceVariant
                                        elide: Text.ElideRight
                                    }
                                }

                                MaterialIcon {
                                    text: "chevron_right"
                                    fontStyle: Tokens.font.icon.small
                                    color: cmdRowItem.isSelected ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.4)
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.selectedIndex = cmdRowItem.index
                                }
                            }
                        }
                    }

                    // Subtle separator dot
                    RowLayout {
                        Layout.fillWidth: true
                        StyledRect {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 4
                            implicitHeight: 4
                            radius: Tokens.rounding.full
                            color: Colours.palette.m3primary
                            opacity: 0.7
                        }
                    }

                    // Bottom Pro tip Callout
                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: proTipText.implicitHeight + 16
                        radius: Tokens.rounding.small
                        color: Qt.alpha(Colours.palette.m3primary, 0.08)
                        border.width: 1
                        border.color: Qt.alpha(Colours.palette.m3primary, 0.25)
                        visible: !!(root.currentCommand && root.currentCommand.pro_tip)

                        StyledText {
                            id: proTipText
                            anchors.fill: parent
                            anchors.margins: 8
                            text: "<font color=\"" + Colours.palette.m3primary + "\"><b>Pro tip:</b></font> " + (root.currentCommand ? root.currentCommand.pro_tip : "")
                            textFormat: Text.RichText
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurface
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }

            // ── Right Column: Detail Inspector ──────────────────────
            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Tokens.rounding.medium
                color: Colours.tPalette.m3surfaceContainerLow
                border.width: 1
                border.color: Colours.palette.m3outlineVariant

                Flickable {
                    id: detailFlick
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: detailCol.implicitHeight + 36
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    StyledScrollBar.vertical: StyledScrollBar {
                        flickable: detailFlick
                    }

                    ColumnLayout {
                        id: detailCol
                        width: parent.width - 32
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 16
                        spacing: 16

                        // Header (Command title, subtitle, tags, Star & Copy all)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                RowLayout {
                                    spacing: 8
                                    StyledText {
                                        text: root.currentCommand ? (root.currentCommand.name || root.currentCommand.title) : ""
                                        font.pixelSize: 24
                                        font.bold: true
                                        color: Colours.palette.m3onSurface
                                    }

                                    StyledText {
                                        text: "—"
                                        font.pixelSize: 20
                                        color: Colours.palette.m3outline
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                // Favorite Star Button
                                MaterialIcon {
                                    text: root.currentCommand?.starred ? "star" : "star_outline"
                                    fontStyle: Tokens.font.icon.medium
                                    color: root.currentCommand?.starred ? "#ffca1b" : Colours.palette.m3onSurfaceVariant

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.currentCommand) root.toggleStar(root.currentCommand.id)
                                        }
                                    }
                                }

                                // Copy All Button
                                StyledRect {
                                    implicitHeight: 32
                                    implicitWidth: copyAllRow.implicitWidth + 20
                                    radius: Tokens.rounding.full
                                    color: copyAllHover.hovered ? Colours.tPalette.m3surfaceContainer : "transparent"
                                    border.width: 1
                                    border.color: Colours.palette.m3outlineVariant

                                    RowLayout {
                                        id: copyAllRow
                                        anchors.centerIn: parent
                                        spacing: 6

                                        MaterialIcon {
                                            text: copyAllTimer.running ? "check" : "content_copy"
                                            fontStyle: Tokens.font.icon.small
                                            color: copyAllTimer.running ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                        }

                                        StyledText {
                                            text: copyAllTimer.running ? qsTr("Copied!") : qsTr("Copy all")
                                            font: Tokens.font.label.medium
                                            color: copyAllTimer.running ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                        }
                                    }

                                    HoverHandler { id: copyAllHover }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!root.currentCommand) return
                                            let script = ""
                                            const exs = root.currentCommand.examples || root.currentCommand.commands || []
                                            for (let i = 0; i < exs.length; i++) {
                                                const cTitle = exs[i].desc || exs[i].title || ""
                                                if (cTitle) script += "# " + cTitle + "\n"
                                                if (exs[i].cmd) script += exs[i].cmd + "\n\n"
                                            }
                                            Quickshell.clipboardText = script.trim()
                                            copyAllTimer.restart()
                                        }
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.currentCommand ? (root.currentCommand.desc || root.currentCommand.subtitle) : ""
                                font: Tokens.font.body.medium
                                color: Colours.palette.m3onSurfaceVariant
                            }

                            // Tags row
                            RowLayout {
                                spacing: 6
                                Repeater {
                                    model: root.currentCommand ? (root.currentCommand.tags || [root.currentCommand.category]) : []
                                    delegate: StyledRect {
                                        required property string modelData
                                        implicitHeight: 24
                                        implicitWidth: tagText.implicitWidth + 16
                                        radius: Tokens.rounding.full
                                        color: Colours.tPalette.m3surfaceContainer
                                        border.width: 1
                                        border.color: Colours.palette.m3outlineVariant

                                        StyledText {
                                            id: tagText
                                            anchors.centerIn: parent
                                            text: modelData
                                            font: Tokens.font.label.small
                                            color: Colours.palette.m3onSurfaceVariant
                                        }
                                    }
                                }
                            }
                        }

                        // Separator line
                        StyledRect {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Colours.palette.m3outlineVariant
                            opacity: 0.5
                        }

                        // Section 1: Purpose
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: !!(root.currentCommand && (root.currentCommand.purpose || root.currentCommand.description))

                            RowLayout {
                                spacing: 6
                                MaterialIcon {
                                    text: "adjust"
                                    fontStyle: Tokens.font.icon.small
                                    color: Colours.palette.m3primary
                                }
                                StyledText {
                                    text: qsTr("Purpose")
                                    font: Tokens.font.title.small
                                    color: Colours.palette.m3onSurface
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.currentCommand ? (root.currentCommand.purpose || root.currentCommand.description) : ""
                                font: Tokens.font.body.medium
                                color: Colours.palette.m3onSurfaceVariant
                                wrapMode: Text.Wrap
                            }
                        }

                        // Section 2: Flags
                        ColumnLayout {
                            id: flagsSection
                            Layout.fillWidth: true
                            spacing: 8
                            property bool showAll: false
                            visible: !!(root.currentCommand && root.currentCommand.flags && root.currentCommand.flags.length > 0)

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                MaterialIcon {
                                    text: "flag"
                                    fontStyle: Tokens.font.icon.small
                                    color: Colours.palette.m3primary
                                }
                                StyledText {
                                    text: qsTr("Flags")
                                    font: Tokens.font.title.small
                                    color: Colours.palette.m3onSurface
                                }

                                Item { Layout.fillWidth: true }

                                StyledText {
                                    visible: (root.currentCommand?.flags?.length ?? 0) > 4
                                    text: flagsSection.showAll ? qsTr("Show less ∧") : qsTr("Show all ∨")
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3primary

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: flagsSection.showAll = !flagsSection.showAll
                                    }
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 24
                                rowSpacing: 8

                                Repeater {
                                    model: {
                                        if (!root.currentCommand || !root.currentCommand.flags) return []
                                        const fl = root.currentCommand.flags
                                        return flagsSection.showAll ? fl : fl.slice(0, 4)
                                    }

                                    delegate: RowLayout {
                                        required property var modelData
                                        spacing: 6
                                        Layout.fillWidth: true

                                        StyledText {
                                            text: modelData.flag
                                            font.family: "monospace"
                                            font.pixelSize: 13
                                            font.bold: true
                                            color: Colours.palette.m3primary
                                        }

                                        StyledText {
                                            text: "·"
                                            color: Colours.palette.m3onSurfaceVariant
                                        }

                                        StyledText {
                                            text: modelData.desc
                                            font: Tokens.font.body.small
                                            color: Colours.palette.m3onSurfaceVariant
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }

                        // Section 3: Examples
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            RowLayout {
                                spacing: 6
                                MaterialIcon {
                                    text: "description"
                                    fontStyle: Tokens.font.icon.small
                                    color: Colours.palette.m3primary
                                }
                                StyledText {
                                    text: qsTr("Examples")
                                    font: Tokens.font.title.small
                                    color: Colours.palette.m3onSurface
                                }
                            }

                            Repeater {
                                model: root.currentCommand ? (root.currentCommand.examples || root.currentCommand.commands || []) : []

                                delegate: StyledRect {
                                    id: exCard
                                    required property var modelData
                                    required property int index

                                    Layout.fillWidth: true
                                    implicitHeight: exRow.implicitHeight + 18
                                    radius: Tokens.rounding.small
                                    color: Colours.tPalette.m3surfaceContainer
                                    border.width: 1
                                    border.color: Colours.palette.m3outlineVariant

                                    property bool isCopied: false

                                    Timer {
                                        id: copyFeedbackTimer
                                        interval: 1500
                                        onTriggered: exCard.isCopied = false
                                    }

                                    RowLayout {
                                        id: exRow
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 10
                                        spacing: 8

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: exCard.modelData.cmd || ""
                                                font.family: "monospace"
                                                font.pixelSize: 13
                                                font.bold: true
                                                color: Colours.palette.m3primary
                                                wrapMode: Text.Wrap
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: exCard.modelData.desc || exCard.modelData.title || ""
                                                font: Tokens.font.body.small
                                                color: Colours.palette.m3onSurfaceVariant
                                                wrapMode: Text.Wrap
                                            }
                                        }

                                        MaterialIcon {
                                            text: exCard.isCopied ? "check" : "content_copy"
                                            fontStyle: Tokens.font.icon.small
                                            color: exCard.isCopied ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.6)

                                            MouseArea {
                                                anchors.fill: parent
                                                anchors.margins: -4
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    Quickshell.clipboardText = exCard.modelData.cmd
                                                    exCard.isCopied = true
                                                    copyFeedbackTimer.restart()
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
