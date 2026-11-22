pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.services

TextEdit {
    id: root

    property bool markdown: false

    readOnly: true
    selectByMouse: true
    cursorVisible: false
    renderType: TextEdit.NativeRendering
    selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
    selectedTextColor: Colours.palette.m3onSurface
    textFormat: markdown ? TextEdit.MarkdownText : TextEdit.PlainText
    wrapMode: TextEdit.Wrap
    color: Colours.palette.m3onSurface
    font: Qt.font({ family: Tokens.font.body.medium.family, pixelSize: 15 })
}
