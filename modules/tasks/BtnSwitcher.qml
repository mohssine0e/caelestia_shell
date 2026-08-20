import QtQuick
import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls

Item {
    id: root

    property var model: []
    property string currentValue: ""
    property color borderColor: "#6750A4"
    property color activeColor: "#6750A4"
    property color activeTextColor: "#FFFFFF"
    property color inactiveTextColor: "#616161"
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
            border.color: root.borderColor
        }

        Repeater {
            model: root.model

            IconTextButton {
                required property var modelData
                implicitHeight: root.givenHeight
                isToggle: false
                checked: root.currentValue === modelData.value
                type: ButtonBase.Tonal
                activeColour: root.activeColor
                activeOnColour: root.activeTextColor
                inactiveColour: "transparent"
                inactiveOnColour: root.inactiveTextColor
                font: Tokens.font.label.medium
                icon: modelData.icon
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