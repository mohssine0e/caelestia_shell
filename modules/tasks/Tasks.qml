pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

FocusScope {
    id: root
    width: 1040
    height: 720

    signal closeRequested() // this is handled by the popout wrapper, not this component itself 
    Keys.onEscapePressed: {
        root.closeRequested();
        event.accepted = true;
    }
    // "/" set focus to the capture field, unless a text field is already active (so you can type "/" in a search box)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Slash && !inputActive) {
            tasksHeader.focusCapture()
            event.accepted = true;
        } else {
            event.accepted = false;
        }
    }
    MouseArea {
        anchors.fill: parent
        onPressed: {
            if (root.activePage === "tasks")
                taskList.forceActiveFocus();
            else
                dailyHabitsList.forceActiveFocus();
        }
    }

    property string activePage: "tasks" // "tasks" | "daily"

    property string statusFilter: "all" // "all" | "active" | "done"
    property string searchQuery: ""

    property var timeLeftToday: ({ hours: 0, mins: 0 })
    
    function updateTimeLeft() {
        const now = new Date();
        const end = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);
        const diffMs = end - now;
        const diffMins = Math.max(0, Math.floor(diffMs / 60000));
        const hours = Math.floor(diffMins / 60);
        const mins = diffMins % 60;
        timeLeftToday = { hours: hours, mins: mins };
    }
    
    Timer {
        id: timeTrackerTimer
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.updateTimeLeft()
    }

    // Icon the next new habit will get (daily page only)
    property string habitIcon: "task_alt"

    // True while any text field inside the popout has focus — the wrapper
    // uses this to suspend the mouse-idle auto-close while typing.
    readonly property Item focusItem: Window.activeFocusItem
    readonly property bool inputActive: focusItem?.cursorPosition !== undefined

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        // switcher and capture field
        TasksHeader{
            id: tasksHeader

            Layout.fillWidth: true
            activePage: root.activePage
            habitIcon: root.habitIcon

            onPageChanged: page => {
                root.activePage = page
            }
            onHabitIconSelected: icon => root.habitIcon = icon

            onCaptureAccepted: text => {
                if (root.activePage === "daily") dailyHabitsList.addTask(text, root.habitIcon)
                else taskList.addTask(text)
            }
        }

        // seperator line
        StyledRect {
            Layout.fillWidth: true; implicitHeight: 1
            color: Colours.palette.m3outlineVariant; opacity: 0.4
        }

        // ── Status filter (All/Active/Done) + search ──────────────
        RowLayout {
            visible: true
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            // Filter buttons (all, active, done)
            BtnSwitcher {
                id: statusFilterSwitcher
                Layout.fillHeight: true   
                model: [
                    { icon: "format_list_bulleted", text: qsTr("All"), value: "all" },
                    { icon: "pending", text: qsTr("Active"), value: "active" },
                    { icon: "task_alt", text: qsTr("Done"), value: "done" }
                ]
                currentValue: root.statusFilter
                onActivated: value => root.statusFilter = value
                showOnlyActiveText: false
                givenHeight: 40
            }

            // IconTextButton {
            //     implicitHeight: statusFilterSwitcher.givenHeight
            //     visible: true
            //     icon: "vertical_align_bottom"
            //     onClicked: (root.activePage === "daily" ? dailyHabitsList : taskList).moveDoneToBottom()
            //     isToggle: false
            //     checked:true
            //     type: ButtonBase.Tonal
            //     activeColour: Colours.palette.m3primary
            //     font: Tokens.font.label.medium
            //     radius: Tokens.rounding.small
            //     padding: Tokens.padding.small
            // }

            // spacer pushes evrything else to the right
            Item { Layout.fillWidth: true }

            // Search input
            StyledTextField {
                implicitHeight: statusFilterSwitcher.givenHeight
                verticalPadding: Tokens.padding.small

                Layout.preferredWidth: 250
                leadingIcon: "search"
                placeholderText: root.activePage === "daily" ? qsTr("Search habits") : qsTr("Search tasks")
                text: root.searchQuery
                onTextChanged: root.searchQuery = text
                Keys.onEscapePressed: { clear(); focus = false; }
            }
        }



        // seperator line
        StyledRect {
            Layout.fillWidth: true; implicitHeight: 1
            color: Colours.palette.m3outlineVariant; opacity: 0.4
            visible: root.activePage === "tasks"
        }

        TaskList {
            id: taskList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.activePage === "tasks"
            focus: root.activePage === "tasks"
            dataType: "tasks"
            statusFilter: root.statusFilter
            searchQuery: root.searchQuery
        }

        TaskList {
            id: dailyHabitsList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.activePage === "daily"
            focus: root.activePage === "daily"
            dataType: "habits"
            statusFilter: root.statusFilter
            searchQuery: root.searchQuery
        }
    }
}
