pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.services

Singleton {
    id: root

    readonly property string backendPath: Quickshell.shellPath("scripts/notes_backend.py")

    property var notes: []
    property bool loading: false
    property bool saving: false
    property bool mutating: false
    property string errorMessage: ""
    property string configuredProvider: ""
    property string fallbackProvider: ""
    property bool providerConfigured: false
    readonly property string providerDisclosure: {
        if (!root.providerConfigured) return ""
        const primary = root.configuredProvider.charAt(0).toUpperCase() + root.configuredProvider.slice(1)
        if (!root.fallbackProvider) return primary
        const fallback = root.fallbackProvider.charAt(0).toUpperCase() + root.fallbackProvider.slice(1)
        return qsTr("%1 first, %2 fallback").arg(primary).arg(fallback)
    }
    readonly property int pendingAnalysisCount: root.notes.filter(note =>
        note.category === "unclassified" && note.keep_decision !== "skip" && !note.local_only
    ).length

    property var _createInput: ({})
    property var _mutationInput: ({})
    property string _mutationAction: ""
    property var _organizeQueue: []
    property string _activeOrganizeId: ""
    property string _rerunOrganizeId: ""
    property var _cancelledOrganizeIds: []
    property var _cancelTriageQueue: []
    property string _activeCancelTriageId: ""
    property var _activeDraftRequest: ({})
    property var _draftQueue: []
    property var _draftIds: ({})
    property string _createOutput: ""
    property string _draftOutput: ""
    property string _listOutput: ""
    property string _mutationOutput: ""
    property string _organizeOutput: ""
    property string _cancelOutput: ""
    readonly property bool generatingTopic: generateTopicProc.running
    property var _generateTopicInput: ({})
    property string _generateTopicOutput: ""
    property var _selectionQueue: []
    property var _activeSelection: ({})
    property string _selectionOutput: ""

    signal noteCreated(var note, bool formattingQueued)
    signal draftSaved(var note, string clientToken)
    signal draftSaveFailed(string message, string clientToken)
    signal saveFailed(string message)
    signal noteChanged(var note)
    signal noteDeleted(string noteId)
    signal topicDeleted(string topic, int count)
    signal topicRestored(string topic, int count)
    signal organizationFinished(string noteId, bool success, string message)
    signal topicGenerated(string topic, int count, string action, string message)
    signal topicGenerateFailed(string message)
    signal assistantSelectionSaved(var note, string clientToken)
    signal assistantSelectionSaveFailed(string message, string clientToken)

    property var concepts: []
    property var currentConceptView: null
    property var searchResults: []
    property int searchTotal: 0
    property int searchNextOffset: 0
    property bool searchHasMore: false
    property bool searching: searchProc.running
    property bool loadingConcept: conceptGetProc.running

    signal conceptsLoaded(var concepts)
    signal conceptViewLoaded(var view)
    signal searchCompleted(var results)

    property var _conceptsListInput: ({})
    property var _conceptGetInput: ({})
    property var _depthInput: ({})
    property var _expansionInput: ({})
    property var _searchInput: ({})
    property var _exportInput: ({})
    property var _seenQueue: []
    property string _activeSeenId: ""
    property var _pendingSyncIds: []
    property var _syncInput: ({})
    property bool _pendingRefresh: false

    function listConcepts(topic, area): void {
        _conceptsListInput = { topic: topic || "", area: area || "" }
        if (conceptsListProc.running) return
        conceptsListProc.command = ["python3", root.backendPath, "list-concepts"]
        conceptsListProc.running = true
    }

    function getConcept(conceptId, mode): void {
        _conceptGetInput = { id: conceptId, mode: mode || "" }
        if (conceptGetProc.running) return
        conceptGetProc.command = ["python3", root.backendPath, "read-concept"]
        conceptGetProc.running = true
    }

    function setConceptDepth(conceptId, depth): void {
        _depthInput = { id: conceptId, depth: depth }
        if (depthProc.running) return
        depthProc.running = true
    }

    function setConceptExpansion(conceptId, expanded): void {
        root._expansionInput = { id: conceptId, expanded: expanded === true }
        if (expansionProc.running) return
        expansionProc.running = true
    }

    function searchConcepts(query, offset): void {
        const value = String(query || "")
        const start = offset === undefined ? 0 : Math.max(0, Number(offset) || 0)
        _searchInput = { query: value, offset: start, limit: 50 }
        if (start === 0) {
            root.searchResults = []
            root.searchTotal = 0
            root.searchNextOffset = 0
            root.searchHasMore = false
        }
        if (searchProc.running) return
        searchProc.command = ["python3", root.backendPath, "search-concepts"]
        searchProc.running = true
    }

    function copyConcept(conceptId): void {
        _exportInput = { id: conceptId, mode: "understand" }
        if (exportProc.running) return
        exportProc.running = true
    }

    function syncLegacyNotes(noteId): void {
        const targetId = String(noteId || "")
        if (syncLegacyProc.running) {
            const pending = root._pendingSyncIds.slice()
            if (!pending.includes(targetId)) pending.push(targetId)
            root._pendingSyncIds = pending
            return
        }
        root._syncInput = targetId ? { id: targetId } : {}
        syncLegacyProc.command = ["python3", root.backendPath, "sync-legacy-notes"]
        syncLegacyProc.running = true
    }

    function markConceptSeen(conceptId): void {
        const id = String(conceptId || "")
        if (!id) return
        root.concepts = root.concepts.map(c => c.id === id ? Object.assign({}, c, { unseen: 0 }) : c)
        const queue = root._seenQueue.slice()
        if (id !== root._activeSeenId && queue.indexOf(id) < 0) queue.push(id)
        root._seenQueue = queue
        root._startNextSeen()
    }

    function _startNextSeen(): void {
        if (seenProc.running || root._seenQueue.length === 0) return
        const queue = root._seenQueue.slice()
        root._activeSeenId = queue.shift()
        root._seenQueue = queue
        seenProc.running = true
    }

    function parseResult(text): var {
        const output = String(text || "").replace(/^\uFEFF/, "").trim()
        try {
            return JSON.parse(output)
        } catch (e) {
            // Process stdout can include a warning before the backend's JSON line.
            // Parse the last standalone JSON object so that noise does not break note loading.
            const lines = output.split(/\r?\n/)
            for (let i = lines.length - 1; i >= 0; i--) {
                const line = lines[i].trim()
                if (!line.startsWith("{") || !line.endsWith("}")) continue
                try {
                    return JSON.parse(line)
                } catch (ignored) {}
            }
            return { success: false, error: qsTr("The notes backend returned an invalid response.") }
        }
    }

    function save(rawContent, organizeAfterSave): bool {
        const content = String(rawContent || "").trim()
        if (!content) return false
        if (createProc.running) {
            root.errorMessage = qsTr("A note is already being saved.")
            root.saveFailed(root.errorMessage)
            return false
        }
        root.errorMessage = ""
        root.saving = true
        root._createOutput = ""
        root._createInput = {
            raw_content: content,
            organize: organizeAfterSave === true
        }
        createProc.command = ["python3", root.backendPath, "smart-upsert"]
        createProc.running = true
        return true
    }

    function smartUpsert(content): bool {
        return root.save(content, true)
    }

    function refresh(): void {
        if (listProc.running) {
            root._pendingRefresh = true
            return
        }
        root.loading = true
        root._listOutput = ""
        listProc.command = ["python3", root.backendPath, "list"]
        listProc.running = true
    }

    function generateTopic(topicQuery): bool {
        const query = String(topicQuery || "").trim()
        if (!query) return false
        if (generateTopicProc.running) {
            Toaster.toast(qsTr("Notes"), qsTr("Already generating a topic in the background…"), "hourglass_top")
            return false
        }
        root._generateTopicOutput = ""
        root._generateTopicInput = { topic: query }
        generateTopicProc.command = ["python3", root.backendPath, "generate-topic"]
        generateTopicProc.running = true
        Toaster.toast(qsTr("Generating notes…"), qsTr("Creating topic notes for \"%1\"").arg(query), "auto_awesome")
        return true
    }

    function saveDraft(noteId, rawContent, clientToken, analyzeAfterSave): bool {
        const content = String(rawContent || "").trim()
        if (!content) return false
        const id = String(noteId || "")
        const token = String(clientToken || "")
        const knownId = id || root._draftIds[token] || ""
        const request = {
            action: knownId ? "update" : "create",
            payload: knownId ? { id: knownId, raw_content: content } : { raw_content: content, client_token: token },
            client_token: token,
            analyze: analyzeAfterSave === true
        }
        const queue = root._draftQueue.slice()
        const existing = queue.findIndex(item => item.client_token === token)
        if (existing >= 0) {
            request.analyze = request.analyze || queue[existing].analyze
            queue[existing] = request
        } else {
            queue.push(request)
        }
        root._draftQueue = queue
        root._startNextDraftSave()
        return true
    }

    function saveAssistantSelection(rawContent, clientToken): bool {
        const content = String(rawContent || "").replace(/\u2029/g, "\n").trim()
        if (!content) return false
        const queue = root._selectionQueue.slice()
        queue.push({ raw_content: content, origin: "assistant_selection", client_token: String(clientToken || "") })
        root._selectionQueue = queue
        root._startNextSelectionSave()
        return true
    }

    function _startNextSelectionSave(): void {
        if (selectionSaveProc.running || root._selectionQueue.length === 0) return
        const queue = root._selectionQueue.slice()
        root._activeSelection = queue.shift()
        root._selectionQueue = queue
        root._selectionOutput = ""
        selectionSaveProc.running = true
    }

    function _startDraftSave(request): void {
        const knownId = root._draftIds[request.client_token] || ""
        if (knownId && request.action === "create") {
            request.action = "update"
            request.payload = { id: knownId, raw_content: request.payload.raw_content }
        }
        root._activeDraftRequest = request
        root._draftOutput = ""
        draftProc.command = ["python3", root.backendPath, request.action]
        draftProc.running = true
    }

    function _startNextDraftSave(): void {
        if (draftProc.running || root._draftQueue.length === 0) return
        const queue = root._draftQueue.slice()
        const next = queue.shift()
        root._draftQueue = queue
        root._startDraftSave(next)
    }

    function queueOrganization(noteId): void {
        const id = String(noteId || "")
        if (!id) return
        if (id === root._activeOrganizeId) {
            root._rerunOrganizeId = id
            return
        }
        if (root._organizeQueue.indexOf(id) >= 0)
            return
        const queue = root._organizeQueue.slice()
        queue.push(id)
        root._organizeQueue = queue
        root._startNextOrganization()
    }

    function analyzeInbox(): void {
        const source = root.notes || []
        for (let i = 0; i < source.length; i++) {
            const note = source[i]
            if (note.category === "unclassified" && note.keep_decision !== "skip" && !note.local_only)
                root.queueOrganization(note.id)
        }
    }

    function _startNextOrganization(): void {
        if (organizeProc.running || root._organizeQueue.length === 0) return
        const queue = root._organizeQueue.slice()
        const id = queue.shift()
        root._organizeQueue = queue
        root._activeOrganizeId = id
        root._organizeOutput = ""
        organizeProc.command = ["python3", root.backendPath, "triage"]
        organizeProc.running = true
    }

    function isFormatting(noteId): bool {
        const id = String(noteId || "")
        return id === root._activeOrganizeId || root._organizeQueue.indexOf(id) >= 0
    }

    function cancelOrganization(noteId): bool {
        const id = String(noteId || "")
        if (!id) return false
        const queued = root._organizeQueue.slice()
        const queuedIndex = queued.indexOf(id)
        if (queuedIndex >= 0) {
            queued.splice(queuedIndex, 1)
            root._organizeQueue = queued
            return true
        }
        if (root._activeOrganizeId !== id || !organizeProc.running) return false
        if (root._cancelledOrganizeIds.indexOf(id) < 0)
            root._cancelledOrganizeIds = root._cancelledOrganizeIds.concat([id])
        root._rerunOrganizeId = root._rerunOrganizeId === id ? "" : root._rerunOrganizeId
        root._cancelTriageQueue = root._cancelTriageQueue.concat([id])
        organizeProc.running = false
        root._startNextTriageCancellation()
        return true
    }

    function _startNextTriageCancellation(): void {
        if (cancelTriageProc.running || !root._cancelTriageQueue.length) return
        const queue = root._cancelTriageQueue.slice()
        root._activeCancelTriageId = queue.shift()
        root._cancelTriageQueue = queue
        cancelTriageProc.running = true
    }

    function setKeepDecision(noteId, decision): bool {
        return root._mutate("set-keep-decision", { id: String(noteId || ""), decision: String(decision || "") })
    }

    function update(noteId, rawContent, tags): bool {
        return root._mutate("update", {
            id: String(noteId || ""),
            raw_content: String(rawContent || ""),
            tags: tags || []
        })
    }

    function remove(noteId): bool {
        return root._mutate("delete", { id: String(noteId || "") })
    }

    function restore(noteId): bool {
        return root._mutate("restore", { id: String(noteId || "") })
    }

    function removeTopic(topic): bool {
        return root._mutate("delete-topic", { topic: String(topic || "") })
    }

    function restoreTopic(topic): bool {
        return root._mutate("restore-topic", { topic: String(topic || "") })
    }

    function _mutate(action, payload): bool {
        if (mutationProc.running) {
            root.errorMessage = qsTr("Another note change is still being saved.")
            return false
        }
        root.errorMessage = ""
        root.mutating = true
        root._mutationAction = action
        root._mutationInput = payload
        root._mutationOutput = ""
        mutationProc.command = ["python3", root.backendPath, action]
        mutationProc.running = true
        return true
    }

    property var _readQueue: []
    property var _readInput: []

    function markNotesSeen(entries): void {
        const pending = root._readQueue.slice()
        for (const entry of entries) {
            if (!pending.some(item => item.id === entry.id && item.revision === entry.revision)) pending.push(entry)
        }
        root._readQueue = pending
        root._flushReadQueue()
    }
    function _flushReadQueue(): void {
        if (noteReadProc.running || !root._readQueue.length) return
        root._readInput = root._readQueue.slice(0, 100)
        root._readQueue = root._readQueue.slice(100)
        noteReadProc.running = true
    }
    Process {
        id: noteReadProc
        command: ["python3", root.backendPath, "mark-notes-seen"]
        stdinEnabled: true
        onStarted: write(JSON.stringify({ notes: root._readInput }) + "\n")
        stdout: StdioCollector { id: readResult }
        onExited: {
            const result = root.parseResult(readResult.text)
            if (result.success) {
                const revisions = ({})
                for (const entry of result.marked || []) revisions[entry.id] = entry.revision
                root.notes = root.notes.map(note => revisions[note.id] === note.content_revision
                    ? Object.assign({}, note, { unread: false, seen_revision: revisions[note.id] }) : note)
            }
            Qt.callLater(() => root._flushReadQueue())
        }
    }

    function refreshProviderStatus(): void {
        if (providerProc.running) return
        providerProc.command = ["python3", root.backendPath, "provider-status"]
        providerProc.running = true
    }

    Component.onCompleted: {
        root.refresh()
        root.refreshProviderStatus()
    }

    Process {
        id: createProc

        stdinEnabled: true
        onStarted: write(JSON.stringify(root._createInput) + "\n")
        stdout: StdioCollector {
            onStreamFinished: {
                root.saving = false
                const result = root.parseResult(text)
                if (!result.success || (!result.note && result.action !== "ignore")) {
                    root.errorMessage = result.error || qsTr("The note could not be saved.")
                    root.saveFailed(root.errorMessage)
                    return
                }
                if (result.action === "ignore") {
                    Toaster.toast(qsTr("Duplicate Note"), qsTr("Already covered, duplicate ignored."), "check_circle")
                    return
                }
                const shouldOrganize = root._createInput.organize === true
                root.noteCreated(result.note, shouldOrganize)
                root.refresh()
                if (result.action === "merge") {
                    Toaster.toast(qsTr("Note merged"), qsTr("Merged into note (%1)").arg(result.subconcept || ""), "call_merge")
                } else if (shouldOrganize) {
                    root.queueOrganization(result.note.id)
                    Toaster.toast(qsTr("Note saved"), qsTr("Formatting in the background…"), "auto_awesome")
                } else {
                    Toaster.toast(qsTr("Note saved"), qsTr("Added to %1 / %2").arg(result.domain || result.note.topic || "Inbox").arg(result.subconcept || "Core"), "note_add")
                }
            }
        }
    }

    Process {
        id: listProc

        stdinEnabled: true
        onStarted: write("{}\n")
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false
                const result = root.parseResult(text)
                if (result.success) {
                    root.errorMessage = ""
                    root.notes = result.notes || []
                } else {
                    root.errorMessage = result.error || qsTr("Notes could not be loaded.")
                }
                if (root._pendingRefresh) {
                    root._pendingRefresh = false
                    Qt.callLater(() => root.refresh())
                }
            }
        }
    }

    Process {
        id: draftProc

        stdinEnabled: true
        onStarted: write(JSON.stringify(root._activeDraftRequest.payload || {}) + "\n")
        stdout: SplitParser {
            onRead: data => root._draftOutput += data
        }
        onExited: exitCode => {
            const request = root._activeDraftRequest
            const result = root.parseResult(root._draftOutput)
            root._draftOutput = ""
            if (exitCode === 0 && result.success && result.note) {
                const ids = Object.assign({}, root._draftIds)
                ids[request.client_token] = result.note.id
                root._draftIds = ids
                root.draftSaved(result.note, request.client_token || "")
                if (request.analyze === true) root.queueOrganization(result.note.id)
                root.refresh()
            } else {
                const message = result.error || qsTr("The note could not be saved.")
                root.draftSaveFailed(message, request.client_token || "")
            }
            Qt.callLater(() => root._startNextDraftSave())
        }
    }

    Process {
        id: selectionSaveProc

        command: ["python3", root.backendPath, "create"]
        stdinEnabled: true
        onStarted: write(JSON.stringify(root._activeSelection) + "\n")
        stdout: SplitParser {
            onRead: data => root._selectionOutput += data
        }
        onExited: exitCode => {
            const request = root._activeSelection
            const result = root.parseResult(root._selectionOutput)
            root._selectionOutput = ""
            if (exitCode === 0 && result.success && result.note) {
                root.assistantSelectionSaved(result.note, request.client_token || "")
                root.refresh()
                root.queueOrganization(result.note.id)
                Toaster.toast(qsTr("Saved to Notes"), qsTr("Selection captured; organizing in the background."), "note_add")
            } else {
                const message = result.error || qsTr("The selection could not be saved.")
                root.assistantSelectionSaveFailed(message, request.client_token || "")
                Toaster.toast(qsTr("Notes"), message, "error")
            }
            Qt.callLater(() => root._startNextSelectionSave())
        }
    }

    Process {
        id: mutationProc

        stdinEnabled: true
        onStarted: write(JSON.stringify(root._mutationInput) + "\n")
        stdout: StdioCollector {
            onStreamFinished: {
                root.mutating = false
                const result = root.parseResult(text)
                if (!result.success) {
                    root.errorMessage = result.error || qsTr("The note change could not be saved.")
                    Toaster.toast(qsTr("Notes"), root.errorMessage, "error")
                    return
                }
                if (root._mutationAction === "delete") {
                    root.noteDeleted(result.id || root._mutationInput.id)
                    Toaster.toast(qsTr("Note moved to trash"), qsTr("The note can be restored from storage."), "delete")
                } else if (root._mutationAction === "delete-topic") {
                    root.topicDeleted(result.topic || root._mutationInput.topic, result.deleted_count || 0)
                } else if (root._mutationAction === "restore-topic") {
                    root.topicRestored(result.topic || root._mutationInput.topic, result.restored_count || 0)
                } else if (result.note) {
                    root.noteChanged(result.note)
                }
                root.refresh()
            }
        }
    }

    Process {
        id: organizeProc

        stdinEnabled: true
        onStarted: write(JSON.stringify({ id: root._activeOrganizeId }) + "\n")
        stdout: SplitParser {
            onRead: data => root._organizeOutput += data
        }
        onExited: exitCode => {
            const noteId = root._activeOrganizeId
            const rerun = root._rerunOrganizeId === noteId
            const cancelled = root._cancelledOrganizeIds.indexOf(noteId) >= 0
            const result = root.parseResult(root._organizeOutput)
            root._organizeOutput = ""
            root._activeOrganizeId = ""
            if (rerun) root._rerunOrganizeId = ""
            if (cancelled) {
                const pending = root._cancelledOrganizeIds.filter(id => id !== noteId)
                root._cancelledOrganizeIds = pending
            } else if (result.success) {
                root.organizationFinished(noteId, true, "")
                root.syncLegacyNotes(noteId)
            } else if (!result.stale) {
                const message = result.error || qsTr("Note analysis failed. Your raw note is safe.")
                root.organizationFinished(noteId, false, message)
                Toaster.toast(qsTr("Note analysis failed"), qsTr("Your raw note is safe."), "error")
            }
            root.refresh()
            if (rerun) root.queueOrganization(noteId)
            else root._startNextOrganization()
        }
    }

    Process {
        id: cancelTriageProc
        command: ["python3", root.backendPath, "cancel-triage"]
        stdinEnabled: true
        onStarted: write(JSON.stringify({ id: root._activeCancelTriageId }) + "\n")
        onExited: exitCode => {
            const result = root.parseResult(root._cancelOutput)
            root._cancelOutput = ""
            if (exitCode !== 0 || !result.success)
                Toaster.toast(qsTr("Could not cancel analysis"), result.error || qsTr("The note is still safe."), "warning")
            root.refresh()
            Qt.callLater(() => root._startNextTriageCancellation())
        }
        stdout: SplitParser { onRead: data => root._cancelOutput += data }
    }

    Process {
        id: generateTopicProc

        stdinEnabled: true
        onStarted: write(JSON.stringify(root._generateTopicInput) + "\n")
        stdout: StdioCollector {
            onStreamFinished: {
                const result = root.parseResult(text)
                if (result.success) {
                    root.refresh()
                    const action = result.action || "created"
                    const count = result.count || 0
                    const topic = result.topic || ""
                    const message = result.message || ""
                    root.topicGenerated(topic, count, action, message)
                    if (action === "already_covered") {
                        Toaster.toast(qsTr("Already covered"), message || qsTr("Topic \"%1\" is already covered.").arg(topic), "check_circle")
                    } else if (action === "merged") {
                        Toaster.toast(qsTr("Merged into topic"), message || qsTr("Merged %1 notes into \"%2\"").arg(count).arg(topic), "call_merge")
                    } else {
                        Toaster.toast(qsTr("Topic created"), message || qsTr("Created dedicated topic \"%1\" with %2 notes").arg(topic).arg(count), "auto_awesome")
                    }
                } else {
                    const msg = result.error || qsTr("Failed to generate notes for this topic.")
                    root.topicGenerateFailed(msg)
                    Toaster.toast(qsTr("Generation failed"), msg, "error")
                }
            }
        }
    }

    Process {
        id: providerProc

        stdinEnabled: true
        onStarted: write("{}\n")
        stdout: StdioCollector {
            onStreamFinished: {
                const result = root.parseResult(text)
                root.providerConfigured = result.success && result.configured === true
                root.configuredProvider = result.provider || ""
                root.fallbackProvider = result.fallback || ""
            }
        }
    }

    Process {
        id: conceptsListProc
        stdinEnabled: true
        property var sentInput: ({})
        onStarted: {
            sentInput = root._conceptsListInput
            write(JSON.stringify(sentInput) + "\n")
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const res = root.parseResult(text)
                if (res.success && Array.isArray(res.concepts)
                        && conceptsListProc.sentInput.topic === root._conceptsListInput.topic
                        && conceptsListProc.sentInput.area === root._conceptsListInput.area) {
                    root.concepts = res.concepts
                    root.conceptsLoaded(res.concepts)
                }
            }
        }
        onExited: {
            if (sentInput.topic !== root._conceptsListInput.topic || sentInput.area !== root._conceptsListInput.area)
                Qt.callLater(() => root.listConcepts(root._conceptsListInput.topic, root._conceptsListInput.area))
        }
    }

    Process {
        id: conceptGetProc
        stdinEnabled: true
        property var sentInput: ({})
        onStarted: {
            sentInput = root._conceptGetInput
            write(JSON.stringify(sentInput) + "\n")
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const res = root.parseResult(text)
                if (res.success && conceptGetProc.sentInput.id === root._conceptGetInput.id
                        && conceptGetProc.sentInput.mode === root._conceptGetInput.mode) {
                    root.currentConceptView = res
                    root.conceptViewLoaded(res)
                }
            }
        }
        onExited: {
            if (sentInput.id !== root._conceptGetInput.id || sentInput.mode !== root._conceptGetInput.mode)
                Qt.callLater(() => root.getConcept(root._conceptGetInput.id, root._conceptGetInput.mode))
        }
    }

    Process {
        id: depthProc
        command: ["python3", root.backendPath, "set-concept-depth"]
        stdinEnabled: true
        property var sentInput: ({})
        onStarted: {
            sentInput = root._depthInput
            write(JSON.stringify(sentInput) + "\n")
        }
        onExited: {
            if (sentInput.id !== root._depthInput.id || sentInput.depth !== root._depthInput.depth)
                Qt.callLater(() => root.setConceptDepth(root._depthInput.id, root._depthInput.depth))
        }
    }

    Process {
        id: expansionProc
        command: ["python3", root.backendPath, "set-concept-expansion"]
        stdinEnabled: true
        property var sentInput: ({})
        onStarted: {
            sentInput = root._expansionInput
            write(JSON.stringify(sentInput) + "\n")
        }
        onExited: {
            if (sentInput.id !== root._expansionInput.id || sentInput.expanded !== root._expansionInput.expanded)
                Qt.callLater(() => root.setConceptExpansion(root._expansionInput.id, root._expansionInput.expanded))
        }
    }

    Process {
        id: searchProc
        stdinEnabled: true
        property var sentInput: ({})
        onStarted: {
            sentInput = root._searchInput
            write(JSON.stringify(sentInput) + "\n")
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const res = root.parseResult(text)
                if (res.success && Array.isArray(res.results)
                        && searchProc.sentInput.query === root._searchInput.query
                        && searchProc.sentInput.offset === root._searchInput.offset) {
                    const prior = searchProc.sentInput.offset > 0 ? root.searchResults : []
                    const seen = new Set(prior.map(item => item.result_key))
                    root.searchResults = prior.concat(res.results.filter(item => !seen.has(item.result_key)))
                    root.searchTotal = Number(res.total || 0)
                    root.searchHasMore = res.next_offset !== null && res.next_offset !== undefined
                    root.searchNextOffset = root.searchHasMore ? Number(res.next_offset) : root.searchResults.length
                    root.searchCompleted(root.searchResults)
                }
            }
        }
        onExited: {
            if (sentInput.query !== root._searchInput.query || sentInput.offset !== root._searchInput.offset)
                Qt.callLater(() => root.searchConcepts(root._searchInput.query, root._searchInput.offset))
        }
    }

    Process {
        id: seenProc
        command: ["python3", root.backendPath, "mark-concept-seen"]
        stdinEnabled: true
        onStarted: write(JSON.stringify({ id: root._activeSeenId }) + "\n")
        onExited: {
            root._activeSeenId = ""
            Qt.callLater(() => root._startNextSeen())
        }
    }

    Process {
        id: exportProc
        command: ["python3", root.backendPath, "export-concept"]
        stdinEnabled: true
        property var sentInput: ({})
        onStarted: {
            sentInput = root._exportInput
            write(JSON.stringify(sentInput) + "\n")
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const res = root.parseResult(text)
                if (res.success && exportProc.sentInput.id === root._exportInput.id) {
                    Quickshell.clipboardText = res.markdown || ""
                    Toaster.toast(qsTr("Copied"), qsTr("Concept copied as Markdown"), "content_copy")
                }
            }
        }
        onExited: {
            if (sentInput.id !== root._exportInput.id)
                Qt.callLater(() => root.copyConcept(root._exportInput.id))
        }
    }

    Process {
        id: syncLegacyProc
        stdinEnabled: true
        onStarted: write(JSON.stringify(root._syncInput) + "\n")
        stdout: StdioCollector {
            onStreamFinished: {
                const res = root.parseResult(text)
                if (!res.success) return
                root.listConcepts("", "")
                const view = root.currentConceptView
                const targetId = String(root._syncInput.id || "")
                if (targetId && view?.concept?.legacy_note_id === targetId)
                    root.getConcept(view.concept.id, view.mode || "")
            }
        }
        onExited: {
            const pending = root._pendingSyncIds.slice()
            if (pending.length) {
                root._pendingSyncIds = pending.slice(1)
                Qt.callLater(() => root.syncLegacyNotes(pending[0]))
            }
        }
    }
}
