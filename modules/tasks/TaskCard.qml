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

Item {
    id: root

    // ── Required Properties ─────────────────────────────────────
    required property var taskData        // The task object
    required property int taskIndex       // Index in tasks array
    required property bool isEditing      // Whether task is being edited
    required property bool expanded       // Whether task is expanded
    required property bool isSelected     // Whether task is selected
    required property int nSub            // Number of subtasks
    required property int dSub            // Number of done subtasks
    required property var subOrder        // Ordered list of subtask IDs
    required property real prog           // Progress (0-1)

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
    readonly property string taskTitle: root.taskData?.task ?? ""
    readonly property bool taskDone: root.taskData?.done ?? false
    readonly property var subtasks: root.taskData?.subtasks ?? []

    readonly property var subtaskMap: {
        const map = {};
        if (task && task.subtasks) {
            for (const sub of task.subtasks) {
                map[sub.id] = sub;
            }
        }
        return map;
    }

    property string icon: ""  // If provided, show icon instead of checkbox

    // this is a ScriptModel that holds the ordered list of subtask IDs for the Repeater
    property var subOrderModel: {
        const model = Qt.createQmlObject('import QtQuick 2.0; ListModel {}', root)
        for (const id of root.subOrder) {
            model.append({ id: id })
        }
        return model
    }

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

        // opacity: root.taskDone ? 0.65 : 1
        Behavior on opacity { Anim { type: Anim.DefaultEffects } }

        implicitHeight: rowCol.implicitHeight + Tokens.padding.small * 2
        Behavior on implicitHeight { Anim { type: Anim.FastSpatial } }
        Behavior on color { CAnim {} }




        HoverHandler { id: rowHover }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.forceActiveFocus()
            }
            onDoubleClicked: root.toggleExpandRequested(root.taskIndex)
        }

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
                    opacity: root.nSub > 0 ? 1
                           : (rowHover.hovered || root.isSelected) ? 0.5 : 0
                    Behavior on opacity { Anim { type: Anim.DefaultEffects } }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleExpandRequested(root.taskIndex)
                    }
                }

               // ── Icon or Checkbox ────────────────────────────────────────
Item {
    Layout.preferredWidth: root.icon ? 60 : 24
    Layout.preferredHeight: 24
    
    // Icon + Checkbox (for habits)
    RowLayout {
        id: iconRow
        anchors.fill: parent
        spacing: Tokens.spacing.small
        visible: root.icon !== ""
        
        StyledRect {
            implicitWidth: 36
            implicitHeight: 36
            radius: Tokens.rounding.medium
            color: root.taskDone ? Colours.tPalette.m3primaryContainer : Colours.tPalette.m3surfaceContainerHigh
            Behavior on color { CAnim {} }
            
            MaterialIcon {
                anchors.centerIn: parent
                text: root.icon
                fontStyle: Tokens.font.icon.medium
                color: root.taskDone ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                Behavior on color { CAnim {} }
            }
        }
        
        MaterialIcon {
            text: root.taskDone ? "check_circle" : "radio_button_unchecked"
            fill: root.taskDone ? 1 : 0
            fontStyle: Tokens.font.icon.medium
            color: root.taskDone ? Colours.palette.m3tertiary : Colours.palette.m3outline
            Behavior on color { CAnim {} }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleRequested(root.taskIndex)
            }
        }
    }
    
    // Checkbox only (for regular tasks)
    MaterialIcon {
        id: checkboxOnly
        anchors.fill: parent
        visible: root.icon === ""
        text: root.taskDone ? "check_box"
            : (root.nSub > 0 && root.dSub > 0) ? "indeterminate_check_box"
            : "check_box_outline_blank"
        fill: root.taskDone ? 1 : 0
        fontStyle: Tokens.font.icon.medium
        color: root.taskDone ? Colours.palette.m3tertiary : Colours.palette.m3primary
        Behavior on color { CAnim {} }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleRequested(root.taskIndex)
        }
    }
}



                // Title
                StyledText {
                    visible: !root.isEditing
                    Layout.fillWidth: true
                    text: root.taskTitle
                    font: Tokens.font.body.large
                    color: root.taskDone ? Colours.palette.m3outline : Colours.palette.m3onSurface
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

                // Edit Field
                StyledTextField {
                    visible: root.isEditing
                    Layout.fillWidth: true
                    text: root.taskTitle
                    font: Tokens.font.body.large
                    onVisibleChanged: if (visible) { forceActiveFocus(); selectAll(); }
                    onAccepted: root.renameRequested(root.taskIndex, text)
                    Keys.onEscapePressed: {
                        root.editingCancelled()
                        text = root.taskTitle
                    }
                }

                // Progress
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
                            color: Colours.palette.m3tertiary
                            Behavior on width { Anim {} }
                        }
                    }
                }

                // Actions
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
                        type: IconButton.Text
                        font: Tokens.font.icon.small
                        icon: "delete_outline"
                        onClicked: root.deleteRequested(root.taskIndex)
                    }
                }
            }

            // ── Subtasks ────────────────────────────────────────
            ColumnLayout {
                visible: root.expanded
                Layout.fillWidth: true
                // Layout.leftMargin: Tokens.padding.extraLarge
                Layout.leftMargin: 40
                spacing: 0

                // ── Subtask Repeater ────────────────────────────
                Repeater {
                    id: subRepeater
                    model: root.subOrderModel
                    delegate: SubtaskCard {
                        required property string modelData
                        required property int index

                        readonly property var sub: root.subtaskMap[modelData] ??{
                            id: modelData, title: "", done: false
                        }
                        readonly property int subIdx: index
                        
                        taskData: root.taskData
                        taskIndex: root.taskIndex
                        subtaskData: sub
                        subtaskIndex: subIdx
                        subtaskId: modelData
                        isEditing: false

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


                        font:{
                            body: Tokens.font.body.medium
                            pointSize:11
                        } 
                        

                        placeholderText: qsTr("Add subtask…")
                        placeholderTextColor: Colours.palette.m3onSurfaceVariant  // ← Set placeholder color

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