pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls

Item {
    id: root

    required property string activePage
    required property string habitIcon

    signal pageChanged(string page)
    signal captureAccepted(string text)

    implicitHeight: headerRow.implicitHeight

    function focusCapture() {
        captureField.forceActiveFocus()
    }

    RowLayout {
        id: headerRow
        anchors.fill: parent
        spacing: Tokens.spacing.small

        StyledTextField {
            id: captureField
            Layout.preferredWidth: 500
            implicitHeight: pageSwitch.implicitHeight+4
            leadingIcon: root.activePage === "daily" ? "wb_sunny" : "checklist"
            placeholderText: root.activePage === "daily"
                ? qsTr("Add a habit")
                : qsTr("Capture a Task")
            onAccepted: {
                root.captureAccepted(text)
                clear()
            }
            Keys.onEscapePressed: {
                clear()
                focus = false
            }

        }


        // spacer to push the page switcher to the right
        Item {
            Layout.fillWidth: true
        }

        BtnSwitcher {
            id: pageSwitch
            Layout.fillHeight: true
            model: [
                { icon: "checklist", text: "Tasks", value: "tasks" ,action: () => { root.pageChanged("tasks") } },
                { icon: "wb_sunny", text: "Daily", value: "daily" ,action: () => { root.pageChanged("daily") } }
            ]
            currentValue: root.activePage
            onActivated: root.pageChanged(value)
            showOnlyActiveText: true
        }
    }
}