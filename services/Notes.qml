pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
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
    property var _activeDraftRequest: ({})
    property var _queuedDraftRequest: null
    property string _createOutput: ""
    property string _draftOutput: ""
    property string _listOutput: ""
    property string _mutationOutput: ""
    property string _organizeOutput: ""

    signal noteCreated(var note, bool formattingQueued)
    signal draftSaved(var note, string clientToken)
    signal draftSaveFailed(string message, string clientToken)
    signal saveFailed(string message)
    signal noteChanged(var note)
    signal noteDeleted(string noteId)
    signal organizationFinished(string noteId, bool success, string message)

    function parseResult(text): var {
        try {
            return JSON.parse(String(text || "").trim())
        } catch (e) {
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
        createProc.command = ["python3", root.backendPath, "create"]
        createProc.running = true
        return true
    }

    function refresh(): void {
        if (listProc.running) return
        root.loading = true
        root._listOutput = ""
        listProc.command = ["python3", root.backendPath, "list"]
        listProc.running = true
    }

    function saveDraft(noteId, rawContent, clientToken, analyzeAfterSave): bool {
        const content = String(rawContent || "").trim()
        if (!content) return false
        const id = String(noteId || "")
        const request = {
            action: id ? "update" : "create",
            payload: id ? { id: id, raw_content: content } : { raw_content: content },
            client_token: String(clientToken || ""),
            analyze: analyzeAfterSave === true
        }
        if (draftProc.running) {
            if (root._queuedDraftRequest && root._queuedDraftRequest.client_token === request.client_token)
                request.analyze = request.analyze || root._queuedDraftRequest.analyze
            root._queuedDraftRequest = request
        } else {
            root._startDraftSave(request)
        }
        return true
    }

    function _startDraftSave(request): void {
        root._activeDraftRequest = request
        root._draftOutput = ""
        draftProc.command = ["python3", root.backendPath, request.action]
        draftProc.running = true
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
        stdout: SplitParser {
            onRead: data => root._createOutput += data
        }
        onExited: exitCode => {
            root.saving = false
            const result = root.parseResult(root._createOutput)
            root._createOutput = ""
            if (!result.success || !result.note) {
                root.errorMessage = result.error || qsTr("The note could not be saved.")
                root.saveFailed(root.errorMessage)
                return
            }
            const shouldOrganize = root._createInput.organize === true
            root.noteCreated(result.note, shouldOrganize)
            root.refresh()
            if (shouldOrganize) {
                root.queueOrganization(result.note.id)
                Toaster.toast(qsTr("Note saved"), qsTr("Formatting in the background…"), "auto_awesome")
            } else {
                Toaster.toast(qsTr("Note saved"), qsTr("Added to your notes inbox"), "note_add")
            }
        }
    }

    Process {
        id: listProc

        stdinEnabled: true
        onStarted: write("{}\n")
        stdout: SplitParser {
            onRead: data => root._listOutput += data
        }
        onExited: exitCode => {
            root.loading = false
            const result = root.parseResult(root._listOutput)
            root._listOutput = ""
            if (result.success) {
                root.notes = result.notes || []
            } else {
                root.errorMessage = result.error || qsTr("Notes could not be loaded.")
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
            if (result.success && result.note) {
                root.draftSaved(result.note, request.client_token || "")
                if (request.analyze === true) root.queueOrganization(result.note.id)
                root.refresh()
            } else {
                const message = result.error || qsTr("The note could not be saved.")
                root.draftSaveFailed(message, request.client_token || "")
            }
            const queued = root._queuedDraftRequest
            root._queuedDraftRequest = null
            if (queued) {
                if (result.success && result.note && request.action === "create"
                        && queued.action === "create" && queued.client_token === request.client_token) {
                    queued.action = "update"
                    queued.payload.id = result.note.id
                }
                root._startDraftSave(queued)
            }
        }
    }

    Process {
        id: mutationProc

        stdinEnabled: true
        onStarted: write(JSON.stringify(root._mutationInput) + "\n")
        stdout: SplitParser {
            onRead: data => root._mutationOutput += data
        }
        onExited: exitCode => {
            root.mutating = false
            const result = root.parseResult(root._mutationOutput)
            root._mutationOutput = ""
            if (!result.success) {
                root.errorMessage = result.error || qsTr("The note change could not be saved.")
                Toaster.toast(qsTr("Notes"), root.errorMessage, "error")
                return
            }
            if (root._mutationAction === "delete") {
                root.noteDeleted(result.id || root._mutationInput.id)
                Toaster.toast(qsTr("Note moved to trash"), qsTr("The note can be restored from storage."), "delete")
            } else if (result.note) {
                root.noteChanged(result.note)
            }
            root.refresh()
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
            const result = root.parseResult(root._organizeOutput)
            root._organizeOutput = ""
            root._activeOrganizeId = ""
            if (rerun) root._rerunOrganizeId = ""
            if (result.success) {
                root.organizationFinished(noteId, true, "")
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
}
