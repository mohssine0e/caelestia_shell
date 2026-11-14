pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: win

    property string query: ""
    property string selectedGroupKey: ""
    property string selectedId: ""
    property string activeTag: ""
    property bool sourcesOpen: false
    property string recentlyDeletedId: ""

    readonly property var allGroups: {
        const groups = []
        const byKey = ({})
        for (const note of Notes.notes || []) {
            let key = ""
            let title = ""
            let category = note.category || "unclassified"
            const topic = String(note.topic || "").trim()
            if (note.keep_decision === "skip" || category === "noise") {
                key = "special:skipped"
                title = qsTr("Skipped")
                category = "noise"
            } else if (category === "personal") {
                key = "special:personal"
                title = qsTr("Personal")
            } else if (category === "idea") {
                key = "special:ideas"
                title = qsTr("Ideas")
            } else if (topic) {
                key = "topic:" + topic.toLowerCase()
                title = topic
                category = "technical"
            } else {
                key = "special:inbox"
                title = qsTr("Inbox")
                category = "unclassified"
            }
            let group = byKey[key]
            if (!group) {
                group = { key: key, title: title, category: category, notes: [], updated_at: note.updated_at || "" }
                byKey[key] = group
                groups.push(group)
            }
            group.notes.push(note)
            if (String(note.updated_at || "") > group.updated_at) group.updated_at = note.updated_at
        }
        const order = { technical: 0, unclassified: 1, personal: 2, idea: 3, noise: 4 }
        return groups.sort((a, b) => {
            const categoryDiff = (order[a.category] ?? 9) - (order[b.category] ?? 9)
            const countDiff = b.notes.length - a.notes.length
            return categoryDiff || countDiff || String(b.updated_at).localeCompare(String(a.updated_at))
        })
    }

    readonly property var visibleGroups: {
        const needle = win.query.trim().toLowerCase()
        return win.allGroups.filter(group => {
            if (win.activeTag && !group.notes.some(note =>
                    (note.tags || []).concat(note.ai_tags || []).includes(win.activeTag))) return false
            if (!needle || String(group.title).toLowerCase().includes(needle)) return true
            return group.notes.some(note => {
                const tags = (note.tags || []).concat(note.ai_tags || []).join(" ")
                return String(note.raw_content || "").toLowerCase().includes(needle)
                    || String(note.formatted_content || "").toLowerCase().includes(needle)
                    || String(note.title || "").toLowerCase().includes(needle)
                    || tags.toLowerCase().includes(needle)
            })
        })
    }

    readonly property var selectedGroup: {
        for (const group of win.allGroups)
            if (group.key === win.selectedGroupKey) return group
        return null
    }
    readonly property var selectedNote: {
        const notes = win.selectedGroup?.notes || []
        for (const note of notes)
            if (note.id === win.selectedId) return note
        return notes.length > 0 ? notes[0] : null
    }
    readonly property var pillItems: {
        const items = []
        const seen = new Set()
        // Keep the current topic at the leading edge, followed by the remaining
        // topics. Tags form a separate, quieter group after all topic pills.
        if (win.selectedGroup)
            items.push({ key: "group:" + win.selectedGroup.key, label: win.selectedGroup.title,
                kind: "group", value: win.selectedGroup.key })
        for (const group of win.allGroups) {
            if (group.key === win.selectedGroupKey) continue
            items.push({ key: "group:" + group.key, label: group.title, kind: "group", value: group.key })
        }
        for (const note of win.selectedGroup?.notes || []) {
            for (const tag of (note.tags || []).concat(note.ai_tags || [])) {
                const key = "tag:" + tag
                if (seen.has(key)) continue
                seen.add(key)
                items.push({ key: key, label: tag, kind: "tag", value: tag })
            }
        }
        for (const group of win.allGroups) {
            for (const note of group.notes) {
                for (const tag of (note.tags || []).concat(note.ai_tags || [])) {
                    const key = "tag:" + tag
                    if (seen.has(key)) continue
                    seen.add(key)
                    items.push({ key: key, label: tag, kind: "tag", value: tag })
                }
            }
        }
        return items
    }
    readonly property var knowledge: win.buildKnowledge(win.selectedGroup)

    signal closeRequested()
    signal moveRequested()

    function displayTitle(note): string {
        if (!note) return ""
        return note.title || String(note.raw_content || "").replace(/\s+/g, " ").trim() || qsTr("Untitled note")
    }
    function conciseExplanation(value): string {
        let text = String(value || "").replace(/^\s*[-*•]\s*/, "").trim()
        text = text.replace(/\s+along with\b.*$/i, "")
        text = text.replace(/\ball currently\b/i, "currently")
        if (text.length > 110) text = text.slice(0, 107).trimEnd() + "…"
        return text
    }
    function buildKnowledge(group): var {
        const result = { overview: [], notes: [], commands: [], code: [], configuration: [], errors: [], references: [] }
        if (!group) return result
        const seenText = new Set()
        const seenCommands = new Set()
        function addText(section, value, note, fieldKey) {
            const text = String(note.display_edits?.[fieldKey] || value || "").trim()
            const key = text.toLowerCase().replace(/[\x60*_#•-]/g, "").replace(/\s+/g, " ").trim()
            if (!text || seenText.has(section + ":" + key)) return
            seenText.add(section + ":" + key)
            result[section].push({ text: text.replace(/^\s*[-*•]\s*/, ""),
                noteId: note.id, key: fieldKey, origin: note.origin || "user" })
        }
        function addCommand(command, explanation, note, commandKey, explanationKey) {
            const clean = String(note.display_edits?.[commandKey] || command || "").trim().replace(/^\$\s*/, "")
            if (!clean || seenCommands.has(clean)) return
            seenCommands.add(clean)
            result.commands.push({
                command: clean,
                explanation: win.conciseExplanation(note.display_edits?.[explanationKey] || explanation),
                commandEntry: { text: clean, noteId: note.id, key: commandKey, origin: note.origin || "user" },
                explanationEntry: { text: win.conciseExplanation(note.display_edits?.[explanationKey] || explanation),
                    noteId: note.id, key: explanationKey, origin: note.origin || "user" }
            })
        }
        for (const note of group.notes || []) {
            if (note.origin === "ai" && !(note.essentials || []).length) {
                addText(note.topic_section === "overview" ? "overview" : "notes",
                    note.raw_content, note, "fallback")
                continue
            }
            const essentials = note.essentials || []
            const excerpts = note.exact_excerpts || []
            const type = note.technical_type || "general"
            if (type === "command") {
                let commandIndex = 0
                for (let excerptIndex = 0; excerptIndex < excerpts.length; excerptIndex++) {
                    const lines = String(excerpts[excerptIndex].content || "").split("\n")
                    for (let lineIndex = 0; lineIndex < lines.length; lineIndex++) {
                        const line = lines[lineIndex].trim()
                        if (!line) continue
                        const essentialIndex = Math.min(commandIndex, Math.max(essentials.length - 1, 0))
                        const explanation = essentials[essentialIndex]
                            || win.displayTitle(note)
                        addCommand(line, explanation, note,
                            "command:" + excerptIndex + ":" + lineIndex, "essential:" + essentialIndex)
                        commandIndex += 1
                    }
                }
                if (excerpts.length === 0 && !String(note.raw_content || "").includes("\n"))
                    addCommand(note.raw_content, essentials[0] || win.displayTitle(note), note, "fallback", "essential:0")
                for (let i = commandIndex; i < essentials.length; i++) addText("notes", essentials[i], note, "essential:" + i)
            } else if (type === "code") {
                for (let i = 0; i < excerpts.length; i++) result.code.push({
                    language: excerpts[i].language || "",
                    content: note.display_edits?.["command:" + i + ":0"] || excerpts[i].content || "",
                    explanation: essentials[0] || win.displayTitle(note),
                    noteId: note.id, key: "command:" + i + ":0", origin: note.origin || "user"
                })
                if (excerpts.length === 0 && note.raw_content)
                    result.code.push({ language: note.technology || "", content: note.display_edits?.fallback || note.raw_content,
                        explanation: essentials[0] || "", noteId: note.id, key: "fallback", origin: note.origin || "user" })
            } else {
                let section = note.topic_section === "overview" ? "overview" : "notes"
                if (type === "configuration") section = "configuration"
                else if (type === "error_fix") section = "errors"
                else if (type === "reference" || note.category === "reference") section = "references"
                for (let i = 0; i < essentials.length; i++) addText(section, essentials[i], note, "essential:" + i)
                if (essentials.length === 0) addText(section, note.formatted_content || note.raw_content, note, "fallback")
            }
        }
        return result
    }
    function topicMarkdown(): string {
        if (!win.selectedGroup) return ""
        const output = ["# " + win.selectedGroup.title]
        function addSection(title, values) {
            if (values.length) output.push("## " + title + "\n\n" + values.map(value => "- " + value.text).join("\n"))
        }
        addSection(qsTr("Overview"), win.knowledge.overview)
        addSection(qsTr("Notes"), win.knowledge.notes)
        if (win.knowledge.commands.length)
            output.push("## " + qsTr("Commands") + "\n\n"
                + win.knowledge.commands.map(item => "$ " + item.command + "\n" + item.explanation).join("\n\n"))
        if (win.knowledge.code.length)
            output.push("## " + qsTr("Code") + "\n\n" + win.knowledge.code.map(item => item.content).join("\n\n"))
        addSection(qsTr("Configuration"), win.knowledge.configuration)
        addSection(qsTr("Errors & Fixes"), win.knowledge.errors)
        addSection(qsTr("References"), win.knowledge.references)
        return output.join("\n\n")
    }
    function analyzeSelectedGroup(): void {
        for (const note of win.selectedGroup?.notes || [])
            if (!note.local_only) Notes.queueOrganization(note.id)
    }
    function groupIsFormatting(): bool {
        for (const note of win.selectedGroup?.notes || [])
            if (Notes.isFormatting(note.id)) return true
        return false
    }
    function selectGroup(key): void {
        win.activeTag = ""
        win.selectedGroupKey = key
        win.selectedId = win.selectedGroup?.notes?.[0]?.id || ""
        contentScroll.contentY = 0
    }
    function activatePill(index): void {
        if (index < 0 || index >= win.pillItems.length) return
        const item = win.pillItems[index]
        if (item.kind === "group") {
            win.selectGroup(item.value)
        } else {
            win.activeTag = item.value
            if (win.visibleGroups.length) {
                win.selectedGroupKey = win.visibleGroups[0].key
                win.selectedId = win.visibleGroups[0].notes[0]?.id || ""
                contentScroll.contentY = 0
            }
        }
        pills.ensureVisible(index)
    }
    function cyclePill(delta): void {
        if (!win.pillItems.length) return
        let index = 0
        for (let i = 0; i < win.pillItems.length; i++) {
            const item = win.pillItems[i]
            if ((item.kind === "group" && item.value === win.selectedGroupKey)
                    || (item.kind === "tag" && item.value === win.activeTag)) index = i
        }
        win.activatePill((index + delta + win.pillItems.length) % win.pillItems.length)
    }
    function closeView(): void {
        if (win.sourcesOpen) {
            win.sourcesOpen = false
        } else {
            win.closeRequested()
        }
    }
    function releaseSearchFocus(): bool {
        if (!searchInput.activeFocus) return false
        win.forceActiveFocus()
        return true
    }

    focus: true
    Component.onCompleted: {
        Notes.refresh()
        if (win.allGroups.length) win.selectGroup(win.allGroups[0].key)
        win.forceActiveFocus()
    }
    onVisibleGroupsChanged: {
        if (win.visibleGroups.length && !win.visibleGroups.some(group => group.key === win.selectedGroupKey))
            win.selectGroup(win.visibleGroups[0].key)
    }
    onSelectedGroupChanged: {
        const notes = win.selectedGroup?.notes || []
        if (notes.length && !notes.some(note => note.id === win.selectedId)) win.selectedId = notes[0].id
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (!win.releaseSearchFocus()) win.closeView()
            event.accepted = true
        } else if (!searchInput.activeFocus && event.key === Qt.Key_Slash) {
            searchInput.forceActiveFocus()
            event.accepted = true
        } else if (!searchInput.activeFocus && event.key === Qt.Key_Left) {
            win.cyclePill(-1)
            event.accepted = true
        } else if (!searchInput.activeFocus && event.key === Qt.Key_Right) {
            win.cyclePill(1)
            event.accepted = true
        }
    }
    Connections {
        function onNoteDeleted(noteId): void {
            win.recentlyDeletedId = noteId
            undoTimer.restart()
        }
        function onNoteChanged(note): void {
            if (note?.id === win.recentlyDeletedId) {
                win.recentlyDeletedId = ""
                undoTimer.stop()
            }
        }
        target: Notes
    }
    Timer {
        id: undoTimer
        interval: 8000
        onTriggered: win.recentlyDeletedId = ""
    }

    component SectionTitle: StyledText {
        font: Qt.font({ family: Tokens.font.label.small.family, pixelSize: 12,
            weight: Font.Bold, letterSpacing: 1.1 })
        color: Colours.palette.m3onSurfaceVariant
    }
    component HeaderAction: Item {
        id: headerAction

        required property string actionIcon
        required property string label
        property bool running: false
        signal triggered()

        implicitWidth: actionContent.implicitWidth
        implicitHeight: 28
        opacity: enabled ? (actionMouse.containsMouse ? 1 : 0.72) : 0.38
        Behavior on opacity { NumberAnimation { duration: 120 } }

        Row {
            id: actionContent
            anchors.centerIn: parent
            spacing: 5
            Item {
                visible: !!headerAction.actionIcon || headerAction.running
                width: 16
                height: 16
                MaterialIcon {
                    anchors.centerIn: parent
                    visible: !headerAction.running
                    text: headerAction.actionIcon
                    color: Colours.palette.m3onSurfaceVariant
                    fill: 0
                    fontStyle: Tokens.font.icon.size(12).build()
                }
                CircularIndicator {
                    anchors.centerIn: parent
                    visible: headerAction.running
                    running: visible
                    implicitSize: 16
                }
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: headerAction.label
                color: Colours.palette.m3onSurfaceVariant
                font: Qt.font({ family: Tokens.font.label.small.family, pixelSize: 12,
                    weight: Tokens.font.label.small.weight })
            }
        }
        MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: headerAction.triggered()
        }
    }
    component SimpleSection: Column {
        id: section

        required property string sectionTitle
        required property string sectionKey
        required property var entries
        property bool bulleted: false
        property bool showWhenEmpty: false
        property string emptyLabel: ""

        width: parent?.width ?? 0
        visible: showWhenEmpty || entries.length > 0 || topicOps.pendingFor(sectionKey).length > 0
        spacing: 10
        SectionTitle { text: parent.sectionTitle.toUpperCase() }
        StyledText {
            width: parent.width
            visible: section.showWhenEmpty && section.entries.length === 0
                && topicOps.pendingFor(section.sectionKey).length === 0
            text: section.emptyLabel
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }
        Repeater {
            model: parent.entries
            delegate: InlineEntry {
                required property var modelData
                width: parent.width
                entry: modelData
                markdown: true
                bullet: section.bulleted
            }
        }
        Repeater {
            model: topicOps.pendingFor(parent.sectionKey)
            delegate: PendingLine {
                required property var modelData
                width: parent.width
                suggestion: modelData
                controller: topicOps
            }
        }
        Rectangle {
            width: parent.width
            height: 1
            color: Colours.palette.m3outlineVariant
            opacity: 0.55
        }
    }

    TopicInline {
        id: topicOps
        topic: win.selectedGroup?.key?.startsWith("topic:") ? win.selectedGroup.title : ""
    }

    Rectangle {
        anchors.fill: parent
        radius: Tokens.rounding.medium
        color: Colours.palette.m3surface
        border.width: 1
        border.color: Colours.palette.m3outlineVariant

        Item {
            id: topBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 48
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onPressed: win.moveRequested()
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 32
                anchors.rightMargin: 32
                spacing: 18
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Quick Notes")
                    color: Colours.palette.m3onSurface
                    font: Qt.font({ family: Tokens.font.title.small.family, pixelSize: 18,
                        weight: Font.DemiBold })
                    elide: Text.ElideRight
                }
                Rectangle {
                    Layout.preferredWidth: 210
                    Layout.preferredHeight: 32
                    radius: 8
                    color: Colours.palette.m3surfaceContainerLow
                    border.width: searchInput.activeFocus ? 1 : 0
                    border.color: Colours.palette.m3primary
                    MaterialIcon {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: "search"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }
                    TextInput {
                        id: searchInput
                        anchors.left: parent.left
                        anchors.leftMargin: 34
                        anchors.right: searchHint.left
                        anchors.rightMargin: 6
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.topMargin: 4
                        anchors.bottomMargin: 4
                        text: win.query
                        verticalAlignment: TextInput.AlignVCenter
                        color: Colours.palette.m3onSurface
                        font: Qt.font({ family: Tokens.font.body.small.family, pixelSize: 13,
                            weight: Tokens.font.body.small.weight })
                        selectByMouse: true
                        clip: true
                        onTextEdited: win.query = text
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                win.releaseSearchFocus()
                                event.accepted = true
                            }
                        }
                    }
                    StyledText {
                        anchors.left: searchInput.left
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !searchInput.text
                        text: qsTr("Search…")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Qt.font({ family: Tokens.font.body.small.family, pixelSize: 13,
                            weight: Tokens.font.body.small.weight })
                    }
                    StyledText {
                        id: searchHint
                        anchors.right: parent.right
                        anchors.rightMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        text: "/"
                        color: Colours.palette.m3outline
                        font: Qt.font({ family: Tokens.font.label.small.family, pixelSize: 10,
                            weight: Tokens.font.label.small.weight })
                    }
                }
            }
        }

        Item {
            id: topicBanner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: topBar.bottom
            height: 44
            Flickable {
                id: pills
                function ensureVisible(index): void {
                    const item = pillRepeater.itemAt(index)
                    if (!item) return
                    if (item.x < contentX) contentX = item.x
                    else if (item.x + item.width > contentX + width) contentX = item.x + item.width - width
                }
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 32
                anchors.rightMargin: 32
                height: 32
                contentWidth: pillRow.implicitWidth
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Row {
                    id: pillRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7
                    Repeater {
                        id: pillRepeater
                        model: win.pillItems
                        delegate: Rectangle {
                            id: pill
                            required property var modelData
                            required property int index
                            readonly property bool active: modelData.kind === "group"
                                ? modelData.value === win.selectedGroupKey : modelData.value === win.activeTag
                            implicitWidth: pillLabel.implicitWidth + 18
                            implicitHeight: 26
                            radius: 7
                            color: modelData.kind === "group"
                                ? (active ? Colours.palette.m3secondaryContainer
                                    : Colours.palette.m3surfaceContainerHigh)
                                : (active ? Qt.alpha(Colours.palette.m3secondaryContainer, 0.72)
                                    : Qt.alpha(Colours.palette.m3surfaceContainerLow, 0.72))
                            StyledText {
                                id: pillLabel
                                anchors.centerIn: parent
                                text: pill.modelData.label
                                color: pill.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                                font: Qt.font({ family: Tokens.font.label.small.family, pixelSize: 12,
                                    weight: Tokens.font.label.small.weight })
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.activatePill(pill.index)
                            }
                        }
                    }
                }
            }
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Colours.palette.m3outlineVariant
            }
        }

        Flickable {
            id: contentScroll
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: topicBanner.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: 32
            anchors.rightMargin: 32
            anchors.topMargin: 16
            anchors.bottomMargin: 22
            contentWidth: width
            contentHeight: contentColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            Column {
                id: contentColumn
                width: contentScroll.width
                spacing: 20
                RowLayout {
                    width: parent.width
                    height: 38
                    spacing: 18
                    StyledText {
                        Layout.fillWidth: true
                        text: win.selectedGroup?.title || qsTr("No notes")
                        color: Colours.palette.m3onSurface
                        font: Qt.font({ family: Tokens.font.title.medium.family, pixelSize: 27,
                            weight: Font.Bold })
                        elide: Text.ElideRight
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            onPressed: win.moveRequested()
                        }
                    }
                    HeaderAction {
                        actionIcon: "lightbulb"
                        label: topicOps.busyAction === "fill-topic" ? qsTr("Filling…") : qsTr("Fill gaps")
                        running: topicOps.busyAction === "fill-topic"
                        enabled: !!topicOps.topic && !topicOps.busy && Notes.providerConfigured
                        onTriggered: topicOps.generate()
                    }
                    HeaderAction {
                        actionIcon: "done_all"
                        label: qsTr("Accept all (%1)").arg(topicOps.available.length)
                        visible: topicOps.available.length > 0
                        enabled: !topicOps.busy
                        onTriggered: topicOps.acceptAll()
                    }
                    HeaderAction {
                        actionIcon: ""
                        label: qsTr("Copy")
                        enabled: !!win.selectedGroup
                        onTriggered: {
                            Quickshell.clipboardText = win.topicMarkdown()
                            Toaster.toast(qsTr("Copied"), qsTr("Topic copied as Markdown"), "check")
                        }
                    }
                    HeaderAction {
                        actionIcon: "sync"
                        label: win.groupIsFormatting() ? qsTr("Syncing…") : qsTr("Sync")
                        running: win.groupIsFormatting()
                        enabled: !!win.selectedGroup && !win.groupIsFormatting() && Notes.providerConfigured
                        onTriggered: win.analyzeSelectedGroup()
                    }
                    HeaderAction {
                        actionIcon: "source"
                        label: qsTr("Sources (%1)").arg(win.selectedGroup?.notes?.length || 0)
                        enabled: !!win.selectedGroup
                        onTriggered: win.sourcesOpen = true
                    }
                }
                StyledText {
                    width: parent.width
                    visible: !!topicOps.errorMessage || !!topicOps.notice
                    text: topicOps.errorMessage || topicOps.notice
                    color: topicOps.errorMessage ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.Wrap
                }
                SimpleSection {
                    sectionTitle: qsTr("Overview")
                    sectionKey: "overview"
                    entries: win.knowledge.overview
                    bulleted: true
                    showWhenEmpty: !!win.selectedGroup?.key?.startsWith("topic:")
                    emptyLabel: qsTr("Fill gaps to suggest an overview.")
                }
                SimpleSection {
                    sectionTitle: qsTr("Notes")
                    sectionKey: "notes"
                    entries: win.knowledge.notes
                    bulleted: true
                    showWhenEmpty: !!win.selectedGroup?.key?.startsWith("topic:")
                    emptyLabel: qsTr("No notes saved for this topic.")
                }
                Column {
                    width: parent.width
                    visible: win.knowledge.commands.length > 0 || topicOps.pendingFor("commands").length > 0
                    spacing: 6
                    SectionTitle { text: qsTr("COMMANDS") }
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Colours.palette.m3outlineVariant
                        opacity: 0.55
                    }
                    Repeater {
                        model: win.knowledge.commands
                        delegate: Item {
                            id: commandRow
                            required property var modelData
                            property bool copied: false
                            width: parent.width
                            height: Math.max(40, commandEntry.implicitHeight + 12, commandExplanation.implicitHeight + 12)
                            Timer {
                                interval: 1200
                                running: commandRow.copied
                                onTriggered: commandRow.copied = false
                            }
                            Item {
                                anchors.fill: parent
                                Item {
                                    id: commandCopy
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 28
                                    height: 28
                                    opacity: commandCopyMouse.containsMouse || commandRow.copied ? 1 : 0.45
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        text: commandRow.copied ? "check" : "content_copy"
                                        color: Colours.palette.m3onSurfaceVariant
                                        fill: 0
                                        fontStyle: Tokens.font.icon.size(12).build()
                                    }
                                    MouseArea {
                                        id: commandCopyMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            Quickshell.clipboardText = commandRow.modelData.command
                                            commandRow.copied = true
                                        }
                                    }
                                }
                                StyledText {
                                    id: commandEntry
                                    anchors.left: commandCopy.right
                                    anchors.leftMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: commandRow.width * 0.38
                                    text: "$ " + commandRow.modelData.command
                                    color: Colours.palette.m3primary
                                    font: Qt.font({ family: Tokens.font.mono.small.family, pixelSize: 14 })
                                    wrapMode: Text.WrapAnywhere
                                }
                                StyledText {
                                    id: commandExplanation
                                    anchors.left: commandEntry.right
                                    anchors.leftMargin: 12
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "•  " + commandRow.modelData.explanation
                                    color: Colours.palette.m3onSurface
                                    font: Qt.font({ family: Tokens.font.body.medium.family, pixelSize: 15 })
                                    wrapMode: Text.WrapAnywhere
                                }
                            }
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 1
                                color: Colours.palette.m3outlineVariant
                                opacity: 0.2
                            }
                        }
                    }
                    Repeater {
                        model: topicOps.pendingFor("commands")
                        delegate: PendingLine {
                            required property var modelData
                            width: parent.width
                            suggestion: modelData
                            controller: topicOps
                        }
                    }
                }
                Column {
                    width: parent.width
                    visible: win.knowledge.code.length > 0 || topicOps.pendingFor("code").length > 0
                    spacing: 8
                    SectionTitle { text: qsTr("CODE") }
                    Repeater {
                        model: win.knowledge.code
                        delegate: Rectangle {
                            id: codeBlock
                            required property var modelData
                            width: parent.width
                            implicitHeight: codeColumn.implicitHeight + 20
                            radius: 8
                            color: Colours.palette.m3surfaceContainerLow
                            Column {
                                id: codeColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 10
                                spacing: 8
                                StyledText {
                                    width: parent.width
                                    visible: !!codeBlock.modelData.explanation
                                    text: codeBlock.modelData.explanation
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Qt.font({ family: Tokens.font.body.small.family, pixelSize: 14,
                                        weight: Tokens.font.body.small.weight })
                                    wrapMode: Text.Wrap
                                }
                                InlineEntry {
                                    width: parent.width
                                    entry: ({ text: codeBlock.modelData.content, noteId: codeBlock.modelData.noteId,
                                        key: codeBlock.modelData.key, origin: codeBlock.modelData.origin })
                                    mono: true
                                }
                            }
                        }
                    }
                    Repeater {
                        model: topicOps.pendingFor("code")
                        delegate: PendingLine {
                            required property var modelData
                            width: parent.width
                            suggestion: modelData
                            controller: topicOps
                        }
                    }
                }
                SimpleSection { sectionTitle: qsTr("Configuration"); sectionKey: "configuration"; entries: win.knowledge.configuration }
                SimpleSection { sectionTitle: qsTr("Errors & Fixes"); sectionKey: "errors"; entries: win.knowledge.errors }
                SimpleSection { sectionTitle: qsTr("References"); sectionKey: "references"; entries: win.knowledge.references }
                StyledText {
                    width: parent.width
                    visible: !!win.query && win.visibleGroups.length === 0
                    text: qsTr("No topics match this search.")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: win.sourcesOpen
            z: 50
            color: Qt.alpha(Colours.palette.m3scrim, 0.48)
            radius: Tokens.rounding.medium
            MouseArea {
                anchors.fill: parent
                onClicked: win.closeView()
            }
            Rectangle {
                id: sourceDrawer
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 12
                width: Math.min(460, parent.width * 0.62)
                radius: 10
                color: Colours.palette.m3surfaceContainerLow
                border.width: 1
                border.color: Colours.palette.m3outlineVariant
                MouseArea { anchors.fill: parent }
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            text: qsTr("Sources (%1)").arg(win.selectedGroup?.notes?.length || 0)
                            color: Colours.palette.m3onSurface
                            font: Qt.font({ family: Tokens.font.title.small.family, pixelSize: 20,
                                weight: Font.Bold })
                        }
                        IconButton {
                            type: IconButton.Text
                            icon: "close"
                            onClicked: win.closeView()
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Original captures remain separate.")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                    ListView {
                        id: sourceList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: win.selectedGroup?.notes || []
                        spacing: 8
                        clip: true
                        ScrollBar.vertical: ScrollBar {}
                        delegate: Rectangle {
                            id: sourceCard
                            required property var modelData
                            width: sourceList.width
                            implicitHeight: sourceContent.implicitHeight + 20
                            radius: 8
                            color: Colours.palette.m3surface
                            border.width: 1
                            border.color: Colours.palette.m3outlineVariant
                            ColumnLayout {
                                id: sourceContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 10
                                spacing: 8
                                RowLayout {
                                    Layout.fillWidth: true
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: win.displayTitle(sourceCard.modelData)
                                        color: Colours.palette.m3onSurface
                                        font: Tokens.font.label.builders.medium.weight(Font.DemiBold).build()
                                        elide: Text.ElideRight
                                    }
                                    TextButton {
                                        text: qsTr("Delete")
                                        type: TextButton.Text
                                        font: Tokens.font.label.small
                                        enabled: !Notes.mutating
                                        onClicked: Notes.remove(sourceCard.modelData.id)
                                    }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: sourceCard.modelData.raw_content || ""
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: sourceCard.modelData.technical_type === "command"
                                        ? Tokens.font.mono.small : Tokens.font.body.small
                                    wrapMode: Text.WrapAnywhere
                                    maximumLineCount: 8
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            z: 80
            visible: !!win.recentlyDeletedId
            implicitWidth: undoRow.implicitWidth + 24
            implicitHeight: 38
            radius: 19
            color: Colours.palette.m3inverseSurface
            RowLayout {
                id: undoRow
                anchors.centerIn: parent
                spacing: 12
                StyledText {
                    text: qsTr("Source deleted")
                    color: Colours.palette.m3inverseOnSurface
                    font: Tokens.font.label.small
                }
                TextButton {
                    text: qsTr("Undo")
                    type: TextButton.Text
                    onClicked: Notes.restore(win.recentlyDeletedId)
                }
            }
        }
    }
}
