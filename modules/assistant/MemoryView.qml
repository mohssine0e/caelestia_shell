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
    property string typeFilter: "all" // "all" | "knowledge" | "fact"
    property string searchQuery: ""
    property string debouncedSearchQuery: ""
    property string editingCardId: ""
    property string editingTopic: ""
    property string editingLinesText: ""
    property string expandedCardId: ""
    implicitHeight: memoryLayout.implicitHeight

    readonly property int knowledgeCount: {
        const list = Memory.cards || []
        let cnt = 0
        for (let i = 0; i < list.length; i++) {
            if (list[i] && (list[i].type === "knowledge" || (!list[i].type && list[i].tier !== "primitive"))) cnt++
        }
        return cnt
    }

    readonly property int factCount: {
        const list = Memory.cards || []
        let cnt = 0
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].type === "fact") cnt++
        }
        return cnt
    }

    readonly property var pendingProposals: (Memory.proposals || []).filter(p => p && p.type !== "context" && p.review_status !== "dismissed")
    readonly property var currentProposal: root.pendingProposals.length ? root.pendingProposals[0] : null

    function proposalSource(proposal) {
        const ids = proposal && Array.isArray(proposal.sources) ? proposal.sources : []
        const history = Assistant.history || []
        for (let i = 0; i < ids.length; i++) {
            for (let j = 0; j < history.length; j++) {
                if (String(history[j].id) === String(ids[i])) {
                    return history[j].prompt || history[j].text || history[j].original || ""
                }
            }
        }
        return qsTr("Source conversation unavailable")
    }

    Timer {
        id: searchDebounceTimer
        interval: 100
        repeat: false
        onTriggered: {
            root.debouncedSearchQuery = root.searchQuery
        }
    }

    function resetGauntlet() {
        if (gauntletView) gauntletView.reset()
    }

    Keys.onEscapePressed: event => {
        if (root.isInChallengeMode) {
            Memory.clearChallenge()
            root.resetGauntlet()
            event.accepted = true
            return
        }
        if (root.editingCardId.length > 0) {
            root.cancelEditing()
            event.accepted = true
            return
        }
        event.accepted = false
    }

    function jumpToCard(cardId) {
        if (!cardId) return
        const targetId = String(cardId)
        root.searchQuery = ""
        root.debouncedSearchQuery = ""
        if (searchInput) searchInput.text = ""

        root.expandedCardId = targetId

        Qt.callLater(() => {
            const list = root.filteredCards || []
            for (let i = 0; i < list.length; i++) {
                if (String(list[i].id) === targetId) {
                    if (cardsListView) cardsListView.positionViewAtIndex(i, ListView.Beginning)
                    break
                }
            }
        })
    }

    function startEditing(card) {
        if (!card) return
        root.expandedCardId = String(card.id || "")
        root.editingCardId = String(card.id || "")
        root.editingTopic = card.title || card.topic || card.front || ""
        root.editingLinesText = card.type === "fact"
            ? (card.back || (card.lines || []).join("\n"))
            : ((card.invariants && card.invariants.length > 0) ? card.invariants : (card.lines || [])).join("\n")
    }

    function cancelEditing() {
        root.editingCardId = ""
        root.editingTopic = ""
        root.editingLinesText = ""
    }

    function focusSearch() {
        if (searchInput) searchInput.forceActiveFocus()
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
        Memory.updateCard(cardId, cleanLines, root.editingTopic)
        root.cancelEditing()
    }

    readonly property var filteredCards: {
        const all = Memory.cards || []
        const tf = root.typeFilter
        const q = (root.debouncedSearchQuery || "").trim().toLowerCase()

        const list = []
        for (let i = 0; i < all.length; i++) {
            const card = all[i]
            if (!card || card.type === "context") continue

            if (tf !== "all") {
                const ctype = card.type || "knowledge"
                if (tf === "knowledge" && ctype !== "knowledge") continue
                if (tf === "fact" && ctype !== "fact") continue
            }

            if (q.length > 0) {
                const topic = (card.title || card.topic || card.front || card.project_path || "").toLowerCase()
                const back = (card.back || "").toLowerCase()
                const mental = (card.mental_model || card.summary || "").toLowerCase()
                if (!topic.includes(q) && !back.includes(q) && !mental.includes(q)) {
                    const tags = card.tags || []
                    let match = false
                    for (let j = 0; j < tags.length; j++) {
                        if (String(tags[j]).toLowerCase().includes(q)) {
                            match = true
                            break
                        }
                    }
                    if (!match) {
                        const lines = card.invariants || card.lines || []
                        for (let j = 0; j < lines.length; j++) {
                            if (String(lines[j]).toLowerCase().includes(q)) {
                                match = true
                                break
                            }
                        }
                        if (!match) continue
                    }
                }
            }

            list.push(card)
        }

        return list.sort((a, b) => (b._ts || 0) - (a._ts || 0))
    }

    readonly property bool isInChallengeMode: (Memory.activeChallenge !== null || Memory.isGeneratingChallenge || Memory.isDailyGauntletLoading || Memory.lastGradeResult !== null || Memory.challengeError.length > 0 || Memory.dailyGauntletError.length > 0)

    // ─────────────────────────────────────────────────────────────
    // MAIN LAYOUT
    // ─────────────────────────────────────────────────────────────
    ColumnLayout {
        id: memoryLayout
        anchors.fill: parent
        spacing: 10

        // ═════════════════════════════════════════════════════════
        // TOP HEADER
        // ═════════════════════════════════════════════════════════
        Item {
            id: headerContainer
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.ArrowCursor
                onPressed: mouse => {
                    if (root.windowRef) root.windowRef.startSystemMove()
                }
            }

            RowLayout {
                id: headerRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                IconButton {
                    type: IconButton.Text
                    icon: "arrow_back"
                    font: Tokens.font.icon.small
                    implicitWidth: 28
                    implicitHeight: 28
                    onClicked: {
                        if (root.isInChallengeMode) {
                            Memory.clearChallenge()
                            root.resetGauntlet()
                        } else {
                            root.backRequested()
                        }
                    }
                }

                RowLayout {
                    spacing: 6
                    MaterialIcon {
                        text: root.isInChallengeMode ? "psychology_alt" : "psychology"
                        fontStyle: Tokens.font.icon.medium
                        color: root.isInChallengeMode ? Colours.palette.m3tertiary : Colours.palette.m3primary
                    }

                    StyledText {
                        text: root.isInChallengeMode 
                            ? (Memory.activeChallenge && Memory.activeChallenge.is_daily_gauntlet ? qsTr("Daily Gauntlet") : qsTr("Mastery Gauntlet")) 
                            : qsTr("Knowledge & Mastery")
                        font: Tokens.font.title.small
                        color: Colours.palette.m3onSurface
                    }
                }

                // Overview Stats Pill (Compact metadata badge in List mode)
                StyledRect {
                    visible: !root.isInChallengeMode
                    implicitWidth: statsRow.implicitWidth + 14
                    implicitHeight: 22
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3surfaceContainerHigh

                    RowLayout {
                        id: statsRow
                        anchors.centerIn: parent
                        spacing: 5

                        StyledText {
                            text: qsTr("%1 saved").arg(root.knowledgeCount + root.factCount)
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurface
                        }

                    }
                }

                Item { Layout.fillWidth: true }

                // Distill Actions
                RowLayout {
                    spacing: 4
                    visible: Memory.isDistilling && !root.isInChallengeMode

                    MaterialIcon {
                        text: "progress_activity"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3primary

                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 1100
                            loops: Animation.Infinite
                            running: Memory.isDistilling
                        }
                    }

                    StyledText {
                        text: qsTr("Extracting…")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3primary
                    }
                }

                IconTextButton {
                    visible: !Memory.isDistilling && !root.isInChallengeMode
                    enabled: Memory.memoryWritesAllowed
                    text: qsTr("Extract Cards")
                    icon: "auto_awesome"
                    type: IconTextButton.Tonal
                    implicitHeight: 28
                    horizontalPadding: Tokens.padding.small
                    onClicked: Memory.distill()
                }

                IconButton {
                    visible: root.isInChallengeMode
                    type: IconButton.Text
                    icon: "close"
                    font: Tokens.font.icon.small
                    implicitWidth: 28
                    implicitHeight: 28
                    onClicked: {
                        Memory.clearChallenge()
                        root.resetGauntlet()
                    }
                }
            }
        }

        Flickable {
            id: controlsFlick
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(memoryControls.implicitHeight,
                Math.max(120, Math.floor((root.height - headerContainer.implicitHeight - 180) * 0.55)))
            Layout.maximumHeight: Math.max(120, Math.floor((root.height - headerContainer.implicitHeight - 180) * 0.55))
            implicitHeight: memoryControls.implicitHeight
            contentWidth: width
            contentHeight: memoryControls.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: controlsFlick
            }

            ColumnLayout {
                id: memoryControls
                width: controlsFlick.width
                spacing: 10

        StyledRect {
            visible: Memory.memoryStoreState === "backup_pending"
                || Memory.memoryStoreState === "blocked"
                || Memory.memoryStoreState === "backup_failed"
            Layout.fillWidth: true
            implicitHeight: recoveryNotice.implicitHeight + 16
            radius: Tokens.rounding.small
            color: Colours.palette.m3errorContainer

            ColumnLayout {
                id: recoveryNotice
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        if (Memory.memoryStoreState === "backup_pending")
                            return qsTr("Memory file is unreadable. Preserving a recovery copy…")
                        if (Memory.memoryStoreState === "blocked")
                            return qsTr("Memory file is unreadable. It is backed up at %1. Memory changes are paused until you choose to replace it.").arg(Memory.memoryBackupPath)
                        return qsTr("Memory file is unreadable and could not be backed up. Saving is disabled. %1").arg(Memory.memoryRecoveryError)
                    }
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onErrorContainer
                    wrapMode: Text.Wrap
                }

                IconTextButton {
                    visible: Memory.memoryStoreState === "blocked"
                    Layout.alignment: Qt.AlignRight
                    text: qsTr("Replace with empty memory")
                    icon: "warning"
                    type: IconTextButton.Tonal
                    implicitHeight: 28
                    horizontalPadding: Tokens.padding.small
                    onClicked: Memory.acceptMemoryRecovery()
                }
            }
        }

        StyledRect {
            visible: Memory.proposalStoreError.length > 0
            Layout.fillWidth: true
            implicitHeight: proposalRecoveryRow.implicitHeight + 16
            radius: Tokens.rounding.small
            color: Colours.palette.m3errorContainer

            RowLayout {
                id: proposalRecoveryRow
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("%1 File: %2").arg(Memory.proposalStoreError).arg(Memory.proposalsPath)
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onErrorContainer
                    wrapMode: Text.Wrap
                }

                IconTextButton {
                    type: IconTextButton.Tonal
                    icon: "refresh"
                    text: qsTr("Retry")
                    font: Tokens.font.label.small
                    onClicked: Memory.reload()
                }
            }
        }

        // ═════════════════════════════════════════════════════════
        // NOTIFICATIONS
        // ═════════════════════════════════════════════════════════
        NotificationBanner {
            visible: Memory.distillMessage.length > 0 && !root.isInChallengeMode
            icon: "check_circle"
            text: Memory.distillMessage
            tone: Colours.palette.m3primary
        }

        NotificationBanner {
            visible: Memory.consolidateMessage.length > 0 && !root.isInChallengeMode
            icon: "merge_type"
            text: Memory.consolidateMessage
            tone: Colours.palette.m3tertiary
        }

        StyledRect {
            visible: !root.isInChallengeMode && root.currentProposal !== null
            Layout.fillWidth: true
            implicitHeight: proposalColumn.implicitHeight + 16
            radius: Tokens.rounding.small
            color: Colours.palette.m3surfaceContainerLow

            ColumnLayout {
                id: proposalColumn
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Memory suggestion · %1 remaining").arg(root.pendingProposals.length)
                        font: Tokens.font.label.large
                        color: Colours.palette.m3onSurface
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: (root.currentProposal && (root.currentProposal.title || root.currentProposal.front)) || qsTr("Knowledge suggestion")
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3onSurface
                    wrapMode: Text.Wrap
                }
                StyledText {
                    visible: !!(root.currentProposal && (root.currentProposal.mental_model || root.currentProposal.summary || root.currentProposal.back))
                    Layout.fillWidth: true
                    text: root.currentProposal && root.currentProposal.type === "fact"
                        ? root.currentProposal.back
                        : (root.currentProposal ? (root.currentProposal.mental_model || root.currentProposal.summary || "") : "")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.Wrap
                }
                Repeater {
                    model: root.currentProposal ? (root.currentProposal.invariants || []).slice(0, 2) : []
                    delegate: StyledText {
                        required property string modelData
                        Layout.fillWidth: true
                        text: "• " + modelData
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                        wrapMode: Text.Wrap
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.currentProposal ? qsTr("From: %1").arg(root.proposalSource(root.currentProposal)) : ""
                    font: Tokens.font.label.small
                    color: Colours.palette.m3outline
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: root.currentProposal && root.currentProposal.scope === "project" ? qsTr("Project knowledge") : qsTr("General knowledge")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                    TextButton {
                        text: qsTr("Dismiss")
                        type: TextButton.Text
                        onClicked: Memory.reviewProposal(root.currentProposal.id, false)
                    }
                    TextButton {
                        text: qsTr("Keep in memory")
                        type: TextButton.Tonal
                        onClicked: Memory.reviewProposal(root.currentProposal.id, true)
                    }
                }
            }
        }

        // ═════════════════════════════════════════════════════════
        // VIEW 2: SEARCH & FILTER CONTROLS (List Mode)
        // ═════════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: !root.isInChallengeMode

            // Simple type filters; workspace context remains out of the knowledge list.
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: [
                        { id: "all", label: qsTr("All"), count: root.knowledgeCount + root.factCount, icon: "apps" },
                        { id: "knowledge", label: qsTr("Knowledge"), count: root.knowledgeCount, icon: "psychology" },
                        { id: "fact", label: qsTr("Facts"), count: root.factCount, icon: "bolt" }
                    ]

                    delegate: StyledRect {
                        required property var modelData

                        readonly property bool isSelected: root.typeFilter === modelData.id
                        readonly property bool isHovered: pillMouse.containsMouse

                        implicitHeight: 28
                        implicitWidth: pillRow.implicitWidth + 16
                        radius: Tokens.rounding.full
                        color: isSelected 
                            ? Colours.palette.m3primary 
                            : (isHovered ? Colours.palette.m3surfaceContainerHigh : Colours.palette.m3surfaceContainerLow)
                        border.width: 1
                        border.color: isSelected ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

                        MouseArea {
                            id: pillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.typeFilter = modelData.id
                            }
                        }

                        RowLayout {
                            id: pillRow
                            anchors.centerIn: parent
                            spacing: 5

                            MaterialIcon {
                                text: modelData.icon
                                fontStyle: Tokens.font.icon.small
                                color: isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                            }

                            StyledText {
                                text: qsTr("%1 (%2)").arg(modelData.label).arg(modelData.count)
                                font: Tokens.font.label.small
                                color: isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                IconTextButton {
                    visible: !Memory.isDistilling
                    enabled: Memory.memoryWritesAllowed && !Memory.isDailyGauntletLoading
                    text: Memory.dueCount > 0 ? qsTr("Practice · %1 due").arg(Memory.dueCount) : qsTr("Practice")
                    icon: Memory.isDailyGauntletLoading ? "progress_activity" : "psychology_alt"
                    type: IconTextButton.Tonal
                    implicitHeight: 28
                    horizontalPadding: Tokens.padding.small
                    onClicked: {
                        root.resetGauntlet()
                        Memory.startDueChallenge()
                    }
                }
            }

            // Row 1: Search Bar & Segmented Status Capsule
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // Search Box
                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3surfaceContainerLowest
                    border.width: 1
                    border.color: searchInput.activeFocus ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8

                        MaterialIcon {
                            text: "search"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3outline
                        }

                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            font.family: Tokens.font.body.small.family
                            font.pointSize: Tokens.font.body.small.pointSize
                            color: Colours.palette.m3onSurface
                            selectByMouse: true
                            onTextChanged: {
                                root.searchQuery = text
                                if (text.length === 0) {
                                    searchDebounceTimer.stop()
                                    root.debouncedSearchQuery = ""
                                } else {
                                    searchDebounceTimer.restart()
                                }
                            }

                            StyledText {
                                visible: searchInput.text.length === 0
                                text: qsTr("Search saved knowledge…")
                                font: Tokens.font.body.small
                                color: Colours.palette.m3outline
                            }
                        }

                        IconButton {
                            visible: root.searchQuery.length > 0
                            type: IconButton.Text
                            icon: "close"
                            font: Tokens.font.icon.small
                            implicitWidth: 20
                            implicitHeight: 20
                            onClicked: {
                                searchInput.text = ""
                                root.searchQuery = ""
                                root.debouncedSearchQuery = ""
                                searchDebounceTimer.stop()
                            }
                        }
                    }
                }

            }
        }
            }
        }

        // ═════════════════════════════════════════════════════════
        // VIEW 1: CHALLENGE / GAUNTLET MODE (Extracted to GauntletView)
        // ═════════════════════════════════════════════════════════
        GauntletView {
            id: gauntletView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 120
            visible: root.isInChallengeMode
            onFinished: Memory.clearChallenge()
        }

        // ═════════════════════════════════════════════════════════
        // CARD LIST (Virtualized ListView with Lazy Drawers)
        // ═════════════════════════════════════════════════════════
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 140
            implicitHeight: 360
            visible: !root.isInChallengeMode

            // Empty State (Centered Overlay)
            StyledRect {
                anchors.centerIn: parent
                implicitWidth: Math.min(parent.width - 40, 400)
                implicitHeight: 120
                radius: Tokens.rounding.medium
                color: Colours.palette.m3surfaceContainerLow
                visible: root.filteredCards.length === 0

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: (root.knowledgeCount + root.factCount === 0) ? "menu_book" : "find_in_page"
                        fontStyle: Tokens.font.icon.large
                        color: Colours.palette.m3outline
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: (root.knowledgeCount + root.factCount === 0)
                            ? qsTr("No saved knowledge yet. Extract suggestions from your conversations.")
                            : qsTr("No saved knowledge matches this search.")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3outline
                    }

                    TextButton {
                        visible: root.searchQuery.length > 0 || root.typeFilter !== "all"
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Clear search")
                        type: TextButton.Tonal
                        onClicked: {
                            searchInput.text = ""
                            root.searchQuery = ""
                            root.debouncedSearchQuery = ""
                            root.typeFilter = "all"
                        }
                    }
                }
            }

            // Virtualized Cards List
            ListView {
                id: cardsListView
                anchors.fill: parent
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 600
                reuseItems: true
                model: root.filteredCards
                visible: root.filteredCards.length > 0

                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: cardsListView
                }

                delegate: MemoryCardItem {
                    id: cardDelegate
                    required property var modelData
                    card: modelData
                    width: cardsListView.width
                    editingCardId: root.editingCardId
                    expandedCardId: root.expandedCardId
                    editingLinesText: root.editingLinesText
                    onStartEditingRequested: cardData => root.startEditing(cardData)
                    onCancelEditingRequested: root.cancelEditing()
                    onSaveEditingRequested: (cardId, text) => {
                        root.editingLinesText = text
                        root.saveEditing(cardId)
                    }
                    onToggleExpandRequested: cardId => {
                        root.expandedCardId = (root.expandedCardId === cardId ? "" : cardId)
                    }
                    onStartChallengeRequested: cardId => {
                        root.resetGauntlet()
                        Memory.startChallenge(cardId)
                    }
                    onEditLinesTextChanged: text => {
                        root.editingLinesText = text
                    }
                }
            }
        }
    }
}
