pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.services

Item {
    id: root

    property string topic: ""
    property string subconcept: ""
    property string question: ""
    property string answer: ""
    property string errorMessage: ""
    property string requestId: ""
    property var suggestions: []
    property var lastAcceptedIds: []
    property var pending: ({})
    readonly property bool busy: worker.running
    readonly property var available: suggestions.filter(item => item.state === "suggested")

    function request(action, fields = ({})): bool {
        if (busy || !topic) return false
        errorMessage = ""
        pending = Object.assign({ topic: topic, subconcept: subconcept, source: "ask",
            request_id: requestId, action: action }, fields)
        worker.command = ["python3", Notes.backendPath, action]
        worker.running = true
        return true
    }
    function ask(text): bool {
        const value = String(text || "").trim()
        if (!value) return false
        question = value
        return request("ask-topic", { question: value })
    }
    function accept(id): void { request("accept-topic-line", { id: id }) }
    function discard(id): void { request("dismiss-gap", { id: id }) }
    function acceptAll(): void { request("accept-all-topic-lines") }
    function undo(): void { request("undo-topic-lines", { ids: lastAcceptedIds }) }

    function finishRequest(output): void {
        const result = Notes.parseResult(output)
        const completed = root.pending
        if (completed.topic !== root.topic || completed.subconcept !== root.subconcept) return
        if (!result.success) {
            root.errorMessage = result.error || qsTr("Could not answer this question.")
            return
        }
        if (completed.action === "ask-topic") {
            root.answer = result.answer || ""
            root.requestId = result.request_id || ""
            root.suggestions = result.suggestions || []
            root.lastAcceptedIds = []
        } else {
            root.suggestions = result.suggestions || []
            if (completed.action === "accept-topic-line" || completed.action === "accept-all-topic-lines") {
                root.lastAcceptedIds = result.changed_ids || []
                Notes.refresh()
            } else if (completed.action === "undo-topic-lines") {
                root.lastAcceptedIds = []
                Notes.refresh()
            }
        }
    }
    onTopicChanged: {
        question = ""
        answer = ""
        suggestions = []
        requestId = ""
        lastAcceptedIds = []
        errorMessage = ""
    }
    onSubconceptChanged: {
        question = ""
        answer = ""
        suggestions = []
        requestId = ""
        lastAcceptedIds = []
        errorMessage = ""
    }

    Process {
        id: worker
        stdinEnabled: true
        onStarted: write(JSON.stringify(root.pending) + "\n")
        stdout: StdioCollector { id: responseCollector }
        onExited: root.finishRequest(responseCollector.text)
    }
}
