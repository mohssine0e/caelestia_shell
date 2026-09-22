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

    required property var nestedData
    required property int nestedIndex
    required property var parentSubtaskData
    required property string parentSubtaskId
    required property int taskIndex
    required property int subtaskIndex
    property bool isHabitList: false
    property bool isSelected: false
    property bool isEditing: false

    property bool showStreak: false

    property bool isFirst: true
    property bool isLast: true

    signal toggleRequested(int taskIdx, int subIdx, int nestedIdx)
    signal deleteRequested(int taskIdx, int subIdx, int nestedIdx)
    signal renameRequested(int taskIdx, int subIdx, int nestedIdx, string newTitle)
    signal editingStarted(string nestedId)
    signal editingCancelled()

    // ── Tree settings come from SubtaskCard.qml ─────────────────
    // Don't edit tree look here — change the "TREE STYLE" block in
    // SubtaskCard.qml. `treeSpineX` = X of this child's spine (set to the
    // center of the parent's checkbox).
    required property var tree
    required property real treeSpineX

    // Where this row's content starts (same formula as the parent).
    readonly property real contentStartX: treeSpineX + tree.elbowLength + tree.contentGap

        readonly property bool isDone: root.nestedData?.done ?? false
    readonly property string nestedId: root.nestedData?.id ?? ""
    readonly property int streak: root.nestedData?.streak ?? 0
    readonly property int bestStreak: root.nestedData?.bestStreak ?? 0

    readonly property color streakColor: {
        if (root.streak >= 20) return "#fe1d1d"
        if (root.streak >= 10) return "#FF8C00"
        if (root.streak >= 3)  return "#FFA500"
        if (root.streak >= 1)  return Colours.palette.m3primary
        return Colours.palette.m3outlineVariant
    }
    readonly property color bestStreakColor:
        root.streak >= root.bestStreak ? "#ffca1b" : Colours.palette.m3onSurfaceVariant
    readonly property string editPrefill: `${root.nestedData?.title ?? ""} @${root.nestedData?.minutes || 0}`

    function commitRename(text) {
        // Ignore pure "@minutes" edits — they carry no title.
        if (!TitleParse.hasTitle(text)) {
            root.editingCancelled()
            return
        }
        root.renameRequested(root.taskIndex, root.subtaskIndex, root.nestedIndex, text)
    }

    Layout.fillWidth: true
    implicitHeight: subRow.implicitHeight

    HoverHandler { id: hover }

    // ── TREE LINES ──────────────────────────────────────────────
    // Spine starts at the row's top (touches the parent row / previous
    // sibling). Last child → └ shape, others → ├ shape. Always has a dot.
    TreeConnector {
        anchors.fill: parent
        rowHeight: root.height
        spineX: root.treeSpineX
        isLast: root.isLast
        showDot: true
        selected: root.isSelected

        lineWidth: root.tree.lineWidth
        cornerRadius: root.tree.cornerRadius
        elbowLength: root.tree.elbowLength
        lineColor: root.tree.color
        dotSize: root.tree.dotSize
        dotSizeSelected: root.tree.dotSizeSelected
        dotOpacity: root.tree.dotOpacity
    }

    // ── Content Row ─────────────────────────────────────────────
    RowLayout {
        id: subRow
        anchors.left: parent.left
        anchors.leftMargin: root.contentStartX
                            + (root.isSelected ? root.tree.selectedContentShift : 0)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacing.small
        Behavior on anchors.leftMargin { Anim { type: Anim.FastSpatial } }

        // Checkbox
        MaterialIcon {
            text: root.isDone ? "check_circle" : "radio_button_unchecked"
            fontStyle: Tokens.font.icon.small
            color: root.isDone ? Colours.palette.m3primary : Colours.palette.m3onSurface

            opacity: 0.9

            TapHandler {
                cursorShape: Qt.PointingHandCursor
                onTapped: root.toggleRequested(root.taskIndex, root.subtaskIndex, root.nestedIndex)
            }
        }

        // Title (rename inline, same interaction as the parent row)
        StyledText {
            visible: !root.isEditing
            Layout.fillWidth: true
            text: root.nestedData?.title ?? ""
            font: Tokens.font.body.medium
            elide: root.isSelected ? Text.ElideNone : Text.ElideRight
            wrapMode: root.isSelected ? Text.Wrap : Text.NoWrap

            color: root.isDone ? Colours.palette.m3outline : Colours.palette.m3onSurface

            opacity: root.isDone ? 0.6 : 0.8

            TapHandler {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onDoubleTapped: (eventPoint, button) => {
                    if (button === Qt.LeftButton) root.editingStarted(root.nestedId)
                }
            }
        }

        StyledTextField {
            visible: root.isEditing
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            placeholderFloats: false
            text: root.editPrefill
            placeholderText: qsTr("Rename…")
            placeholderTextColor: Colours.palette.m3onSurfaceVariant
            color: Colours.palette.m3onSurface
            background: Rectangle { color: "transparent"; border.width: 0 }
            topPadding: 2
            bottomPadding: 2
            leftPadding: 5
            rightPadding: 5
            Component.onCompleted: {
                if (root.isEditing) {
                    cursorPosition = length
                    forceActiveFocus()
                }
            }
            onVisibleChanged: {
                if (visible) {
                    text = root.editPrefill
                    cursorPosition = text.length
                    forceActiveFocus()
                }
            }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.commitRename(text)
                    event.accepted = true
                }
            }
            Keys.onEscapePressed: {
                clear()
                focus = false
                root.editingCancelled()
            }
        }

        // Minutes chip
        RowLayout {
            visible: !root.isHabitList
                     && (root.nestedData?.minutes || 0) > 0
            Layout.alignment: Qt.AlignVCenter

            StyledRect {
                implicitHeight: 20
                implicitWidth: subMinutesLabel.implicitWidth + Tokens.padding.small * 2
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceContainerHighest

                StyledText {
                    id: subMinutesLabel
                    anchors.centerIn: parent
                    text: `${root.nestedData?.minutes || 0}m`
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }

                // ── Streak (habits only) ────────────────────────────────
        RowLayout {
            id: streakBadge
            visible: root.showStreak
                     && (root.streak > 0 || root.bestStreak > 0)
                     && !root.isEditing
            Layout.leftMargin: Tokens.spacing.small
            Layout.alignment: Qt.AlignVCenter
            spacing: 4

            RowLayout {
                spacing: 2
                MaterialIcon {
                    text: "local_fire_department"
                    fill: 1
                    fontStyle: Tokens.font.icon.small
                    color: root.streakColor
                    Behavior on color { CAnim { duration: 300 } }
                }
                StyledText {
                    text: String(root.streak)
                    font: Tokens.font.label.medium
                    color: root.streakColor
                    Behavior on color { CAnim { duration: 300 } }
                }
            }

            RowLayout {
                spacing: 1
                opacity: root.streak >= root.bestStreak ? 0.8 : 0.3

                MaterialIcon {
                    text: "emoji_events"
                    fontStyle: Tokens.font.icon.small
                    color: root.bestStreakColor
                    fill: root.streak >= root.bestStreak ? 1 : 0
                    Behavior on color { CAnim { duration: 300 } }
                }
                StyledText {
                    text: String(root.bestStreak)
                    font: Tokens.font.label.small
                    color: root.bestStreakColor
                    Behavior on color { CAnim { duration: 300 } }
                }
            }
        }

        // Actions (hover-reveal only)
        RowLayout {
            spacing: 0
            opacity: (hover.hovered || root.isSelected) ? 1 : 0.3
            Behavior on opacity { Anim { type: Anim.DefaultEffects } }

            IconButton {
                type: IconButton.Text
                font: Tokens.font.icon.small
                icon: "edit"
                onClicked: root.editingStarted(root.nestedId)
            }
            IconButton {
                type: IconButton.Text
                font: Tokens.font.icon.small
                icon: "delete_outline"
                onClicked: root.deleteRequested(root.taskIndex, root.subtaskIndex, root.nestedIndex)
            }
        }
    }
}
