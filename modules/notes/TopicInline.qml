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
    property string output: ""
    readonly property bool busy: worker.running
    readonly property string busyAction: busy ? pending.action || "" : ""
    readonly property var available: suggestions.filter(item => item.state === "suggested" && item.content)

    function request(action, fields = ({})): bool {
        if (busy || !topic) return false
        errorMessage = ""
        notice = ""
        pending = Object.assign({ topic: topic, action: action, subconcept: subconcept }, fields)
        output = ""
        worker.command = ["python3", Notes.backendPath, action]
        worker.running = true
        return true
    }
    function pendingFor(section): var {
        const target = String(section || "").toLowerCase().trim()
        return available.filter(item => String(item.section || "").toLowerCase().trim() === target)
    }
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

    onTopicChanged: {
        suggestions = []
        errorMessage = ""
        notice = ""
        if (topic && !busy) request("learning-list")
    }
    onSubconceptChanged: {
        suggestions = []
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
        stdout: SplitParser { onRead: data => root.output += data }
        onExited: exitCode => {
            const result = Notes.parseResult(root.output)
            const request = root.pending
            if (result.note) Notes.refresh()
            if (request.topic !== root.topic || request.subconcept !== root.subconcept) {
                if (root.topic) Qt.callLater(() => root.request("learning-list"))
                return
            }
            if (!result.success) {
                root.errorMessage = result.error || qsTr("Could not update this topic.")
                return
            }
            root.suggestions = result.suggestions || []
            if (request.action === "accept-topic-line" || request.action === "accept-all-topic-lines") {
                Notes.refresh()
                root.notice = qsTr("Added to topic.")
                noticeTimer.restart()
            } else if (request.action === "fill-topic" && root.available.length === 0) {
                root.notice = qsTr("No new gaps found.")
                noticeTimer.restart()
            }
        }
    }
}
