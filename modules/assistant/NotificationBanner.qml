pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls

StyledRect {
    id: root

    property string text: ""
    property string icon: "info"
    property color tone: Colours.palette.m3primary
    property color textColor: Colours.palette.m3onSurface
    property bool showClose: false
    signal closed()

    Layout.fillWidth: true
    implicitHeight: 28
    radius: Tokens.rounding.small
    color: Qt.alpha(tone, 0.15)
    border.width: 1
    border.color: Qt.alpha(tone, 0.3)

    RowLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 6

        MaterialIcon {
            text: root.icon
            fontStyle: Tokens.font.icon.small
            color: root.tone
        }

        StyledText {
            Layout.fillWidth: true
            text: root.text
            font: Tokens.font.label.small
            color: root.textColor
            elide: Text.ElideRight
        }

        IconButton {
            visible: root.showClose
            icon: "close"
            font: Tokens.font.icon.small
            implicitWidth: 20
            implicitHeight: 20
            type: IconButton.Text
            onClicked: root.closed()
        }
    }
}
