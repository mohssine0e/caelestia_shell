pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import qs.components

StyledRect {
    id: root

    property string text: ""
    property string icon: ""
    property color tone: Colours.palette.m3primary
    property color onTone: tone
    property int heightPx: 20
    property int spacingPx: 4

    implicitHeight: heightPx
    implicitWidth: badgeRow.implicitWidth + 10
    radius: Tokens.rounding.full
    color: Qt.alpha(tone, 0.15)
    border.width: 1
    border.color: Qt.alpha(tone, 0.4)

    RowLayout {
        id: badgeRow
        anchors.centerIn: parent
        spacing: root.spacingPx

        MaterialIcon {
            visible: root.icon.length > 0
            text: root.icon
            fontStyle: Tokens.font.icon.small
            color: root.tone
        }

        StyledText {
            visible: root.text.length > 0
            text: root.text
            font: Tokens.font.label.small
            color: root.onTone
        }
    }
}
