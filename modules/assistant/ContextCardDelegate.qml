pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
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
    readonly property string cardId: String(card ? (card.id || "") : "")

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
    implicitHeight: contentRow.implicitHeight + 18
    radius: Tokens.rounding.medium
    color: Qt.alpha(Colours.palette.m3secondaryContainer, 0.25)
    border.width: 1
    border.color: Qt.alpha(Colours.palette.m3secondary, 0.4)

    RowLayout {
        id: contentRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 8

        MaterialIcon {
            text: "folder_special"
            fontStyle: Tokens.font.icon.small
            color: Colours.palette.m3secondary
        }

        StyledText {
            text: qsTr("Workspace Active:")
            font: Tokens.font.label.large
            color: Colours.palette.m3secondary
        }

        StyledText {
            Layout.fillWidth: true
            text: (root.card && (root.card.project_path || root.card.title)) || qsTr("Active Workspace")
            font: Tokens.font.body.medium
            color: Colours.palette.m3onSurface
            elide: Text.ElideMiddle
        }

        AssistantBadge {
            icon: "commit"
            text: qsTr("git: %1").arg((root.card && root.card.git_branch) || "main")
            tone: Colours.palette.m3secondary
        }

        StyledText {
            text: root.formatTime(root.card)
            font: Tokens.font.label.small
            color: Colours.palette.m3outline
        }

        IconButton {
            type: IconButton.Text
            icon: "delete_outline"
            font: Tokens.font.icon.small
            implicitWidth: 24
            implicitHeight: 24

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onDoubleClicked: Memory.deleteCard(root.cardId)
            }
        }
    }
}

