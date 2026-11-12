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
    readonly property bool isMastered: card ? (card.status === "mastered") : false
    readonly property bool isEnrichingThis: Memory.isEnriching && Memory.enrichingCardId === cardId
    readonly property var cardSections: card ? (card.sections || []) : []
    readonly property bool isCodeHub: cardSections.length > 0
    property int activeSectionIndex: 0
    readonly property var currentSection: (cardSections.length > 0 && activeSectionIndex >= 0 && activeSectionIndex < cardSections.length) ? cardSections[activeSectionIndex] : null

    readonly property bool isReviewDue: {
        if (!card) return false
        const nr = (card.srs_data && card.srs_data.next_review) || card.next_review
        if (!nr) return false
        const reviewDate = Date.parse(nr)
        return !isNaN(reviewDate) && Date.now() >= reviewDate
    }

    readonly property string activeSnippet: {
        if (!card) return ""
        if (currentSection && currentSection.snippet) return String(currentSection.snippet).trim()
        if (card.snippet && String(card.snippet).trim().length > 0) return String(card.snippet).trim()
        if (card.primer && card.primer.snippet && String(card.primer.snippet).trim().length > 0) {
            return String(card.primer.snippet).trim()
        }
        return ""
    }

    readonly property var activeInvariants: {
        if (!card) return []
        if (card.invariants && card.invariants.length > 0) return card.invariants
        if (card.lines && card.lines.length > 0) return card.lines
        return []
    }

    readonly property var activeTraps: {
        if (!card) return []
        if (card.user_traps && card.user_traps.length > 0) return card.user_traps
        if (card.personal_traps && card.personal_traps.length > 0) return card.personal_traps
        return []
    }


    width: parent ? parent.width : 0
    implicitHeight: mainCol.implicitHeight + 18
    radius: Tokens.rounding.medium
    color: Colours.palette.m3surfaceContainerLow
    border.width: 1
    border.color: {
        if (root.isExpanded) return Qt.alpha(Colours.palette.m3primary, 0.5)
        if (root.isMastered) return Qt.alpha(Qt.color("#4ade80"), 0.35)
        return Qt.alpha(Colours.palette.m3outlineVariant, 0.4)
    }

    Behavior on border.color { ColorAnimation { duration: Tokens.anim.durations.expressiveDefaultEffects } }
    Behavior on implicitHeight { Anim { duration: Tokens.anim.durations.expressiveDefaultEffects } }

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

            Rectangle {
                width: 8
                height: 8
                radius: 4
                color: root.isMastered ? "#4ade80" : "#fbbf24"
            }

            StyledText {
                Layout.fillWidth: true
                text: (root.card && (root.card.title || root.card.topic)) || qsTr("Untitled Card")
                font: Tokens.font.body.medium
                color: Colours.palette.m3onSurface
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            AssistantBadge {
                visible: root.isCodeHub
                icon: "code"
                text: root.cardSections.length > 0 ? qsTr("%1 modules").arg(root.cardSections.length) : qsTr("Code Hub")
                tone: Colours.palette.m3primary
                heightPx: 18
            }

            AssistantBadge {
                visible: root.isReviewDue
                icon: "schedule"
                text: qsTr("Review Due")
                tone: Colours.palette.m3tertiary
            }

            MaterialIcon {
                text: root.isExpanded ? "expand_less" : "expand_more"
                fontStyle: Tokens.font.icon.small
                color: root.isExpanded ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
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

            // Tier 2: Status Chip, Tags & Icons
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Flickable {
                    Layout.fillWidth: true
                    implicitHeight: 24
                    contentWidth: tagsRow.implicitWidth
                    contentHeight: height
                    clip: true
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    visible: (root.card?.tags || []).length > 0

                    RowLayout {
                        id: tagsRow
                        spacing: 6
                        anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            model: root.card?.tags || []
                            delegate: StyledRect {
                                implicitHeight: 20
                                implicitWidth: tagTxt.implicitWidth + 10
                                radius: Tokens.rounding.full
                                color: Qt.alpha(Colours.palette.m3surfaceVariant, 0.5)
                                StyledText {
                                    id: tagTxt
                                    anchors.centerIn: parent
                                    text: "#" + modelData
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3onSurfaceVariant
                                }
                            }
                        }
                    }
                }

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
            }

            // Mental Model Box
            StyledRect {
                visible: !!(root.card?.mental_model || root.card?.summary)
                Layout.fillWidth: true
                implicitHeight: mentalModelCol.implicitHeight + 16
                radius: Tokens.rounding.small
                color: Qt.alpha(Colours.palette.m3primary, 0.06)
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3primary, 0.25)

                ColumnLayout {
                    id: mentalModelCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 4
                    RowLayout {
                        spacing: 6
                        MaterialIcon { text: "psychology"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3primary }
                        StyledText { text: qsTr("Mental Model:"); font: Tokens.font.label.small; color: Colours.palette.m3primary }
                    }
                    SelectableText {
                        Layout.fillWidth: true
                        text: root.card?.mental_model || root.card?.summary || ""
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurface
                    }
                }
            }

            // Invariants List
            Repeater {
                model: root.activeInvariants
                delegate: RowLayout {
                    required property string modelData
                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                        width: 5
                        height: 5
                        radius: 2.5
                        color: Colours.palette.m3primary
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 5
                    }

                    SelectableText {
                        Layout.fillWidth: true
                        text: modelData
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurface
                    }
                }
            }

            // Code Snippet Box
            StyledRect {
                visible: root.activeSnippet.length > 0
                Layout.fillWidth: true
                implicitHeight: snipInner.implicitHeight + 16
                radius: Tokens.rounding.small
                color: Qt.alpha(Colours.palette.m3surfaceContainerLowest, 0.9)
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

                ColumnLayout {
                    id: snipInner
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        MaterialIcon { text: "code"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3primary }
                        StyledText { text: qsTr("Code Snippet:"); font: Tokens.font.label.small; color: Colours.palette.m3primary }
                        Item { Layout.fillWidth: true }
                        IconButton {
                            type: IconButton.Text
                            icon: "content_copy"
                            font: Tokens.font.icon.small
                            implicitWidth: 22
                            implicitHeight: 22
                            onClicked: {
                                let s = String(root.activeSnippet).trim()
                                if (s.startsWith("```")) {
                                    const firstNl = s.indexOf("\n")
                                    if (firstNl !== -1) s = s.substring(firstNl + 1)
                                    if (s.endsWith("```")) s = s.substring(0, s.length - 3)
                                }
                                Quickshell.clipboardText = s.trim()
                            }
                        }
                    }

                    SelectableText {
                        Layout.fillWidth: true
                        text: {
                            let s = String(root.activeSnippet).trim()
                            if (s.startsWith("```")) {
                                const firstNl = s.indexOf("\n")
                                if (firstNl !== -1) s = s.substring(firstNl + 1)
                                if (s.endsWith("```")) s = s.substring(0, s.length - 3)
                            }
                            return s.trim()
                        }
                        font.family: "monospace"
                        font.pointSize: Tokens.font.body.small.pointSize - 0.5
                        color: Colours.palette.m3onSurface
                    }
                }
            }

            // Personal Traps
            Repeater {
                model: root.activeTraps
                delegate: RowLayout {
                    id: trapRow
                    required property string modelData
                    Layout.fillWidth: true
                    spacing: 6

                    MaterialIcon {
                        text: "crisis_alert"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3error
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 1
                    }

                    SelectableText {
                        Layout.fillWidth: true
                        text: trapRow.modelData
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurface
                    }

                    IconButton {
                        type: IconButton.Text
                        icon: "close"
                        font: Tokens.font.icon.small
                        implicitWidth: 20
                        implicitHeight: 20
                        onClicked: Memory.removeTrap(root.cardId, trapRow.modelData)
                    }
                }
            }

            // Action Dock
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                IconTextButton {
                    enabled: !root.isEnrichingThis
                    text: root.isEnrichingThis ? qsTr("Adding Info…") : (root.card?.primer ? qsTr("Enriched ✨") : qsTr("Add Info ✨"))
                    icon: root.isEnrichingThis ? "progress_activity" : "auto_awesome"
                    type: IconTextButton.Tonal
                    implicitHeight: 26
                    horizontalPadding: 8
                    onClicked: {
                        if (!root.isEnrichingThis) {
                            Memory.enrichCard(root.cardId)
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                IconTextButton {
                    text: root.isMastered ? qsTr("Practice") : qsTr("Test Mastery")
                    icon: "psychology_alt"
                    type: IconTextButton.Filled
                    implicitHeight: 26
                    horizontalPadding: 8
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
