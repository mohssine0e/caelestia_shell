pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Facts about the user. All reads and writes go through scripts/user_facts.py,
// the only writer of ~/.config/caelestia/user_facts.json. Commands run one at a
// time and carry the revision this view last saw, so a stale view cannot
// overwrite a newer change.
Singleton {
    id: root

    readonly property string scriptPath: Quickshell.env("HOME") + "/.config/quickshell/caelestia/scripts/user_facts.py"
    readonly property string factsPath: Quickshell.env("HOME") + "/.config/caelestia/user_facts.json"

    property var facts: []
    property var sources: []
    property var counts: ({ candidate: 0, approved: 0, rejected: 0, archived: 0 })
    property int staleCount: 0
    property int revision: 0
    property string storeState: "checking" // checking | missing | healthy | corrupt
    property bool includeSensitive: false
    property bool busy: false
    property string lastError: ""
    property var lastImport: null
    property var _queue: []
    property var _current: null

    readonly property int pendingCount: root.counts.candidate || 0

    function reload() {
        root.run("list", {}, false)
    }

    function addFact(text, category) {
        root.run("add", { fact: { text: text, category: category } }, true)
    }

    function editFact(id, changes) {
        root.run("edit", { id: id, changes: changes }, true)
    }

    function setStatus(id, status) {
        root.run("status", { id: id, status: status }, true)
    }

    function confirmFact(id) {
        root.run("confirm", { id: id }, true)
    }

    function deleteFact(id) {
        root.run("delete", { ids: [id] }, true)
    }

    function approveSource(sourceAi) {
        root.run("batch_status", { status: "approved", source_ai: sourceAi, only_status: "candidate" }, true)
    }

    function deleteSource(sourceAi) {
        root.run("delete", { source_ai: sourceAi }, true)
    }

    function setIncludeSensitive(enabled) {
        root.run("settings", { changes: { include_sensitive_in_replies: !!enabled } }, true)
    }

    function previewImport(path, sourceAi) {
        root.run("import", { path: path, source_ai: sourceAi, dry_run: true }, false)
    }

    function applyImport(path, sourceAi) {
        root.run("import", { path: path, source_ai: sourceAi, dry_run: false }, false)
    }

    function recover() {
        root.run("recover", {}, false)
    }

    function run(cmd, payload, withRevision) {
        const body = Object.assign({}, payload || {})
        root._queue = root._queue.concat([{ cmd: cmd, payload: body, withRevision: withRevision }])
        root._next()
    }

    function _next() {
        if (factsProc.running || root._queue.length === 0) return
        const job = root._queue[0]
        root._queue = root._queue.slice(1)
        if (job.withRevision) job.payload.revision = root.revision
        root._current = job
        root.busy = true
        factsProc.command = ["python3", root.scriptPath, job.cmd, "--stdin-json"]
        factsProc.running = true
    }

    function _applyList(res) {
        root.facts = res.facts || []
        root.sources = res.sources || []
        root.counts = res.counts || ({ candidate: 0, approved: 0, rejected: 0, archived: 0 })
        root.staleCount = res.stale_count || 0
        root.revision = res.revision || 0
        root.storeState = res.state || "healthy"
        root.includeSensitive = !!(res.settings && res.settings.include_sensitive_in_replies)
    }

    function _handle(text) {
        const job = root._current
        root._current = null
        let res = null
        try {
            res = JSON.parse(String(text || "").trim().split("\n").pop())
        } catch (e) {
            res = { success: false, message: qsTr("The facts helper returned no readable result.") }
        }
        if (!job) return
        if (job.cmd === "list") {
            if (res.state === "corrupt") {
                root._applyList(res)
                root.lastError = qsTr("user_facts.json could not be read. Nothing will be changed until you recover it.")
            } else if (res.facts !== undefined) {
                root._applyList(res)
                root.lastError = ""
            } else {
                root.lastError = res.message || qsTr("Could not load facts.")
            }
            return
        }
        if (job.cmd === "import") {
            root.lastImport = res
            if (!res.success) root.lastError = res.message || qsTr("Import failed.")
            else root.lastError = ""
            if (res.success && !res.dry_run) root.reload()
            return
        }
        if (!res.success) {
            root.lastError = res.message || qsTr("That change was not saved.")
        } else {
            root.lastError = ""
        }
        // Always re-read after a change (or a refused change) so the view matches the file.
        root.reload()
    }

    Component.onCompleted: root.reload()

    Process {
        id: factsProc

        stdinEnabled: true
        onStarted: {
            const job = root._current
            write(JSON.stringify(job ? job.payload : {}) + "\n")
        }
        stdout: StdioCollector {
            id: factsOutput

            onStreamFinished: root._handle(factsOutput.text)
        }
        onExited: {
            root.busy = root._queue.length > 0
            Qt.callLater(root._next)
        }
    }

    // Pick up changes made by the CLI or another window.
    FileView {
        path: root.factsPath
        watchChanges: true
        printErrors: false
        onFileChanged: if (!factsProc.running) root.reload()
    }
}
