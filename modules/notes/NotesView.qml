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
    property string generationFeedback: ""
    property string generationAction: ""
    property string generationTopic: ""
    property string activeSubconcept: "All"
    property string recentlyDeletedTopic: ""
    property bool confirmDeleteActive: false
    property string activeFlagText: ""
    property string activeFlagExplanation: ""
    property real flagTooltipX: 0
    property real flagTooltipY: 0

    function showFlagTooltip(flag, exp, gx, gy): void {
        win.activeFlagText = flag
        win.activeFlagExplanation = exp
        const localPt = win.mapFromGlobal(gx, gy)
        win.flagTooltipX = localPt.x
        win.flagTooltipY = localPt.y
    }

    function hideFlagTooltip(): void {
        win.activeFlagText = ""
        win.activeFlagExplanation = ""
    }

    Timer {
        id: confirmDeleteTimer
        interval: 4000
        running: false
        onTriggered: win.confirmDeleteActive = false
    }

    onSelectedGroupKeyChanged: {
        win.activeSubconcept = "All"
        win.confirmDeleteActive = false
    }

    readonly property var activeSubconcepts: {
        const list = ["All"]
        const seen = new Set()
        for (const note of win.selectedGroup?.notes || []) {
            const sc = String(note.subconcept || "").trim()
            if (sc && !seen.has(sc.toLowerCase())) {
                seen.add(sc.toLowerCase())
                list.push(sc)
            }
        }
        return list
    }

    readonly property var filteredNotes: {
        const notes = win.selectedGroup?.notes || []
        if (!win.activeSubconcept || win.activeSubconcept === "All")
            return notes
        return notes.filter(n => String(n.subconcept || "").trim().toLowerCase() === win.activeSubconcept.toLowerCase())
    }

    readonly property var filteredGroup: {
        if (!win.selectedGroup) return null
        return Object.assign({}, win.selectedGroup, { notes: win.filteredNotes })
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
                continue
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
    readonly property var selectedNote: {
        const notes = win.selectedGroup?.notes || []
        for (const note of notes)
            if (note.id === win.selectedId) return note
        return notes.length > 0 ? notes[0] : null
    }
    readonly property var pillItems: {
        const items = []
        function groupHasRecent(g) {
            return (g?.notes || []).some(n => win.isRecent(n.created_at))
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
    readonly property var knowledge: win.buildKnowledge(win.filteredGroup)
    readonly property var activeDynamicSections: {
        const map = new Map()
        for (const sec of (win.knowledge?.dynamicSections || [])) {
            map.set(sec.key, {
                title: sec.title,
                key: sec.key,
                bullets: sec.bullets || [],
                commands: sec.commands || [],
                code: sec.code || []
            })
        }
        const standardKeys = new Set(["overview", "notes", "commands", "code", "configuration", "errors", "references"])
        for (const pendingSec of (topicOps.pendingSections || [])) {
            const key = String(pendingSec).toLowerCase().trim()
            if (!standardKeys.has(key) && !map.has(key)) {
                map.set(key, {
                    title: pendingSec,
                    key: key,
                    bullets: [],
                    commands: [],
                    code: []
                })
            }
        }
        return Array.from(map.values())
    }

    signal closeRequested()
    signal moveRequested()

    function isRecent(timestamp): bool {
        if (!timestamp) return false
        const time = new Date(timestamp).getTime()
        if (isNaN(time)) return false
        const diff = Date.now() - time
        return diff >= 0 && diff < 24 * 3600 * 1000
    }
    function displayTitle(note): string {
        if (!note) return ""
        return note.title || String(note.raw_content || "").replace(/\s+/g, " ").trim() || qsTr("Untitled note")
    }
    function conciseExplanation(value): string {
        let text = String(value || "").replace(/^\s*[-*•]\s*/, "").trim()
        text = text.replace(/\s+along with\b.*$/i, "")
        text = text.replace(/\ball currently\b/i, "currently")
        if (text.length > 110) text = text.slice(0, 107).replace(/\s+$/, "") + "…"
        return text
    }
    function buildSubconceptBlocks(group): var {
        if (!group || !group.notes || group.notes.length === 0) return []
        const blocks = []
        const isAll = !win.activeSubconcept || win.activeSubconcept === "All"

        let targetSubconcepts = []
        if (isAll) {
            const seen = new Set()
            for (const note of group.notes) {
                let sc = String(note.subconcept || "").trim()
                if (!sc) sc = "Core " + (group.title || "Topic")
                const lower = sc.toLowerCase()
                if (!seen.has(lower)) {
                    seen.add(lower)
                    targetSubconcepts.push(sc)
                }
            }
        } else {
            targetSubconcepts = [win.activeSubconcept]
        }

        for (const scName of targetSubconcepts) {
            const blockNotes = group.notes.filter(n => {
                let sc = String(n.subconcept || "").trim()
                if (!sc) sc = "Core " + (group.title || "Topic")
                return sc.toLowerCase() === scName.toLowerCase()
            })
            if (blockNotes.length === 0) continue

            const block = {
                title: scName,
                bullets: [],
                commands: [],
                code: [],
                configuration: [],
                errors: [],
                references: []
            }

            const seenText = new Set()
            const seenCmd = new Set()

            function addText(listName, val, note, fieldKey) {
                const text = String(note.display_edits?.[fieldKey] || val || "").trim()
                const cleanKey = text.toLowerCase().replace(/[`*_#•-]/g, "").replace(/\s+/g, " ").trim()
                if (!text || seenText.has(listName + ":" + cleanKey)) return
                seenText.add(listName + ":" + cleanKey)
                block[listName].push({
                    text: text.replace(/^\s*[-*•]\s*/, ""),
                    noteId: note.id,
                    key: fieldKey,
                    origin: note.origin || "user",
                    isRecent: win.isRecent(note.created_at)
                })
            }

            function addCommand(cmd, exp, note, cmdKey, expKey) {
                const clean = String(note.display_edits?.[cmdKey] || cmd || "").trim().replace(/^\$\s*/, "")
                if (!clean || seenCmd.has(clean)) return
                seenCmd.add(clean)
                const isRecent = win.isRecent(note.created_at)
                block.commands.push({
                    command: clean,
                    explanation: win.conciseExplanation(note.display_edits?.[expKey] || exp),
                    commandEntry: { text: clean, noteId: note.id, key: cmdKey, origin: note.origin || "user", isRecent: isRecent },
                    explanationEntry: { text: win.conciseExplanation(note.display_edits?.[expKey] || exp),
                        noteId: note.id, key: expKey, origin: note.origin || "user", isRecent: isRecent },
                    isRecent: isRecent
                })
            }

            for (const note of blockNotes) {
                const targetSec = String(note.topic_section || "").trim().toLowerCase()
                const essentials = note.essentials || []
                const excerpts = note.exact_excerpts || []
                const type = String(note.technical_type || "general").toLowerCase()
                const isRecent = win.isRecent(note.created_at)

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
                        const label = ex.label || (ex.role === "before" ? qsTr("Legacy") : (ex.role === "after" ? qsTr("Modern") : ""))
                        const exp = label ? (label + (essentials[i] ? ": " + essentials[i] : "")) : (essentials[i] || win.displayTitle(note))
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
                    if (excerpts.length === 0 && note.raw_content) {
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

            if (block.bullets.length > 0 || block.commands.length > 0 || block.code.length > 0
                || block.configuration.length > 0 || block.errors.length > 0 || block.references.length > 0) {
                blocks.push(block)
            }
        }
        return blocks
    }

    function buildKnowledge(group): var {
        const result = {
            overview: [], notes: [], commands: [], code: [],
            configuration: [], errors: [], references: [],
            dynamicSections: []
        }
        if (!group) return result
        const seenText = new Set()
        const seenCommands = new Set()
        const customMap = new Map()

        function getOrCreateCustomSection(title) {
            const trimmed = String(title || "").trim()
            const key = trimmed.toLowerCase()
            if (!customMap.has(key)) {
                customMap.set(key, { title: trimmed, key: key, bullets: [], commands: [], code: [] })
            }
            return customMap.get(key)
        }

        function addText(section, value, note, fieldKey) {
            const text = String(note.display_edits?.[fieldKey] || value || "").trim()
            const key = text.toLowerCase().replace(/[\x60*_#•-]/g, "").replace(/\s+/g, " ").trim()
            if (!text || seenText.has(section + ":" + key)) return
            seenText.add(section + ":" + key)
            const entry = { text: text.replace(/^\s*[-*•]\s*/, ""),
                noteId: note.id, key: fieldKey, origin: note.origin || "user",
                isRecent: win.isRecent(note.created_at) }
            const secKey = String(section || "").toLowerCase().trim()
            if (result[secKey]) {
                result[secKey].push(entry)
            } else {
                getOrCreateCustomSection(section).bullets.push(entry)
            }
        }
        function addCommand(section, command, explanation, note, commandKey, explanationKey) {
            const clean = String(note.display_edits?.[commandKey] || command || "").trim().replace(/^\$\s*/, "")
            if (!clean || seenCommands.has(clean)) return
            seenCommands.add(clean)
            const isRecent = win.isRecent(note.created_at)
            const cmdObj = {
                command: clean,
                explanation: win.conciseExplanation(note.display_edits?.[explanationKey] || explanation),
                commandEntry: { text: clean, noteId: note.id, key: commandKey, origin: note.origin || "user", isRecent: isRecent },
                explanationEntry: { text: win.conciseExplanation(note.display_edits?.[explanationKey] || explanation),
                    noteId: note.id, key: explanationKey, origin: note.origin || "user", isRecent: isRecent },
                isRecent: isRecent
            }
            const secKey = String(section || "").toLowerCase().trim()
            if (secKey === "commands") {
                result.commands.push(cmdObj)
            } else {
                getOrCreateCustomSection(section).commands.push(cmdObj)
            }
        }
        function addCode(section, codeItem) {
            const secKey = String(section || "").toLowerCase().trim()
            if (secKey === "code") {
                result.code.push(codeItem)
            } else {
                getOrCreateCustomSection(section).code.push(codeItem)
            }
        }

        for (const note of group.notes || []) {
            const targetSection = String(note.topic_section || "").trim()
            const essentials = note.essentials || []
            const excerpts = note.exact_excerpts || []
            const type = note.technical_type || "general"
            const isRecent = win.isRecent(note.created_at)

            if (note.origin === "ai" && !(note.essentials || []).length) {
                const sec = targetSection ? targetSection : "notes"
                addText(sec, note.raw_content, note, "fallback")
                continue
            }

            if (type === "command") {
                const sec = targetSection ? targetSection : "commands"
                let commandIndex = 0
                for (let excerptIndex = 0; excerptIndex < excerpts.length; excerptIndex++) {
                    const lines = String(excerpts[excerptIndex].content || "").split("\n")
                    for (let lineIndex = 0; lineIndex < lines.length; lineIndex++) {
                        const line = lines[lineIndex].trim()
                        if (!line) continue
                        const essentialIndex = Math.min(commandIndex, Math.max(essentials.length - 1, 0))
                        const explanation = essentials[essentialIndex]
                            || win.displayTitle(note)
                        addCommand(sec, line, explanation, note,
                            "command:" + excerptIndex + ":" + lineIndex, "essential:" + essentialIndex)
                        commandIndex += 1
                    }
                }
                if (excerpts.length === 0 && !String(note.raw_content || "").includes("\n"))
                    addCommand(sec, note.raw_content, essentials[0] || win.displayTitle(note), note, "fallback", "essential:0")
                for (let i = commandIndex; i < essentials.length; i++) addText(sec === "commands" ? "notes" : sec, essentials[i], note, "essential:" + i)
            } else if (type === "code") {
                const sec = targetSection ? targetSection : "code"
                for (let i = 0; i < excerpts.length; i++) {
                    addCode(sec, {
                        language: excerpts[i].language || "",
                        content: note.display_edits?.["command:" + i + ":0"] || excerpts[i].content || "",
                        explanation: essentials[0] || win.displayTitle(note),
                        noteId: note.id, key: "command:" + i + ":0", origin: note.origin || "user",
                        isRecent: isRecent
                    })
                }
                if (excerpts.length === 0 && note.raw_content) {
                    addCode(sec, {
                        language: note.technology || "",
                        content: note.display_edits?.fallback || note.raw_content,
                        explanation: essentials[0] || "", noteId: note.id, key: "fallback", origin: note.origin || "user",
                        isRecent: isRecent
                    })
                }
            } else {
                let sec = targetSection
                if (!sec) {
                    if (type === "configuration") sec = "configuration"
                    else if (type === "error_fix") sec = "errors"
                    else if (type === "reference" || note.category === "reference") sec = "references"
                    else sec = "notes"
                }
                for (let i = 0; i < essentials.length; i++) addText(sec, essentials[i], note, "essential:" + i)
                if (essentials.length === 0) addText(sec, note.formatted_content || note.raw_content, note, "fallback")
            }
        }
        result.dynamicSections = Array.from(customMap.values())
        return result
    }
    function topicMarkdown(): string {
        if (!win.selectedGroup) return ""
        const output = ["# " + win.selectedGroup.title]
        for (const block of win.subconceptBlocks) {
            output.push("## " + block.title)
            if (block.bullets.length) {
                output.push(block.bullets.map(b => "- " + b.text).join("\n"))
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
            if (topicInput.activeFocus) {
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
                anchors.leftMargin: 32
                anchors.rightMargin: 32
                anchors.topMargin: topBar.compact ? 6 : 0
                anchors.bottomMargin: topBar.compact ? 6 : 0
                columns: topBar.compact ? 2 : 4
                columnSpacing: 12
                rowSpacing: 4
                StyledText {
                    Layout.row: 0
                    Layout.column: 0
                    Layout.fillWidth: true
                    Layout.minimumWidth: 80
                    text: qsTr("Quick Notes")
                    color: Colours.palette.m3onSurface
                    font: Qt.font({ family: Tokens.font.title.small.family, pixelSize: 18,
                        weight: Font.DemiBold })
                    elide: Text.ElideRight
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
                            Rectangle {
                                id: pillDot
                                visible: !!pill.modelData.hasRecent
                                width: 5
                                height: 5
                                radius: 2.5
                                color: Colours.palette.m3primary
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 3
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

        Item {
            id: subconceptBanner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: topicBanner.bottom
            height: visible ? 40 : 0
            visible: !!win.selectedGroup && !win.noSearchResults
            clip: true

            Flickable {
                id: subconceptScroll
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 32
                anchors.rightMargin: 32
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
                            implicitWidth: scLabel.implicitWidth + 18
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
                                anchors.centerIn: parent
                                text: scPill.modelData
                                color: scPill.active
                                    ? Colours.palette.m3onPrimary
                                    : Colours.palette.m3onSurfaceVariant
                                font: Qt.font({
                                    family: Tokens.font.label.small.family,
                                    pixelSize: 11,
                                    weight: scPill.active ? Font.DemiBold : Tokens.font.label.small.weight
                                })
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
                                label: win.groupIsFormatting() ? qsTr("Syncing…") : qsTr("Sync")
                                running: win.groupIsFormatting()
                                enabled: !!win.selectedGroup && !win.groupIsFormatting() && Notes.providerConfigured
                                onTriggered: win.analyzeSelectedGroup()
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
                Repeater {
                    model: win.noSearchResults ? [] : win.subconceptBlocks
                    delegate: Column {
                        id: scBlockCol
                        required property var modelData
                        width: parent.width
                        spacing: 12

                        SectionTitle {
                            text: scBlockCol.modelData.title.toUpperCase()
                        }
                        Rectangle {
                            width: parent.width
                            height: 1
                            color: Colours.palette.m3outlineVariant
                            opacity: 0.55
                        }

                        Repeater {
                            model: scBlockCol.modelData.bullets
                            delegate: Item {
                                id: scBulletItem
                                required property var modelData
                                width: parent.width
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

                        Column {
                            width: parent.width
                            visible: scBlockCol.modelData.commands.length > 0
                            spacing: 6
                            StyledText {
                                text: qsTr("COMMANDS")
                                color: Colours.palette.m3onSurfaceVariant
                                font: Qt.font({ family: Tokens.font.label.small.family, pixelSize: 11, weight: Font.Bold })
                            }
                            Repeater {
                                model: scBlockCol.modelData.commands
                                delegate: Item {
                                    id: scCmdRow
                                    required property var modelData
                                    property bool copied: false
                                    width: parent.width
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
                                            text: "•  " + scCmdRow.modelData.explanation
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

                        Column {
                            width: parent.width
                            visible: scBlockCol.modelData.code.length > 0
                            spacing: 8
                            StyledText {
                                text: qsTr("CODE")
                                color: Colours.palette.m3onSurfaceVariant
                                font: Qt.font({ family: Tokens.font.label.small.family, pixelSize: 11, weight: Font.Bold })
                            }
                            Repeater {
                                model: scBlockCol.modelData.code
                                delegate: Rectangle {
                                    id: scCodeBlock
                                    required property var modelData
                                    property bool copied: false
                                    property bool showRaw: false
                                    width: parent.width
                                    implicitHeight: scCodeCol.implicitHeight + 20
                                    radius: 8
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
                                        anchors.margins: 10
                                        spacing: 8

                                        RowLayout {
                                            width: parent.width
                                            spacing: 8

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

                                            Rectangle {
                                                visible: !!scCodeBlock.modelData.label
                                                radius: 4
                                                color: Colours.palette.m3surfaceContainerHigh
                                                implicitWidth: scLabelText.implicitWidth + 12
                                                implicitHeight: 20
                                                StyledText {
                                                    id: scLabelText
                                                    anchors.centerIn: parent
                                                    text: scCodeBlock.modelData.label || ""
                                                    color: Colours.palette.m3onSurfaceVariant
                                                    font: Qt.font({ family: Tokens.font.label.small.family, pixelSize: 10, weight: Font.Medium })
                                                }
                                            }

                                            Item { Layout.fillWidth: true }

                                            Item {
                                                visible: !!scCodeBlock.modelData.rawContent
                                                implicitWidth: scRawRow.implicitWidth + 8
                                                implicitHeight: 24
                                                RowLayout {
                                                    id: scRawRow
                                                    anchors.centerIn: parent
                                                    spacing: 4
                                                    MaterialIcon {
                                                        text: scCodeBlock.showRaw ? "expand_less" : "notes"
                                                        fontStyle: Tokens.font.icon.size(13).build()
                                                        color: Colours.palette.m3onSurfaceVariant
                                                    }
                                                    StyledText {
                                                        text: scCodeBlock.showRaw ? qsTr("Hide Raw") : qsTr("Raw Note")
                                                        font: Qt.font({ family: Tokens.font.label.small.family, pixelSize: 11 })
                                                        color: Colours.palette.m3onSurfaceVariant
                                                    }
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: scCodeBlock.showRaw = !scCodeBlock.showRaw
                                                }
                                            }

                                            Rectangle {
                                                radius: 4
                                                color: scCopyMouse.containsMouse || scCodeBlock.copied ? Colours.palette.m3surfaceContainerHigh : "transparent"
                                                implicitWidth: scCopyRow.implicitWidth + 12
                                                implicitHeight: 24
                                                RowLayout {
                                                    id: scCopyRow
                                                    anchors.centerIn: parent
                                                    spacing: 4
                                                    MaterialIcon {
                                                        text: scCodeBlock.copied ? "check" : "content_copy"
                                                        fontStyle: Tokens.font.icon.size(13).build()
                                                        color: scCodeBlock.copied ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                                    }
                                                    StyledText {
                                                        text: scCodeBlock.copied ? qsTr("Copied") : qsTr("Copy")
                                                        font: Qt.font({ family: Tokens.font.label.small.family, pixelSize: 11, weight: Font.Medium })
                                                        color: scCodeBlock.copied ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                                    }
                                                }
                                                MouseArea {
                                                    id: scCopyMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        Quickshell.clipboardText = scCodeBlock.modelData.content
                                                        scCodeBlock.copied = true
                                                    }
                                                }
                                            }
                                        }

                                        SelectableText {
                                            width: parent.width
                                            visible: !!scCodeBlock.modelData.explanation && scCodeBlock.modelData.explanation !== scCodeBlock.modelData.label
                                            text: scCodeBlock.modelData.explanation
                                            color: Colours.palette.m3onSurfaceVariant
                                            font: Qt.font({ family: Tokens.font.body.small.family, pixelSize: 14, weight: Tokens.font.body.small.weight })
                                        }

                                        Rectangle {
                                            width: parent.width
                                            radius: 6
                                            color: Colours.palette.m3surfaceContainerLowest
                                            border.width: 1
                                            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.35)
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

                                        Column {
                                            width: parent.width
                                            visible: scCodeBlock.showRaw && !!scCodeBlock.modelData.rawContent
                                            spacing: 4

                                            Rectangle {
                                                width: parent.width
                                                height: 1
                                                color: Colours.palette.m3outlineVariant
                                                opacity: 0.3
                                            }

                                            StyledText {
                                                text: qsTr("ORIGINAL NOTE")
                                                color: Colours.palette.m3onSurfaceVariant
                                                font: Qt.font({ family: Tokens.font.label.small.family, pixelSize: 10, weight: Font.Bold })
                                            }

                                            Rectangle {
                                                width: parent.width
                                                radius: 4
                                                color: Colours.palette.m3surfaceContainer
                                                implicitHeight: scRawEdit.implicitHeight + 12

                                                SelectableText {
                                                    id: scRawEdit
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    anchors.margins: 6
                                                    text: scCodeBlock.modelData.rawContent || ""
                                                    color: Colours.palette.m3onSurface
                                                    font: Qt.font({ family: Tokens.font.body.small.family, pixelSize: 12 })
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            visible: scBlockCol.modelData.configuration.length > 0
                            spacing: 6
                            StyledText {
                                text: qsTr("CONFIGURATION")
                                color: Colours.palette.m3onSurfaceVariant
                                font: Qt.font({ family: Tokens.font.label.small.family, pixelSize: 11, weight: Font.Bold })
                            }
                            Repeater {
                                model: scBlockCol.modelData.configuration
                                delegate: Item {
                                    id: scCfgItem
                                    required property var modelData
                                    width: parent.width
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
                            StyledText {
                                text: qsTr("GOTCHAS & FIXES")
                                color: Colours.palette.m3onSurfaceVariant
                                font: Qt.font({ family: Tokens.font.label.small.family, pixelSize: 11, weight: Font.Bold })
                            }
                            Repeater {
                                model: scBlockCol.modelData.errors
                                delegate: Item {
                                    id: scErrItem
                                    required property var modelData
                                    width: parent.width
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
                            StyledText {
                                text: qsTr("REFERENCES")
                                color: Colours.palette.m3onSurfaceVariant
                                font: Qt.font({ family: Tokens.font.label.small.family, pixelSize: 11, weight: Font.Bold })
                            }
                            Repeater {
                                model: scBlockCol.modelData.references
                                delegate: Item {
                                    id: scRefItem
                                    required property var modelData
                                    width: parent.width
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

                Column {
                    width: parent.width
                    visible: !win.noSearchResults && topicOps.available.length > 0
                    spacing: 8
                    SectionTitle { text: qsTr("SUGGESTED ADDITIONS") }
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Colours.palette.m3outlineVariant
                        opacity: 0.55
                    }
                    Repeater {
                        model: topicOps.available
                        delegate: PendingLine {
                            required property var modelData
                            width: parent.width
                            suggestion: modelData
                            controller: topicOps
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
                                        color: win.isRecent(sourceCard.modelData.created_at) ? Colours.palette.m3primary : Colours.palette.m3onSurface
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
