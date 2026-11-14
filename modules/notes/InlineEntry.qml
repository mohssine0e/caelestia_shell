pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

StyledText {
    id: root

    required property var entry
    property bool markdown: false
    property bool mono: false
    property bool bullet: false
    property string prefix: ""

    text: prefix + (bullet ? "•  " : "") + (entry?.text || "")
    textFormat: markdown ? Text.MarkdownText : Text.PlainText
    wrapMode: Text.WrapAnywhere
    color: mono ? Colours.palette.m3primary : Colours.palette.m3onSurface
    font: mono
        ? Qt.font({ family: Tokens.font.mono.small.family, pixelSize: 14 })
        : Qt.font({ family: Tokens.font.body.medium.family, pixelSize: 15 })
}
