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
data model used: for both tasks and habits
{
    todoId: string,
    title: string,
    done: bool,
    icon: string | null, // optional
    minutes: int,
    priority: int,
    
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
    required property var taskData        // The task object
    required property int taskIndex       // Index in tasks array
    required property bool isEditing      // Whether task is being edited
    property bool expanded: false        // Independent per-card state
    required property bool isSelected     // Whether task is selected
    required property int nSub            // Number of subtasks
    required property int dSub            // Number of done subtasks
    required property var subOrder        // Ordered list of subtask IDs
    required property real prog           // Progress (0-1)

    // ── Additional Property for Subtask Editing ──────────────
    property string editingSubId: ""      // ID of subtask being edited (passed from parent)

    // Double-click handler
    MouseArea {
        anchors.fill: parent
        onClicked: root.forceActiveFocus()
        onDoubleClicked: {
            root.toggleExpandRequested(root.taskIndex)
        }
    }

    // ── Signals ──────────────────────────────────────────────────
    signal toggleRequested(int taskIdx)
    signal toggleExpandRequested(int taskIdx)
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

    // ── Layout ──────────────────────────────────────────────────
    Layout.fillWidth: true
    implicitHeight: rowBg.implicitHeight

    // ── Internal State ──────────────────────────────────────────
    readonly property string taskId: root.taskData?.todoId ?? ""
    readonly property string taskTitle: root.taskData?.title ?? ""
    readonly property bool taskDone: root.taskData?.done ?? false
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

    property string icon: ""  // If provided, show icon instead of checkbox

    // ── Main Card ──────────────────────────────────────────────
    StyledRect {
        id: rowBg
        width: parent.width
        radius: Tokens.rounding.small
        color: root.isSelected ? Colours.tPalette.m3surfaceContainerHigh
             : rowHover.hovered ? Colours.tPalette.m3surfaceContainer
             : Colours.tPalette.m3surfaceContainerLow
        border.width: root.isSelected ? 2 : 0
        border.color: Colours.palette.m3primary

        Behavior on opacity { Anim { type: Anim.DefaultEffects } }

        // implicitHeight: rowCol.implicitHeight + Tokens.padding.small * 2
        implicitHeight:rowCol.implicitHeight + Tokens.padding.small * 2
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
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                // Expander
                MaterialIcon {
                    text: root.expanded ? "keyboard_arrow_down" : "keyboard_arrow_right"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
                    Behavior on opacity { Anim { type: Anim.DefaultEffects } }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleExpandRequested(root.taskIndex)
                    }
                }

                // ── Icon or Checkbox ───────────────────────────
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
                        visible: true
                        
                        // ── Show icon if present, otherwise checkbox ──
                        text: {
                            if (root.icon === "" || root.icon === null || root.icon === "block") {
                                // No icon → show checkbox/circle
                                if (root.nSub > 0) {
                                    return root.taskDone ? "check_box"
                                        : (root.dSub > 0 && root.dSub < root.nSub) ? "indeterminate_check_box"
                                        : "check_box_outline_blank"
                                } else {
                                    return root.taskDone ? "check_circle" : "radio_button_unchecked"
                                }
                            }else {
                                // Show the provided icon
                                return root.icon
                            }
                        }
                        
                        fill: root.taskDone ? 1 : 0
                        
                        fontStyle: root.icon !== "" ? Tokens.font.icon.medium : Tokens.font.icon.medium
                        color: {
                            if (root.icon !== "") {
                                // Icon color - primary when done, normal when not
                                return root.taskDone ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            } else {
                                // Checkbox color
                                return root.taskDone ? Colours.palette.m3primary : Colours.palette.m3outline
                            }
                        }
                        Behavior on color { CAnim {} }
                        
                        // ── Click handler ────────────────────────────
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: root.nSub > 0 ? Qt.ArrowCursor : Qt.PointingHandCursor
                            enabled: root.nSub === 0  // Disabled when has subtasks
                            onClicked: {
                                if (root.nSub === 0) {
                                    root.toggleRequested(root.taskIndex)
                                }
                            }
                        }
                        
                    }
                }

                // ── Title ──────────────────────────────────────
                StyledText {
                    visible: !root.isEditing
                    Layout.fillWidth: true
                    text: root.taskTitle
                    font: Tokens.font.body.large
                    color: root.taskDone ? Colours.palette.m3primary : Colours.palette.m3onSurface
                    elide: Text.ElideRight
                    Behavior on color { CAnim {} }

                    StyledRect {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.taskDone ? Math.min(parent.contentWidth, parent.width) : 0
                        height: 2
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3outline
                        Behavior on width { Anim { type: Anim.FastSpatial } }
                    }
                }

                // ── Edit Field ──────────────────────────────────
                StyledTextField {
                    visible: root.isEditing
                    Layout.fillWidth: true
                    text: root.taskTitle
                    font: Tokens.font.body.large
                    
                    background: Rectangle {
                        color: "transparent"
                        border.width: 0
                    }
                    
                    leftPadding: 0
                    rightPadding: 0
                    topPadding: 0
                    bottomPadding: 0
                    verticalAlignment: Text.AlignVCenter
                    
                    onVisibleChanged: if (visible) { forceActiveFocus(); selectAll(); }
                    onAccepted: root.renameRequested(root.taskIndex, text)
                    Keys.onEscapePressed: {
                        root.editingCancelled()
                        text = root.taskTitle
                    }
                    onFocusChanged: if (!focus && root.isEditing) { root.renameRequested(root.taskIndex, text) }
                }

                // ── Progress ────────────────────────────────────
                RowLayout {
                    visible: root.nSub > 0 && !root.isEditing
                    spacing: Tokens.spacing.small
                    StyledText {
                        text: `${root.dSub} / ${root.nSub}`
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                    StyledRect {
                        implicitWidth: 128
                        implicitHeight: 6
                        radius: Tokens.rounding.full
                        color: Colours.tPalette.m3surfaceContainerHighest

                        StyledRect {
                            width: parent.width * root.prog
                            height: parent.height
                            radius: parent.radius
                            color: Colours.palette.m3primary
                            Behavior on width { Anim {} }
                        }
                    }
                }

                // ── Actions ─────────────────────────────────────
                RowLayout {
                    visible: !root.isEditing
                    spacing: 0
                    opacity: (rowHover.hovered || root.isSelected) ? 1 : 0
                    Behavior on opacity { Anim { type: Anim.DefaultEffects } }

                    IconButton {
                        type: IconButton.Text
                        font: Tokens.font.icon.small
                        icon: "edit"
                        onClicked: root.editingStarted(root.taskId)
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
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            
                            onClicked: {
                                deleteButton.clicked()
                            }
                            
                            onDoubleClicked: {
                                // Handle double click for delete
                                root.deleteRequested(root.taskIndex)
                            }
                        }
                        
                        // ── Shake Animation ──────────────────────────────────────
                        SequentialAnimation {
                            id: shakeAnim
                            onFinished: {
                                deleteButton.isShaking = false
                                deleteButton.rotation = 0  // Reset rotation
                            }
                            
                            // Shake 2 times
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
                Layout.leftMargin: 40
                spacing: 0

                // ── Subtask Repeater ────────────────────────────
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