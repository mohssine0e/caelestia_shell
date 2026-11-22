pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.services

Item {
    id: root

    property string topic: ""
    property string subconcept: ""
    property var suggestions: []
    property string errorMessage: ""
    property string notice: ""
    property var pending: ({})
    property var lastAcceptedIds: []
    readonly property bool busy: worker.running
    readonly property string busyAction: busy ? pending.action || "" : ""
    readonly property var available: suggestions.filter(item => item.state === "suggested" && item.content)

    function request(action, fields = ({})): bool {
        if (busy || !topic) return false
        errorMessage = ""
        notice = ""
        pending = Object.assign({ topic: topic, action: action, subconcept: subconcept }, fields)
        worker.command = ["python3", Notes.backendPath, action]
        worker.running = true
        return true
    }
    function pendingFor(section): var {
        const target = String(section || "").toLowerCase().trim()
        return available.filter(item => String(item.section || "").toLowerCase().trim() === target)
    }
    function pendingByKind(kind): var {
        return available.filter(item => {
            const target = item.action === "replace" ? Notes.notes.find(n => n.id === item.target_note_id) : null
            const targetKind = target?.technical_type === "command" ? "command"
                : ((target?.exact_excerpts || []).length ? "code" : "bullet")
            return (target ? targetKind : (item.kind || "bullet")) === kind
        })
    }
    function reload(): void { request("learning-list") }
    function undo(): void { request("undo-topic-lines", { ids: lastAcceptedIds }) }
    readonly property var pendingSections: {
        const list = []
        const seen = new Set()
        for (const item of available) {
            const sec = String(item.section || "").trim()
            if (sec && !seen.has(sec.toLowerCase())) {
                seen.add(sec.toLowerCase())
                list.push(sec)
            }
        }
        return list
    }
    function generate(): void { request("fill-topic") }
    function accept(id): void { request("accept-topic-line", { id: id }) }
    function discard(id): void { request("dismiss-gap", { id: id }) }
    function acceptAll(): void { request("accept-all-topic-lines") }

    function finishRequest(output): void {
        const result = Notes.parseResult(output)
        const completedRequest = root.pending
        if (result.note) Notes.refresh()
        if (completedRequest.topic !== root.topic || completedRequest.subconcept !== root.subconcept) {
            if (root.topic) Qt.callLater(() => root.request("learning-list"))
            return
        }
        if (!result.success) {
            root.errorMessage = result.error || qsTr("Could not update this topic.")
            return
        }
        root.suggestions = result.suggestions || []
        if (completedRequest.action === "accept-topic-line" || completedRequest.action === "accept-all-topic-lines") {
            Notes.refresh()
            root.lastAcceptedIds = result.changed_ids || []
            root.notice = qsTr("Saved.")
            noticeTimer.restart()
        } else if (completedRequest.action === "undo-topic-lines") {
            Notes.refresh()
            root.lastAcceptedIds = []
            root.notice = qsTr("Changes undone.")
            noticeTimer.restart()
        } else if (completedRequest.action === "fill-topic" && root.available.length === 0) {
            root.notice = qsTr("No useful additions found for this subsection.")
            noticeTimer.restart()
        }
    }

    onTopicChanged: {
        suggestions = []
        lastAcceptedIds = []
        errorMessage = ""
        notice = ""
        if (topic && !busy) request("learning-list")
    }
    onSubconceptChanged: {
        suggestions = []
        lastAcceptedIds = []
        errorMessage = ""
        notice = ""
        if (topic && !busy) request("learning-list")
    }

    Timer {
        id: noticeTimer
        interval: 3500
        running: false
        onTriggered: root.notice = ""
    }

    Process {
        id: worker

        stdinEnabled: true
        onStarted: write(JSON.stringify(root.pending) + "\n")
        stdout: StdioCollector { id: responseCollector }
        onExited: root.finishRequest(responseCollector.text)
    }
}
