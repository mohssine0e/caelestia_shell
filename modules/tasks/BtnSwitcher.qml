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

    signal activated(string value)

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 0
        clip: true
        
        // Background and border for the switcher
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: Tokens.rounding.small
            border.width: 1
            border.color: root.Colours.palette.m3secondary
        }

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

                font: Tokens.font.label.medium
                icon: {
                    if (root.showOnlyActiveText) {
                        return modelData.icon
                    } else {
                        return root.currentValue === modelData.value ? modelData.icon : ""
                    }
                }
                text: {
                    if (!root.showOnlyActiveText) {
                        return modelData.text
                    } else {
                        return root.currentValue === modelData.value ? modelData.text : ""
                    }
                }
                radius: Tokens.rounding.small
                padding: Tokens.padding.small
                onClicked: {
                    if (root.currentValue !== modelData.value) {
                        root.currentValue = modelData.value
                        root.activated(modelData.value)
                        if (modelData.action) modelData.action()
                    }
                }
            }
        }
    }
}