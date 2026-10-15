import QtQuick
import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    property var model: []
    property string currentValue: ""

    property bool showOnlyActiveText: false
    property int givenHeight: 45
    property bool allowReclick: false
    property color borderColor: Colours.palette.m3secondary
    property color backgroundColor: "transparent"
    property real radius: Tokens.rounding.small
    property font font: Tokens.font.label.medium

    signal activated(string value)

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    // Background and border for the switcher
    Rectangle {
        anchors.fill: row
        color: root.backgroundColor
        radius: root.radius
        border.width: 1
        border.color: root.borderColor
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 0
        clip: true

        Repeater {
            model: root.model

            IconTextButton {
                required property var modelData
                implicitHeight: root.givenHeight
                isToggle: false
                checked: root.currentValue === modelData.value
                type: ButtonBase.Tonal

                activeColour: Colours.palette.m3primary
                inactiveColour: "transparent"
                inactiveOnColour: Colours.palette.m3onSurfaceVariant

                font: root.font
                icon: {
                    if (root.showOnlyActiveText) {
                        return modelData.icon || ""
                    } else {
                        return root.currentValue === modelData.value ? (modelData.icon || "") : ""
                    }
                }
                text: {
                    if (!root.showOnlyActiveText) {
                        return modelData.text || ""
                    } else {
                        return root.currentValue === modelData.value ? (modelData.text || "") : ""
                    }
                }
                radius: root.radius
                padding: Tokens.padding.small
                horizontalPadding: root.showOnlyActiveText && root.currentValue !== modelData.value
                    ? Tokens.padding.small
                    : Tokens.padding.medium

                onClicked: {
                    if (root.allowReclick || root.currentValue !== modelData.value) {
                        root.activated(modelData.value)
                        if (modelData.action) modelData.action()
                    }
                }
            }
        }
    }
}

