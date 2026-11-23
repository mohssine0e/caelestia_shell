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
    property string activeTag: ""
    property bool sourcesOpen: false
    property bool askOpen: false
    property bool askWholeTopic: false
    property string recentlyDeletedId: ""
    property string generationFeedback: ""
    property string generationAction: ""
    property string generationTopic: ""
    property string activeSubconcept: ""
    property string recentlyDeletedTopic: ""
    property bool confirmDeleteActive: false
    property string activeFlagText: ""
    property string activeFlagExplanation: ""
    property string activeDetailConceptId: ""
    property real flagTooltipX: 0
    property real flagTooltipY: 0

    function showFlagTooltip(flag, exp, gx, gy): void {
        win.activeFlagText = flag
        win.activeFlagExplanation = exp
        // CommandWithFlags maps into the window scene. The tooltip shares this
        // view's origin, so treating scene coordinates as desktop-global added
        // the window offset twice on non-primary monitors.
        win.flagTooltipX = gx
        win.flagTooltipY = gy
    }

    function hideFlagTooltip(): void {
        win.activeFlagText = ""
        win.activeFlagExplanation = ""
    }

    function openConceptDetail(conceptId): void {
        const id = String(conceptId || "").trim()
        if (!id) return
        win.activeDetailConceptId = id
        Notes.getConcept(id, "")
    }

    Timer {
        id: confirmDeleteTimer
        interval: 4000
        running: false
        onTriggered: win.confirmDeleteActive = false
    }

    onSelectedGroupKeyChanged: {
        win.askWholeTopic = false
        win.activeSubconcept = ""
        Qt.callLater(() => {
            if (!win.activeSubconcept && win.activeSubconcepts.length)
                win.activeSubconcept = win.activeSubconcepts[0]
        })
        win.confirmDeleteActive = false
    }

    function displaySubconcept(value): string {
        return String(value || "").trim()
    }

    function subconceptRank(value): int {
        const name = win.displaySubconcept(value).toLowerCase()
        if (win.selectedGroup?.title?.toLowerCase() === "kubernetes") {
            const index = ["overview", "pods", "deployments", "services", "images", "inspect & debug"].indexOf(name)
            if (index >= 0) return index
        }
        if (/^(core|overview|basics|fundamentals)\b/.test(name)) return 0
        if (/(advanced|internals|deep dive|performance|security|troubleshooting|gotchas|failure modes)/.test(name)) return 20
        return 10
    }

    property var viewedNotes: ({})
    function collectVisibleNotes(): void {
        if (!win.visible) return
        const viewed = Object.assign({}, win.viewedNotes)
        function visit(item) {
            if (!item.visible) return
            if (item.seenNoteId && item.height > 0) {
                const position = item.mapToItem(contentScroll, 0, 0)
                if (position.y < contentScroll.height && position.y + item.height > 0) {
                    const note = Notes.notes.find(n => n.id === item.seenNoteId)
                    if (note?.unread) viewed[note.id] = note.content_revision
                }
            }
            for (const child of item.children || []) visit(child)
        }
        visit(contentColumn)
        win.viewedNotes = viewed
    }
    function flushReadMarkers(): void {
        const entries = Object.keys(win.viewedNotes).map(id => ({ id: id, revision: win.viewedNotes[id] }))
        win.viewedNotes = ({})
        if (entries.length) Notes.markNotesSeen(entries)
    }
    Timer {
        id: readTimer
        interval: 1800
        onTriggered: {
            win.collectVisibleNotes()
            win.flushReadMarkers()
        }
    }
    onActiveSubconceptChanged: {
        win.flushReadMarkers()
        contentScroll.contentY = 0
        readTimer.restart()
    }
    onVisibleChanged: {
        if (visible) readTimer.restart()
        else win.flushReadMarkers()
    }
    Component.onDestruction: win.flushReadMarkers()

    readonly property var activeSubconcepts: {
        const list = []
        const seen = new Set()
        for (const note of win.selectedGroup?.notes || []) {
            const sc = String(note.subconcept || "").trim() || ("Core " + (win.selectedGroup?.title || "Topic"))
            const label = win.displaySubconcept(sc)
            if (label && !seen.has(label.toLowerCase())) {
                seen.add(label.toLowerCase())
                list.push(label)
            }
        }
        return list.sort((a, b) => win.subconceptRank(a) - win.subconceptRank(b)
            || win.displaySubconcept(a).localeCompare(win.displaySubconcept(b), undefined, { numeric: true }))
    }

    readonly property var filteredNotes: {
        const notes = win.selectedGroup?.notes || []
        const active = win.activeSubconcept || win.activeSubconcepts[0] || ""
        if (!active) return notes
        return notes.filter(n => win.displaySubconcept(String(n.subconcept || "").trim()
            || ("Core " + (win.selectedGroup?.title || "Topic"))).toLowerCase() === active.toLowerCase())
    }


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
    readonly property bool noSearchResults: !!win.query.trim() && win.visibleGroups.length === 0

    readonly property var selectedGroup: {
        for (const group of win.allGroups)
            if (group.key === win.selectedGroupKey) return group
        return null
    }
    readonly property var pillItems: {
        const items = []
        function groupHasRecent(g) {
            return (g?.notes || []).some(n => n.unread)
        }
        if (win.selectedGroup)
            items.push({ key: "group:" + win.selectedGroup.key, label: win.selectedGroup.title,
                kind: "group", value: win.selectedGroup.key, hasRecent: groupHasRecent(win.selectedGroup) })
        for (const group of win.allGroups) {
            if (group.key === win.selectedGroupKey) continue
            items.push({ key: "group:" + group.key, label: group.title, kind: "group", value: group.key,
                hasRecent: groupHasRecent(group) })
        }
        return items
    }
    readonly property var subconceptBlocks: win.buildSubconceptBlocks(win.selectedGroup)
    signal closeRequested()
    signal moveRequested()

    function displayTitle(note): string {
        if (!note) return ""
        return note.title || String(note.raw_content || "").replace(/\s+/g, " ").trim() || qsTr("Untitled note")
    }
    function cleanExplanation(value): string {
        let text = String(value || "").replace(/^\s*[-*•]\s*/, "").replace(/\s+/g, " ").trim()
        text = text.replace(/\ball currently\b/i, "currently")
        return text
    }
    function learnerVoice(value): string {
        const text = String(value || "").trim()
        return text.replace(/^Defines\s+/i, "This is how I define ")
    }
    function buildSubconceptBlocks(group): var {
        if (!group || !group.notes || group.notes.length === 0) return []
        const blocks = []
        const targetSubconcepts = [win.activeSubconcept || win.activeSubconcepts[0] || ""]

        for (const scName of targetSubconcepts) {
            const blockNotes = group.notes.filter(n => {
                const sc = String(n.subconcept || "").trim() || ("Core " + (group.title || "Topic"))
                return win.displaySubconcept(sc).toLowerCase() === scName.toLowerCase()
            }).sort((a, b) => (a.display_order ?? 1000) - (b.display_order ?? 1000)
                || String(a.created_at).localeCompare(String(b.created_at)))
            if (blockNotes.length === 0) continue

            const block = {
                title: win.displaySubconcept(scName),
                bullets: [],
                diagrams: [],
                concepts: [],
                commands: [],
                code: [],
                configuration: [],
                errors: [],
                references: []
            }

            const seenText = new Set()
            const commandIndexes = new Map()

            function addText(listName, val, note, fieldKey) {
                if ((note.hidden_entries || []).includes(fieldKey)) return
                const text = win.learnerVoice(String(note.display_edits?.[fieldKey] || val || "").trim())
                const cleanKey = text.toLowerCase().replace(/[`*_#•-]/g, "").replace(/\s+/g, " ").trim()
                if (!text || seenText.has(listName + ":" + cleanKey)) return
                seenText.add(listName + ":" + cleanKey)
                block[listName].push({
                    text: text.replace(/^\s*[-*•]\s*/, ""),
                    noteId: note.id,
                    key: fieldKey,
                    origin: note.origin || "user",
                    isRecent: !!note.unread
                })
            }

            function addCommand(cmd, exp, note, cmdKey, expKey) {
                if ((note.hidden_entries || []).includes(cmdKey)) return
                const clean = String(note.display_edits?.[cmdKey] || cmd || "").trim().replace(/^\$\s*/, "")
                if (!clean) return
                const commandKey = clean.replace(/\s+/g, " ").trim()
                const isRecent = !!note.unread
                const explanation = (note.hidden_entries || []).includes(expKey)
                    ? "" : win.cleanExplanation(note.display_edits?.[expKey] || exp)
                if (commandIndexes.has(commandKey)) {
                    const existing = block.commands[commandIndexes.get(commandKey)]
                    const explanations = String(existing.explanation || "").split(" · ")
                    if (explanation && !explanations.some(item => item.toLowerCase() === explanation.toLowerCase())) {
                        explanations.push(explanation)
                        existing.explanation = explanations.join(" · ")
                        existing.explanationEntry.text = existing.explanation
                    }
                    existing.isRecent = existing.isRecent || isRecent
                    return
                }
                commandIndexes.set(commandKey, block.commands.length)
                block.commands.push({
                    command: clean,
                    explanation: explanation,
                    commandEntry: { text: clean, noteId: note.id, key: cmdKey, origin: note.origin || "user", isRecent: isRecent },
                    explanationEntry: { text: explanation,
                        noteId: note.id, key: expKey, origin: note.origin || "user", isRecent: isRecent },
                    isRecent: isRecent
                })
            }

            for (const note of blockNotes) {
                const targetSec = String(note.topic_section || "").trim().toLowerCase()
                const essentials = note.essentials || []
                const completions = note.completions || []
                const excerpts = note.exact_excerpts || []
                const type = String(note.technical_type || "general").toLowerCase()
                const isRecent = !!note.unread

                for (const diagram of note.diagrams || []) {
                    if (diagram && Array.isArray(diagram.nodes) && Array.isArray(diagram.layers)
                            && Array.isArray(diagram.edges) && diagram.nodes.length > 0) {
                        block.diagrams.push(Object.assign({}, diagram, {
                            noteId: note.id,
                            isRecent: isRecent
                        }))
                    }
                }

                if (type === "command" || targetSec === "commands") {
                    let cmdIdx = 0
                    for (let eIdx = 0; eIdx < excerpts.length; eIdx++) {
                        const lines = String(excerpts[eIdx].content || "").split("\n")
                        for (let lIdx = 0; lIdx < lines.length; lIdx++) {
                            const line = lines[lIdx].trim()
                            if (!line) continue
                            const essIdx = Math.min(cmdIdx, Math.max(essentials.length - 1, 0))
                            const exp = essentials[essIdx] || win.displayTitle(note)
                            addCommand(line, exp, note, "command:" + eIdx + ":" + lIdx, "essential:" + essIdx)
                            cmdIdx++
                        }
                    }
                    if (excerpts.length === 0 && !String(note.raw_content || "").includes("\n")) {
                        addCommand(note.raw_content, essentials[0] || win.displayTitle(note), note, "fallback", "essential:0")
                    }
                    for (let i = cmdIdx; i < essentials.length; i++) {
                        addText("bullets", essentials[i], note, "essential:" + i)
                    }
                } else if (type === "code" || targetSec === "code" || excerpts.length > 0) {
                    for (let i = 0; i < excerpts.length; i++) {
                        const ex = excerpts[i]
                        if ((note.hidden_entries || []).includes("command:" + i + ":0")) continue
                        const label = ex.label || (ex.role === "before" ? qsTr("Legacy") : (ex.role === "after" ? qsTr("Modern") : ""))
                        const exp = label || ((note.hidden_entries || []).includes("essential:" + i)
                            ? "" : (essentials[i] || win.displayTitle(note)))
                        block.code.push({
                            language: ex.language || note.technology || "code",
                            content: note.display_edits?.["command:" + i + ":0"] || ex.content || "",
                            label: label,
                            explanation: exp,
                            noteId: note.id,
                            key: "command:" + i + ":0",
                            origin: note.origin || "user",
                            rawContent: note.raw_content || "",
                            isRecent: isRecent
                        })
                    }
                    if (excerpts.length === 0 && note.raw_content
                            && !(note.hidden_entries || []).includes("fallback")) {
                        block.code.push({
                            language: note.technology || "",
                            content: note.display_edits?.fallback || note.raw_content,
                            label: "",
                            explanation: essentials[0] || win.displayTitle(note),
                            noteId: note.id,
                            key: "fallback",
                            origin: note.origin || "user",
                            rawContent: note.raw_content || "",
                            isRecent: isRecent
                        })
                    }
                    for (let i = 0; i < essentials.length; i++) {
                        if (!block.code.some(c => c.noteId === note.id && c.explanation === essentials[i]))
                            addText("bullets", essentials[i], note, "essential:" + i)
                    }
                } else if (type === "configuration" || targetSec === "configuration") {
                    for (let i = 0; i < essentials.length; i++) addText("configuration", essentials[i], note, "essential:" + i)
                    if (essentials.length === 0) addText("configuration", note.formatted_content || note.raw_content, note, "fallback")
                } else if (type === "error_fix" || targetSec === "errors" || targetSec === "gotchas") {
                    for (let i = 0; i < essentials.length; i++) addText("errors", essentials[i], note, "essential:" + i)
                    if (essentials.length === 0) addText("errors", note.formatted_content || note.raw_content, note, "fallback")
                } else if (type === "reference" || targetSec === "references" || note.category === "reference") {
                    for (let i = 0; i < essentials.length; i++) addText("references", essentials[i], note, "essential:" + i)
                    if (essentials.length === 0) addText("references", note.formatted_content || note.raw_content, note, "fallback")
                } else {
                    for (let i = 0; i < essentials.length; i++) addText("bullets", essentials[i], note, "essential:" + i)
                    if (essentials.length === 0) addText("bullets", note.formatted_content || note.raw_content, note, "fallback")
                }
            }

            const sourceNoteIds = new Set(blockNotes.map(note => String(note.id || "")))
            block.concepts = (Notes.concepts || []).filter(concept =>
                String(concept.topic || "").toLowerCase() === String(group.title || "").toLowerCase()
                && (String(concept.area || "").toLowerCase() === scName.toLowerCase()
                    || sourceNoteIds.has(String(concept.legacy_note_id || ""))))

            for (const note of blockNotes) {
                for (let i = 0; i < (note.completions || []).length; i++)
                    addText("bullets", note.completions[i], note, "completion:" + i)
            }

            if (block.bullets.length > 0 || block.diagrams.length > 0 || block.concepts.length > 0
                || block.commands.length > 0 || block.code.length > 0
                || block.configuration.length > 0 || block.errors.length > 0 || block.references.length > 0) {
                blocks.push(block)
            }
        }
        return blocks
    }

    function topicMarkdown(): string {
        if (!win.selectedGroup) return ""
        const output = ["# " + win.selectedGroup.title]
        for (const block of win.subconceptBlocks) {
            output.push("## " + block.title)
            if (block.bullets.length) {
                output.push(block.bullets.map(b => "- " + b.text).join("\n"))
            }
            for (const diagram of block.diagrams) {
                const names = ({})
                for (const node of diagram.nodes) names[node.id] = node.label
                output.push("### " + String(diagram.title || qsTr("Diagram")) + "\n"
                    + diagram.edges.map(edge => "- " + (names[edge.from] || edge.from)
                        + " → " + (names[edge.to] || edge.to)).join("\n"))
            }
            if (block.commands.length) {
                output.push("### " + qsTr("Commands") + "\n\n"
                    + block.commands.map(item => "~~~sh\n" + item.command + "\n~~~\n" + item.explanation).join("\n\n"))
            }
            if (block.code.length) {
                output.push("### " + qsTr("Code") + "\n\n" + block.code.map(item => {
                    const language = String(item.language || "").replace(/[^a-zA-Z0-9_+-]/g, "")
                    const explanation = item.explanation ? item.explanation + "\n\n" : ""
                    return explanation + "~~~" + language + "\n" + item.content + "\n~~~"
                }).join("\n\n"))
            }
            if (block.configuration.length) {
                output.push("### " + qsTr("Configuration") + "\n\n" + block.configuration.map(b => "- " + b.text).join("\n"))
            }
            if (block.errors.length) {
                output.push("### " + qsTr("Errors & Fixes") + "\n\n" + block.errors.map(b => "- " + b.text).join("\n"))
            }
            if (block.references.length) {
                output.push("### " + qsTr("References") + "\n\n" + block.references.map(b => "- " + b.text).join("\n"))
            }
        }
        return output.join("\n\n")
    }
    function selectGroup(key): void {
        win.activeTag = ""
        win.selectedGroupKey = key
        win.activeSubconcept = ""
        Qt.callLater(() => {
            if (win.activeSubconcepts.length)
                win.activeSubconcept = win.activeSubconcepts[0]
        })
        contentScroll.contentY = 0
    }
    function deleteCurrentTopic(): void {
        const topicName = win.selectedGroup?.title || ""
        if (!topicName) return

        if (!win.confirmDeleteActive) {
            win.confirmDeleteActive = true
            confirmDeleteTimer.restart()
            return
        }

        win.confirmDeleteActive = false
        confirmDeleteTimer.stop()
        Notes.removeTopic(topicName)
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
                contentScroll.contentY = 0
            }
        }
        headerConcepts.ensureVisible(index)
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
        if (conceptDetailPage.sourcesOpen) {
            conceptDetailPage.sourcesOpen = false
        } else if (win.activeDetailConceptId) {
            win.activeDetailConceptId = ""
        } else if (win.sourcesOpen) {
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
        Notes.listConcepts("", "")
        if (win.allGroups.length) win.selectGroup(win.allGroups[0].key)
        win.forceActiveFocus()
    }
    onVisibleGroupsChanged: {
        if (win.visibleGroups.length && !win.visibleGroups.some(group => group.key === win.selectedGroupKey))
            win.selectGroup(win.visibleGroups[0].key)
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (conceptDetailPage.sourcesOpen) {
                conceptDetailPage.sourcesOpen = false
                event.accepted = true
            } else if (win.activeDetailConceptId) {
                win.activeDetailConceptId = ""
                event.accepted = true
            } else if (win.askOpen) {
                win.askOpen = false
                win.forceActiveFocus()
                event.accepted = true
            } else if (topicInput.activeFocus) {
                topicInput.text = ""
                topicInput.focus = false
                win.forceActiveFocus()
                event.accepted = true
            } else if (!win.releaseSearchFocus()) {
                win.closeView()
                event.accepted = true
            }
        } else if (!searchInput.activeFocus && !topicInput.activeFocus && event.key === Qt.Key_Slash) {
            searchInput.forceActiveFocus()
            event.accepted = true
        } else if (!searchInput.activeFocus && !topicInput.activeFocus && event.key === Qt.Key_Left) {
            win.cyclePill(-1)
            event.accepted = true
        } else if (!searchInput.activeFocus && !topicInput.activeFocus && event.key === Qt.Key_Right) {
            win.cyclePill(1)
            event.accepted = true
        }
    }
    Connections {
        function onConceptViewLoaded(view): void {
            if (win.activeDetailConceptId
                    && String(view?.concept?.id || "") === win.activeDetailConceptId)
                Notes.markConceptSeen(win.activeDetailConceptId)
        }
        function onNotesChanged(): void { readTimer.restart() }
        function onNoteDeleted(noteId): void {
            win.recentlyDeletedId = noteId
            undoTimer.restart()
        }
        function onNoteChanged(note): void {
            Notes.listConcepts("", "")
            if (note?.id === win.recentlyDeletedId) {
                win.recentlyDeletedId = ""
                undoTimer.stop()
            }
        }
        function onTopicDeleted(topic, count): void {
            if (count < 1) return
            win.recentlyDeletedTopic = topic
            undoTimer.restart()
            Toaster.toast(qsTr("Concept deleted"), qsTr("Deleted '%1'").arg(topic), "delete")
        }
        function onTopicRestored(topic): void {
            if (topic.toLowerCase() === win.recentlyDeletedTopic.toLowerCase()) {
                win.recentlyDeletedTopic = ""
                undoTimer.stop()
            }
        }
        function onTopicGenerated(topic, count, action, message): void {
            win.generationTopic = String(topic || "")
            win.generationAction = String(action || "created")
            win.generationFeedback = String(message || "")
            feedbackTimer.restart()
            win.selectGroup("topic:" + String(topic || "").toLowerCase())
        }
        target: Notes
    }
    Timer {
        id: undoTimer
        interval: 8000
        onTriggered: {
            win.recentlyDeletedId = ""
            win.recentlyDeletedTopic = ""
        }
    }
    Timer {
        id: feedbackTimer
        interval: 8000
        onTriggered: {
            win.generationFeedback = ""
            win.generationAction = ""
        }
    }

    component SectionTitle: StyledText {
        font: Qt.font({ family: Tokens.font.label.small.family, pixelSize: 12,
            weight: Font.Bold, letterSpacing: 1.1 })
        color: Colours.palette.m3onSurfaceVariant
    }
    component SectionHeading: RowLayout {
        id: sectionHeading
        required property string text
        property bool uppercase: true
        width: parent ? parent.width : implicitWidth
        spacing: 9
        SectionTitle {
            text: sectionHeading.uppercase ? sectionHeading.text.toUpperCase() : sectionHeading.text
        }
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.alpha(Colours.palette.m3outlineVariant, 0.42)
        }
    }
    component HeaderAction: Item {
        id: headerAction

        required property string actionIcon
        required property string label
        property bool running: false
        signal triggered()

        width: implicitWidth
        height: implicitHeight
        implicitWidth: actionContent.implicitWidth + 8
        implicitHeight: 28
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight
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
    TopicInline {
        id: topicOps
        topic: win.selectedGroup?.key?.startsWith("topic:") ? win.selectedGroup.title : ""
        subconcept: win.activeSubconcept
    }
    AskTopic {
        id: askOps
        topic: topicOps.topic
        subconcept: win.askWholeTopic ? "" : win.activeSubconcept
    }

    Rectangle {
        anchors.fill: parent
        radius: Tokens.rounding.medium
        color: Colours.palette.m3surface
        border.width: 1
        border.color: Colours.palette.m3outlineVariant

        Item {
            id: topBar
            readonly property bool compact: win.width < 780
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: compact ? 84 : 48
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onPressed: win.moveRequested()
            }
            GridLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 54
                anchors.topMargin: topBar.compact ? 6 : 0
                anchors.bottomMargin: topBar.compact ? 6 : 0
                columns: topBar.compact ? 2 : 4
                columnSpacing: 12
                rowSpacing: 4
                Flickable {
                    id: headerConcepts
                    Layout.row: 0
                    Layout.column: 0
                    Layout.fillWidth: true
                    Layout.minimumWidth: 80
                    implicitHeight: 32
                    clip: true
                    function ensureVisible(index): void {
                        const item = headerConceptRepeater.itemAt(index)
                        if (!item) return
                        if (item.x < contentX) contentX = item.x
                        else if (item.x + item.width > contentX + width) contentX = item.x + item.width - width
                    }
                    contentWidth: headerConceptRow.implicitWidth
                    contentHeight: height
                    boundsBehavior: Flickable.StopAtBounds
                    Row {
                        id: headerConceptRow
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 7
                        Repeater {
                            id: headerConceptRepeater
                            model: win.pillItems
                            delegate: Rectangle {
                                id: headerConceptPill
                                required property var modelData
                                required property int index
                                readonly property bool active: modelData.value === win.selectedGroupKey
                                implicitWidth: headerConceptLabel.implicitWidth + 22
                                implicitHeight: 26
                                radius: 7
                                color: active ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHigh
                                StyledText {
                                    id: headerConceptLabel
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 9
                                    anchors.rightMargin: 9
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: headerConceptPill.modelData.label
                                    color: headerConceptPill.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                                    font: Qt.font({ family: Tokens.font.label.small.family, pixelSize: 12,
                                        weight: Tokens.font.label.small.weight })
                                }
                                Rectangle {
                                    visible: !!headerConceptPill.modelData.hasRecent
                                    width: 5; height: 5; radius: 2.5
                                    color: Colours.palette.m3primary
                                    anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 3
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.activatePill(headerConceptPill.index)
                                }
                            }
                        }
                    }
                }
                Rectangle {
                    visible: win.generationFeedback.length > 0
                    Layout.row: topBar.compact ? 1 : 0
                    Layout.column: topBar.compact ? 0 : 1
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: Math.min(feedbackText.implicitWidth + 44, topBar.compact ? 220 : 180)
                    implicitHeight: 28
                    radius: 14
                    color: win.generationAction === "already_covered"
                        ? Qt.alpha(Colours.palette.m3primary, 0.16)
                        : (win.generationAction === "merged"
                            ? Qt.alpha(Colours.palette.m3tertiary || Colours.palette.m3secondary, 0.18)
                            : Qt.alpha(Colours.palette.m3primary, 0.22))
                    border.width: 1
                    border.color: win.generationAction === "already_covered"
                        ? Colours.palette.m3primary
                        : (win.generationAction === "merged"
                            ? (Colours.palette.m3tertiary || Colours.palette.m3secondary)
                            : Colours.palette.m3primary)

                    RowLayout {
                        id: feedbackRow
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 6
                        MaterialIcon {
                            text: win.generationAction === "already_covered"
                                ? "check_circle"
                                : (win.generationAction === "merged" ? "call_merge" : "auto_awesome")
                            color: win.generationAction === "already_covered"
                                ? Colours.palette.m3primary
                                : (win.generationAction === "merged"
                                    ? (Colours.palette.m3tertiary || Colours.palette.m3secondary)
                                    : Colours.palette.m3primary)
                            fill: 1
                            fontStyle: Tokens.font.icon.size(14).build()
                        }
                        StyledText {
                            id: feedbackText
                            Layout.fillWidth: true
                            text: win.generationFeedback
                            color: Colours.palette.m3onSurface
                            font: Qt.font({ family: Tokens.font.label.small.family, pixelSize: 12,
                                weight: Font.Medium })
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (win.generationTopic)
                                win.selectGroup("topic:" + win.generationTopic.toLowerCase())
                        }
                    }
                }
                Rectangle {
                    Layout.row: topBar.compact ? 1 : 0
                    Layout.column: topBar.compact && !win.generationFeedback ? 0 : (topBar.compact ? 1 : 2)
                    Layout.columnSpan: topBar.compact && !win.generationFeedback ? 2 : 1
                    Layout.preferredWidth: topBar.compact ? 300 : 200
                    Layout.fillWidth: topBar.compact
                    Layout.preferredHeight: 32
                    radius: 8
                    color: Colours.palette.m3surfaceContainerLow
                    border.width: topicInput.activeFocus ? 1 : 0
                    border.color: Colours.palette.m3primary
                    opacity: Notes.generatingTopic ? 0.6 : 1.0

                    MaterialIcon {
                        id: sparkIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        text: Notes.generatingTopic ? "hourglass_top" : "auto_awesome"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.small
                    }
                    TextInput {
                        id: topicInput
                        anchors.left: sparkIcon.right
                        anchors.leftMargin: 7
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.topMargin: 4
                        anchors.bottomMargin: 4
                        verticalAlignment: TextInput.AlignVCenter
                        color: Colours.palette.m3onSurface
                        font: Qt.font({ family: Tokens.font.body.small.family, pixelSize: 13,
                            weight: Tokens.font.body.small.weight })
                        selectByMouse: true
                        clip: true
                        enabled: !Notes.generatingTopic
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                const val = topicInput.text.trim()
                                if (val) {
                                    Notes.generateTopic(val)
                                    topicInput.text = ""
                                }
                                event.accepted = true
                            } else if (event.key === Qt.Key_Escape) {
                                topicInput.text = ""
                                topicInput.focus = false
                                win.forceActiveFocus()
                                event.accepted = true
                            }
                        }
                    }
                    StyledText {
                        anchors.left: topicInput.left
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !topicInput.text
                        text: Notes.generatingTopic ? qsTr("Generating…") : qsTr("AI generate topic…")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Qt.font({ family: Tokens.font.body.small.family, pixelSize: 13,
                            weight: Tokens.font.body.small.weight })
                    }
                }
                Rectangle {
                    Layout.row: 0
                    Layout.column: topBar.compact ? 1 : 3
                    Layout.preferredWidth: 180
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
            IconButton {
                anchors.right: parent.right
                anchors.rightMargin: 14
                y: topBar.compact ? 8 : (topBar.height - height) / 2
                width: 32
                height: 32
                type: IconButton.Text
                icon: "close"
                onClicked: win.closeRequested()
            }
        }

        Item {
            id: subconceptBanner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: topBar.bottom
            height: visible ? 40 : 0
            visible: !!win.selectedGroup && !win.noSearchResults
            clip: true

            Flickable {
                id: subconceptScroll
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                height: 28
                contentWidth: subconceptRow.implicitWidth
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: subconceptRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Repeater {
                        model: win.activeSubconcepts
                        delegate: Rectangle {
                            id: scPill
                            required property var modelData
                            required property int index

                            readonly property bool active: win.activeSubconcept.toLowerCase() === String(modelData).toLowerCase()
                            readonly property bool hasRecent: (win.selectedGroup?.notes || []).some(note => {
                                const sc = String(note.subconcept || "").trim() || ("Core " + (win.selectedGroup?.title || "Topic"))
                                return win.displaySubconcept(sc).toLowerCase() === String(modelData).toLowerCase()
                                    && note.unread
                            })
                            implicitWidth: scLabel.implicitWidth + (hasRecent ? 24 : 18)
                            implicitHeight: 24
                            radius: 6
                            color: active
                                ? Colours.palette.m3primary
                                : Colours.palette.m3surfaceContainerHigh
                            border.width: 1
                            border.color: active
                                ? Colours.palette.m3primary
                                : Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

                            StyledText {
                                id: scLabel
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 8
                                anchors.rightMargin: scPill.hasRecent ? 10 : 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: win.displaySubconcept(scPill.modelData)
                                color: scPill.active
                                    ? Colours.palette.m3onPrimary
                                    : Colours.palette.m3onSurfaceVariant
                                font: Qt.font({
                                    family: Tokens.font.label.small.family,
                                    pixelSize: 11,
                                    weight: scPill.active ? Font.DemiBold : Tokens.font.label.small.weight
                                })
                            }
                            Rectangle {
                                visible: scPill.hasRecent
                                width: 5
                                height: 5
                                radius: 2.5
                                color: Colours.palette.m3primary
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 2
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.activeSubconcept = scPill.modelData
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
                color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)
            }
        }

        Flickable {
            id: contentScroll
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: subconceptBanner.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.topMargin: 16
            anchors.bottomMargin: 22
            contentWidth: width
            contentHeight: contentColumn.implicitHeight
            onContentYChanged: readTimer.restart()
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            Column {
                id: contentColumn
                width: contentScroll.width
                spacing: 20
                Item {
                    id: topicHeader
                    readonly property bool compact: win.width < 780
                    width: parent.width
                    height: compact ? 76 : 38
                    visible: !win.noSearchResults
                    StyledText {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        width: topicHeader.compact ? parent.width : Math.max(0, actionFlick.x - 18)
                        height: 38
                        verticalAlignment: Text.AlignVCenter
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
                    Flickable {
                        id: actionFlick
                        x: topicHeader.compact ? 0 : parent.width - width
                        y: topicHeader.compact ? 42 : 5
                        width: topicHeader.compact ? parent.width
                            : Math.min(actionRow.implicitWidth, Math.max(0, parent.width - 168))
                        height: 28
                        contentWidth: actionRow.implicitWidth
                        contentHeight: height
                        flickableDirection: Flickable.HorizontalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                        RowLayout {
                            id: actionRow
                            width: implicitWidth
                            height: 28
                            spacing: topicHeader.compact ? 10 : 18
                            HeaderAction {
                                actionIcon: "auto_awesome"
                                label: askOps.busy ? qsTr("Thinking…") : qsTr("Ask AI")
                                running: askOps.busy
                                enabled: !!askOps.topic && Notes.providerConfigured
                                onTriggered: {
                                    win.askOpen = !win.askOpen
                                    if (win.askOpen) Qt.callLater(() => askInput.forceActiveFocus())
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
                                actionIcon: win.confirmDeleteActive ? "warning" : "delete"
                                label: win.confirmDeleteActive ? qsTr("Confirm delete?") : qsTr("Delete")
                                visible: !!win.selectedGroup?.key?.startsWith("topic:")
                                enabled: visible && !Notes.mutating
                                onTriggered: win.deleteCurrentTopic()
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
                                label: qsTr("Refresh")
                                running: Notes.loading
                                enabled: !Notes.loading && !topicOps.busy
                                onTriggered: {
                                    Notes.refresh()
                                    topicOps.reload()
                                }
                            }
                            HeaderAction {
                                actionIcon: "undo"
                                label: qsTr("Undo")
                                visible: topicOps.lastAcceptedIds.length > 0
                                enabled: !topicOps.busy
                                onTriggered: topicOps.undo()
                            }
                            HeaderAction {
                                actionIcon: "source"
                                label: qsTr("Sources (%1)").arg(win.filteredNotes.length)
                                enabled: !!win.selectedGroup
                                onTriggered: win.sourcesOpen = true
                            }
                        }
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
                Rectangle {
                    id: askPanel
                    width: parent.width
                    visible: win.askOpen && !!askOps.topic
                    height: visible ? askColumn.implicitHeight + 24 : 0
                    implicitHeight: askColumn.implicitHeight + 24
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3surfaceContainerLow
                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.65)

                    ColumnLayout {
                        id: askColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 9
                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                Layout.fillWidth: true
                                text: qsTr("Ask about %1").arg((!win.askWholeTopic && win.activeSubconcept) ? win.activeSubconcept : askOps.topic)
                                color: Colours.palette.m3onSurface
                                font: Tokens.font.label.medium
                            }
                            TextButton {
                                text: win.askWholeTopic ? qsTr("Whole topic") : (win.activeSubconcept ? qsTr("Subsection: %1").arg(win.activeSubconcept) : qsTr("This subsection"))
                                type: TextButton.Text
                                enabled: !askOps.busy
                                onClicked: win.askWholeTopic = !win.askWholeTopic
                            }
                            HeaderAction {
                                actionIcon: "close"
                                label: ""
                                onTriggered: win.askOpen = false
                            }
                        }
                        ScrollView {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(108, Math.max(42, askInput.contentHeight + 16))
                            clip: true
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                            background: Rectangle {
                                radius: Tokens.rounding.small
                                color: Colours.palette.m3surface
                                border.width: askInput.activeFocus ? 1 : 0
                                border.color: Colours.palette.m3primary
                            }
                            TextArea {
                                id: askInput
                                placeholderText: qsTr("Ask, explain, add commands, make a diagram… (Ctrl+Enter)")
                                wrapMode: TextEdit.Wrap
                                color: Colours.palette.m3onSurface
                                placeholderTextColor: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.small
                                enabled: !askOps.busy
                                selectByMouse: true
                                background: null
                                Keys.onPressed: event => {
                                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                            && (event.modifiers & Qt.ControlModifier)) {
                                        if (askOps.ask(askInput.text)) askInput.text = ""
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Escape) {
                                        win.askOpen = false
                                        win.forceActiveFocus()
                                        event.accepted = true
                                    }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            RowLayout {
                                visible: askOps.busy
                                spacing: 8
                                CircularIndicator {
                                    running: askOps.busy
                                    implicitSize: 16
                                }
                                StyledText {
                                    text: qsTr("Thinking…")
                                    color: Colours.palette.m3primary
                                    font: Tokens.font.body.small
                                }
                                TextButton {
                                    text: qsTr("Cancel")
                                    type: TextButton.Text
                                    onClicked: askOps.cancel()
                                }
                            }
                            Item { Layout.fillWidth: true }
                            TextButton {
                                text: askOps.busy ? qsTr("Thinking…") : qsTr("Ask")
                                type: TextButton.Text
                                enabled: !!askInput.text.trim() && !askOps.busy
                                onClicked: if (askOps.ask(askInput.text)) askInput.text = ""
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: !!askOps.errorMessage
                            spacing: 8
                            StyledText {
                                Layout.fillWidth: true
                                text: askOps.errorMessage
                                color: Colours.palette.m3error
                                font: Tokens.font.body.small
                                wrapMode: Text.Wrap
                            }
                            TextButton {
                                text: qsTr("Restore question")
                                type: TextButton.Text
                                visible: !askInput.text.trim() && !!askOps.question
                                onClicked: askInput.text = askOps.question
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: !!askOps.answer && !!askOps.question
                            spacing: 6
                            MaterialIcon {
                                text: "help_outline"
                                color: Colours.palette.m3primary
                                fontStyle: Tokens.font.icon.size(14).build()
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: askOps.question
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.medium
                                wrapMode: Text.Wrap
                            }
                            TextButton {
                                text: qsTr("Copy")
                                type: TextButton.Text
                                onClicked: {
                                    Quickshell.clipboardText = askOps.answer
                                    Toaster.toast(qsTr("Copied"), qsTr("Answer copied to clipboard."), "content_copy")
                                }
                            }
                        }
                        SelectableText {
                            Layout.fillWidth: true
                            visible: !!askOps.answer
                            text: askOps.answer
                            markdown: true
                            font: Tokens.font.body.small
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: askOps.available.length > 0 || askOps.lastAcceptedIds.length > 0
                            StyledText {
                                Layout.fillWidth: true
                                text: qsTr("Suggested note changes (%1)").arg(askOps.available.length)
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                            }
                            TextButton {
                                visible: askOps.available.length > 0
                                text: qsTr("Accept all")
                                type: TextButton.Text
                                enabled: !askOps.busy
                                onClicked: askOps.acceptAll()
                            }
                            TextButton {
                                visible: askOps.lastAcceptedIds.length > 0
                                text: qsTr("Undo")
                                type: TextButton.Text
                                enabled: !askOps.busy
                                onClicked: askOps.undo()
                            }
                        }
                        Repeater {
                            model: askOps.available
                            delegate: PendingLine {
                                required property var modelData
                                Layout.fillWidth: true
                                suggestion: modelData
                                controller: askOps
                            }
                        }
                    }
                }
                Repeater {
                    model: win.noSearchResults ? [] : win.subconceptBlocks
                    delegate: Column {
                        id: scBlockCol
                        required property var modelData
                        width: parent.width
                        spacing: 12

                        SectionHeading { text: scBlockCol.modelData.title }

                        Repeater {
                            model: scBlockCol.modelData.diagrams
                            delegate: DiagramCard {
                                required property var modelData
                                readonly property string seenNoteId: modelData.noteId || ""
                                width: scBlockCol.width
                                diagram: modelData
                            }
                        }

                        Repeater {
                            model: scBlockCol.modelData.bullets
                            delegate: Item {
                                id: scBulletItem
                                    readonly property string seenNoteId: modelData.noteId || modelData.commandEntry?.noteId || ""
                                required property var modelData
                                width: scBlockCol.width
                                implicitHeight: scBulletEntry.implicitHeight + 6
                                InlineEntry {
                                    id: scBulletEntry
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    entry: scBulletItem.modelData
                                    bullet: true
                                }
                            }
                        }

                        Repeater {
                            model: topicOps.pendingByKind("bullet")
                            delegate: PendingLine {
                                required property var modelData
                                width: scBlockCol.width
                                suggestion: modelData
                                controller: topicOps
                            }
                        }

                        Column {
                            width: parent.width
                            visible: scBlockCol.modelData.commands.length > 0 || topicOps.pendingByKind("command").length > 0
                            spacing: 6
                            SectionHeading { text: qsTr("Commands") }
                            Repeater {
                                model: scBlockCol.modelData.commands
                                delegate: Item {
                                    id: scCmdRow
                                    readonly property string seenNoteId: modelData.noteId || modelData.commandEntry?.noteId || ""
                                    required property var modelData
                                    property bool copied: false
                                    width: scBlockCol.width
                                    height: Math.max(40, scCmdEntry.implicitHeight + 12, scCmdExp.implicitHeight + 12)
                                    Timer {
                                        interval: 1200
                                        running: scCmdRow.copied
                                        onTriggered: scCmdRow.copied = false
                                    }
                                    Item {
                                        anchors.fill: parent
                                        Item {
                                            id: scCmdCopy
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 28
                                            height: 28
                                            opacity: scCmdCopyMouse.containsMouse || scCmdRow.copied ? 1 : 0.45
                                            Behavior on opacity { NumberAnimation { duration: 120 } }
                                            MaterialIcon {
                                                anchors.centerIn: parent
                                                text: scCmdRow.copied ? "check" : "content_copy"
                                                color: Colours.palette.m3onSurfaceVariant
                                                fill: 0
                                                fontStyle: Tokens.font.icon.size(12).build()
                                            }
                                            MouseArea {
                                                id: scCmdCopyMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    Quickshell.clipboardText = scCmdRow.modelData.command
                                                    scCmdRow.copied = true
                                                }
                                            }
                                        }
                                        CommandWithFlags {
                                            id: scCmdEntry
                                            anchors.left: scCmdCopy.right
                                            anchors.leftMargin: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: scCmdRow.width * 0.38
                                            command: scCmdRow.modelData.command
                                            isRecent: scCmdRow.modelData.isRecent
                                            onFlagHovered: (flag, exp, gx, gy) => {
                                                win.showFlagTooltip(flag, exp, gx, gy)
                                            }
                                            onFlagUnhovered: {
                                                win.hideFlagTooltip()
                                            }
                                        }
                                        SelectableText {
                                            id: scCmdExp
                                            anchors.left: scCmdEntry.right
                                            anchors.leftMargin: 12
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: scCmdRow.modelData.explanation
                                                ? "•  " + scCmdRow.modelData.explanation : ""
                                            color: Colours.palette.m3onSurface
                                            font: Qt.font({ family: Tokens.font.body.medium.family, pixelSize: 15 })
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
                        }

                        Repeater {
                            model: topicOps.pendingByKind("command")
                            delegate: PendingLine {
                                required property var modelData
                                width: scBlockCol.width
                                suggestion: modelData
                                controller: topicOps
                            }
                        }

                        Column {
                            width: parent.width
                            visible: scBlockCol.modelData.code.length > 0 || topicOps.pendingByKind("code").length > 0
                            spacing: 4
                            SectionHeading { text: qsTr("Code") }
                            Repeater {
                                model: scBlockCol.modelData.code
                                delegate: Rectangle {
                                    id: scCodeBlock
                                    readonly property string seenNoteId: modelData.noteId || modelData.commandEntry?.noteId || ""
                                    required property var modelData
                                    property bool copied: false
                                    property bool expanded: false
                                    width: scBlockCol.width
                                    implicitHeight: scCodeCol.implicitHeight + 14
                                    radius: 7
                                    color: Colours.palette.m3surfaceContainerLow
                                    border.width: scCodeBlock.modelData.isRecent ? 1 : 0
                                    border.color: scCodeBlock.modelData.isRecent ? Qt.alpha(Colours.palette.m3primary, 0.45) : "transparent"

                                    Timer {
                                        interval: 1400
                                        running: scCodeBlock.copied
                                        onTriggered: scCodeBlock.copied = false
                                    }

                                    Column {
                                        id: scCodeCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 7
                                        spacing: 4

                                        RowLayout {
                                            id: scCodeHeader
                                            width: parent.width
                                            spacing: 7

                                            Rectangle {
                                                visible: !!scCodeBlock.modelData.language
                                                radius: 4
                                                color: Qt.alpha(Colours.palette.m3primary, 0.15)
                                                border.width: 1
                                                border.color: Qt.alpha(Colours.palette.m3primary, 0.3)
                                                implicitWidth: scLangText.implicitWidth + 12
                                                implicitHeight: 20
                                                StyledText {
                                                    id: scLangText
                                                    anchors.centerIn: parent
                                                    text: String(scCodeBlock.modelData.language || "").toUpperCase()
                                                    color: Colours.palette.m3primary
                                                    font: Qt.font({ family: Tokens.font.mono.small.family, pixelSize: 10, weight: Font.Bold })
                                                }
                                            }

                                            SelectableText {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: scCodeBlock.modelData.explanation || scCodeBlock.modelData.label || ""
                                                color: Colours.palette.m3onSurfaceVariant
                                                font: Qt.font({ family: Tokens.font.body.small.family, pixelSize: 12,
                                                    weight: Tokens.font.body.small.weight })
                                                wrapMode: TextEdit.Wrap
                                            }

                                            Item {
                                                id: scCodeCopy
                                                Layout.preferredWidth: 28
                                                Layout.preferredHeight: 28
                                                opacity: scCodeCopyMouse.containsMouse || scCodeBlock.copied ? 1 : 0.45
                                                Behavior on opacity { NumberAnimation { duration: 120 } }
                                                MaterialIcon {
                                                    anchors.centerIn: parent
                                                    text: scCodeBlock.copied ? "check" : "content_copy"
                                                    color: Colours.palette.m3onSurfaceVariant
                                                    fill: 0
                                                    fontStyle: Tokens.font.icon.size(12).build()
                                                }
                                                MouseArea {
                                                    id: scCodeCopyMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        Quickshell.clipboardText = scCodeBlock.modelData.content
                                                        scCodeBlock.copied = true
                                                    }
                                                }
                                            }
                                            TapHandler {
                                                onTapped: point => {
                                                    if (point.position.x < scCodeHeader.width - scCodeCopy.width - 7)
                                                        scCodeBlock.expanded = !scCodeBlock.expanded
                                                }
                                            }
                                        }

                                        Rectangle {
                                            width: parent.width
                                            visible: scCodeBlock.expanded
                                            radius: 5
                                            color: Colours.palette.m3surfaceContainerLow
                                            implicitHeight: scCodeTextEdit.implicitHeight + 16

                                            InlineEntry {
                                                id: scCodeTextEdit
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.margins: 8
                                                entry: ({
                                                    text: scCodeBlock.modelData.content,
                                                    noteId: scCodeBlock.modelData.noteId,
                                                    key: scCodeBlock.modelData.key,
                                                    origin: scCodeBlock.modelData.origin,
                                                    isRecent: scCodeBlock.modelData.isRecent
                                                })
                                                mono: true
                                            }
                                        }

                                    }
                                }
                            }
                        }

                        Repeater {
                            model: topicOps.pendingByKind("code")
                            delegate: PendingLine {
                                required property var modelData
                                width: scBlockCol.width
                                suggestion: modelData
                                controller: topicOps
                            }
                        }

                        Column {
                            width: parent.width
                            visible: scBlockCol.modelData.configuration.length > 0
                            spacing: 6
                            SectionHeading { text: qsTr("Configuration") }
                            Repeater {
                                model: scBlockCol.modelData.configuration
                                delegate: Item {
                                    id: scCfgItem
                                    readonly property string seenNoteId: modelData.noteId || modelData.commandEntry?.noteId || ""
                                    required property var modelData
                                    width: scBlockCol.width
                                    implicitHeight: scCfgEntry.implicitHeight + 6
                                    InlineEntry {
                                        id: scCfgEntry
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        entry: scCfgItem.modelData
                                        bullet: true
                                    }
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            visible: scBlockCol.modelData.errors.length > 0
                            spacing: 6
                            SectionHeading { text: qsTr("Gotchas & fixes") }
                            Repeater {
                                model: scBlockCol.modelData.errors
                                delegate: Item {
                                    id: scErrItem
                                    readonly property string seenNoteId: modelData.noteId || modelData.commandEntry?.noteId || ""
                                    required property var modelData
                                    width: scBlockCol.width
                                    implicitHeight: scErrEntry.implicitHeight + 6
                                    InlineEntry {
                                        id: scErrEntry
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        entry: scErrItem.modelData
                                        bullet: true
                                    }
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            visible: scBlockCol.modelData.references.length > 0
                            spacing: 6
                            SectionHeading { text: qsTr("References") }
                            Repeater {
                                model: scBlockCol.modelData.references
                                delegate: Item {
                                    id: scRefItem
                                    readonly property string seenNoteId: modelData.noteId || modelData.commandEntry?.noteId || ""
                                    required property var modelData
                                    width: scBlockCol.width
                                    implicitHeight: scRefEntry.implicitHeight + 6
                                    InlineEntry {
                                        id: scRefEntry
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        entry: scRefItem.modelData
                                        bullet: true
                                    }
                                }
                            }
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    visible: !!win.query && win.visibleGroups.length === 0
                    text: qsTr("No topics match this search.")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                    horizontalAlignment: Text.AlignHCenter
                }
                StyledText {
                    width: parent.width
                    visible: !win.query && win.subconceptBlocks.length === 0 && !!win.selectedGroup
                    text: qsTr("No notes saved for this view.")
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
                            text: qsTr("Sources (%1)").arg(win.filteredNotes.length)
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
                        model: win.filteredNotes
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
                                    spacing: 8
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: win.displayTitle(sourceCard.modelData)
                                        color: sourceCard.modelData.unread ? Colours.palette.m3primary : Colours.palette.m3onSurface
                                        font: Tokens.font.label.builders.medium.weight(Font.DemiBold).build()
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        visible: sourceCard.modelData.origin === "assistant_selection"
                                        text: qsTr("Assistant")
                                        color: Colours.palette.m3onSurfaceVariant
                                        font: Tokens.font.label.small
                                    }
                                    StyledRect {
                                        visible: !!sourceCard.modelData.subconcept
                                        radius: Tokens.rounding.full
                                        color: Colours.tPalette.m3surfaceContainerHigh
                                        implicitHeight: 20
                                        implicitWidth: scBadge.implicitWidth + 12
                                        StyledText {
                                            id: scBadge
                                            anchors.centerIn: parent
                                            text: sourceCard.modelData.subconcept || ""
                                            font: Tokens.font.label.small
                                            color: Colours.palette.m3primary
                                        }
                                    }
                                    TextButton {
                                        text: qsTr("Delete")
                                        type: TextButton.Text
                                        font: Tokens.font.label.small
                                        enabled: !Notes.mutating
                                        onClicked: Notes.remove(sourceCard.modelData.id)
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: !!(sourceCard.modelData.triage_error || sourceCard.modelData.format_error)
                                        text: sourceCard.modelData.triage_error || sourceCard.modelData.format_error || ""
                                        color: Colours.palette.m3error
                                        font: Tokens.font.label.small
                                        elide: Text.ElideRight
                                    }
                                    TextButton {
                                        visible: Notes.isFormatting(sourceCard.modelData.id)
                                        text: qsTr("Stop")
                                        type: ButtonBase.Text
                                        font: Tokens.font.label.small
                                        onClicked: Notes.cancelOrganization(sourceCard.modelData.id)
                                    }
                                    TextButton {
                                        visible: sourceCard.modelData.status === "format_failed"
                                            || (sourceCard.modelData.category === "unclassified"
                                                && sourceCard.modelData.keep_decision !== "skip")
                                        text: qsTr("Retry")
                                        type: ButtonBase.Text
                                        font: Tokens.font.label.small
                                        enabled: !Notes.isFormatting(sourceCard.modelData.id)
                                        onClicked: Notes.queueOrganization(sourceCard.modelData.id)
                                    }
                                    TextButton {
                                        visible: sourceCard.modelData.keep_decision === "skip"
                                        text: qsTr("Keep")
                                        type: ButtonBase.Text
                                        font: Tokens.font.label.small
                                        onClicked: Notes.setKeepDecision(sourceCard.modelData.id, "pending")
                                    }
                                    TextButton {
                                        visible: sourceCard.modelData.keep_decision !== "skip"
                                        text: qsTr("Ignore")
                                        type: ButtonBase.Text
                                        font: Tokens.font.label.small
                                        onClicked: Notes.setKeepDecision(sourceCard.modelData.id, "skip")
                                    }
                                }
                                SelectableText {
                                    Layout.fillWidth: true
                                    text: sourceCard.modelData.raw_content || ""
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: sourceCard.modelData.technical_type === "command"
                                        ? Tokens.font.mono.small : Tokens.font.body.small
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: conceptDetailOverlay
            anchors.fill: parent
            visible: !!win.activeDetailConceptId
            z: 100
            color: Qt.alpha(Colours.palette.m3scrim, 0.48)
            radius: Tokens.rounding.medium
            MouseArea {
                anchors.fill: parent
                onClicked: win.activeDetailConceptId = ""
            }
            Rectangle {
                id: conceptDetailSurface
                anchors.fill: parent
                anchors.margins: 12
                radius: Tokens.rounding.medium
                color: Colours.palette.m3surface
                border.width: 1
                border.color: Colours.palette.m3outlineVariant
                MouseArea { anchors.fill: parent }
                ConceptPage {
                    id: conceptDetailPage
                    anchors.fill: parent
                    anchors.margins: 12
                    visible: Notes.currentConceptView?.concept?.id === win.activeDetailConceptId
                    conceptView: Notes.currentConceptView || ({})
                    onBackRequested: win.activeDetailConceptId = ""
                }
                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: win.activeDetailConceptId
                        && Notes.currentConceptView?.concept?.id !== win.activeDetailConceptId
                    CircularIndicator {
                        anchors.horizontalCenter: parent.horizontalCenter
                        running: Notes.loadingConcept
                        implicitSize: 22
                    }
                    StyledText {
                        text: Notes.loadingConcept ? qsTr("Loading concept…") : qsTr("Could not load this concept.")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                    }
                }
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            z: 80
            visible: !!win.recentlyDeletedId || !!win.recentlyDeletedTopic
            implicitWidth: undoRow.implicitWidth + 24
            implicitHeight: 38
            radius: 19
            color: Colours.palette.m3inverseSurface
            RowLayout {
                id: undoRow
                anchors.centerIn: parent
                spacing: 12
                StyledText {
                    text: win.recentlyDeletedTopic
                        ? qsTr("Concept '%1' deleted").arg(win.recentlyDeletedTopic)
                        : qsTr("Source deleted")
                    color: Colours.palette.m3inverseOnSurface
                    font: Tokens.font.label.small
                }
                TextButton {
                    text: qsTr("Undo")
                    type: TextButton.Text
                    enabled: !Notes.mutating
                    onClicked: {
                        if (win.recentlyDeletedTopic) {
                            Notes.restoreTopic(win.recentlyDeletedTopic)
                        } else if (win.recentlyDeletedId) {
                            Notes.restore(win.recentlyDeletedId)
                        }
                    }
                }
            }
        }
        // ── Floating Flag Inspector Tooltip ───────────────────────
        Rectangle {
            id: flagTooltipPill
            z: 999
            visible: !!win.activeFlagText && !!win.activeFlagExplanation
            x: Math.max(16, Math.min(parent.width - width - 16, win.flagTooltipX - 10))
            y: Math.max(16, win.flagTooltipY - height - 8)
            implicitWidth: tooltipRow.implicitWidth + 20
            implicitHeight: Math.max(30, tooltipRow.implicitHeight + 10)
            radius: 8
            color: Colours.palette.m3inverseSurface
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

            RowLayout {
                id: tooltipRow
                anchors.centerIn: parent
                spacing: 8
                Rectangle {
                    implicitWidth: flagBadge.implicitWidth + 8
                    implicitHeight: 20
                    radius: 4
                    color: Qt.alpha(Colours.palette.m3primary, 0.25)
                    StyledText {
                        id: flagBadge
                        anchors.centerIn: parent
                        text: win.activeFlagText
                        font: Qt.font({ family: Tokens.font.mono.small.family, pixelSize: 11, weight: Font.Bold })
                        color: Colours.palette.m3primary
                    }
                }
                StyledText {
                    Layout.maximumWidth: 320
                    text: win.activeFlagExplanation
                    font: Tokens.font.body.small
                    color: Colours.palette.m3inverseOnSurface
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
