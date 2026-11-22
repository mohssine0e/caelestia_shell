pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Today's Focus Hero Card: prominent top card highlighting today's primary quest,
// its completion progress, next subtask action, and direct Focus Timer link.
StyledRect {
    id: root

    required property var taskList

    function findTodayTask(taskListTasks) {
        if (!taskListTasks || taskListTasks.length === 0) return null;
        // 1. Explicit todayFocus
        var t = taskListTasks.find(x => x.todayFocus && !x.done);
        if (t) return t;
        // 2. Task titled "TODAY" (case-insensitive)
        t = taskListTasks.find(x => x.title && x.title.trim().toLowerCase() === "today" && !x.done);
        if (t) return t;
        // 3. Category or tag #today
        t = taskListTasks.find(x => (x.category === "today" || (x.title && x.title.toLowerCase().includes("#today"))) && !x.done);
        if (t) return t;
        // 4. First active pinned task
        t = taskListTasks.find(x => x.pinned && !x.done);
        if (t) return t;
        // 5. Fallback first active task
        t = taskListTasks.find(x => !x.done);
        return t || null;
    }

    readonly property var task: root.taskList ? root.findTodayTask(root.taskList.tasks) : null
    readonly property bool hasTask: root.task !== null
    readonly property bool isLinkedTimer: root.hasTask && FocusTimer.linkedTaskId === root.task.todoId
    readonly property bool isTimerRunning: root.isLinkedTimer && FocusTimer.isRunning

    readonly property var progressData: root.taskList && root.task ? root.taskList.getProgressData(root.task.todoId) : ({ done: 0, total: 0, ratio: 0 })
    readonly property int progressDone: progressData.done
    readonly property int progressTotal: progressData.total
    readonly property real progressRatio: progressData.ratio

    readonly property var nextSubtask: {
        if (!root.task || !root.task.subtasks) return null;
        return root.task.subtasks.find(s => !s.done) || null;
    }

    Layout.fillWidth: true
    implicitHeight: mainCol.implicitHeight + Tokens.padding.medium * 2
    radius: Tokens.rounding.large
    color: Colours.palette.m3surfaceContainerHigh
    border.width: 1.5
    border.color: root.isTimerRunning ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3primary, 0.45)
    clip: true

    Behavior on border.color { CAnim {} }
    Behavior on implicitHeight { Anim { type: Anim.FastSpatial } }

    ColumnLayout {
        id: mainCol
        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.small

        // Top Row: Badges & Timer Action
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            // "★ TODAY'S FOCUS" Pill
            StyledRect {
                Layout.preferredHeight: 26
                Layout.preferredWidth: badgeRow.implicitWidth + 20
                radius: Tokens.rounding.full
                color: Colours.palette.m3primaryContainer

                RowLayout {
                    id: badgeRow
                    anchors.centerIn: parent
                    spacing: 5

                    MaterialIcon {
                        text: "star"
                        fill: 1
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onPrimaryContainer
                    }
                    StyledText {
                        text: qsTr("TODAY'S FOCUS")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onPrimaryContainer
                    }
                }
            }

            // Category badge if present
            StyledRect {
                visible: (root.task?.category ?? "").length > 0
                Layout.preferredHeight: 26
                Layout.preferredWidth: catRow.implicitWidth + 18
                radius: Tokens.rounding.full
                color: Qt.alpha(Colours.palette.m3secondaryContainer, 0.6)

                RowLayout {
                    id: catRow
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialIcon {
                        text: "tag"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onSecondaryContainer
                    }
                    StyledText {
                        text: root.task?.category ?? ""
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSecondaryContainer
                    }
                }
            }

            // Estimated duration chip
            StyledRect {
                visible: (root.task?.minutes ?? 0) > 0
                Layout.preferredHeight: 26
                Layout.preferredWidth: timeRow.implicitWidth + 18
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceContainerHighest

                RowLayout {
                    id: timeRow
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialIcon {
                        text: "schedule"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                    StyledText {
                        text: `${root.task?.minutes ?? 0}m`
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Pomodoro Start / Pause Button
            StyledRect {
                Layout.preferredHeight: 32
                Layout.preferredWidth: timerBtnRow.implicitWidth + 24
                radius: Tokens.rounding.full
                color: root.isTimerRunning ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3primary, 0.15)
                border.width: 1
                border.color: Colours.palette.m3primary

                StateLayer {
                    onClicked: {
                        if (!root.task) return;
                        if (root.isLinkedTimer) {
                            FocusTimer.toggle();
                        } else {
                            FocusTimer.startForTask(root.task.todoId, root.task.title, root.task.minutes || 35);
                        }
                        const st = ShellState.forActive();
                        if (st) st.timer = true;
                    }
                }

                RowLayout {
                    id: timerBtnRow
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialIcon {
                        text: root.isTimerRunning ? "pause" : "play_arrow"
                        fontStyle: Tokens.font.icon.medium
                        color: root.isTimerRunning ? Colours.palette.m3onPrimary : Colours.palette.m3primary
                    }

                    StyledText {
                        text: root.isTimerRunning
                            ? qsTr("Focusing (%1)").arg(FocusTimer.formattedTime)
                            : root.isLinkedTimer
                                ? qsTr("Resume (%1)").arg(FocusTimer.formattedTime)
                                : qsTr("Start Focus")
                        font: Tokens.font.label.medium
                        color: root.isTimerRunning ? Colours.palette.m3onPrimary : Colours.palette.m3primary
                    }
                }
            }
        }

        // Main Title Row with Checkbox
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            // Big custom checkbox
            StyledRect {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: Tokens.rounding.small
                color: root.task?.done ? Colours.palette.m3primary : "transparent"
                border.width: 2
                border.color: root.task?.done ? Colours.palette.m3primary : Colours.palette.m3outline

                StateLayer {
                    onClicked: {
                        if (!root.task || !root.taskList) return;
                        const absIdx = root.taskList.taskIndexMap[root.task.todoId];
                        if (absIdx !== undefined && absIdx >= 0) {
                            root.taskList.dataManager.toggleDone(absIdx);
                        }
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: root.task?.done ?? false
                    text: "check"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onPrimary
                }
            }

            // Task Title
            StyledText {
                Layout.fillWidth: true
                text: root.task?.title ?? ""
                font: Tokens.font.title.medium
                color: root.task?.done ? Colours.palette.m3outline : Colours.palette.m3onSurface
                elide: Text.ElideRight
            }
        }

        // Bottom Progress & Next Subtask Row
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            // Progress Bar (if task has subtasks)
            RowLayout {
                visible: (root.task?.subtasks?.length ?? 0) > 0
                spacing: Tokens.spacing.small

                StyledRect {
                    Layout.preferredWidth: 130
                    Layout.preferredHeight: 6
                    radius: 3
                    color: Colours.palette.m3surfaceContainerHighest

                    StyledRect {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: Math.round(parent.width * root.progressRatio)
                        radius: 3
                        color: Colours.palette.m3primary

                        Behavior on width { Anim { type: Anim.FastSpatial } }
                    }
                }

                StyledText {
                    text: `${root.progressDone}/${root.progressTotal} (${Math.round(root.progressRatio * 100)}%)`
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            // Next pending subtask chip
            StyledRect {
                id: nextSubtaskPill
                visible: root.nextSubtask !== null
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                radius: Tokens.rounding.small
                color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.7)
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outline, 0.2)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 6

                    MaterialIcon {
                        text: "arrow_forward"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3primary
                    }

                    StyledText {
                        text: qsTr("Next: %1").arg(root.nextSubtask?.title ?? "")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurface
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    // 1-click complete next subtask button
                    StyledRect {
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        radius: Tokens.rounding.full
                        color: Qt.alpha(Colours.palette.m3primary, 0.15)

                        StateLayer {
                            onClicked: {
                                if (!root.task || !root.nextSubtask || !root.taskList) return;
                                const absIdx = root.taskList.taskIndexMap[root.task.todoId];
                                const subIdx = root.task.subtasks.findIndex(s => s.id === root.nextSubtask.id);
                                if (absIdx !== undefined && subIdx >= 0) {
                                    root.taskList.dataManager.toggleSubtask(absIdx, subIdx);
                                }
                            }
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "check"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3primary
                        }
                    }
                }
            }

            // If no subtasks or all subtasks completed
            StyledText {
                visible: (root.task?.subtasks?.length ?? 0) === 0 || root.nextSubtask === null
                text: root.task?.done ? qsTr("Task completed! 🎉") : root.nextSubtask === null && (root.task?.subtasks?.length ?? 0) > 0 ? qsTr("All subtasks completed! 🚀") : ""
                font: Tokens.font.body.small
                color: Colours.palette.m3primary
            }
        }
    }
}
