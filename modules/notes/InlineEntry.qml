pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.services

Item {
    id: root

    required property var entry
    property bool markdown: false
    property bool mono: false
    property bool bullet: false
    property string prefix: ""
    readonly property bool isRecent: !!entry?.isRecent

    implicitWidth: parent?.width ?? 0
    implicitHeight: Math.max(bulletContainer.height, textEdit.implicitHeight)

    Item {
        id: bulletContainer
        visible: root.bullet
        width: 14
        height: 18
        anchors.left: parent.left
        anchors.top: textEdit.top

        Rectangle {
            visible: root.isRecent
            anchors.centerIn: parent
            width: 12
            height: 12
            radius: 6
            color: Qt.alpha(Colours.palette.m3primary, 0.22)
        }

        Rectangle {
            anchors.centerIn: parent
            width: root.isRecent ? 6.5 : 4
            height: root.isRecent ? 6.5 : 4
            radius: root.isRecent ? 3.25 : 2
            color: root.isRecent ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.55)
        }
    }

    SelectableText {
        id: textEdit
        anchors.left: root.bullet ? bulletContainer.right : parent.left
        anchors.leftMargin: root.bullet ? 4 : 0
        anchors.right: parent.right
        markdown: root.markdown
        text: root.prefix + (root.entry?.text || "")
        color: root.mono ? Colours.palette.m3primary : Colours.palette.m3onSurface
        font: root.mono
            ? Qt.font({ family: Tokens.font.mono.small.family, pixelSize: 14 })
            : Qt.font({ family: Tokens.font.body.medium.family, pixelSize: 15 })
    }
}
