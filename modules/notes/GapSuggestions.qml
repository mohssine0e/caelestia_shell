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
    property string message: ""
    property string errorMessage: ""
    property bool opened: false
    property var request: ({})
    property string output: ""

    readonly property string scopeKey: scope + "|" + topic + "|" + area + "|" + conceptId
    width: parent?.width ?? 0
    spacing: 8

    onScopeKeyChanged: {
        root.opened = false
        root.suggestions = []
        root.message = ""
        root.errorMessage = ""
    }

    TextButton {
        text: worker.running && root.request.key === root.scopeKey ? qsTr("Looking for gaps…") : qsTr("Fill gaps")
        type: root.opened ? ButtonBase.Tonal : ButtonBase.Text
        horizontalPadding: 9
        verticalPadding: 5
        enabled: Notes.providerConfigured && !worker.running &&
            (root.scope === "concept" ? !!root.conceptId : !!root.topic && root.topic !== "All")
        onClicked: {
            if (root.opened) {
                root.opened = false
                return
            }
            root.opened = true
            root.suggestions = []
            root.errorMessage = ""
            root.message = ""
            root.request = {
                key: root.scopeKey,
                payload: { scope: root.scope, topic: root.topic, area: root.area, id: root.conceptId }
            }
            root.output = ""
            worker.running = true
        }
    }

    Column {
        width: parent.width
        visible: root.opened
        spacing: 8

        StyledText {
            width: parent.width
            visible: worker.running && root.request.key === root.scopeKey ||
                !!root.message || !!root.errorMessage || root.suggestions.length === 0
            text: worker.running && root.request.key === root.scopeKey
                ? qsTr("Checking this %1…").arg(root.scope)
                : root.errorMessage || root.message || qsTr("No clear gaps suggested for this %1.").arg(root.scope)
            color: root.errorMessage ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: root.suggestions
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
                        text: qsTr("%1 · %2").arg(suggestionCard.modelData.area)
                            .arg(suggestionCard.modelData.reason)
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }

    Process {
        id: worker
        stdinEnabled: true
        command: ["python3", Notes.backendPath, "suggest-gaps"]
        onStarted: write(JSON.stringify(root.request.payload) + "\n")
        stdout: SplitParser { onRead: data => root.output += data }
        onExited: {
            if (root.request.key !== root.scopeKey) return
            const result = Notes.parseResult(root.output)
            if (!result.success) {
                root.errorMessage = result.error || qsTr("Gap review failed. Try again.")
                return
            }
            root.suggestions = result.suggestions || []
            root.message = result.message || ""
        }
    }
}
