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

    // ── Indent scaling by depth ─────────────────────────────────
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
    readonly property int streak: root.subtaskData?.streak ?? 0

    readonly property string editId: `${root.taskData.todoId}__${root.subtaskId}`

    // ── Tree line color logic ───────────────────────────────────
    readonly property color lineColor: {
        if (root.isDone) return Colours.palette.m3primary
        if (root.isSelected) return Colours.palette.m3secondary
        return Colours.palette.m3outlineVariant
    }
    readonly property real lineOpacity: {
        if (root.isDone) return 1.0
        if (root.isSelected) return 0.6
        return 0.3
    }

    // ── Content color logic ─────────────────────────────────────
    readonly property color contentColor: {
        if (root.isDone) return Colours.palette.m3primary
        if (root.isSelected) return Colours.palette.m3secondary
        return Colours.palette.m3onSurfaceVariant
    }
    readonly property real contentOpacity: root.isDone ? 0.6 : 1.0

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

        // ── Vertical Line ──────────────────────────────────────
        StyledRect {
            id: verticalLine
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }
            width: 1
            color: root.lineColor
            opacity: root.lineOpacity
            visible: !root.isFirst || !root.isLast
            anchors.topMargin: 0
            anchors.bottomMargin: root.isLast ? parent.height / 2 : 0
            Behavior on color { CAnim {} }
            Behavior on opacity { CAnim {} }
        }

        // ── Horizontal Line ────────────────────────────────────
        StyledRect {
            id: horizontalLine
            anchors {
                left: verticalLine.right
                verticalCenter: parent.verticalCenter
            }
            width: Tokens.padding.extraLarge - Tokens.spacing.small
            height: 1
            color: root.lineColor
            opacity: root.lineOpacity
            Behavior on color { CAnim {} }
            Behavior on opacity { CAnim {} }
        }

        // ── Node Circle ────────────────────────────────────────
        StyledRect {
            anchors {
                left: horizontalLine.right
                verticalCenter: parent.verticalCenter
            }
            width: 6
            height: 6
            radius: 3
            color: root.lineColor
            opacity: root.lineOpacity
            Behavior on color { CAnim {} }
            Behavior on opacity { CAnim {} }
        }
    }

    // ── Content Row ─────────────────────────────────────────────
    RowLayout {
        id: subRow
        anchors.left: treeContainer.right
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacing.small

        // ── Checkbox ────────────────────────────────────────────
        MaterialIcon {
            text: root.isDone ? "check_box" : "check_box_outline_blank"
            fill: root.isDone ? 1 : 0
            fontStyle: Tokens.font.icon.small
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            color: root.contentColor
            opacity: root.isSelected || subRowHover.hovered ? 1.0 : (root.isDone ? 0.8 : 0.6)
            Behavior on color { CAnim {} }
            Behavior on opacity { CAnim {} }

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
            color: root.contentColor
            opacity: root.isSelected ? 1.0 : (subRowHover.hovered ? 0.85 : root.contentOpacity)
            elide: Text.ElideRight
            Behavior on color { CAnim {} }
            Behavior on opacity { CAnim {} }

            // Strikethrough
            StyledRect {
                anchors.verticalCenter: parent.verticalCenter
                width: root.isDone ? Math.min(parent.contentWidth, parent.width) : 0
                height: 2
                radius: Tokens.rounding.full
                color: Colours.palette.m3outline
                Behavior on width { Anim { type: Anim.FastSpatial } }
            }

            // Click to select
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectionRequested(root.taskIndex, root.subtaskIndex)
            }
        }

        // ── Streak (subtasks can have streaks too) ──────────────
        RowLayout {
            visible: root.streak > 0 && !root.isEditing
            Layout.preferredWidth: 48
            spacing: Tokens.spacing.extraSmall
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            opacity: root.isSelected ? 1 : 0.8
            Behavior on opacity { CAnim {} }

            MaterialIcon {
                text: "local_fire_department"
                fontStyle: Tokens.font.icon.small
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                color: root.isSelected ? Colours.palette.m3secondary : Colours.palette.m3primary
                Behavior on color { CAnim {} }
            }
            StyledText {
                text: String(root.streak)
                font: Tokens.font.label.small
                color: root.isSelected ? Colours.palette.m3secondary : Colours.palette.m3primary
                Behavior on color { CAnim {} }
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
            property bool commitInProgress: false

            function commit() {
                if (commitInProgress || !root.isEditing)
                    return
                commitInProgress = true
                if (text.trim())
                    root.renameRequested(root.taskIndex, root.subtaskIndex, text)
                else {
                    text = root.title
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
                text = root.title
            }
            onFocusChanged: if (!focus) commit()
        }

        // ── Action Buttons ──────────────────────────────────────
        RowLayout {
            visible: !root.isEditing
            Layout.preferredWidth: 48
            spacing: 0
            opacity: subRowHover.hovered || root.isSelected ? 1 : 0.3
            Behavior on opacity { Anim { type: Anim.DefaultEffects } }

            IconButton {
                type: IconButton.Text
                font: Tokens.font.icon.small
                icon: "edit"
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
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
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20

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