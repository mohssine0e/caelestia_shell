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
    focus: true
    width: 1040
    height: 720
    implicitWidth: 1040
    implicitHeight: 720

    signal closeRequested()

    // ── Root key handler ─────────────────────────────────────────
    // Only handles keys that should work globally (not when typing).
    Keys.onPressed: event => {
        // Q — quick page switch (only when no text field has focus)
        if (event.key === Qt.Key_Q && !root.inputActive) {
            if (root.activePage === "daily") {
                root.activePage = "tasks"
                taskList.forceActiveFocus()
            } else {
                root.activePage = "daily"
                dailyHabitsList.forceActiveFocus()
            }
            event.accepted = true
            return
        }

        // "/" — focus the capture field
        if (event.key === Qt.Key_Slash && !root.inputActive) {
            tasksHeader.focusCapture()
            event.accepted = true
            return
        }

        event.accepted = false
    }

    // ── Escape at the root closes the popout ─────────────────────
    // Text fields inside will consume Escape first (via event.accepted).
    Keys.onEscapePressed: event => {
        if (root.inputActive) {
            // A text field owns Escape; let it handle it.
            event.accepted = false
            return
        }
        root.closeRequested()
        event.accepted = true
    }

    // ── Background click catcher ─────────────────────────────────
    MouseArea {
        anchors.fill: parent
        onPressed: {
            if (root.activePage === "tasks")
                taskList.forceActiveFocus()
            else
                dailyHabitsList.forceActiveFocus()
        }
    }

    property string activePage: "tasks"
    property string statusFilter: "all"
    property string searchQuery: ""
    property string habitType: "build"
    property string habitIcon: "task_alt"

    property var timeUntilReset: ({ hours: 0, mins: 0 })

    function updateTimeLeft() {
        const now = new Date()
        const resetHour = 2
        let end = new Date(now.getFullYear(), now.getMonth(), now.getDate(), resetHour, 0, 0, 0)
        if (now >= end)
            end.setDate(end.getDate() + 1)
        const diffMs = Math.max(0, end - now)
        const diffMins = Math.floor(diffMs / 60000)
        const hours = Math.floor(diffMins / 60)
        const mins = diffMins % 60
        timeUntilReset = { hours: hours, mins: mins }
    }

    Timer {
        id: timeTrackerTimer
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.updateTimeLeft()
    }

    // ── True while any text field has focus ──────────────────────
    readonly property Item focusItem: Window.activeFocusItem
    readonly property bool inputActive: focusItem?.cursorPosition !== undefined

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        // ── Header (capture field + switchers) ───────────────────
        TasksHeader {
            id: tasksHeader

            Layout.fillWidth: true
            activePage: root.activePage
            habitIcon: root.habitIcon
            habitType: root.habitType

            onHabitTypeSelected: type => root.habitType = type
            onHabitIconSelected: icon => root.habitIcon = icon
            onPageChanged: page => root.activePage = page

            onEscapePressed: {
                (root.activePage === "tasks" ? taskList : dailyHabitsList).forceActiveFocus()
            }

            onCaptureAccepted: text => {
                if (root.activePage === "daily")
                    dailyHabitsList.addTask(text, root.habitIcon, root.habitType)
                else
                    taskList.addTask(text)
            }
        }

        // ── Separator ────────────────────────────────────────────
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Colours.palette.m3outlineVariant
            opacity: 0.4
        }

        // ── Status filter + search ───────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

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

            // Daily: completions today + countdown to 2am reset
            RowLayout {
                visible: root.activePage === "daily"
                spacing: Tokens.spacing.small
                Layout.fillHeight: true

                MaterialIcon {
                    text: "local_fire_department"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3primary
                    fill: dailyHabitsList.doneCount > 0 ? 1 : 0
                }
                StyledText {
                    text: qsTr("%1 / %2 today").arg(dailyHabitsList.doneCount).arg(dailyHabitsList.tasks.length)
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onSurfaceVariant
                }
                StyledText {
                    text: root.timeUntilReset.hours > 0
                          ? qsTr("resets in %1h %2m").arg(root.timeUntilReset.hours).arg(root.timeUntilReset.mins)
                          : qsTr("resets in %1m").arg(root.timeUntilReset.mins)
                    font: Tokens.font.body.small
                    color: Colours.palette.m3outline
                }
            }

            Item { Layout.fillWidth: true }

            // Search
            StyledTextField {
                implicitHeight: statusFilterSwitcher.givenHeight
                verticalPadding: Tokens.padding.small

                Layout.preferredWidth: 250
                leadingIcon: "search"
                placeholderText: root.activePage === "daily" ? qsTr("Search habits") : qsTr("Search tasks")
                text: root.searchQuery
                onTextChanged: root.searchQuery = text

                onAccepted: {
                    focus = false
                    clear()
                    Qt.callLater(() => {
                        (root.activePage === "tasks" ? taskList : dailyHabitsList).forceActiveFocus()
                    })                }


                Keys.onEscapePressed: {
                    clear()
                    focus = false
                    Qt.callLater(() => {
                        (root.activePage === "tasks" ? taskList : dailyHabitsList).forceActiveFocus()
                    })
                }
            }
        }

        // ── Separator ────────────────────────────────────────────
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Colours.palette.m3outlineVariant
            opacity: 0.4
            visible: root.activePage === "tasks"
        }

        // ── Task list ────────────────────────────────────────────
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

        // ── Habit list ───────────────────────────────────────────
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
