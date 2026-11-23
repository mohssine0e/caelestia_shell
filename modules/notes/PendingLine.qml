pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Rectangle {
    id: root
    required property var suggestion
    required property var controller
    readonly property var diagramData: {
        if (suggestion.kind !== "diagram") return ({})
        try { return JSON.parse(suggestion.diagram_json || "{}") }
        catch (error) { return ({}) }
    }

    implicitHeight: contents.implicitHeight + 16
    radius: 6
    color: Qt.alpha(Colours.palette.m3secondaryContainer, 0.32)

    ColumnLayout {
        id: contents
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        spacing: 6

        StyledText {
            Layout.fillWidth: true
            visible: !!root.suggestion.subconcept && (root.controller.subconcept === "" || root.controller.subconcept.toLowerCase() !== root.suggestion.subconcept.toLowerCase())
            text: root.suggestion.subconcept + " · " + (root.suggestion.section || qsTr("Notes"))
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.suggestion.action === "replace" || root.suggestion.action === "remove"
            text: root.suggestion.action === "remove" ? qsTr("Remove from notes")
                : qsTr("Replace: %1").arg(root.suggestion.previous_content || "")
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.Wrap
        }
        SelectableText {
            Layout.fillWidth: true
            visible: root.suggestion.kind !== "diagram"
            text: root.suggestion.kind === "command" ? "$ " + root.suggestion.command
                : (root.suggestion.kind === "code" ? root.suggestion.code : root.suggestion.content)
            font: root.suggestion.kind === "bullet" ? Tokens.font.body.small : Tokens.font.mono.small
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.suggestion.kind !== "bullet" && root.suggestion.kind !== "diagram"
                && root.suggestion.action !== "remove"
            text: root.suggestion.content || ""
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.Wrap
        }
        DiagramCard {
            Layout.fillWidth: true
            visible: root.suggestion.kind === "diagram"
            diagram: root.diagramData
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            StyledText {
                Layout.fillWidth: true
                text: root.suggestion.reason || ""
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.Wrap
            }
            TextButton {
                visible: !!root.suggestion.reference_url
                text: qsTr("Docs")
                type: TextButton.Text
                onClicked: Qt.openUrlExternally(root.suggestion.reference_url)
            }
            TextButton {
                text: root.suggestion.action === "remove" ? qsTr("Remove") : qsTr("Accept")
                type: TextButton.Text
                enabled: !root.controller.busy
                onClicked: root.controller.accept(root.suggestion.id)
            }
            TextButton {
                text: qsTr("Dismiss")
                type: TextButton.Text
                enabled: !root.controller.busy
                onClicked: root.controller.discard(root.suggestion.id)
            }
        }
    }
}
