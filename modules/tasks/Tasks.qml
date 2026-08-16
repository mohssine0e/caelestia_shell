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

    implicitWidth: 1040
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2
    Behavior on implicitHeight { Anim { type: Anim.FastSpatial } }

    // Emitted on Escape when nothing deeper (an edit field, a menu) has
    // already consumed it — the popout wrapper closes on this.
    signal closeRequested()
    Keys.onEscapePressed: root.closeRequested()

    // "/" jumps to the capture field (only reachable while the popout is
    // open and no text field already has focus — otherwise "/" just types).
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Slash && !inputActive) {
            captureField.forceActiveFocus();
            event.accepted = true;
        } else {
            event.accepted = false;
        }
    }

    // Return keyboard focus to the active list when clicking any empty
    // space, so text fields lose focus on click-outside. Sits underneath
    // all content; interactive elements on top still win.
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

        // ── Header: capture + page switch ─────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            // Capture task — stays neutral; focus is signalled by a thin
            // accent border only.
            StyledRect {
                id: captureBox
                Layout.preferredWidth: 270
                radius: Tokens.rounding.full
                color: Colours.tPalette.m3surfaceContainerHigh
                border.width: captureField.activeFocus ? 1 : 0
                border.color: Colours.palette.m3primary
                implicitHeight: captureField.implicitHeight + Tokens.padding.small * 2

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.small
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        // On the daily page this previews the icon the new
                        // habit will get (picked from the row below)
                        text: root.activePage === "daily" ? root.habitIcon : "add"
                        fontStyle: Tokens.font.icon.small
                        color: captureField.activeFocus ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        Behavior on color { CAnim {} }
                    }

                    StyledTextField {
                        id: captureField
                        Layout.fillWidth: true
                        // Context-aware: feeds whichever page is showing
                        placeholderText: root.activePage === "daily" ? qsTr("Add a habit…") : qsTr("Capture a task…")
                        onAccepted: {
                            if (root.activePage === "daily") {
                                dailyHabits.addHabit(text, root.habitIcon);
                                root.habitIcon = "task_alt";
                            } else {
                                taskList.addTask(text);
                            }
                            clear();
                        }
                        Keys.onEscapePressed: { clear(); focus = false; }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Page switch: Tasks / Daily — a real segmented control: subtle
            // track, only the active tab gets a solid pill so it doesn't
            // read as two stacked chips.
            StyledRect {
                radius: Tokens.rounding.full
                color: Colours.tPalette.m3surfaceContainerHigh
                implicitWidth: pageSwitchRow.implicitWidth + Tokens.padding.extraSmall * 2
                implicitHeight: pageSwitchRow.implicitHeight + Tokens.padding.extraSmall * 2

                RowLayout {
                    id: pageSwitchRow
                    anchors.centerIn: parent
                    spacing: 2

                    IconTextButton {
                        isToggle: true
                        checked: root.activePage === "tasks"
                        type: ButtonBase.Tonal
                        inactiveColour: "transparent"
                        activeColour: Colours.palette.m3primary
                        activeOnColour: Colours.palette.m3onPrimary
                        inactiveOnColour: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.medium
                        icon: "checklist"
                        text: qsTr("Tasks")
                        onClicked: root.activePage = "tasks"
                    }
                    IconTextButton {
                        isToggle: true
                        checked: root.activePage === "daily"
                        type: ButtonBase.Tonal
                        inactiveColour: "transparent"
                        activeColour: Colours.palette.m3primary
                        activeOnColour: Colours.palette.m3onPrimary
                        inactiveOnColour: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.medium
                        icon: "wb_sunny"
                        text: dailyHabits.streakCount > 0 ? qsTr("Daily 🔥 %1").arg(dailyHabits.streakCount) : qsTr("Daily")
                        onClicked: root.activePage = "daily"
                    }
                }
            }
        }

        // ── Icon picker for a new habit (daily page, while composing) ─
        RowLayout {
            visible: root.activePage === "daily" && (captureField.activeFocus || captureField.text.length > 0)
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                text: qsTr("Icon:")
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
            }

            Repeater {
                model: ["task_alt", "water_drop", "directions_run", "fitness_center", "menu_book",
                        "self_improvement", "block", "bedtime", "restaurant", "code",
                        "favorite", "music_note", "brush", "savings", "mop"]
                delegate: StyledRect {
                    id: iconChip
                    required property string modelData
                    readonly property bool selected: root.habitIcon === modelData

                    implicitWidth: 32; implicitHeight: 32
                    radius: Tokens.rounding.full
                    color: selected ? Colours.palette.m3primary
                         : iconChipHover.hovered ? Colours.tPalette.m3surfaceContainerHigh
                         : "transparent"
                    Behavior on color { CAnim {} }

                    HoverHandler { id: iconChipHover }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: iconChip.modelData
                        fontStyle: Tokens.font.icon.small
                        color: iconChip.selected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                        Behavior on color { CAnim {} }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.habitIcon = iconChip.modelData
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }

        // ── Status filter (All/Active/Done) + search ──────────────
        RowLayout {
            visible: root.activePage === "tasks"
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Repeater {
                model: [
                    { key: "all",    icon: "format_list_bulleted", label: qsTr("All") },
                    { key: "active", icon: "pending",              label: qsTr("Active") },
                    { key: "done",   icon: "task_alt",             label: qsTr("Done") }
                ]
                delegate: IconTextButton {
                    id: schip
                    required property var modelData

                    readonly property int count: modelData.key === "active" ? taskList.activeCount
                                               : modelData.key === "done"   ? taskList.doneCount
                                               : taskList.activeCount + taskList.doneCount

                    isToggle: true
                    checked: root.statusFilter === modelData.key
                    type: ButtonBase.Text
                    font: Tokens.font.label.small
                    icon: modelData.icon
                    text: count > 0 ? `${modelData.label} · ${count}` : modelData.label

                    onClicked: root.statusFilter = modelData.key
                }
            }

            Item { Layout.fillWidth: true }

            StyledText {
                visible: taskList.totalActiveMinutes > 0
                text: {
                    const activeMins = taskList.totalActiveMinutes;
                    const h = Math.floor(activeMins / 60);
                    const m = activeMins % 60;
                    const estStr = h > 0 ? `${h}h${m > 0 ? ` ${m}m` : ""}` : `${m}m`;
                    
                    const left = root.timeLeftToday;
                    const leftStr = left.hours > 0 ? `${left.hours}h${left.mins > 0 ? ` ${left.mins}m` : ""}` : `${left.mins}m`;
                    
                    return `📊 ${estStr} estimated · ${leftStr} left today`;
                }
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }

            // Sweep away everything already completed (undoable)
            IconTextButton {
                visible: taskList.doneCount > 0
                type: ButtonBase.Text
                font: Tokens.font.label.small
                icon: "delete_sweep"
                text: qsTr("Clear done")
                onClicked: taskList.clearDone()
            }

            StyledRect {
                Layout.preferredWidth: 200
                radius: Tokens.rounding.full
                color: Colours.tPalette.m3surfaceContainerHigh
                border.width: searchField.activeFocus ? 1 : 0
                border.color: Colours.palette.m3primary
                implicitHeight: searchField.implicitHeight + Tokens.padding.small * 2

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.small
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        text: "search"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    StyledTextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: qsTr("Search…")
                        text: root.searchQuery
                        onTextChanged: root.searchQuery = text
                        Keys.onEscapePressed: { clear(); focus = false; }
                    }

                    IconButton {
                        visible: searchField.text.length > 0
                        type: IconButton.Text
                        font: Tokens.font.icon.small
                        icon: "close"
                        onClicked: searchField.clear()
                    }
                }
            }
        }

        StyledRect {
            Layout.fillWidth: true; implicitHeight: 1
            color: Colours.palette.m3outlineVariant; opacity: 0.4
        }

        TaskList {
            id: taskList
            Layout.fillWidth: true
            visible: root.activePage === "tasks"
            focus: root.activePage === "tasks"

            statusFilter: root.statusFilter
            searchQuery: root.searchQuery
        }

        DailyHabits {
            id: dailyHabits
            Layout.fillWidth: true
            visible: root.activePage === "daily"
            focus: root.activePage === "daily"
        }
    }
}
