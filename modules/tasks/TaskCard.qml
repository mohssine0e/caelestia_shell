// TaskCard.qml
// A reusable component for displaying a task with its subtasks

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import "TitleParse.js" as TitleParse
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils as Utils
/*
data model used: for both tasks and habits // to keep for reference
{
    todoId: string,
    title: string,
    done: bool,           // avoid type initiliazed to true 
    icon: string | null, // optional
    "type": "avoid",    //string : "build" | "avoid"

    minutes: int,       // estimated time in minutes, 0 = unset
    priority: int,

    streak: int,
    bestStreak: int,
    lastCompletedDate: string | null,
    
    subtasks: [
        {
            id: string,
            title: string,
            done: bool,
            minutes: int
        },
        ...
    ]
}
*/ 

Item {
    id: root

    // ── Required Properties ─────────────────────────────────────
    required property var taskData
    required property int taskIndex
    required property bool isEditing
        required property bool isSelected
    // Cursor owned by TaskNavigationController; TaskCard is a pure view.
    // Read directly off the controller (same source as `expanded` below) so
    // there is exactly one writer (TaskList) and nothing leaks across
    // ListView.onPooled/onReused recycling.
    readonly property int selectedSubtaskIndex:
        root.nav ? root.nav.selectedSubtaskIndex : -1
    readonly property int selectedNestedIndex:
        root.nav ? root.nav.selectedNestedIndex : -1
    // Expansion is owned by TaskNavigationController (survives ListView
    // recycling — no local state to leak through reuseItems).
    required property var nav
    readonly property bool expanded:
        root.nav.expandedTasks[root.taskData.todoId] ?? false
    required property int nSub
    required property int dSub
    required property real prog

    // Passed in by TaskList (no more reaching for the outer `list` id)
    property bool isHabitList: false
    property int taskDuration: 0      // subtask sum for parents, own minutes otherwise

    property string editingSubId: ""
    property bool showStreak: false

    property string icon: ""
    readonly property int streak: root.taskData?.streak ?? 0
    readonly property int bestStreak: root.taskData?.bestStreak ?? 0

    // Turned off while ListView recycles this card so Behaviors don't
    // replay colour/width animations when it is reused for another task.
    property bool animate: true

    // ── Signals ──────────────────────────────────────────────────
    signal toggleRequested(int taskIdx)
    signal renameRequested(int taskIdx, string newTitle)
    signal deleteRequested(int taskIdx)
    signal addSubtaskRequested(int taskIdx, string title)
    signal toggleSubtaskRequested(int taskIdx, int subIdx)
    signal deleteSubtaskRequested(int taskIdx, int subIdx)
    signal renameSubtaskRequested(int taskIdx, int subIdx, string newTitle)
    signal addNestedSubtaskRequested(int taskIdx, int subIdx, string title)
    signal toggleNestedSubtaskRequested(int taskIdx, int subIdx, int nestedIdx)
    signal deleteNestedSubtaskRequested(int taskIdx, int subIdx, int nestedIdx)
    signal renameNestedSubtaskRequested(int taskIdx, int subIdx, int nestedIdx, string newTitle)
    signal editingStarted(string taskId)
    signal editingCancelled()
    signal subtaskEditingStarted(string subtaskId)
    signal subtaskEditingCancelled()
    signal selectionRequested(int taskIdx)
    signal subtaskSelectionRequested(int subIdx)
    signal addChildCancelled(int taskIdx, int subIdx)

    // ── ListView recycling (reuseItems: true) ───────────────────
    // Reset only non-controller local state; expansion lives in the
    // TaskNavigationController and intentionally survives recycling.
    ListView.onPooled: {
        root.animate = false
        addSubtaskField.clear()
    }
    ListView.onReused: Qt.callLater(function() { root.animate = true })

    // ── Layout ──────────────────────────────────────────────────
    Layout.fillWidth: true
    implicitHeight: rowBg.implicitHeight

    // ── Internal State ──────────────────────────────────────────
    readonly property string taskId: root.taskData?.todoId ?? ""
    readonly property string taskTitle: root.taskData?.title ?? ""
    readonly property bool taskDone: root.taskData?.done ?? false
    readonly property bool taskPartial: root.dSub > 0 && root.dSub < root.nSub
    readonly property var subtasks: root.taskData?.subtasks ?? []
    readonly property var emptySub: ({ id: "", title: "", done: false, minutes: 0 })

    // Read-only accessor used by TaskList's key handler (Right drill-in).
    // Returns null for collapsed/virtualized rows — callers guard for that.
    function subDelegate(subIdx) {
        return subRepeater.itemAt(subIdx)
    }

    // One colour binding shared by the streak icon + number
    readonly property color streakColor: {
        if (root.streak >= 20) return "#fe1d1d"
        if (root.streak >= 10) return "#FF8C00"
        if (root.streak >= 3)  return "#FFA500"
        if (root.streak >= 1)  return Colours.palette.m3primary
        return Colours.palette.m3outlineVariant
    }

    // Prefill for the title edit field. Subtask-less tasks carry their
    // estimate inline as "@minutes" (even when it is 0); the submitted
    // text is parsed back into title + minutes by DataManager.renameTask.
    readonly property string editPrefill: root.nSub === 0 && !root.isHabitList
        ? `${root.taskTitle} @${root.taskData?.minutes || 0}`
        : root.taskTitle


    // ── Main Card ──────────────────────────────────────────────
    StyledRect {
        id: rowBg
        width: parent.width
        radius: Tokens.rounding.small

        // ── Full-card selection ─────────────────────────
        TapHandler {
            onTapped: {
                root.selectionRequested(root.taskIndex)
            }
        }
        // ── Background color states ──
        color: root.isSelected ? Colours.tPalette.m3surfaceContainerHigh
             : rowHover.hovered ? Colours.tPalette.m3surfaceContainer
             : Colours.tPalette.m3surfaceContainerLow

        // ── Border ──
        border.width: root.isSelected ? 1 : 0
        border.color: Qt.alpha(Colours.palette.m3primary, 0.35)

        // No Behavior on implicitHeight: animating it re-flowed the whole
        // ListView (and resized the popout) on every frame.
        implicitHeight: rowCol.implicitHeight + Tokens.padding.small * 2
        Behavior on color { enabled: root.animate; CAnim {} }

        HoverHandler { id: rowHover }

        ColumnLayout {
            id: rowCol
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Tokens.padding.small
                leftMargin: Tokens.padding.medium
                rightMargin: Tokens.padding.medium
            }
            spacing: Tokens.spacing.small

            // ── Main row ───────────────────────────────────────
            RowLayout {
                id: mainRow
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                // ── Expander / Collapser ─────────────────────────
                MaterialIcon {
                    text: root.expanded ? "expand_more" : "chevron_right"
                    fontStyle: Tokens.font.icon.medium
                    color: root.expanded ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    opacity: root.expanded ? 1 : 0.5
                    Behavior on opacity { enabled: root.animate; CAnim {} }
                    Behavior on color { enabled: root.animate; CAnim {} }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.nav?.setTaskExpanded(root.taskData.todoId, !root.expanded)
                            root.selectionRequested(root.taskIndex)
                        }
                    }
                }

                // ── Checkbox / Icon ─────────────────────────────
                Item {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    // (was anchors.verticalCenter — anchors on a layout child
                    //  trigger a runtime warning per card; this is the layout way)
                    Layout.alignment: Qt.AlignVCenter

                    MaterialIcon {
                        id: toggleIcon
                        anchors {
                            verticalCenter: parent.verticalCenter
                            left: parent.left
                        }

                        text: {
                            if (root.icon === "" || root.icon === null || root.icon === "block") {
                                if (root.nSub > 0) {
                                    return root.taskDone ? "check_box"
                                        : root.taskPartial ? "indeterminate_check_box"
                                        : "check_box_outline_blank"
                                } else {
                                    return root.taskDone ? "check_circle" : "radio_button_unchecked"
                                }
                            } else {
                                return root.icon
                            }
                        }

                        fill: root.taskDone ? 1 : 0
                        fontStyle: Tokens.font.icon.medium

                        color: {
                            if (root.icon !== "") {
                                return root.taskDone ? Colours.palette.m3primary
                                                    : Colours.palette.m3onSurfaceVariant
                            }
                            if (root.taskDone) return Colours.palette.m3primary
                            if (root.taskPartial) return Colours.palette.m3secondary
                            if (root.nSub === 0) return Colours.palette.m3onSurface
                            return Colours.palette.m3outline
                        }
                        opacity: root.taskDone ? 0.5 : 1
                        
                        Behavior on color { enabled: root.animate; CAnim {} }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: root.nSub > 0 ? Qt.ArrowCursor : Qt.PointingHandCursor
                            enabled: root.nSub === 0
                            onClicked: {
                                if (root.nSub === 0) {
                                    root.toggleRequested(root.taskIndex)
                                    root.selectionRequested(root.taskIndex)
                                }
                            }
                        }
                    }
                }

                // ── Title ───────────────────────────────────────
                StyledText {
                    visible: !root.isEditing
                    Layout.fillWidth: true

                    text: root.taskTitle
                    font: Tokens.font.body.large

                    elide: root.isSelected ? Text.ElideNone : Text.ElideRight
                    wrapMode: root.isSelected ? Text.Wrap : Text.NoWrap
                    color: root.taskDone
                        ? Colours.palette.m3onSurfaceVariant
                        : (root.nSub === 0 ? Colours.palette.m3onSurface
                                            : Colours.palette.m3primary)                    
                    opacity: root.taskDone ? 0.6 : 1
                    Behavior on color { enabled: root.animate; CAnim {} }

                    // ── Strikethrough WHEN DONE ──
                    StyledRect {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.taskDone ? Math.min(parent.contentWidth, parent.width) : 0
                        height: 2
                        radius: Tokens.rounding.full
                        color:  Colours.palette.m3outline
                        opacity: root.taskDone ? 0.6 : 0
                        Behavior on width { enabled: root.animate; Anim { type: Anim.FastSpatial } }
                        Behavior on opacity { enabled: root.animate; CAnim {} }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectionRequested(root.taskIndex)
                    }
                }

                // ── Edit Field ──────────────────────────────────
                StyledTextField {
                    visible: root.isEditing
                    Layout.fillWidth: true
                    text: root.editPrefill
                    font: Tokens.font.body.large
                    property bool commitInProgress: false

                    background: Rectangle {
                        color: "transparent"
                        border.width: 0
                    }

                    leftPadding: 0
                    rightPadding: 0
                    topPadding: 0
                    bottomPadding: 0
                    verticalAlignment: Text.AlignVCenter

                    function commitEdit() {
                        if (commitInProgress || !root.isEditing)
                            return
                        commitInProgress = true
                        focus = false   // ← release focus BEFORE emitting
                        // An empty *title* cancels the edit: the "@minutes" tail
                        // must not count as one (e.g. text "@5" alone).
                        if (TitleParse.hasTitle(text))
                            root.renameRequested(root.taskIndex, text)
                        else {
                            text = root.editPrefill
                            root.editingCancelled()
                        }
                    }

                    onVisibleChanged: {
                        if (visible) {
                            commitInProgress = false
                            text = root.editPrefill
                            forceActiveFocus()
                            // Pre-select only the title part so a quick retype
                            // keeps the "@minutes" tail that gets parsed on submit.
                            if (root.nSub === 0 && !root.isHabitList && root.taskTitle.length > 0 && text.length > root.taskTitle.length)
                                select(0, root.taskTitle.length)
                            else
                                selectAll()
                        }
                    }

                    Keys.onPressed: event => {
                        // Consume Return/Enter so commit doesn't let the same
                        // key bubble up to TaskList and toggle the task.
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            commitEdit()
                            event.accepted = true
                        }
                    }

                    Keys.onEscapePressed: event => {
                        commitInProgress = true
                        focus = false
                        root.editingCancelled()
                        text = root.editPrefill
                        event.accepted = true   // don't bubble Escape to the root
                    }
                    onFocusChanged: {
                        if (!focus && root.isEditing && !commitInProgress)
                            commitEdit()
                    }
                }

                // ── Spacer ──────────────────────────────────────
                Item { Layout.fillWidth: true }

                // ── Estimated time chip (tasks only) ────────────
                // Right-aligned with the progress/streak cluster. Hidden
                // for habits, while editing a subtask-less task (the
                // estimate is inline in the edit field) and when unset.
                RowLayout {
                    visible: !root.isHabitList
                        && root.taskDuration > 0
                        && !(root.nSub === 0 && root.isEditing)
                    Layout.alignment: Qt.AlignVCenter

                    StyledRect {
                        implicitHeight: 20
                        implicitWidth: minutesLabel.implicitWidth + Tokens.padding.small * 2
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3surfaceContainerHighest

                        StyledText {
                            id: minutesLabel
                            anchors.centerIn: parent
                            text: `${root.taskDuration}m`
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }

                // ── Progress ────────────────────────────────────
                RowLayout {
                    visible: root.nSub > 0 && !root.isEditing
                    spacing: Tokens.spacing.small
                    Layout.preferredWidth: 100
                    Layout.alignment: Qt.AlignVCenter

                    StyledText {
                        text: `${root.dSub}/${root.nSub}`
                        font: Tokens.font.body.small
                        color: root.taskDone ? Colours.palette.m3primary
                                                : Colours.palette.m3onSurfaceVariant
                        opacity: 0.7
                        Behavior on color { enabled: root.animate; CAnim {} }
                    }

                    StyledRect {
                        implicitWidth: 120
                        implicitHeight: 4
                        radius: Tokens.rounding.full
                        color: Colours.tPalette.m3surfaceContainerHighest

                        StyledRect {
                            width: parent.width * root.prog
                            height: parent.height
                            radius: parent.radius
                            color: root.taskDone ? Colours.palette.m3tertiary
                                                    : Colours.palette.m3primary
                            Behavior on width { enabled: root.animate; Anim {} }
                            Behavior on color { enabled: root.animate; CAnim {} }
                        }
                    }
                }

               // ── Streak (habits only) ────────────────────────
                RowLayout {
                    id: streakBadge
                    visible: root.showStreak && (root.streak > 0 || root.bestStreak > 0) && !root.isEditing
                    Layout.leftMargin: Tokens.spacing.small
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 4

                    // Current Streak Indicator
                    RowLayout {
                        spacing: 2
                        MaterialIcon {
                            text: "local_fire_department"
                            fill: 1
                            fontStyle: Tokens.font.icon.small
                            color: root.streakColor
                            Behavior on color { enabled: root.animate; CAnim { duration: 300 } }
                        }
                        StyledText {
                            text: String(root.streak)
                            font: Tokens.font.label.medium
                            color: root.streakColor
                            Behavior on color { enabled: root.animate; CAnim { duration: 300 } }
                        }
                    }

                    // Best Streak Target Badge (shows when bestStreak exceeds current streak)
                    RowLayout {
                        visible: root.bestStreak > root.streak
                        spacing: 1
                        opacity: 0.65

                        MaterialIcon {
                            text: "emoji_events" // Trophy icon for best record target
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        StyledText {
                            text: String(root.bestStreak)
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }

                // ── Actions ─────────────────────────────────────
                RowLayout {
                    visible: !root.isEditing
                    spacing: 0
                    opacity: (rowHover.hovered || root.isSelected) ? 1 : 0.3
                    Behavior on opacity { enabled: root.animate; Anim { type: Anim.DefaultEffects } }

                    IconButton {
                        type: IconButton.Text
                        font: Tokens.font.icon.small
                        icon: "edit"
                        onClicked: {
                            root.selectionRequested(root.taskIndex)
                            root.editingStarted(root.taskId)
                        }
                    }

                    IconButton {
                        id: deleteButton
                        type: IconButton.Text
                        font: Tokens.font.icon.small
                        icon: "delete_outline"

                        property bool isShaking: false

                        onClicked: {
                            if (!isShaking) {
                                isShaking = true
                                shakeAnim.start()
                            }
                            root.selectionRequested(root.taskIndex)
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            onClicked: deleteButton.clicked()
                            onDoubleClicked: root.deleteRequested(root.taskIndex)
                        }

                        SequentialAnimation {
                            id: shakeAnim
                            onFinished: {
                                deleteButton.isShaking = false
                                deleteButton.rotation = 0
                            }
                            PropertyAnimation {
                                target: deleteButton
                                property: "rotation"
                                from: -8
                                to: 8
                                duration: 80
                            }
                            PropertyAnimation {
                                target: deleteButton
                                property: "rotation"
                                from: 8
                                to: -8
                                duration: 80
                            }
                            PropertyAnimation {
                                target: deleteButton
                                property: "rotation"
                                from: -8
                                to: 8
                                duration: 80
                            }
                            PropertyAnimation {
                                target: deleteButton
                                property: "rotation"
                                from: 8
                                to: -8
                                duration: 80
                            }
                            PropertyAnimation {
                                target: deleteButton
                                property: "rotation"
                                from: -4
                                to: 4
                                duration: 50
                            }
                            PropertyAnimation {
                                target: deleteButton
                                property: "rotation"
                                from: 4
                                to: 0
                                duration: 50
                            }
                        }
                    }
                }
            }       
            
            // ── Subtasks ────────────────────────────────────────
            ColumnLayout {
                visible: root.expanded
                Layout.fillWidth: true
                Layout.leftMargin: 11
                spacing: 0

                Repeater {
                    id: subRepeater
                    // Integer model + lazy: subtask rows only exist while the
                    // card is expanded (collapsed cards used to build every
                    // SubtaskCard + its nested rows anyway), and adding /
                    // toggling / renaming a subtask no longer rebuilds them —
                    // delegates just re-read root.subtasks[index].
                    model: root.expanded ? root.subtasks.length : 0
                    delegate: SubtaskCard {
                        required property int index

                        readonly property var sub: root.subtasks[index] ?? root.emptySub

                        taskData: root.taskData
                        taskIndex: root.taskIndex
                        subtaskData: sub
                        subtaskIndex: index
                        subtaskId: sub.id ?? ""

                        isHabitList: root.isHabitList
                        isEditing: root.editingSubId === `${root.taskId}__${sub.id}`
                        isSelected: root.isSelected && root.selectedSubtaskIndex === index
                        nav: root.nav

                        isFirst: index === 0
                        isLast: index === subRepeater.count - 1
                        hasChildren: (sub.children?.length ?? 0) > 0
                        depth: 1
                        editingNestedId: root.editingSubId
                        selectedNestedIndex: (root.isSelected && root.selectedSubtaskIndex === index) ? root.selectedNestedIndex : -1

                        onToggleRequested: (taskIdx, subIdx) => {
                            root.toggleSubtaskRequested(taskIdx, subIdx)
                        }
                        onDeleteRequested: (taskIdx, subIdx) => {
                            root.deleteSubtaskRequested(taskIdx, subIdx)
                        }
                        onRenameRequested: (taskIdx, subIdx, newTitle) => {
                            root.renameSubtaskRequested(taskIdx, subIdx, newTitle)
                        }
                        onEditingStarted: (subtaskId) => {
                            root.subtaskEditingStarted(subtaskId)
                        }
                        onEditingCancelled: {
                            root.subtaskEditingCancelled()
                        }
                        onNestedEditingStarted: (nestedId) => {
                            root.subtaskEditingStarted(nestedId)
                        }
                        onNestedEditingCancelled: {
                            root.subtaskEditingCancelled()
                        }
                        onAddChildRequested: (taskIdx, subIdx, title) => {
                            root.addNestedSubtaskRequested(taskIdx, subIdx, title)
                        }
                        onAddChildCancelled: (taskIdx, subIdx) => {
                            root.addChildCancelled(taskIdx, subIdx)
                        }
                        onToggleNestedRequested: (taskIdx, subIdx, nestedIdx) => {
                            root.toggleNestedSubtaskRequested(taskIdx, subIdx, nestedIdx)
                        }
                        onDeleteNestedRequested: (taskIdx, subIdx, nestedIdx) => {
                            root.deleteNestedSubtaskRequested(taskIdx, subIdx, nestedIdx)
                        }
                        onRenameNestedRequested: (taskIdx, subIdx, nestedIdx, newTitle) => {
                            root.renameNestedSubtaskRequested(taskIdx, subIdx, nestedIdx, newTitle)
                        }
                        onSelectionRequested: (taskIdx, subIdx) => {
                            root.subtaskSelectionRequested(subIdx)
                        }
                    }
                }

                // ── Add-subtask field ──────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 0

                    MaterialIcon {
                        text: "add_circle_outline"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3primary
                        opacity: addSubtaskField.focus ? 1 : 0.5
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 18

                        Behavior on opacity { enabled: root.animate; CAnim {} }
                    }

                    StyledTextField {
                        id: addSubtaskField
                        placeholderFloats: false
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28


                        placeholderText: qsTr("Add subtask…")
                        placeholderTextColor: Colours.palette.m3onSurfaceVariant
                        color: Colours.palette.m3onSurfaceVariant

                        background: Rectangle {
                            color: "transparent"
                            border.width: 0
                        }

                        topPadding: 2
                        bottomPadding: 2
                        leftPadding: 5
                        rightPadding: 5

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                // Ignore pure "@minutes" input — it has no title.
                                if (TitleParse.hasTitle(text)) {
                                    root.addSubtaskRequested(root.taskIndex, text)
                                    clear()
                                }
                                event.accepted = true
                            }
                        }
                        Keys.onEscapePressed: {
                            clear()
                            focus = false
                            root.subtaskEditingCancelled()
                        }
                    }
                }
            }
        }
        
    }
}
