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
    property bool isSelected: false

    // ── Tree line properties ────────────────────────────────────
    property bool isFirst: false
    property bool isLast: false
    property bool hasChildren: false
    property int depth: 1

    // ── Indent scaling ──────────────────────────────────────────
    readonly property int indentUnit: 28
    readonly property int scaledIndent: root.depth * root.indentUnit

    signal toggleRequested(int taskIdx, int subIdx)
    signal deleteRequested(int taskIdx, int subIdx)
    signal renameRequested(int taskIdx, int subIdx, string newTitle)
    signal editingStarted(string subtaskId)
    signal editingCancelled()
    signal selectionRequested(int taskIdx, int subIdx)

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
        width: root.scaledIndent + Tokens.spacing.small

        // ── Vertical Line ───────────────────────────────────────
        StyledRect {
            id: verticalLine
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }
            width: 2
            color: Colours.palette.m3primary
            visible: !root.isFirst || !root.isLast
            anchors.topMargin: 0
            anchors.bottomMargin: root.isLast ? parent.height / 2 : 0
            Behavior on color { CAnim {} }
        }

        // ── Horizontal Line ─────────────────────────────────────
        StyledRect {
            id: horizontalLine
            anchors {
                left: verticalLine.right
                verticalCenter: parent.verticalCenter
            }
            width: Tokens.padding.extraLarge - Tokens.spacing.small+(root.isSelected?6:0)
            height: 2
            color: Colours.palette.m3primary
            Behavior on color { CAnim {} }
            Behavior on width { Anim { type: Anim.FastSpatial } }
        }

        // ── Node Dot ────────────────────────────────────────────
        StyledRect {
            id: nodeDot
            anchors {
                left: horizontalLine.right
                verticalCenter: parent.verticalCenter
            }
            width: root.isSelected ? 12 : 6
            height: root.isSelected ? 12 : 6
            radius: root.isSelected ? Tokens.rounding.full : Tokens.rounding.small
            color: Colours.palette.m3primary
            opacity: 0.8
            Behavior on color { CAnim {} }
            Behavior on width { Anim { type: Anim.FastSpatial } }
            Behavior on height { Anim { type: Anim.FastSpatial } }
        }
    }

    // ── Content Row ─────────────────────────────────────────────
    RowLayout {
        id: subRow
        anchors.left: treeContainer.right
        anchors.leftMargin: root.isSelected ? 9 : 0
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacing.small

        Behavior on anchors.leftMargin { Anim { type: Anim.FastSpatial } }
        // ── Checkbox ────────────────────────────────────────────
        MaterialIcon {
            text: root.isDone ? "check_box" : "check_box_outline_blank"
            fill: root.isDone ? 1 : 0
            fontStyle: Tokens.font.icon.small
            color: Colours.palette.m3primary
            opacity: root.isDone ? 0.5 : 1
            Behavior on color { CAnim {} }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.toggleRequested(root.taskIndex, root.subtaskIndex)
                    root.selectionRequested(root.taskIndex, root.subtaskIndex)
                }
            }
        }

        // ── Title ───────────────────────────────────────────────
        StyledText {
            visible: !root.isEditing
            Layout.fillWidth: true
            text: root.title
            font: Tokens.font.body.medium
            color: root.isDone ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3primary
            opacity: root.isDone ? 0.6 : 1
            elide: Text.ElideRight
            Behavior on color { CAnim {} }

            StyledRect {
                anchors.verticalCenter: parent.verticalCenter
                width: root.isDone ? Math.min(parent.contentWidth, parent.width) : 0
                height: 1
                radius: Tokens.rounding.full
                color: Colours.palette.m3outline
                Behavior on width { Anim { type: Anim.FastSpatial } }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectionRequested(root.taskIndex, root.subtaskIndex)
            }
        }


        // ── Edit Field ──────────────────────────────────────────
        StyledTextField {
            visible: root.isEditing
            Layout.fillWidth: true
            text: root.title
            font: Tokens.font.body.medium

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
            opacity: (subRowHover.hovered || root.isSelected) ? 1 : 0
            Behavior on opacity { Anim { type: Anim.DefaultEffects } }

            IconButton {
                type: IconButton.Text
                font: Tokens.font.icon.small
                icon: "edit"
                onClicked: {
                    root.selectionRequested(root.taskIndex, root.subtaskIndex)
                    root.editingStarted(root.editId)
                }
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
                    onClicked: subDeleteButton.clicked()
                    onDoubleClicked: root.deleteRequested(root.taskIndex, root.subtaskIndex)
                }

                SequentialAnimation {
                    id: shakeAnim
                    onFinished: {
                        subDeleteButton.isShaking = false
                        subDeleteButton.rotation = 0
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