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
                dailyHabits.forceActiveFocus();
        }
    }

    property string activePage: "tasks" // "tasks" | "daily"

    property string statusFilter: "active"
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
        anchors.margins: Tokens.padding.large
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

            onCaptureAccepted: text => {
                if (root.activePage === "daily") {
                    dailyHabits.addHabit(text, root.habitIcon)
                    root.habitIcon = "task_alt"
                } else {
                    taskList.addTask(text)
                }
            }
        }

        // seperator line
        StyledRect {
            Layout.fillWidth: true; implicitHeight: 1
            color: Colours.palette.m3outlineVariant; opacity: 0.4
        }

        // ── Status filter (All/Active/Done) + search ──────────────
        RowLayout {
            visible: root.activePage === "tasks"
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            // Filter buttons (all, active, done)
            BtnSwitcher {
                id: statusFilterSwitcher
                Layout.fillHeight: true   
                model: [
                    { icon: "format_list_bulleted", text: qsTr("All"), value: "all", action: () => { root.statusFilter = "all" } },
                    { icon: "pending", text: qsTr("Active"), value: "active", action: () => { root.statusFilter = "active" } },
                    { icon: "task_alt", text: qsTr("Done"), value: "done", action: () => { root.statusFilter = "done" } }
                ]
                currentValue: root.statusFilter
                showOnlyActiveText: false
                givenHeight: 40
            }

            // Clear done button when any done tasks exist (only on tasks page)
            IconTextButton {
                implicitHeight: statusFilterSwitcher.givenHeight
                visible: taskList.doneCount > 0
                icon: "delete_sweep"
                onClicked: taskList.clearDone()
                isToggle: false
                checked:true
                type: ButtonBase.Tonal
                activeColour: "#6750A4"
                activeOnColour: "#FFFFFF"
                font: Tokens.font.label.medium
                radius: Tokens.rounding.small
                padding: Tokens.padding.small
            }

            // spacer pushes evrything else to the right
            Item { Layout.fillWidth: true }

            // Estimated time  and time left today (only if any active tasks exist)
            // StyledText {
            //     visible: taskList.totalActiveMinutes > 0
            //     text: {
            //         const activeMins = taskList.totalActiveMinutes;
            //         const h = Math.floor(activeMins / 60);
            //         const m = activeMins % 60;
            //         const estStr = h > 0 ? `${h}h${m > 0 ? ` ${m}m` : ""}` : `${m}m`;
            //         const left = root.timeLeftToday;
            //         const leftStr = left.hours > 0 ? `${left.hours}h${left.mins > 0 ? ` ${left.mins}m` : ""}` : `${left.mins}m`;
            //         return `📊 ${estStr} estimated · ${leftStr} left today`;
            //     }
            //     font: Tokens.font.body.small
            //     color: Colours.palette.m3onSurfaceVariant
            // }

            

            // Search input
            StyledTextField {
                implicitHeight: statusFilterSwitcher.givenHeight
                verticalPadding: Tokens.padding.small

                Layout.preferredWidth: 250
                // Layout.fillHeight: true
                leadingIcon: "search"
                placeholderText: qsTr("Search")
                text: root.searchQuery
                onTextChanged: root.searchQuery = text
                Keys.onEscapePressed: { clear(); focus = false; }
            }
        }


        // ── Icon picker for a new habit (daily page, while composing) ─
        // RowLayout {
        //     visible: root.activePage === "daily" && (captureField.activeFocus || captureField.text.length > 0)
        //     Layout.fillWidth: true
        //     spacing: Tokens.spacing.small

        //     StyledText {
        //         text: qsTr("Icon:")
        //         font: Tokens.font.label.small
        //         color: Colours.palette.m3onSurfaceVariant
        //     }

        //     Repeater {
        //         model: ["task_alt", "water_drop", "directions_run", "fitness_center", "menu_book",
        //                 "self_improvement", "block", "bedtime", "restaurant", "code",
        //                 "favorite", "music_note", "brush", "savings", "mop"]
        //         delegate: StyledRect {
        //             id: iconChip
        //             required property string modelData
        //             readonly property bool selected: root.habitIcon === modelData

        //             implicitWidth: 32; implicitHeight: 32
        //             radius: Tokens.rounding.full
        //             color: selected ? Colours.palette.m3primary
        //                  : iconChipHover.hovered ? Colours.tPalette.m3surfaceContainerHigh
        //                  : "transparent"
        //             Behavior on color { CAnim {} }

        //             HoverHandler { id: iconChipHover }

        //             MaterialIcon {
        //                 anchors.centerIn: parent
        //                 text: iconChip.modelData
        //                 fontStyle: Tokens.font.icon.small
        //                 color: iconChip.selected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
        //                 Behavior on color { CAnim {} }
        //             }

        //             MouseArea {
        //                 anchors.fill: parent
        //                 cursorShape: Qt.PointingHandCursor
        //                 onClicked: root.habitIcon = iconChip.modelData
        //             }
        //         }
        //     }

        //     Item { Layout.fillWidth: true }
        // }



        // seperator line
        StyledRect {
            Layout.fillWidth: true; implicitHeight: 1
            color: Colours.palette.m3outlineVariant; opacity: 0.4
        }

        TaskList {
            id: taskList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.activePage === "tasks"
            
            focus: root.activePage === "tasks"

            statusFilter: root.statusFilter
            searchQuery: root.searchQuery
        }

        DailyHabits {
            id: dailyHabits
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.activePage === "daily"
            focus: root.activePage === "daily"
        }
    }
}
