pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.containers
import qs.components.effects
import qs.services

FocusScope {
    id: root

    signal backRequested()
    signal closeRequested()

    property var windowRef: null
    property string searchQuery: ""
    property string editingCardId: ""
    property string editingTopic: ""
    property string editingLinesText: ""
    property var expandedSources: ({})

    focus: true

    Keys.onEscapePressed: event => {
        if (root.editingCardId.length > 0) {
            root.cancelEditing()
            event.accepted = true
            return
        }
        root.backRequested()
        event.accepted = true
    }

    function startEditing(card) {
        if (!card) return
        root.editingCardId = String(card.id || "")
        root.editingTopic = card.topic || ""
        root.editingLinesText = (card.lines || []).join("\n")
    }

    function cancelEditing() {
        root.editingCardId = ""
        root.editingTopic = ""
        root.editingLinesText = ""
    }

    function saveEditing(cardId) {
        if (!cardId) return
        const rawLines = root.editingLinesText.split("\n")
        const cleanLines = []
        for (let i = 0; i < rawLines.length; i++) {
            const l = rawLines[i].trim()
            if (l.length > 0) {
                cleanLines.push(l)
            }
        }
        Assistant.updateMemoryCard(cardId, cleanLines, root.editingTopic)
        root.cancelEditing()
    }

    function toggleSources(cardId) {
        const idStr = String(cardId)
        const updated = Object.assign({}, root.expandedSources)
        updated[idStr] = !updated[idStr]
        root.expandedSources = updated
    }

    readonly property var filteredCards: {
        const list = Assistant.memory || []
        const q = (root.searchQuery || "").trim().toLowerCase()
        if (!q) return list

        return list.filter(card => {
            const topicMatch = (card.topic || "").toLowerCase().includes(q)
            const tagsMatch = (card.tags || []).some(t => String(t).toLowerCase().includes(q))
            const linesMatch = (card.lines || []).some(l => String(l).toLowerCase().includes(q))
            return topicMatch || tagsMatch || linesMatch
        })
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.small

        // ── Top Bar ───────────────────────────────────────────────
        Item {
            id: headerContainer
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight

            MouseArea {
                id: headerDragArea
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.ArrowCursor
                onPressed: mouse => {
                    if (root.windowRef) {
                        root.windowRef.startSystemMove()
                    }
                }
            }

            RowLayout {
                id: headerRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Tokens.spacing.small

                IconButton {
                    type: IconButton.Text
                    icon: "arrow_back"
                    font: Tokens.font.icon.small
                    implicitWidth: 32
                    implicitHeight: 32
                    onClicked: root.backRequested()
                }

                MaterialIcon {
                    text: "psychology"
                    fontStyle: Tokens.font.icon.medium
                    color: Colours.palette.m3primary
                }

                StyledText {
                    text: qsTr("Curated Memory")
                    font: Tokens.font.title.small
                    color: Colours.palette.m3onSurface
                }

                // Card Count Badge
                StyledRect {
                    implicitWidth: countText.implicitWidth + Tokens.padding.small * 2
                    implicitHeight: 22
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3surfaceContainerHigh

                    StyledText {
                        id: countText
                        anchors.centerIn: parent
                        text: {
                            const count = (Assistant.memory || []).length
                            return count === 1 ? qsTr("1 card") : qsTr("%1 cards").arg(count)
                        }
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                    }
                }

                Item { Layout.fillWidth: true }

                // Distilling state spinner or Distill button
                RowLayout {
                    spacing: 6
                    visible: Assistant.isDistilling

                    MaterialIcon {
                        text: "progress_activity"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3primary

                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 1100
                            loops: Animation.Infinite
                            running: Assistant.isDistilling
                        }
                    }

                    StyledText {
                        text: qsTr("Organizing memory…")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3primary
                    }
                }

                IconTextButton {
                    visible: !Assistant.isDistilling
                    text: qsTr("Distill")
                    icon: "auto_awesome"
                    type: IconTextButton.Filled
                    onClicked: Assistant.distill()
                }
            }
        }

        // ── Distill Error Banner ──────────────────────────────────
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: errorRow.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.small
            color: Qt.alpha(Colours.palette.m3error, 0.15)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3error, 0.5)
            visible: Assistant.distillError.length > 0 && !Assistant.isDistilling

            RowLayout {
                id: errorRow
                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "error"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3error
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Assistant.distillError
                    font: Tokens.font.body.small
                    color: Colours.palette.m3error
                    elide: Text.ElideRight
                }

                IconTextButton {
                    text: qsTr("Retry")
                    icon: "refresh"
                    type: IconTextButton.Tonal
                    onClicked: Assistant.distill()
                }
            }
        }

        // ── Search Input ──────────────────────────────────────────
        StyledTextField {
            id: searchInput
            Layout.fillWidth: true
            placeholderText: qsTr("Search curated memory...")
            placeholderFloats: false
            leadingIcon: "search"
            text: root.searchQuery
            onTextChanged: root.searchQuery = text
        }

        // ── Memory Cards List ─────────────────────────────────────
        Flickable {
            id: cardsFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: cardsColumn.implicitHeight
            clip: true

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: cardsFlick
            }

            ColumnLayout {
                id: cardsColumn
                width: cardsFlick.width - Tokens.padding.small
                spacing: Tokens.spacing.small

                // Empty State
                StyledRect {
                    visible: root.filteredCards.length === 0
                    Layout.fillWidth: true
                    implicitHeight: 180
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3surfaceContainerLowest
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        MaterialIcon {
                            Layout.alignment: Qt.AlignHCenter
                            text: "psychology"
                            fontStyle: Tokens.font.icon.large
                            color: Colours.palette.m3outline
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: (Assistant.memory || []).length === 0 ? qsTr("No memory cards yet.") : qsTr("No matching memory cards.")
                            font: Tokens.font.title.small
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: (Assistant.memory || []).length === 0 ? qsTr("Click 'Distill' to synthesize your raw history into curated knowledge.") : qsTr("Try searching for different keywords or clear the search.")
                            font: Tokens.font.body.small
                            color: Colours.palette.m3outline
                        }
                    }
                }

                // Card Repeater
                Repeater {
                    model: root.filteredCards

                    delegate: StyledRect {
                        id: cardItem
                        required property var modelData
                        readonly property bool isEditing: root.editingCardId === String(cardItem.modelData.id)
                        readonly property bool hasExpandedSources: !!root.expandedSources[String(cardItem.modelData.id)]

                        Layout.fillWidth: true
                        implicitHeight: cardInner.implicitHeight + Tokens.padding.medium * 2
                        radius: Tokens.rounding.small
                        color: Colours.palette.m3surfaceContainerHigh
                        border.width: 1
                        border.color: cardItem.isEditing ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outlineVariant, 0.3)

                        ColumnLayout {
                            id: cardInner
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: Tokens.padding.medium
                            spacing: 8

                            // Card Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small

                                StyledText {
                                    visible: !cardItem.isEditing
                                    Layout.fillWidth: true
                                    text: cardItem.modelData.topic || qsTr("Untitled Card")
                                    font: Tokens.font.title.small
                                    color: Colours.palette.m3primary
                                    wrapMode: Text.Wrap
                                }

                                StyledTextField {
                                    visible: cardItem.isEditing
                                    Layout.fillWidth: true
                                    placeholderText: qsTr("Topic title...")
                                    placeholderFloats: false
                                    text: root.editingTopic
                                    onTextChanged: {
                                        if (cardItem.isEditing) root.editingTopic = text
                                    }
                                }

                                IconButton {
                                    visible: !cardItem.isEditing
                                    type: IconButton.Text
                                    icon: "edit"
                                    font: Tokens.font.icon.small
                                    implicitWidth: 26
                                    implicitHeight: 26
                                    onClicked: root.startEditing(cardItem.modelData)
                                }

                                IconButton {
                                    type: IconButton.Text
                                    icon: "delete_outline"
                                    font: Tokens.font.icon.small
                                    implicitWidth: 26
                                    implicitHeight: 26
                                    onClicked: Assistant.deleteMemoryCard(cardItem.modelData.id)
                                }
                            }

                            // Tags Row
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                visible: cardItem.modelData.tags && cardItem.modelData.tags.length > 0

                                Repeater {
                                    model: cardItem.modelData.tags

                                    delegate: StyledRect {
                                        id: tagPill
                                        required property string modelData
                                        implicitHeight: 20
                                        implicitWidth: tagLabel.implicitWidth + 12
                                        radius: Tokens.rounding.full
                                        color: Colours.palette.m3surfaceContainerHighest

                                        StyledText {
                                            id: tagLabel
                                            anchors.centerIn: parent
                                            text: tagPill.modelData
                                            font: Tokens.font.label.small
                                            color: Colours.palette.m3outline
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }
                            }

                            // Normal View: Bulleted Lines & Sources
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                visible: !cardItem.isEditing

                                MouseArea {
                                    Layout.fillWidth: true
                                    implicitHeight: linesLayout.implicitHeight
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.startEditing(cardItem.modelData)

                                    ColumnLayout {
                                        id: linesLayout
                                        anchors.fill: parent
                                        spacing: 6

                                        Repeater {
                                            model: cardItem.modelData.lines || []

                                            delegate: RowLayout {
                                                id: bulletRow
                                                required property string modelData
                                                Layout.fillWidth: true
                                                spacing: 8

                                                StyledText {
                                                    text: "•"
                                                    font: Tokens.font.body.medium
                                                    color: Colours.palette.m3primary
                                                    Layout.alignment: Qt.AlignTop
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: bulletRow.modelData
                                                    font: Tokens.font.body.medium
                                                    color: Colours.palette.m3onSurface
                                                    wrapMode: Text.Wrap
                                                }
                                            }
                                        }
                                    }
                                }

                                // See sources link
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    MouseArea {
                                        implicitWidth: sourcesLink.implicitWidth
                                        implicitHeight: sourcesLink.implicitHeight
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleSources(cardItem.modelData.id)

                                        RowLayout {
                                            id: sourcesLink
                                            spacing: 4

                                            MaterialIcon {
                                                text: cardItem.hasExpandedSources ? "expand_less" : "expand_more"
                                                fontStyle: Tokens.font.icon.small
                                                color: Colours.palette.m3tertiary
                                            }

                                            StyledText {
                                                text: {
                                                    const sCount = (cardItem.modelData.sources || []).length
                                                    return qsTr("Sources (%1)").arg(sCount)
                                                }
                                                font: Tokens.font.label.small
                                                color: Colours.palette.m3tertiary
                                            }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }
                                }

                                // Expanded Sources Box
                                StyledRect {
                                    Layout.fillWidth: true
                                    visible: cardItem.hasExpandedSources
                                    implicitHeight: sourcesBox.implicitHeight + Tokens.padding.small * 2
                                    radius: Tokens.rounding.small
                                    color: Colours.palette.m3surfaceContainerLowest
                                    border.width: 1
                                    border.color: Colours.palette.m3outlineVariant

                                    ColumnLayout {
                                        id: sourcesBox
                                        anchors.fill: parent
                                        anchors.margins: Tokens.padding.small
                                        spacing: 4

                                        StyledText {
                                            text: qsTr("Source entries from raw log:")
                                            font: Tokens.font.label.small
                                            color: Colours.palette.m3outline
                                        }

                                        Repeater {
                                            model: cardItem.modelData.sources || []

                                            delegate: StyledText {
                                                id: sourceEntry
                                                required property string modelData
                                                Layout.fillWidth: true
                                                text: "↳ " + sourceEntry.modelData
                                                font: Tokens.font.label.small
                                                color: Colours.palette.m3onSurfaceVariant
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }

                            // Edit Mode View
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                visible: cardItem.isEditing

                                StyledRect {
                                    Layout.fillWidth: true
                                    implicitHeight: Math.max(100, editArea.implicitHeight + Tokens.padding.small * 2)
                                    radius: Tokens.rounding.small
                                    color: Colours.palette.m3surfaceContainerLowest
                                    border.width: 1
                                    border.color: Colours.palette.m3primary

                                    Flickable {
                                        anchors.fill: parent
                                        anchors.margins: Tokens.padding.small
                                        contentWidth: width
                                        contentHeight: editArea.implicitHeight
                                        clip: true

                                        TextEdit {
                                            id: editArea
                                            width: parent.width
                                            text: root.editingLinesText
                                            font.family: Tokens.font.body.medium.family
                                            font.pointSize: Tokens.font.body.medium.pointSize
                                            color: Colours.palette.m3onSurface
                                            wrapMode: TextEdit.Wrap
                                            selectByMouse: true
                                            onTextChanged: {
                                                if (cardItem.isEditing) root.editingLinesText = text
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.spacing.small

                                    Item { Layout.fillWidth: true }

                                    TextButton {
                                        text: qsTr("Cancel")
                                        type: TextButton.Tonal
                                        onClicked: root.cancelEditing()
                                    }

                                    IconTextButton {
                                        text: qsTr("Save")
                                        icon: "check"
                                        type: IconTextButton.Filled
                                        onClicked: root.saveEditing(cardItem.modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
