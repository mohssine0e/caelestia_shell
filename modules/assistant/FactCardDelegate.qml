pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Caelestia
import Caelestia.Config
import qs.services
import qs.components
import qs.components.controls
import qs.components.containers

StyledRect {
    id: root

    required property var card
    property string expandedCardId: ""
    property string editingCardId: ""
    property string editingLinesText: ""

    signal toggleExpandRequested(string cardId)
    signal startEditingRequested(var cardData)
    signal cancelEditingRequested()
    signal saveEditingRequested(string cardId, string text)
    signal startChallengeRequested(string cardId)

    readonly property string cardId: String(card ? (card.id || "") : "")
    readonly property bool isExpanded: (cardId.length > 0 && expandedCardId === cardId) || isEditing
    readonly property bool isEditing: cardId.length > 0 && editingCardId === cardId

    function formatTime(t) {
        if (!t) return ""
        let ts = 0
        if (t.updated) {
            const parsed = Date.parse(t.updated)
            if (!isNaN(parsed)) ts = Math.max(ts, parsed)
        }
        if (t.created) {
            const parsed = Date.parse(t.created)
            if (!isNaN(parsed)) ts = Math.max(ts, parsed)
        }
        if (!ts) return ""
        const diff = Math.floor((Date.now() - ts) / 1000)
        if (diff < 60) return qsTr("just now")
        if (diff < 3600) return qsTr("%1m ago").arg(Math.floor(diff / 60))
        if (diff < 86400) return qsTr("%1h ago").arg(Math.floor(diff / 86400))
        return new Date(ts).toLocaleDateString(Qt.locale(), "MMM d")
    }

    width: parent ? parent.width : 0
    implicitHeight: mainCol.implicitHeight + 18
    radius: Tokens.rounding.medium
    color: Colours.palette.m3surfaceContainerLow
    border.width: 1
    border.color: isExpanded ? Qt.alpha(Colours.palette.m3primary, 0.5) : Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

    Behavior on border.color {
        ColorAnimation { duration: Tokens.anim.durations.expressiveDefaultEffects }
    }

    Behavior on implicitHeight {
        Anim { duration: Tokens.anim.durations.expressiveDefaultEffects }
    }

    ColumnLayout {
        id: mainCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 9
        spacing: 8

        // Header Row
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Status Dot
            Rectangle {
                width: 8
                height: 8
                radius: 4
                color: Qt.color("#38bdf8")
            }

            // Question / Title
            StyledText {
                Layout.fillWidth: true
                text: (root.card && (root.card.front || root.card.title || root.card.topic)) || qsTr("Flash Fact")
                font: Tokens.font.title.small
                color: Colours.palette.m3onSurface
                elide: Text.ElideRight
            }

            // Badge
            AssistantBadge {
                icon: "bolt"
                text: qsTr("Flash Fact")
                tone: Colours.palette.m3secondary
            }

            // Timestamp
            StyledText {
                text: root.formatTime(root.card)
                font: Tokens.font.label.small
                color: Colours.palette.m3outline
            }

            // Expand Chevron
            MaterialIcon {
                text: root.isExpanded ? "expand_less" : "expand_more"
                fontStyle: Tokens.font.icon.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }

        // Click to expand / Double-click to edit
        MouseArea {
            Layout.fillWidth: true
            implicitHeight: 0
            onClicked: root.toggleExpandRequested(root.cardId)
            onDoubleClicked: root.startEditingRequested(root.card)
        }

        // Expanded Details
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.isExpanded && !root.isEditing
            spacing: 8

            // Front Box
            StyledRect {
                Layout.fillWidth: true
                implicitHeight: frontInner.implicitHeight + 16
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerLowest
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

                ColumnLayout {
                    id: frontInner
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 4

                    RowLayout {
                        spacing: 6
                        MaterialIcon { text: "help_outline"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3primary }
                        StyledText { text: qsTr("Front (Question):"); font: Tokens.font.label.small; color: Colours.palette.m3primary }
                    }

                    SelectableText {
                        Layout.fillWidth: true
                        text: (root.card && (root.card.front || root.card.title)) || ""
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                    }
                }
            }

            // Back Box
            StyledRect {
                Layout.fillWidth: true
                implicitHeight: backInner.implicitHeight + 16
                radius: Tokens.rounding.small
                color: Qt.alpha(Colours.palette.m3secondaryContainer, 0.15)
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3secondary, 0.3)

                ColumnLayout {
                    id: backInner
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 4

                    RowLayout {
                        spacing: 6
                        MaterialIcon { text: "lightbulb"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3secondary }
                        StyledText { text: qsTr("Back (Answer):"); font: Tokens.font.label.small; color: Colours.palette.m3secondary }
                    }

                    SelectableText {
                        Layout.fillWidth: true
                        text: (root.card && (root.card.back || (root.card.lines || []).join("\n"))) || ""
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurface
                    }
                }
            }

            // Action Dock
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                IconButton {
                    type: IconButton.Text
                    icon: "edit"
                    font: Tokens.font.icon.small
                    implicitWidth: 26
                    implicitHeight: 26
                    onClicked: root.startEditingRequested(root.card)
                }

                IconButton {
                    type: IconButton.Text
                    icon: "delete_outline"
                    font: Tokens.font.icon.small
                    implicitWidth: 26
                    implicitHeight: 26
                    onClicked: Memory.deleteCard(root.cardId)
                }

                Item { Layout.fillWidth: true }

                IconTextButton {
                    text: qsTr("Quick Quiz")
                    icon: "bolt"
                    type: IconTextButton.Filled
                    implicitHeight: 26
                    horizontalPadding: 10
                    onClicked: root.startChallengeRequested(root.cardId)
                }
            }
        }

        // Inline Edit Drawer
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.isEditing
            spacing: 8

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: Math.max(90, editArea.implicitHeight + 16)
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerLowest
                border.width: 1
                border.color: Colours.palette.m3primary

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 8
                    contentWidth: width
                    contentHeight: editArea.implicitHeight
                    clip: true

                    TextEdit {
                        id: editArea
                        width: parent.width
                        text: root.editingLinesText
                        font.family: Tokens.font.body.small.family
                        font.pointSize: Tokens.font.body.small.pointSize
                        color: Colours.palette.m3onSurface
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item { Layout.fillWidth: true }

                TextButton {
                    text: qsTr("Cancel")
                    type: TextButton.Tonal
                    implicitHeight: 28
                    onClicked: root.cancelEditingRequested()
                }

                IconTextButton {
                    text: qsTr("Save")
                    icon: "check"
                    type: IconTextButton.Filled
                    implicitHeight: 28
                    onClicked: root.saveEditingRequested(root.cardId, editArea.text)
                }
            }
        }
    }
}

