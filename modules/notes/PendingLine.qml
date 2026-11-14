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

    implicitHeight: contents.implicitHeight + 12
    radius: 6
    color: Qt.alpha(Colours.palette.m3secondaryContainer, 0.32)

    RowLayout {
        id: contents

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 10
        anchors.rightMargin: 8
        spacing: 8

        StyledText {
            Layout.fillWidth: true
            text: (root.suggestion.kind === "command" || root.suggestion.command
                    ? "$ " + root.suggestion.command + "  •  "
                    : (root.suggestion.kind === "code" || root.suggestion.code
                        ? (root.suggestion.language ? "[" + root.suggestion.language + "] " : "") + (root.suggestion.code || "") + "  •  "
                        : "•  "))
                + root.suggestion.content
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurface
            wrapMode: Text.WrapAnywhere
        }
        TextButton {
            text: qsTr("Accept")
            type: TextButton.Text
            enabled: !root.controller.busy
            onClicked: root.controller.accept(root.suggestion.id)
        }
        TextButton {
            text: qsTr("Delete")
            type: TextButton.Text
            enabled: !root.controller.busy
            onClicked: root.controller.discard(root.suggestion.id)
        }
    }
}
