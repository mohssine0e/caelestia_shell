pragma ComponentBehavior: Bound
import QtQuick
import Caelestia
import Caelestia.Config

TextEdit {
    readOnly: true
    selectByMouse: true
    cursorVisible: false
    wrapMode: TextEdit.Wrap
    textFormat: TextEdit.PlainText
    font.family: Tokens.font.body.small.family
    font.pointSize: Tokens.font.body.small.pointSize
    color: Colours.palette.m3onSurface
    selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
    selectedTextColor: Colours.palette.m3onSurface
    renderType: TextEdit.NativeRendering
}

