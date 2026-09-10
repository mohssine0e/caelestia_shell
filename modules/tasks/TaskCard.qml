// TaskCard.qml
// A reusable component for displaying a task with its subtasks

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
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
    done: bool,
    icon: string | null, // optional
    minutes: int,
    priority: int,

    completions: { "YYYY-MM-DD": [ids] }, // habits only field
    streak: int,
    bestStreak: int,
    lastCompleted: string | null,
    
    subtasks: [
        {
            id: string,
            title: string,
            done: bool,
            minutes: int
            completions: { "YYYY-MM-DD": [ids] }, // habits only field future add
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
    property bool expanded: false
    required property bool isSelected
    property int selectedSubtaskIndex: -1
    required property int nSub
    required property int dSub
    required property var subOrder
    required property real prog

    property string editingSubId: ""
    property bool showStreak: false

    // ── Signals ──────────────────────────────────────────────────
    signal toggleRequested(int taskIdx)
    signal renameRequested(int taskIdx, string newTitle)
    signal deleteRequested(int taskIdx)
    signal addSubtaskRequested(int taskIdx, string title)
    signal toggleSubtaskRequested(int taskIdx, int subIdx)
    signal deleteSubtaskRequested(int taskIdx, int subIdx)
    signal renameSubtaskRequested(int taskIdx, int subIdx, string newTitle)
    signal editingStarted(string taskId)
    signal editingCancelled()
    signal subtaskEditingStarted(string subtaskId)
    signal subtaskEditingCancelled()
    signal selectionRequested(int taskIdx)
    signal subtaskSelectionRequested(int subIdx)

    // ── Layout ──────────────────────────────────────────────────
    Layout.fillWidth: true
    implicitHeight: rowBg.implicitHeight

    // ── Internal State ──────────────────────────────────────────
    readonly property string taskId: root.taskData?.todoId ?? ""
    readonly property string taskTitle: root.taskData?.title ?? ""
    readonly property bool taskDone: root.taskData?.done ?? false
    readonly property bool taskPartial: root.dSub > 0 && root.dSub < root.nSub
    readonly property var subtasks: root.taskData?.subtasks ?? []

    readonly property var subtaskMap: {
        const map = {};
        if (taskData && taskData.subtasks) {
            for (const sub of taskData.subtasks) {
                map[sub.id] = sub;
            }
        }
        return map;
    }

    property string icon: ""
    readonly property int streak: root.taskData?.streak ?? 0

    // ── Main Card ──────────────────────────────────────────────
    StyledRect {
        id: rowBg
        width: parent.width
        radius: Tokens.rounding.small

        // ── Selection/Click catcher ─────────────────────
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            propagateComposedEvents: true
            onClicked: function(mouse) {
                root.selectionRequested(root.taskIndex)
                mouse.accepted = false
            }
            onPressed: function(mouse) {
                mouse.accepted = false
            }
        }
        // ── Background color states ──
        color: root.isSelected ? Colours.tPalette.m3surfaceContainerHigh
             : rowHover.hovered ? Colours.tPalette.m3surfaceContainer
             : Colours.tPalette.m3surfaceContainerLow

        // ── Border ──
        border.width: root.isSelected ? 1 : 0
        border.color: Qt.alpha(Colours.palette.m3primary, 0.35)

        implicitHeight: rowCol.implicitHeight + Tokens.padding.small * 2
        Behavior on implicitHeight { Anim { type: Anim.FastSpatial } }
        Behavior on color { CAnim {} }

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

                // ── Expander (only when has subtasks) ──────────
                MaterialIcon {
                    text: root.expanded ? "expand_more" : "chevron_right"
                    fontStyle: Tokens.font.icon.medium
                    color: Colours.palette.m3onSurfaceVariant
                    opacity: root.expanded ? 1.0 : 0.6
                    Behavior on opacity { CAnim {} }
                    Behavior on color { CAnim {} }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.expanded = !root.expanded
                            root.selectionRequested(root.taskIndex)
                        }
                    }
                }

                // ── Checkbox / Icon ─────────────────────────────
                Item {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    anchors.verticalCenter: parent.verticalCenter

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

                        // ── FIXED: consistent color logic ──
                        color: {
                            if (root.icon !== "") {
                                return root.taskDone ? Colours.palette.m3primary
                                                     : Colours.palette.m3onSurfaceVariant
                            }
                            if (root.taskDone) return Colours.palette.m3primary
                            if (root.taskPartial) return Colours.palette.m3secondary
                            return Colours.palette.m3outline
                        }
                        Behavior on color { CAnim {} }

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
                    elide: Text.ElideRight

                    // ── FIXED: proper done/undone colors ──
                    color: root.taskDone ? Colours.palette.m3primary
                                         : Colours.palette.m3onSurface
                    opacity: root.taskDone ? 0.6 : 1.0
                    Behavior on color { CAnim {} }
                    Behavior on opacity { Anim { type: Anim.DefaultEffects } }

                    // ── Strikethrough (only when done) ──
                    StyledRect {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.taskDone ? Math.min(parent.contentWidth, parent.width) : 0
                        height: 2
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary
                        opacity: root.taskDone ? 0.5 : 0
                        Behavior on width { Anim { type: Anim.FastSpatial } }
                        Behavior on opacity { CAnim {} }
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
                    text: root.taskTitle
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

                    function commit() {
                        if (commitInProgress || !root.isEditing)
                            return
                        commitInProgress = true
                        if (text.trim())
                            root.renameRequested(root.taskIndex, text)
                        else {
                            text = root.taskTitle
                            root.editingCancelled()
                        }
                    }

                    onVisibleChanged: {
                        if (visible) {
                            commitInProgress = false
                            forceActiveFocus()
                            selectAll()
                        }
                    }
                    onAccepted: commit()
                    Keys.onEscapePressed: {
                        commitInProgress = true
                        root.editingCancelled()
                        text = root.taskTitle
                    }
                    onFocusChanged: if (!focus) commit()
                }

                // ── Spacer ──────────────────────────────────────
                Item { Layout.fillWidth: true }

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
                        Behavior on color { CAnim {} }
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
                            Behavior on width { Anim {} }
                            Behavior on color { CAnim {} }
                        }
                    }
                }

                // ── Streak (habits only) ────────────────────────
                RowLayout {
                    id: streakBadge
                    visible: root.showStreak && !root.isEditing
                        Layout.preferredWidth: 48
                    Layout.leftMargin: Tokens.spacing.small
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    MaterialIcon {
                        text: "local_fire_department"
                        fill: 1
                        fontStyle: Tokens.font.icon.small
                        color: {
                            if (root.streak >= 20) return '#fe1d1d'
                            if (root.streak >= 10) return "#FF8C00"
                            if (root.streak >= 3)  return "#FFA500"
                            if (root.streak >= 1)  return Colours.palette.m3primary
                            return Colours.palette.m3outlineVariant
                        }
                        Behavior on color { CAnim { duration: 300 } }
                    }
                    StyledText {
                        text: String(root.streak)
                        font: Tokens.font.label.medium
                        // font.weight: Font.Bold
                        color: {
                            if (root.streak >= 20) return '#fe1d1d'
                            if (root.streak >= 10) return "#FF8C00"
                            if (root.streak >= 3)  return "#FFA500"
                            if (root.streak >= 1)  return Colours.palette.m3primary
                            return Colours.palette.m3outlineVariant
                        }
                        Behavior on color { CAnim { duration: 300 } }
                    }
                }

                // ── Actions ─────────────────────────────────────
                RowLayout {
                    visible: !root.isEditing
                    spacing: 0
                    Layout.preferredWidth: 48
                    opacity: (rowHover.hovered || root.isSelected) ? 1 : 0.3
                    Behavior on opacity { Anim { type: Anim.DefaultEffects } }

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
                    model: root.subOrder
                    delegate: SubtaskCard {
                        required property string modelData
                        required property int index

                        readonly property var sub: root.subtaskMap[modelData] ?? {
                            id: modelData, title: "", done: false
                        }
                        readonly property int subIdx: index

                        taskData: root.taskData
                        taskIndex: root.taskIndex
                        subtaskData: sub
                        subtaskIndex: subIdx
                        subtaskId: modelData

                        isEditing: root.editingSubId === modelData
                        isSelected: root.isSelected && root.selectedSubtaskIndex === subIdx

                        isFirst: index === 0
                        isLast: index === subRepeater.count - 1
                        hasChildren: false
                        depth: 1

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
                        opacity: 0.6
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 18
                    }

                    StyledTextField {
                        placeholderFloats: false
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28

                        font: {
                            body: Tokens.font.body.medium
                            pointSize: 11
                        }

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

                        onAccepted: {
                            if (text.trim()) {
                                root.addSubtaskRequested(root.taskIndex, text)
                                clear()
                            }
                        }
                        Keys.onEscapePressed: {
                            clear()
                            focus = false
                        }
                    }
                }
            }
        }
    }
}