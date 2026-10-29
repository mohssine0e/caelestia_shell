pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Caelestia
import Caelestia.Config
import qs.services
import qs.components
import qs.components.controls
import qs.components.containers

Item {
    id: cardItem

    property var card: null
    property bool showArchived: false
    property string editingCardId: ""
    property string expandedCardId: ""
    property string selectedConcept: ""
    property string editingLinesText: ""

    signal startEditingRequested(string cardId)
    signal cancelEditingRequested()
    signal saveEditingRequested(string cardId, string text)
    signal toggleExpandRequested(string cardId)
    signal startChallengeRequested(string cardId)
    signal selectConceptRequested(string concept)
    signal editLinesTextChanged(string text)

    function getCardTimestamp(card) {
        if (!card) return 0
        let maxTime = 0
        if (card.last_reviewed) {
            const t = Date.parse(card.last_reviewed)
            if (!isNaN(t)) maxTime = Math.max(maxTime, t)
        }
        if (card.updated) {
            const t = Date.parse(card.updated)
            if (!isNaN(t)) maxTime = Math.max(maxTime, t)
        }
        if (card.created) {
            const t = Date.parse(card.created)
            if (!isNaN(t)) maxTime = Math.max(maxTime, t)
        }
        return maxTime
    }

    function formatCardTime(card) {
        const ts = getCardTimestamp(card)
        if (!ts) return ""
        const diff = Math.floor((Date.now() - ts) / 1000)
        if (diff < 60) return qsTr("just now")
        if (diff < 3600) return qsTr("%1m ago").arg(Math.floor(diff / 60))
        if (diff < 86400) return qsTr("%1h ago").arg(Math.floor(diff / 86400))
        if (diff < 604800) return qsTr("%1d ago").arg(Math.floor(diff / 86400))
        return new Date(ts).toLocaleDateString(Qt.locale(), "MMM d")
    }

    width: ListView.view ? ListView.view.width : parent ? parent.width : 0
    implicitHeight: cardRect.implicitHeight
    height: cardRect.implicitHeight

    readonly property var cardData: (cardItem && cardItem.card) ? cardItem.card : ({})
                    readonly property var cardPrimer: cardData ? (cardData.primer || null) : null
                    readonly property string cardId: String(cardData ? (cardData.id || "") : "")
                    readonly property bool isEditing: cardItem.editingCardId.length > 0 && cardItem.editingCardId === cardId
                    readonly property bool isMastered: cardData ? (cardData.status === "mastered") : false
                    readonly property bool hasFailFeedback: !!(cardData && cardData.last_fail_feedback && cardData.last_fail_feedback.length > 0)
                    readonly property bool isEnrichingThis: (Memory.isEnriching && Memory.enrichingCardId === cardId)
                    readonly property var cardSections: cardData ? (cardData.sections || []) : []
                    readonly property bool isCodeHub: cardData ? (cardData.type === "code_hub" || cardSections.length > 0) : false
                    property int activeSectionIndex: 0
                    readonly property var currentSection: (cardSections && cardSections.length > 0 && activeSectionIndex >= 0 && activeSectionIndex < cardSections.length) ? cardSections[activeSectionIndex] : null
                    readonly property bool expanded: (cardId.length > 0 && cardItem.expandedCardId === cardId) || isEditing
                    readonly property bool isReviewDue: {
                        if (!cardData) return false
                        const lr = cardData.last_reviewed || cardData.updated || cardData.created
                        if (!lr) return false
                        const t = Date.parse(lr)
                        if (isNaN(t) || t <= 0) return false
                        const FOURTEEN_DAYS_MS = 14 * 24 * 60 * 60 * 1000
                        return (Date.now() - t) > FOURTEEN_DAYS_MS
                    }
                    readonly property bool isInjectedInPrompt: {
                        const list = Memory.lastInjectedCardIds || []
                        return list.indexOf(cardId) !== -1
                    }

                    StyledRect {
                        id: cardRect
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        implicitHeight: cardContent.implicitHeight + 18
                        radius: Tokens.rounding.medium
                        color: Colours.palette.m3surfaceContainerLow
                        clip: true

                        border.width: (cardItem.expanded || cardItem.isInjectedInPrompt) ? 1.5 : 1
                        border.color: {
                            if (cardItem.isInjectedInPrompt) return Colours.palette.m3secondary
                            if (cardItem.expanded || cardHover.hovered) return Qt.alpha(Colours.palette.m3primary, 0.5)
                            if (cardItem.isMastered) return Qt.alpha(Qt.color("#4ade80"), 0.35)
                            return Qt.alpha(Colours.palette.m3outlineVariant, 0.4)
                        }

                        Behavior on border.color {
                            ColorAnimation { duration: Tokens.anim.durations.expressiveDefaultEffects }
                        }

                        Behavior on implicitHeight {
                            Anim { duration: Tokens.anim.durations.expressiveDefaultEffects }
                        }

                        HoverHandler {
                            id: cardHover
                        }

                        MouseArea {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 38
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const sid = cardItem.cardId
                                if (sid) {
                                    cardItem.expandedCardId = (cardItem.expandedCardId === sid) ? "" : sid
                                }
                            }
                        }

                        ColumnLayout {
                            id: cardContent
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            anchors.topMargin: 9
                            anchors.bottomMargin: 9
                            spacing: 8

                            // Tier 1: Status Dot, Topic Title, Badges, and Timestamp
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // Status Dot: Mastered (Emerald Green #4ade80) vs Learning (Warm Amber #fbbf24)
                                Rectangle {
                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    color: cardItem.isMastered ? "#4ade80" : "#fbbf24"
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: cardItem.cardData.topic || qsTr("Untitled Card")
                                    font: Tokens.font.body.medium
                                    color: Colours.palette.m3onSurface
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                // Domain Code Hub badge (shows section count)
                                AssistantBadge {
                                    visible: cardItem.isCodeHub
                                    icon: "code"
                                    text: cardItem.cardSections.length > 0
                                        ? qsTr("%1 modules").arg(cardItem.cardSections.length)
                                        : qsTr("Code Hub")
                                    tone: Colours.palette.m3primary
                                    heightPx: 18
                                }

                                // Active In-Context Badge (HUD Prompt Injection)
                                AssistantBadge {
                                    visible: cardItem.isInjectedInPrompt
                                    icon: "psychology"
                                    text: qsTr("In Context")
                                    tone: Colours.palette.m3secondary
                                }

                                // Spaced Repetition: Review Due Badge (> 14 days)
                                AssistantBadge {
                                    visible: cardItem.isReviewDue
                                    icon: "schedule"
                                    text: qsTr("Review Due")
                                    tone: Colours.palette.m3tertiary
                                }

                                StyledText {
                                    text: cardItem.formatCardTime(cardItem.cardData)
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3outline
                                }

                                // Expand Chevron
                                MaterialIcon {
                                    text: cardItem.expanded ? "expand_less" : "expand_more"
                                    fontStyle: Tokens.font.icon.small
                                    color: cardItem.expanded ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                }
                            }

                            // Expanded Content (Collapsible Details)
                            ColumnLayout {
                                id: cardDetails
                                Layout.fillWidth: true
                                visible: cardItem.expanded
                                spacing: 10

                                // Divider Line
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)
                                }

                            // Tier 2: Primer Status Badge, Tag Chips, and Subtle Management Icons
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                StyledRect {
                                    implicitWidth: primerTagRow.implicitWidth + 10
                                    implicitHeight: 22
                                    radius: Tokens.rounding.full
                                    color: cardItem.cardPrimer
                                        ? Qt.alpha(Colours.palette.m3primary, 0.12)
                                        : Colours.palette.m3surfaceContainerHigh

                                    RowLayout {
                                        id: primerTagRow
                                        anchors.centerIn: parent
                                        spacing: 4

                                        MaterialIcon {
                                            text: cardItem.cardPrimer ? "auto_awesome" : "notes"
                                            fontStyle: Tokens.font.icon.small
                                            color: cardItem.cardPrimer ? Colours.palette.m3primary : Colours.palette.m3outline
                                        }

                                        StyledText {
                                            text: cardItem.cardPrimer ? qsTr("Primer Ready") : qsTr("Raw Notes")
                                            font: Tokens.font.label.small
                                            color: cardItem.cardPrimer ? Colours.palette.m3primary : Colours.palette.m3outline
                                        }
                                    }
                                }

                                Flickable {
                                    id: tagsFlickable
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    contentWidth: tagsRow.implicitWidth
                                    contentHeight: height
                                    clip: true
                                    flickableDirection: Flickable.HorizontalFlick
                                    boundsBehavior: Flickable.StopAtBounds
                                    visible: !cardItem.isEditing && (cardItem.cardData.tags || []).length > 0

                                    RowLayout {
                                        id: tagsRow
                                        spacing: 6
                                        anchors.verticalCenter: parent.verticalCenter

                                        Repeater {
                                            model: cardItem.cardData.tags || []

                                            delegate: StyledRect {
                                                id: cardTagChip
                                                required property var modelData
                                                readonly property string tagStr: String(modelData).toLowerCase()
                                                readonly property bool isTagSelected: cardItem.selectedConcept === tagStr

                                                implicitWidth: tagRow.implicitWidth + 10
                                                implicitHeight: 22
                                                radius: Tokens.rounding.full
                                                color: isTagSelected
                                                    ? Colours.palette.m3secondaryContainer
                                                    : (tagMouse.containsMouse ? Colours.palette.m3surfaceContainerHigh : Colours.palette.m3surfaceContainerLow)
                                                border.width: isTagSelected ? 1 : 0
                                                border.color: Colours.palette.m3secondary

                                                RowLayout {
                                                    id: tagRow
                                                    anchors.centerIn: parent
                                                    spacing: 3

                                                    StyledText {
                                                        text: "#" + String(cardTagChip.modelData)
                                                        font: Tokens.font.label.small
                                                        color: cardTagChip.isTagSelected
                                                            ? Colours.palette.m3onSecondaryContainer
                                                            : Colours.palette.m3outline
                                                    }
                                                }

                                                MouseArea {
                                                    id: tagMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (cardItem.selectedConcept === cardTagChip.tagStr) {
                                                            cardItem.selectedConcept = ""
                                                        } else {
                                                            cardItem.selectedConcept = cardTagChip.tagStr
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    WheelHandler {
                                        onWheel: event => {
                                            const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                                            tagsFlickable.contentX = Math.max(0, Math.min(tagsFlickable.contentWidth - tagsFlickable.width, tagsFlickable.contentX - delta))
                                        }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                    visible: !tagsFlickable.visible
                                }

                                IconButton {
                                    type: IconButton.Text
                                    icon: "edit"
                                    font: Tokens.font.icon.small
                                    implicitWidth: 24
                                    implicitHeight: 24
                                    onClicked: cardItem.startEditingRequested(cardItem.cardData)
                                }

                                IconButton {
                                    id: deleteCardButton
                                    type: IconButton.Text
                                    icon: "delete_outline"
                                    font: Tokens.font.icon.small
                                    implicitWidth: 24
                                    implicitHeight: 24

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
                                        onClicked: deleteCardButton.clicked()
                                        onDoubleClicked: {
                                            if (cardItem.expandedCardId === cardItem.cardId) {
                                                cardItem.expandedCardId = ""
                                            }
                                            Memory.deleteCard(cardItem.cardId)
                                        }
                                    }

                                    SequentialAnimation {
                                        id: shakeAnim
                                        onFinished: {
                                            deleteCardButton.isShaking = false
                                            deleteCardButton.rotation = 0
                                        }
                                        PropertyAnimation {
                                            target: deleteCardButton
                                            property: "rotation"
                                            from: -8
                                            to: 8
                                            duration: 80
                                        }
                                        PropertyAnimation {
                                            target: deleteCardButton
                                            property: "rotation"
                                            from: 8
                                            to: -8
                                            duration: 80
                                        }
                                        PropertyAnimation {
                                            target: deleteCardButton
                                            property: "rotation"
                                            from: -8
                                            to: 8
                                            duration: 80
                                        }
                                        PropertyAnimation {
                                            target: deleteCardButton
                                            property: "rotation"
                                            from: 8
                                            to: -8
                                            duration: 80
                                        }
                                        PropertyAnimation {
                                            target: deleteCardButton
                                            property: "rotation"
                                            from: -4
                                            to: 4
                                            duration: 50
                                        }
                                        PropertyAnimation {
                                            target: deleteCardButton
                                            property: "rotation"
                                            from: 4
                                            to: 0
                                            duration: 50
                                        }
                                    }
                                }
                            }

                            // Last Fail Feedback Alert (if present)
                            StyledRect {
                                Layout.fillWidth: true
                                implicitHeight: failRow.implicitHeight + 12
                                radius: Tokens.rounding.small
                                color: Qt.alpha(Colours.palette.m3error, 0.1)
                                border.width: 1
                                border.color: Qt.alpha(Colours.palette.m3error, 0.25)
                                visible: cardItem.hasFailFeedback && !cardItem.isMastered

                                RowLayout {
                                    id: failRow
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 6

                                    MaterialIcon {
                                        text: "warning"
                                        fontStyle: Tokens.font.icon.small
                                        color: Colours.palette.m3error
                                    }

                                    SelectableText {
                                        Layout.fillWidth: true
                                        text: qsTr("**Last Trial Blindspot:** %1").arg(cardItem.cardData.last_fail_feedback || "")
                                        textFormat: TextEdit.MarkdownText
                                        color: Colours.palette.m3onSurface
                                    }
                                }
                            }

                            // Mastered Invariant Highlight Box (for Mastered Cards)
                            StyledRect {
                                Layout.fillWidth: true
                                implicitHeight: masterCol.implicitHeight + 16
                                radius: Tokens.rounding.small
                                color: Qt.alpha(Colours.palette.m3primary, 0.08)
                                border.width: 1
                                border.color: Qt.alpha(Colours.palette.m3primary, 0.2)
                                visible: cardItem.isMastered && !cardItem.isEditing && cardItem.cardSections.length === 0

                                ColumnLayout {
                                    id: masterCol
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 6

                                    RowLayout {
                                        spacing: 6
                                        MaterialIcon {
                                            text: "verified"
                                            fontStyle: Tokens.font.icon.small
                                            color: Colours.palette.m3primary
                                        }
                                        StyledText {
                                            text: qsTr("Distilled Invariant:")
                                            font: Tokens.font.label.small
                                            color: Colours.palette.m3primary
                                        }
                                    }

                                    SelectableText {
                                        Layout.fillWidth: true
                                        text: {
                                            const lines = cardItem.cardData ? (cardItem.cardData.lines || []) : []
                                            return lines.join("\n")
                                        }
                                        color: Colours.palette.m3onSurface
                                    }

                                    TextButton {
                                        visible: (cardItem.cardData.archived_lines || []).length > 0
                                        text: cardItem.showArchived
                                            ? qsTr("Hide %1 archived notes ▴").arg(cardItem.cardData.archived_lines.length)
                                            : qsTr("Show %1 archived notes ▾").arg(cardItem.cardData.archived_lines.length)
                                        type: TextButton.Text
                                        onClicked: cardItem.showArchived = !cardItem.showArchived
                                    }

                                    SelectableText {
                                        visible: cardItem.showArchived
                                        Layout.fillWidth: true
                                        text: (cardItem.cardData.archived_lines || []).map(l => "•  " + l).join("\n")
                                        color: Colours.palette.m3outline
                                    }
                                }
                            }

                            // =========================================
                            // DOMAIN CODE HUB: MULTI-SECTION BROWSER
                            // =========================================
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                visible: cardItem.cardSections.length > 0 && !cardItem.isEditing

                                // Section Tabs (Horizontal pill strip)
                                Flickable {
                                    Layout.fillWidth: true
                                    implicitHeight: 28
                                    contentWidth: secRow.implicitWidth
                                    clip: true
                                    flickableDirection: Flickable.HorizontalFlick

                                    RowLayout {
                                        id: secRow
                                        spacing: 6

                                        Repeater {
                                            model: cardItem.cardSections

                                            delegate: StyledRect {
                                                id: secPill
                                                required property var modelData
                                                required property int index
                                                readonly property bool isCurrent: cardItem.activeSectionIndex === index

                                                implicitWidth: Math.min(secPillInner.implicitWidth + 14, 220)
                                                implicitHeight: 26
                                                radius: Tokens.rounding.full
                                                color: isCurrent ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh
                                                border.width: isCurrent ? 0 : 1
                                                border.color: Colours.palette.m3outlineVariant

                                                RowLayout {
                                                    id: secPillInner
                                                    anchors.centerIn: parent
                                                    spacing: 4

                                                    MaterialIcon {
                                                        text: "code"
                                                        fontStyle: Tokens.font.icon.small
                                                        color: secPill.isCurrent ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                                    }

                                                    StyledText {
                                                        text: secPill.modelData.title || qsTr("Module %1").arg(secPill.index + 1)
                                                        font: Tokens.font.label.small
                                                        color: secPill.isCurrent ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                                        elide: Text.ElideRight
                                                        Layout.maximumWidth: 180
                                                    }
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: cardItem.activeSectionIndex = secPill.index
                                                }
                                            }
                                        }
                                    }
                                }

                                // Active Section Box
                                StyledRect {
                                    Layout.fillWidth: true
                                    implicitHeight: actSecCol.implicitHeight + 20
                                    radius: Tokens.rounding.small
                                    color: Colours.palette.m3surfaceContainerLowest
                                    border.width: 1
                                    border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)

                                    ColumnLayout {
                                        id: actSecCol
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 8

                                        // Section Title Header
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            MaterialIcon {
                                                text: "developer_mode"
                                                fontStyle: Tokens.font.icon.small
                                                color: Colours.palette.m3primary
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: cardItem.currentSection ? String(cardItem.currentSection.title || "") : ""
                                                font: Tokens.font.label.large
                                                color: Colours.palette.m3onSurface
                                            }
                                        }

                                        // Section Rules
                                        Repeater {
                                            model: cardItem.currentSection ? (cardItem.currentSection.rules || []) : []

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

                                        // Section Traps & Gotchas (Merged with danger icon)
                                        Repeater {
                                            model: cardItem.currentSection ? (cardItem.currentSection.pitfalls || []) : []

                                            delegate: RowLayout {
                                                required property string modelData
                                                Layout.fillWidth: true
                                                spacing: 6

                                                MaterialIcon {
                                                    text: "warning"
                                                    fontStyle: Tokens.font.icon.small
                                                    color: Colours.palette.m3error
                                                    Layout.alignment: Qt.AlignTop
                                                    Layout.topMargin: 1
                                                }

                                                SelectableText {
                                                    Layout.fillWidth: true
                                                    text: modelData
                                                    font: Tokens.font.body.small
                                                    color: Colours.palette.m3onSurface
                                                }
                                            }
                                        }

                                        // Section Code Snippet
                                        StyledRect {
                                            visible: !!(cardItem.currentSection && cardItem.currentSection.snippet && cardItem.currentSection.snippet.length > 0)
                                            Layout.fillWidth: true
                                            implicitHeight: secSnipInner.implicitHeight + 16
                                            radius: Tokens.rounding.small
                                            color: Qt.alpha(Colours.palette.m3surfaceContainerLowest, 0.95)
                                            border.width: 1
                                            border.color: Qt.alpha(Colours.palette.m3outline, 0.3)

                                            ColumnLayout {
                                                id: secSnipInner
                                                anchors.fill: parent
                                                anchors.margins: 8
                                                spacing: 4

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
                                                            if (cardItem.currentSection && cardItem.currentSection.snippet) {
                                                                let s = String(cardItem.currentSection.snippet).trim()
                                                                if (s.startsWith("```")) {
                                                                    const firstNl = s.indexOf("\n")
                                                                    if (firstNl !== -1) s = s.substring(firstNl + 1)
                                                                    if (s.endsWith("```")) s = s.substring(0, s.length - 3)
                                                                }
                                                                Quickshell.clipboardText = s.trim()
                                                            }
                                                        }
                                                    }
                                                }

                                                SelectableText {
                                                    Layout.fillWidth: true
                                                    text: {
                                                        if (!cardItem.currentSection || !cardItem.currentSection.snippet) return ""
                                                        let s = String(cardItem.currentSection.snippet).trim()
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
                                    }
                                }
                            }

                            // Knowledge & Info Stream (for Cards without sections)
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                visible: !cardItem.isMastered && !cardItem.isEditing && cardItem.cardSections.length === 0

                                // 1. Base Knowledge Lines
                                Repeater {
                                    model: cardItem.cardData ? (cardItem.cardData.lines || []) : []

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

                                // 2. Enriched Additional Info / Primer Rules (Marked with ✨ icon)
                                Repeater {
                                    model: (cardItem.cardPrimer && cardItem.cardPrimer.rules) ? cardItem.cardPrimer.rules : []

                                    delegate: RowLayout {
                                        required property string modelData
                                        Layout.fillWidth: true
                                        spacing: 6

                                        MaterialIcon {
                                            text: "auto_awesome"
                                            fontStyle: Tokens.font.icon.small
                                            color: Colours.palette.m3tertiary
                                            Layout.alignment: Qt.AlignTop
                                            Layout.topMargin: 1
                                        }

                                        SelectableText {
                                            Layout.fillWidth: true
                                            text: modelData
                                            font: Tokens.font.body.small
                                            color: Colours.palette.m3onSurface
                                        }
                                    }
                                }

                                // 3. Enriched Pitfall (Merged with ⚠️ danger icon)
                                RowLayout {
                                    visible: !!(cardItem.cardPrimer && cardItem.cardPrimer.pitfall && cardItem.cardPrimer.pitfall.length > 0)
                                    Layout.fillWidth: true
                                    spacing: 6

                                    MaterialIcon {
                                        text: "warning"
                                        fontStyle: Tokens.font.icon.small
                                        color: Colours.palette.m3error
                                        Layout.alignment: Qt.AlignTop
                                        Layout.topMargin: 1
                                    }

                                    SelectableText {
                                        Layout.fillWidth: true
                                        text: cardItem.cardPrimer ? String(cardItem.cardPrimer.pitfall || "") : ""
                                        font: Tokens.font.body.small
                                        color: Colours.palette.m3onSurface
                                    }
                                }

                                // 4. Enriched Snippet (if present in primer)
                                StyledRect {
                                    visible: !!(cardItem.cardPrimer && cardItem.cardPrimer.snippet && cardItem.cardPrimer.snippet.length > 0)
                                    Layout.fillWidth: true
                                    implicitHeight: primerSnipInner.implicitHeight + 16
                                    radius: Tokens.rounding.small
                                    color: Qt.alpha(Colours.palette.m3surfaceContainerLowest, 0.95)
                                    border.width: 1
                                    border.color: Qt.alpha(Colours.palette.m3outline, 0.3)

                                    ColumnLayout {
                                        id: primerSnipInner
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 4

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
                                                    if (cardItem.cardPrimer && cardItem.cardPrimer.snippet) {
                                                        let s = String(cardItem.cardPrimer.snippet).trim()
                                                        if (s.startsWith("```")) {
                                                            const firstNl = s.indexOf("\n")
                                                            if (firstNl !== -1) s = s.substring(firstNl + 1)
                                                            if (s.endsWith("```")) s = s.substring(0, s.length - 3)
                                                        }
                                                        Quickshell.clipboardText = s.trim()
                                                    }
                                                }
                                            }
                                        }

                                        SelectableText {
                                            Layout.fillWidth: true
                                            text: {
                                                if (!cardItem.cardPrimer || !cardItem.cardPrimer.snippet) return ""
                                                let s = String(cardItem.cardPrimer.snippet).trim()
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
                            }

                            // Personal Traps & Caveats (Merged with ⚠️ danger icon, no heavy box)
                            Repeater {
                                model: cardItem.cardData.personal_traps || []

                                delegate: RowLayout {
                                    id: trapRowItem
                                    required property string modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    spacing: 6
                                    visible: !cardItem.isEditing

                                    MaterialIcon {
                                        text: "crisis_alert"
                                        fontStyle: Tokens.font.icon.small
                                        color: Colours.palette.m3error
                                        Layout.alignment: Qt.AlignTop
                                        Layout.topMargin: 1
                                    }

                                    SelectableText {
                                        Layout.fillWidth: true
                                        text: trapRowItem.modelData
                                        font: Tokens.font.body.small
                                        color: Colours.palette.m3onSurface
                                    }

                                    IconButton {
                                        type: IconButton.Text
                                        icon: "close"
                                        font: Tokens.font.icon.small
                                        implicitWidth: 20
                                        implicitHeight: 20
                                        onClicked: Memory.removeTrap(cardItem.cardId, trapRowItem.modelData)
                                    }
                                }
                            }

                            // Card Action Dock (Compact Sleek Bottom Bar)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                visible: !cardItem.isEditing

                                IconTextButton {
                                    enabled: !cardItem.isEnrichingThis
                                    text: cardItem.isEnrichingThis ? qsTr("Adding Info…") : (cardItem.cardPrimer ? qsTr("Enriched ✨") : qsTr("Add Info ✨"))
                                    icon: cardItem.isEnrichingThis ? "progress_activity" : "auto_awesome"
                                    type: IconTextButton.Tonal
                                    implicitHeight: 26
                                    horizontalPadding: 8
                                    onClicked: {
                                        if (!cardItem.isEnrichingThis) {
                                            Memory.enrichCard(cardItem.cardId)
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                IconTextButton {
                                    text: cardItem.isMastered ? qsTr("Practice") : qsTr("Test Mastery")
                                    icon: "psychology_alt"
                                    type: IconTextButton.Filled
                                    implicitHeight: 26
                                    horizontalPadding: 8
                                    onClicked: {
                                        cardItem.startChallengeRequested(cardItem.cardId)
                                    }
                                }
                            }

                            // Lazy Loader for Edit Mode Drawer
                            Loader {
                                Layout.fillWidth: true
                                active: cardItem.isEditing
                                visible: active
                                sourceComponent: editDrawerComp
                            }
                        }
                    }
                }

                // ═════════════════════════════════════════════════
                // Component: Edit Mode Drawer (Lazy Loaded)
                // ═════════════════════════════════════════════════
                Component {
                    id: editDrawerComp

                        ColumnLayout {
                            Layout.fillWidth: true
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
                                        text: cardItem.editingLinesText
                                        font.family: Tokens.font.body.small.family
                                        font.pointSize: Tokens.font.body.small.pointSize
                                        color: Colours.palette.m3onSurface
                                        wrapMode: TextEdit.Wrap
                                        selectByMouse: true
                                        onTextChanged: {
                                            if (cardItem.isEditing) cardItem.editingLinesText = text
                                        }
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
                                    implicitHeight: 32
                                    onClicked: cardItem.cancelEditingRequested()
                                }

                                IconTextButton {
                                    text: qsTr("Save")
                                    icon: "check"
                                    type: IconTextButton.Filled
                                    implicitHeight: 32
                                    onClicked: cardItem.saveEditingRequested(cardItem.cardId, cardItem.editingLinesText)
                                }
                            }
                        }
                    }
}
