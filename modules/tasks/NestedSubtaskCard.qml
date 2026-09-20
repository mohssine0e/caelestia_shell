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

    required property var parentSubtaskData
    required property string parentSubtaskId
    property bool isHabitList: false
    property bool isSelected: false

    property bool isFirst: true
    property bool isLast: true

    // ── Tree settings come from SubtaskCard.qml ─────────────────
    // Don't edit tree look here — change the "TREE STYLE" block in
    // SubtaskCard.qml. `treeSpineX` = X of this child's spine (set to the
    // center of the parent's checkbox).
    required property var tree
    required property real treeSpineX

    // Where this row's content starts (same formula as the parent).
    readonly property real contentStartX: treeSpineX + tree.elbowLength + tree.contentGap

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

        // Checkbox (static)
        MaterialIcon {
            text: "check_box_outline_blank"
            fontStyle: Tokens.font.icon.small
            color: Colours.palette.m3primary
            opacity: 0.9
        }

        // Title (static, marked as placeholder)
        StyledText {
            Layout.fillWidth: true
            text: root.parentSubtaskData && root.parentSubtaskData.title
                  ? root.parentSubtaskData.title + " → nested"
                  : "nested subtask"
            font: Tokens.font.body.medium
            elide: Text.ElideRight
            color: Colours.palette.m3secondary
            opacity: 0.8
        }

        // Minutes chip (static)
        RowLayout {
            visible: !root.isHabitList
                     && root.parentSubtaskData
                     && (root.parentSubtaskData.minutes || 0) > 0
            Layout.alignment: Qt.AlignVCenter

            StyledRect {
                implicitHeight: 20
                implicitWidth: subMinutesLabel.implicitWidth + Tokens.padding.small * 2
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceContainerHighest

                StyledText {
                    id: subMinutesLabel
                    anchors.centerIn: parent
                    text: `${root.parentSubtaskData.minutes || 0}m`
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }

        // Actions (static, hover-reveal only)
        RowLayout {
            spacing: 0
            opacity: (hover.hovered || root.isSelected) ? 1 : 0
            Behavior on opacity { Anim { type: Anim.DefaultEffects } }

            IconButton {
                type: IconButton.Text
                font: Tokens.font.icon.small
                icon: "edit"
            }
            IconButton {
                type: IconButton.Text
                font: Tokens.font.icon.small
                icon: "delete_outline"
            }
        }
    }
}
