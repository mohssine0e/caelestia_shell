pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Column {
    id: root
    required property string conceptId
    property string question: ""
    property string state: ""
    property string content: ""
    property string proposalId: ""
    property string errorMessage: ""
    property var request: ({})
    property string output: ""
    signal explanationAccepted()

    width: parent?.width ?? 0
    spacing: 8

    function ask(kind): void {
        if (!root.conceptId || worker.running) return
        if (root.question === kind && root.content) {
            root.question = ""
            return
        }
        root.question = kind
        root.state = ""
        root.content = ""
        root.proposalId = ""
        root.errorMessage = ""
        root.run("concept-detail", { id: root.conceptId, kind: kind })
    }
    function run(action, payload): void {
        if (worker.running) return
        root.request = { action: action, payload: payload, conceptId: root.conceptId }
        root.output = ""
        worker.command = ["python3", Notes.backendPath, action]
        worker.running = true
    }
    onConceptIdChanged: {
        root.question = ""
        root.state = ""
        root.content = ""
        root.proposalId = ""
        root.errorMessage = ""
    }

    Row {
        width: parent.width
        spacing: 4
        Repeater {
            model: [
                { key: "why", label: qsTr("Why?") },
                { key: "name", label: qsTr("Why this name?") },
                { key: "counterexample", label: qsTr("Counterexample") },
                { key: "compare", label: qsTr("Compare") }
            ]
            delegate: TextButton {
                required property var modelData
                text: modelData.label
                type: root.question === modelData.key ? ButtonBase.Tonal : ButtonBase.Text
                horizontalPadding: 7
                verticalPadding: 4
                enabled: !worker.running
                onClicked: root.ask(modelData.key)
            }
        }
    }

    Rectangle {
        visible: !!root.question
        width: parent.width
        implicitHeight: detailColumn.implicitHeight + 18
        radius: Tokens.rounding.small
        color: Colours.palette.m3surfaceContainerLow
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.55)

        Column {
            id: detailColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 9
            spacing: 7
            StyledText {
                width: parent.width
                text: worker.running ? qsTr("Thinking about this concept…")
                    : root.errorMessage || (root.state === "unknown"
                        ? qsTr("I don't have enough reliable information to answer this yet.") : root.content)
                color: root.errorMessage ? Colours.palette.m3error : Colours.palette.m3onSurface
                font: Tokens.font.body.small
                wrapMode: Text.WordWrap
            }
            Row {
                visible: root.state === "suggested" && !worker.running
                spacing: 8
                TextButton {
                    text: qsTr("Add to notes")
                    type: ButtonBase.Tonal
                    horizontalPadding: 8
                    verticalPadding: 4
                    onClicked: root.run("accept-concept-detail", { proposal_id: root.proposalId })
                }
                TextButton {
                    text: qsTr("Dismiss")
                    type: ButtonBase.Text
                    horizontalPadding: 8
                    verticalPadding: 4
                    onClicked: root.run("dismiss-concept-detail", { proposal_id: root.proposalId })
                }
            }
        }
    }

    Process {
        id: worker
        stdinEnabled: true
        onStarted: write(JSON.stringify(root.request.payload) + "\n")
        stdout: SplitParser { onRead: data => root.output += data }
        onExited: {
            const req = root.request
            if (req.conceptId !== root.conceptId) return
            const result = Notes.parseResult(root.output)
            if (!result.success) {
                root.errorMessage = result.error || qsTr("Could not load this explanation.")
                return
            }
            if (req.action === "dismiss-concept-detail") {
                root.question = ""
                root.content = ""
                root.state = ""
                return
            }
            if (req.action === "accept-concept-detail") {
                root.state = "saved"
                root.explanationAccepted()
                return
            }
            root.state = result.state || ""
            root.content = result.content || ""
            root.proposalId = result.proposal_id || ""
            if (root.state === "stale")
                root.errorMessage = qsTr("The concept changed while this was being prepared. Try again.")
        }
    }
}
