pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    required property var taskData        
    required property int taskIndex
    required property var subtaskData     
    required property int subtaskIndex  
    required property string subtaskId    
    required property bool isEditing

    // ── New Properties for Tree Lines ──────────────────────────
    property bool isFirst: false      // Is this the first subtask?
    property bool isLast: false       // Is this the last subtask?
    property bool hasChildren: false  // Does this subtask have children?
    property int depth: 1             // Nesting level (for future expansion)

    signal toggleRequested(int taskIdx, int subIdx)
    signal deleteRequested(int taskIdx, int subIdx)
    signal renameRequested(int taskIdx, int subIdx, string newTitle)
    signal editingStarted(string subtaskId)
    signal editingCancelled()

    readonly property bool isDone: root.subtaskData?.done ?? false
    readonly property string title: root.subtaskData?.title ?? ""

    readonly property string editId: `${root.taskData.todoId}__${root.subtaskId}`

    implicitHeight: subRow.implicitHeight
    Layout.fillWidth: true

    HoverHandler { id: subRowHover }

    // ── Tree Line Container ─────────────────────────────────────
    Item {
        id: treeContainer
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
        }
        width: Tokens.padding.extraLarge + Tokens.spacing.small

        // ── Vertical Line (connects subtasks vertically) ──
        StyledRect {
            id: verticalLine
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }
            width: 2
            color: root.isDone ? Colours.palette.m3primary : Colours.palette.m3outlineVariant
            opacity: root.isDone ? 0.6 : 0.3
            
            visible: !root.isFirst || !root.isLast
            anchors.topMargin: 0
            anchors.bottomMargin: root.isLast ? parent.height / 2 : 0
            
            Behavior on color { CAnim {} }
        }

        // ── Horizontal Line (connects vertical line to subtask) ──
        StyledRect {
            id: horizontalLine
            anchors {
                left: verticalLine.right
                verticalCenter: parent.verticalCenter
            }
            width: Tokens.padding.extraLarge - Tokens.spacing.small
            height: 2
            color: root.isDone ? Colours.palette.m3primary : Colours.palette.m3outlineVariant
            opacity: root.isDone ? 0.6 : 0.3
            
            visible: true
            Behavior on color { CAnim {} }
        }

        // ── Node Circle (at connection point) ──────────────────
        StyledRect {
            anchors {
                left: horizontalLine.right
                verticalCenter: parent.verticalCenter
            }
            width: 6
            height: 6
            radius: 3
            color: root.isDone ? Colours.palette.m3primary : Colours.palette.m3outlineVariant
            opacity: 0.5
            Behavior on color { CAnim {} }
        }
    }

    RowLayout {
        id: subRow
        anchors.left: treeContainer.right
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: root.isDone ? "check_box" : "check_box_outline_blank"
            fill: root.isDone ? 1 : 0
            fontStyle: Tokens.font.icon.small
            color: root.isDone ? Colours.palette.m3primary : Colours.palette.m3outline
            Behavior on color { CAnim {} }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleRequested(root.taskIndex, root.subtaskIndex)
            }
        }

        StyledText {
            visible: !root.isEditing
            Layout.fillWidth: true
            text: root.title
            font: Tokens.font.body.medium
            color: root.isDone ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            elide: Text.ElideRight
            Behavior on color { CAnim {} }

            // Strikethrough overlay
            StyledRect {
                anchors.verticalCenter: parent.verticalCenter
                width: root.isDone ? Math.min(parent.contentWidth, parent.width) : 0
                height: 2
                radius: Tokens.rounding.full
                color: Colours.palette.m3outline    
                Behavior on width { Anim { type: Anim.FastSpatial } }
            }
        }

        // ── Edit Field ──────────────────────────────────────────
        StyledTextField {
            visible: root.isEditing
            Layout.fillWidth: true
            text: root.title
            font: Tokens.font.body.medium
            
            // Match the non-editing text style
            background: Rectangle {
                color: "transparent"
                border.width: 0
            }
            
            leftPadding: 0
            rightPadding: 0
            topPadding: 0
            bottomPadding: 0
            verticalAlignment: Text.AlignVCenter

            onVisibleChanged: {
                if (visible) {
                    forceActiveFocus()
                    selectAll()
                }
            }

            onAccepted: {
                if (text.trim()) {
                    root.renameRequested(root.taskIndex, root.subtaskIndex, text)
                } else {
                    text = root.title
                    root.editingCancelled()
                }
            }

            Keys.onEscapePressed: {
                root.editingCancelled()
                text = root.title
            }
            onFocusChanged: if (!focus && root.isEditing) { root.renameRequested(root.taskIndex, root.subtaskIndex, text) }
        }

        // ── Action Buttons ──────────────────────────────────────
        RowLayout {
            visible: !root.isEditing
            spacing: 0
            opacity: subRowHover.hovered ? 1 : 0
            Behavior on opacity { Anim { type: Anim.DefaultEffects } }

            IconButton {
                type: IconButton.Text
                font: Tokens.font.icon.small
                icon: "edit"
                // onClicked: root.editingStarted(root.editId)
                onClicked: root.editingStarted(root.subtaskId)  // ✅ Just "789012"

            }

            IconButton {
                id: subDeleteButton
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
                        subDeleteButton.clicked()
                    }
                    
                    onDoubleClicked: {
                        root.deleteRequested(root.taskIndex, root.subtaskIndex)
                    }
                }
                        
                        // ── Shake Animation ──────────────────────────────────────
                        SequentialAnimation {
                            id: shakeAnim
                            onFinished: {
                                subDeleteButton.isShaking = false
                                subDeleteButton.rotation = 0  // Reset rotation
                            }
                            
                            // Shake 2 times
                            PropertyAnimation {
                                target: subDeleteButton
                                property: "rotation"
                                from: -8
                                to: 8
                                duration: 80
                            }
                            PropertyAnimation {
                                target: subDeleteButton
                                property: "rotation"
                                from: 8
                                to: -8
                                duration: 80
                            }
                            PropertyAnimation {
                                target: subDeleteButton
                                property: "rotation"
                                from: -8
                                to: 8
                                duration: 80
                            }
                            PropertyAnimation {
                                target: subDeleteButton
                                property: "rotation"
                                from: 8
                                to: -8
                                duration: 80
                            }
                            PropertyAnimation {
                                target: subDeleteButton
                                property: "rotation"
                                from: -4
                                to: 4
                                duration: 50
                            }
                            PropertyAnimation {
                                target: subDeleteButton
                                property: "rotation"
                                from: 4
                                to: 0
                                duration: 50
                            }
                        }
                    
            }
        }
    }
}