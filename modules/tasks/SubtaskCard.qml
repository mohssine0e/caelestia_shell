pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "TitleParse.js" as TitleParse
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
    property string editingNestedId: ""
    // Scope cursor from TaskList: which nested row (if any) is highlighted
    // while this subtask is selected (-1 = this row itself).
    property int selectedNestedIndex: -1
    property bool isSelected: false
    property bool isHabitList: false

    property bool isFirst: false
    property bool isLast: false
    property bool hasChildren: false
    property int depth: 1

    property bool expanded: false

    // Expansion is owned by TaskNavigationController when one is wired in
    // (falls back to the local property otherwise).
    property var nav: null
    readonly property bool effectiveExpanded:
        root.nav ? (root.nav.expandedSubtasks[`${root.taskData?.todoId}/${root.subtaskId}`] ?? false) : root.expanded

    // Expansion toggle routed through the controller when wired in.
    function setExpanded(v) {
        if (root.nav)
            root.nav.setSubExpanded(root.taskData?.todoId ?? "", root.subtaskId, v)
        else
            root.expanded = v
    }

    // ── Add-child state ─────────────────────────────────────────
    property bool addingChild: false

    signal addChildRequested(int taskIdx, int subIdx, string title)
    signal addChildCancelled(int taskIdx, int subIdx)
    signal toggleNestedRequested(int taskIdx, int subIdx, int nestedIdx)
    signal deleteNestedRequested(int taskIdx, int subIdx, int nestedIdx)
    signal renameNestedRequested(int taskIdx, int subIdx, int nestedIdx, string newTitle)
    signal nestedEditingStarted(string nestedId)
    signal nestedEditingCancelled()

    // Dynamic: show the section when there is real data or a pending add field.
    // (Previously a static 2-row preview.)
    readonly property var nestedChildren: root.subtaskData?.children ?? []
    readonly property bool effectiveHasChildren:
        root.hasChildren || root.nestedChildren.length > 0 || root.addingChild
    readonly property int visibleChildCount:
        (root.effectiveHasChildren && root.effectiveExpanded) ? Math.max(root.nestedChildren.length, root.addingChild ? 1 : 0) : 0

    // ╔════════════════════════════════════════════════════════════╗
    // ║  TREE STYLE                                                ║
    // ╚════════════════════════════════════════════════════════════╝
    readonly property var tree: QtObject {
        readonly property real lineWidth: 2
        readonly property real cornerRadius: 8
        readonly property real spineX: 6
        readonly property real elbowLength: 24
        readonly property real contentGap: 6
        readonly property real dotSize: 6
        readonly property real dotOpacity: 1
        readonly property color color: Colours.palette.m3primary
        readonly property real selectedContentShift: 15
    }

    // ── Derived tree geometry ───────────────────────────────────
    readonly property real contentStartX:
        tree.spineX + tree.elbowLength + tree.contentGap
    readonly property real childSpineX:
        Math.round(contentStartX + parentCheckbox.x + parentCheckbox.width / 2)
    // Where a child's content (checkbox) would sit
    readonly property real childContentX:
        childSpineX + tree.elbowLength + tree.contentGap

    signal toggleRequested(int taskIdx, int subIdx)
    signal deleteRequested(int taskIdx, int subIdx)
    signal renameRequested(int taskIdx, int subIdx, string newTitle)
    signal editingStarted(string subtaskId)
    signal editingCancelled()
    signal selectionRequested(int taskIdx, int subIdx)

    readonly property bool isDone: root.subtaskData?.done ?? false
    readonly property string title: root.subtaskData?.title ?? ""

    onSubtaskIdChanged: {
        root.addingChild = false
    }

    readonly property string editId: `${root.taskData.todoId}__${root.subtaskId}`
    readonly property string editPrefill: `${root.title} @${root.subtaskData?.minutes || 0}`

    implicitHeight: mainCol.implicitHeight
    Layout.fillWidth: true

    // ── TREE LINES ──────────────────────────────────────────────
    TreeConnector {
        anchors.fill: parent
        rowHeight: rowContainer.height
        spineX: root.tree.spineX
        isLast: root.isLast
        // showDot: !root.effectiveHasChildren
        showDot: true
        selected: root.isSelected

        lineWidth: root.tree.lineWidth
        cornerRadius: root.tree.cornerRadius
        elbowLength: root.tree.elbowLength
        lineColor: root.tree.color
        dotSize: root.tree.dotSize
        dotOpacity: root.tree.dotOpacity
    }

    ColumnLayout {
        id: mainCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        // ── THIS ROW ────────────────────────────────────────────
        Item {
            id: rowContainer
            Layout.fillWidth: true
            implicitHeight: subRow.implicitHeight

            HoverHandler { id: subRowHover }

            // ── Content Row ─────────────────────────────────────
            RowLayout {
                id: subRow
                anchors.left: parent.left
                anchors.leftMargin: root.contentStartX
                                    + (root.isSelected ? root.tree.selectedContentShift : 0)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Tokens.spacing.small

                Behavior on anchors.leftMargin { Anim { type: Anim.FastSpatial } }

                // ── Checkbox ────────────────────────────────────
                MaterialIcon {
                    id: parentCheckbox
                    text: root.effectiveHasChildren
                        ? (root.isDone ? "check_box" : "check_box_outline_blank")
                        : (root.isDone ? "check_circle" : "radio_button_unchecked")
                    fill: root.isDone ? 1 : 0
                    font: Tokens.font.icon.small
                    color: (!root.effectiveHasChildren && !root.isDone)
                            ? Colours.palette.m3onSurface
                            : Colours.palette.m3primary
                    opacity: root.isDone ? 0.5 : 1
                    Behavior on color { CAnim {} }

                    MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: root.effectiveHasChildren ? Qt.ArrowCursor : Qt.PointingHandCursor
                    enabled: !root.effectiveHasChildren
                    onClicked: {
                        if (!root.effectiveHasChildren) {
                            root.toggleRequested(root.taskIndex, root.subtaskIndex)
                            root.selectionRequested(root.taskIndex, root.subtaskIndex)
                        }
                    }
}
                }

                // ── Title ───────────────────────────────────────
                StyledText {
                    visible: !root.isEditing
                    Layout.fillWidth: true
                    text: root.title
                    font: Tokens.font.body.medium
                    elide: root.isSelected ? Text.ElideNone : Text.ElideRight
                    wrapMode: root.isSelected ? Text.Wrap : Text.NoWrap

                    color: root.isDone ? Colours.palette.m3onSurfaceVariant
                        : (root.effectiveHasChildren ? Colours.palette.m3primary : Colours.palette.m3onSurface)
                    opacity: root.isDone ? 0.6 : 1
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
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.effectiveHasChildren) {
                                root.setExpanded(!root.effectiveExpanded)
                            } else {
                                root.selectionRequested(root.taskIndex, root.subtaskIndex)
                            }
                        }
                    }
                }

                // ── Edit Field ──────────────────────────────────
                StyledTextField {
                    visible: root.isEditing
                    Layout.fillWidth: true
                    text: root.editPrefill
                    font: Tokens.font.body.medium
                    property bool commitInProgress: false

                    background: Rectangle { color: "transparent"; border.width: 0 }
                    leftPadding: 0
                    rightPadding: 0
                    topPadding: 0
                    bottomPadding: 0
                    verticalAlignment: Text.AlignVCenter

                    function commitEdit() {
                        if (commitInProgress || !root.isEditing) return
                        commitInProgress = true
                        focus = false
                        if (TitleParse.hasTitle(text))
                            root.renameRequested(root.taskIndex, root.subtaskIndex, text)
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
                            if (root.title.length > 0 && text.length > root.title.length)
                                select(0, root.title.length)
                            else
                                selectAll()
                        }
                    }
                    onAccepted: commitEdit()
                    Keys.onPressed: event => {
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
                        event.accepted = true
                    }
                    onFocusChanged: {
                        if (!focus && root.isEditing && !commitInProgress)
                            commitEdit()
                    }
                }

                // ── Estimated time chip ─────────────────────────
                RowLayout {
                    visible: !root.isHabitList && !root.isEditing && (root.subtaskData?.minutes || 0) > 0
                    Layout.alignment: Qt.AlignVCenter

                    StyledRect {
                        implicitHeight: 20
                        implicitWidth: subMinutesLabel.implicitWidth + Tokens.padding.small * 2
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3surfaceContainerHighest

                        StyledText {
                            id: subMinutesLabel
                            anchors.centerIn: parent
                            text: `${root.subtaskData?.minutes || 0}m`
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }

                // ── Action Buttons ──────────────────────────────
                RowLayout {
                    visible: !root.isEditing
                    spacing: 0
                    opacity: (subRowHover.hovered || root.isSelected) ? 1 : 0.3
                    Behavior on opacity { Anim { type: Anim.DefaultEffects } }

                    // Add-child button
                    IconButton {
                        type: IconButton.Text
                        font: Tokens.font.icon.small
                        icon: "add"
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectionRequested(root.taskIndex, root.subtaskIndex)
                                root.setExpanded(true)
                                root.addingChild = true
                                addChildField.focus=true
                            }
                        }
                    }

                    // Edit button
                    IconButton {
                        type: IconButton.Text
                        font: Tokens.font.icon.small
                        icon: "edit"
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectionRequested(root.taskIndex, root.subtaskIndex)
                                root.editingStarted(root.editId)
                            }
                        }
                    }

                    // Delete button
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
                            PropertyAnimation { target: subDeleteButton; property: "rotation"; from: -8; to: 8; duration: 80 }
                            PropertyAnimation { target: subDeleteButton; property: "rotation"; from: 8; to: -8; duration: 80 }
                            PropertyAnimation { target: subDeleteButton; property: "rotation"; from: -8; to: 8; duration: 80 }
                            PropertyAnimation { target: subDeleteButton; property: "rotation"; from: 8; to: -8; duration: 80 }
                            PropertyAnimation { target: subDeleteButton; property: "rotation"; from: -4; to: 4; duration: 50 }
                            PropertyAnimation { target: subDeleteButton; property: "rotation"; from: 4; to: 0; duration: 50 }
                        }
                    }
                }
            }
        }

        // ── NESTED ROWS (dynamic: one level from subtaskData.children) ──
        ColumnLayout {
            id: nestedColumn
            Layout.fillWidth: true
            Layout.leftMargin: root.isSelected ? root.tree.selectedContentShift : 0
            Behavior on Layout.leftMargin { Anim { type: Anim.FastSpatial } }
            Layout.topMargin: 0
            spacing: 0
            visible: root.effectiveHasChildren && root.effectiveExpanded

            Repeater {
                id: nestedRepeater
                model: root.nestedChildren

                delegate: NestedSubtaskCard {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    nestedData: modelData
                    nestedIndex: index
                    parentSubtaskData: root.subtaskData
                    parentSubtaskId: root.subtaskId
                    taskIndex: root.taskIndex
                    subtaskIndex: root.subtaskIndex
                    isHabitList: root.isHabitList
                    isSelected: root.isSelected && root.selectedNestedIndex === index
                    isEditing: root.editingNestedId === (modelData?.id ?? "")
                    isFirst: index === 0
                    isLast: index === nestedRepeater.count - 1
                    tree: root.tree
                    treeSpineX: root.childSpineX

                    onToggleRequested: (taskIdx, subIdx, nestedIdx) => {
                        root.toggleNestedRequested(taskIdx, subIdx, nestedIdx)
                    }
                    onDeleteRequested: (taskIdx, subIdx, nestedIdx) => {
                        root.deleteNestedRequested(taskIdx, subIdx, nestedIdx)
                    }
                    onRenameRequested: (taskIdx, subIdx, nestedIdx, newTitle) => {
                        root.renameNestedRequested(taskIdx, subIdx, nestedIdx, newTitle)
                    }
                    onEditingStarted: (nestedId) => {
                        root.nestedEditingStarted(nestedId)
                    }
                    onEditingCancelled: {
                        root.nestedEditingCancelled()
                    }
                }
            }

            // ── Add-child inline input ──────────────────────────
            RowLayout {
                visible: root.addingChild
                Layout.fillWidth: true
                Layout.leftMargin: root.childContentX
                Layout.topMargin: 0


                MaterialIcon {
                    text: "add_circle_outline"
                    font: Tokens.font.icon.small
                    color: Colours.palette.m3primary
                    opacity: 0.6
                }

                StyledTextField {
                    id: addChildField
                    placeholderFloats: false
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    placeholderText: qsTr("Add nested subtask…")
                    placeholderTextColor: Colours.palette.m3onSurfaceVariant
                    color: Colours.palette.m3onSurfaceVariant

                    background: Rectangle { color: "transparent"; border.width: 0 }

                    topPadding: 2
                    bottomPadding: 2
                    leftPadding: 5
                    rightPadding: 5


                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            // Ignore pure "@minutes" input — it has no title.
                            if (TitleParse.hasTitle(text)) {
                                root.addChildRequested(root.taskIndex, root.subtaskIndex, text)
                                clear()
                            }
                            event.accepted = true
                        }
                    }
                    Keys.onEscapePressed:{
                        clear()
                        focus = false
                        root.addingChild = false
                        root.addChildCancelled(root.taskIndex, root.subtaskIndex)
                    }
                    onVisibleChanged: {
                        if (visible) {
                            clear()
                            forceActiveFocus()
                        }
                    }
                }
            }
        }
    }
}