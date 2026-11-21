pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Column {
    id: root
    required property string scope
    property string topic: ""
    property string area: ""
    property string conceptId: ""
    property var suggestions: []
    property var accepted: []
    property string message: ""
    property string errorMessage: ""
    property bool opened: false
    property var request: ({})
    property string output: ""

    readonly property string scopeKey: scope + "|" + topic + "|" + area + "|" + conceptId
    width: parent?.width ?? 0
    spacing: 8

    Component.onCompleted: loadPending()
    onScopeKeyChanged: {
        opened = false
        suggestions = []
        accepted = []
        message = ""
        errorMessage = ""
        Qt.callLater(() => loadPending())
    }

    function loadPending(): void {
        if (worker.running || (root.scope !== "concept" && (!root.topic || root.topic === "All"))) return
        run("list-gap-proposals", { scope: root.scope, topic: root.topic,
            area: root.area, id: root.conceptId }, false)
    }
    function run(action, payload, showPanel): void {
        if (worker.running) return
        if (showPanel !== false) opened = true
        errorMessage = ""
        request = { key: scopeKey, action: action, payload: payload }
        output = ""
        worker.command = ["python3", Notes.backendPath, action]
        worker.running = true
    }
    function proposalPayload(proposalId): var {
        return { proposal_id: proposalId, scope: root.scope, topic: root.topic,
            area: root.area, id: root.conceptId }
    }
    function refreshAfterMutation(): void {
        Notes.listConcepts("", "")
        if (scope === "concept" && conceptId) Notes.getConcept(conceptId, "")
        Qt.callLater(() => loadPending())
    }

    TextButton {
        text: worker.running && root.request.key === root.scopeKey ? qsTr("Working…") : qsTr("Fill gaps")
        type: root.opened ? ButtonBase.Tonal : ButtonBase.Text
        horizontalPadding: 9
        verticalPadding: 5
        enabled: !worker.running && (root.scope === "concept"
            ? !!root.conceptId : !!root.topic && root.topic !== "All")
        onClicked: {
            if (root.opened) {
                root.opened = false
                return
            }
            root.opened = true
            root.errorMessage = ""
            root.message = ""
            if (!Notes.providerConfigured) {
                root.errorMessage = qsTr("Configure an AI provider to look for gaps.")
                return
            }
            root.run("suggest-gaps", { scope: root.scope, topic: root.topic,
                area: root.area, id: root.conceptId }, true)
        }
    }

    Column {
        width: parent.width
        visible: root.opened
        spacing: 8
        StyledText {
            width: parent.width
            visible: worker.running && root.request.key === root.scopeKey || !!root.message
                || !!root.errorMessage || (root.suggestions.length + root.accepted.length === 0)
            text: worker.running && root.request.key === root.scopeKey
                ? qsTr("Reviewing this %1…").arg(root.scope)
                : root.errorMessage || root.message || qsTr("No clear gaps suggested for this %1.").arg(root.scope)
            color: root.errorMessage ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }
        Repeater {
            model: root.suggestions.concat(root.accepted)
            delegate: Rectangle {
                id: suggestionCard
                required property var modelData
                width: parent.width
                implicitHeight: suggestionContent.implicitHeight + 20
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerLow
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.55)
                Column {
                    id: suggestionContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 10
                    spacing: 4
                    StyledText {
                        width: parent.width
                        text: suggestionCard.modelData.title
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.title.small
                        wrapMode: Text.WordWrap
                    }
                    StyledText {
                        width: parent.width
                        text: suggestionCard.modelData.content
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.body.small
                        wrapMode: Text.WordWrap
                    }
                    StyledText {
                        width: parent.width
                        text: qsTr("%1 · %2").arg(suggestionCard.modelData.evidence || suggestionCard.modelData.area)
                            .arg(suggestionCard.modelData.reason || "")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                        wrapMode: Text.WordWrap
                    }
                    Row {
                        spacing: 6
                        TextButton {
                            visible: suggestionCard.modelData.state !== "accepted"
                            text: qsTr("Add")
                            type: ButtonBase.Tonal
                            horizontalPadding: 8
                            verticalPadding: 4
                            onClicked: root.run("accept-gap-proposal",
                                root.proposalPayload(suggestionCard.modelData.proposal_id), true)
                        }
                        TextButton {
                            visible: suggestionCard.modelData.state !== "accepted"
                            text: qsTr("Dismiss")
                            type: ButtonBase.Text
                            horizontalPadding: 8
                            verticalPadding: 4
                            onClicked: root.run("dismiss-gap-proposal",
                                root.proposalPayload(suggestionCard.modelData.proposal_id), true)
                        }
                        TextButton {
                            visible: suggestionCard.modelData.state === "accepted"
                            text: qsTr("Undo")
                            type: ButtonBase.Text
                            horizontalPadding: 8
                            verticalPadding: 4
                            onClicked: root.run("undo-gap-proposal",
                                root.proposalPayload(suggestionCard.modelData.proposal_id), true)
                        }
                    }
                }
            }
        }
        TextButton {
            visible: root.suggestions.length > 0
            text: qsTr("Accept all (%1)").arg(root.suggestions.length)
            type: ButtonBase.Tonal
            horizontalPadding: 9
            verticalPadding: 5
            onClicked: root.run("accept-all-gap-proposals", Object.assign(
                root.proposalPayload(""), {
                    proposal_ids: root.suggestions.map(item => item.proposal_id)
                }), true)
        }
    }

    Process {
        id: worker
        stdinEnabled: true
        onStarted: write(JSON.stringify(root.request.payload) + "\n")
        stdout: SplitParser { onRead: data => root.output += data }
        onExited: {
            if (root.request.key !== root.scopeKey) {
                Qt.callLater(() => root.loadPending())
                return
            }
            const action = root.request.action
            const result = Notes.parseResult(root.output)
            if (!result.success) {
                root.errorMessage = result.error || qsTr("Gap review failed. Try again.")
                return
            }
            if (action === "suggest-gaps") {
                root.suggestions = result.suggestions || []
                root.message = result.message || ""
                if (!root.suggestions.length && !root.message)
                    root.message = qsTr("No clear gaps suggested for this %1.").arg(root.scope)
            } else if (action === "list-gap-proposals") {
                const proposals = result.proposals || []
                root.suggestions = proposals.filter(item => item.state === "suggested")
                root.accepted = proposals.filter(item => item.state === "accepted")
            } else {
                root.refreshAfterMutation()
            }
        }
    }
}
