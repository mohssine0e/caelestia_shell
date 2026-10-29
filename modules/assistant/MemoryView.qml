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
    property string debouncedSearchQuery: ""
    property string statusFilter: "all" // "all" | "learning" | "mastered"
    property string selectedConcept: ""
    property string editingCardId: ""
    property string editingTopic: ""
    property string editingLinesText: ""
    property string expandedCardId: ""

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

    // Dynamic Topics & Concepts Extraction
    readonly property int uniqueTopicCount: {
        const list = Memory.cards || []
        const set = new Set()
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].topic) set.add(String(list[i].topic).trim().toLowerCase())
        }
        return set.size
    }

    readonly property var availableConcepts: {
        const counts = {}
        const list = Memory.cards || []
        for (let i = 0; i < list.length; i++) {
            const c = list[i]
            if (!c) continue
            const tags = Array.isArray(c.tags) ? c.tags : []
            for (let j = 0; j < tags.length; j++) {
                const t = String(tags[j]).trim().toLowerCase()
                if (!t) continue
                counts[t] = (counts[t] || 0) + 1
            }
        }
        const result = []
        const keys = Object.keys(counts)
        for (let i = 0; i < keys.length; i++) {
            result.push({ name: keys[i], count: counts[keys[i]] })
        }
        result.sort((a, b) => b.count - a.count || a.name.localeCompare(b.name))
        return result
    }

    readonly property var filterChips: {
        const chips = [{
            name: qsTr("All"),
            tag: "",
            count: Memory.totalCount
        }]
        const concepts = root.availableConcepts
        for (let i = 0; i < concepts.length; i++) {
            chips.push({
                name: concepts[i].name,
                tag: concepts[i].name,
                count: concepts[i].count
            })
        }
        return chips
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
        root.statusFilter = "all"
        root.selectedConcept = ""
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
        root.editingTopic = card.topic || ""
        root.editingLinesText = (card.lines || []).join("\n")
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

    function getCardTimestamp(card) {
        if (!card) return 0
        let maxTime = 0
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
        const ts = root.getCardTimestamp(card)
        if (!ts) return ""
        const diff = Math.floor((Date.now() - ts) / 1000)
        if (diff < 60) return qsTr("just now")
        if (diff < 3600) return qsTr("%1m ago").arg(Math.floor(diff / 60))
        if (diff < 86400) return qsTr("%1h ago").arg(Math.floor(diff / 86400))
        if (diff < 604800) return qsTr("%1d ago").arg(Math.floor(diff / 86400))
        return new Date(ts).toLocaleDateString(Qt.locale(), "MMM d")
    }

    readonly property var filteredCards: {
        const all = Memory.cards || []
        const sf = root.statusFilter
        const sc = root.selectedConcept ? root.selectedConcept.toLowerCase() : ""
        const q = (root.debouncedSearchQuery || "").trim().toLowerCase()

        if (sf === "all" && sc.length === 0 && q.length === 0) {
            return all.slice().sort((a, b) => (b._ts || 0) - (a._ts || 0))
        }

        const list = []
        for (let i = 0; i < all.length; i++) {
            const card = all[i]
            if (!card) continue

            // 1. Status Filter
            if (sf === "mastered" && card.status !== "mastered") continue
            if (sf === "learning" && card.status === "mastered") continue

            // 2. Concept Filter
            if (sc.length > 0) {
                const tags = card.tags || []
                let matchConcept = false
                for (let j = 0; j < tags.length; j++) {
                    if (String(tags[j]).toLowerCase() === sc) {
                        matchConcept = true
                        break
                    }
                }
                if (!matchConcept) continue
            }

            // 3. Search Query
            if (q.length > 0) {
                const topic = (card.topic || "").toLowerCase()
                if (!topic.includes(q)) {
                    const tags = card.tags || []
                    let match = false
                    for (let j = 0; j < tags.length; j++) {
                        if (String(tags[j]).toLowerCase().includes(q)) {
                            match = true
                            break
                        }
                    }
                    if (!match) {
                        const lines = card.lines || []
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
                            text: qsTr("%1 cards").arg(Memory.totalCount)
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            text: "•"
                            font: Tokens.font.label.small
                            color: Colours.palette.m3outline
                        }

                        StyledText {
                            text: qsTr("%1 topics").arg(root.uniqueTopicCount)
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Daily Gauntlet Action (Compact 28x28 button saving maximum header space)
                IconButton {
                    visible: !Memory.isDistilling && !root.isInChallengeMode
                    icon: Memory.isDailyGauntletLoading ? "progress_activity" : "psychology_alt"
                    font: Tokens.font.icon.small
                    implicitWidth: 28
                    implicitHeight: 28
                    type: IconButton.Tonal
                    enabled: !Memory.isDailyGauntletLoading
                    onClicked: {
                        root.resetGauntlet()
                        Memory.startDailyGauntlet()
                    }
                }

                // Knowledge Graph Sync Action
                RowLayout {
                    spacing: 4
                    visible: Memory.isSyncingGraph && !root.isInChallengeMode

                    MaterialIcon {
                        text: "progress_activity"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3secondary

                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 1100
                            loops: Animation.Infinite
                            running: Memory.isSyncingGraph
                        }
                    }

                    StyledText {
                        text: qsTr("Mapping…")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3secondary
                    }
                }

                IconButton {
                    visible: !Memory.isSyncingGraph && !Memory.isDistilling && !root.isInChallengeMode
                    icon: "hub"
                    font: Tokens.font.icon.small
                    implicitWidth: 28
                    implicitHeight: 28
                    type: IconButton.Tonal
                    enabled: Memory.totalCount >= 2
                    onClicked: Memory.syncGraph()
                }

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
                        text: qsTr("Distilling…")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3primary
                    }
                }

                IconTextButton {
                    visible: !Memory.isDistilling && !root.isInChallengeMode
                    text: qsTr("Distill")
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

        NotificationBanner {
            visible: Memory.syncGraphMessage.length > 0 && !root.isInChallengeMode
            icon: "hub"
            text: Memory.syncGraphMessage
            tone: Colours.palette.m3secondary
        }

        NotificationBanner {
            visible: Memory.syncGraphError.length > 0 && !root.isInChallengeMode
            icon: "error"
            text: Memory.syncGraphError
            tone: Colours.palette.m3error
            textColor: Colours.palette.m3error
        }

        // ═════════════════════════════════════════════════════════
        // VIEW 1: CHALLENGE / GAUNTLET MODE (Extracted to GauntletView)
        // ═════════════════════════════════════════════════════════
        GauntletView {
            id: gauntletView
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.isInChallengeMode
            onFinished: {
                Memory.clearChallenge()
            }
        }

        // ═════════════════════════════════════════════════════════
        // VIEW 2: SEARCH & FILTER CONTROLS (List Mode)
        // ═════════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: !root.isInChallengeMode

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
                                text: qsTr("Search cards, topics, or code…")
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

                // Compact Segmented Status Capsule (Counts + Filter)
                StyledRect {
                    implicitHeight: 34
                    implicitWidth: statusSegmentRow.implicitWidth + 8
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3surfaceContainerLow
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant

                    RowLayout {
                        id: statusSegmentRow
                        anchors.centerIn: parent
                        spacing: 3

                        // All Segment
                        StyledRect {
                            implicitHeight: 26
                            implicitWidth: allText.implicitWidth + 14
                            radius: Tokens.rounding.full
                            color: root.statusFilter === "all" ? Colours.palette.m3primary : "transparent"

                            StyledText {
                                id: allText
                                anchors.centerIn: parent
                                text: qsTr("All %1").arg(Memory.totalCount)
                                font: Tokens.font.label.small
                                color: root.statusFilter === "all" ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.statusFilter = "all"
                            }
                        }

                        // Learning Segment
                        StyledRect {
                            implicitHeight: 26
                            implicitWidth: learningRow.implicitWidth + 14
                            radius: Tokens.rounding.full
                            color: root.statusFilter === "learning" ? Qt.alpha(Qt.color("#fbbf24"), 0.2) : "transparent"
                            border.width: root.statusFilter === "learning" ? 1 : 0
                            border.color: "#fbbf24"

                            RowLayout {
                                id: learningRow
                                anchors.centerIn: parent
                                spacing: 4

                                Rectangle {
                                    width: 7; height: 7; radius: 3.5
                                    color: "#fbbf24"
                                }

                                StyledText {
                                    text: String(Memory.learningCount)
                                    font: Tokens.font.label.small
                                    color: root.statusFilter === "learning" ? "#fbbf24" : Colours.palette.m3onSurfaceVariant
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.statusFilter = "learning"
                            }
                        }

                        // Mastered Segment
                        StyledRect {
                            implicitHeight: 26
                            implicitWidth: masteredRow.implicitWidth + 14
                            radius: Tokens.rounding.full
                            color: root.statusFilter === "mastered" ? Qt.alpha(Qt.color("#4ade80"), 0.2) : "transparent"
                            border.width: root.statusFilter === "mastered" ? 1 : 0
                            border.color: "#4ade80"

                            RowLayout {
                                id: masteredRow
                                anchors.centerIn: parent
                                spacing: 4

                                Rectangle {
                                    width: 7; height: 7; radius: 3.5
                                    color: "#4ade80"
                                }

                                StyledText {
                                    text: String(Memory.masteredCount)
                                    font: Tokens.font.label.small
                                    color: root.statusFilter === "mastered" ? "#4ade80" : Colours.palette.m3onSurfaceVariant
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.statusFilter = "mastered"
                            }
                        }
                    }
                }
            }

            // Row 2: Concepts / Topics Filter Strip (Horizontal scrolling chips)
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: root.filterChips.length > 1

                MaterialIcon {
                    text: "label"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3outline
                }

                ListView {
                    id: conceptListView
                    Layout.fillWidth: true
                    implicitHeight: 30
                    orientation: ListView.Horizontal
                    spacing: 6
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    model: root.filterChips

                    delegate: StyledRect {
                        id: chipRect
                        required property var modelData
                        required property int index

                        readonly property bool isSelected: (modelData.tag === "" && root.selectedConcept === "") || (modelData.tag !== "" && root.selectedConcept === modelData.tag)

                        implicitHeight: 26
                        implicitWidth: chipInner.implicitWidth + 14
                        radius: Tokens.rounding.full
                        color: isSelected
                            ? (modelData.tag === "" ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer)
                            : (chipMouse.containsMouse ? Colours.palette.m3surfaceContainerHigh : Colours.palette.m3surfaceContainerLow)
                        border.width: 1
                        border.color: isSelected
                            ? (modelData.tag === "" ? Colours.palette.m3primary : Colours.palette.m3secondary)
                            : Colours.palette.m3outlineVariant

                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            id: chipInner
                            anchors.centerIn: parent
                            spacing: 4

                            StyledText {
                                text: modelData.name
                                font: Tokens.font.label.small
                                color: chipRect.isSelected
                                    ? (modelData.tag === "" ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer)
                                    : Colours.palette.m3onSurfaceVariant
                            }

                            StyledText {
                                text: String(modelData.count)
                                font: Tokens.font.label.small
                                color: chipRect.isSelected
                                    ? (modelData.tag === "" ? Colours.palette.m3onPrimary : Colours.palette.m3secondary)
                                    : Colours.palette.m3outline
                            }

                            MaterialIcon {
                                visible: chipRect.isSelected && modelData.tag !== ""
                                text: "close"
                                fontStyle: Tokens.font.icon.small
                                color: Colours.palette.m3onSecondaryContainer
                            }
                        }

                        MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (chipRect.modelData.tag === "") {
                                    root.selectedConcept = ""
                                } else if (root.selectedConcept === chipRect.modelData.tag) {
                                    root.selectedConcept = ""
                                } else {
                                    root.selectedConcept = chipRect.modelData.tag
                                }
                            }
                        }
                    }
                }

                IconButton {
                    visible: root.selectedConcept.length > 0
                    type: IconButton.Text
                    icon: "filter_alt_off"
                    font: Tokens.font.icon.small
                    implicitWidth: 24
                    implicitHeight: 24
                    onClicked: root.selectedConcept = ""
                }
            }
        }

        // ═════════════════════════════════════════════════════════
        // CARD LIST (Virtualized ListView with Lazy Drawers)
        // ═════════════════════════════════════════════════════════
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
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
                        text: (Memory.totalCount === 0) ? "menu_book" : "find_in_page"
                        fontStyle: Tokens.font.icon.large
                        color: Colours.palette.m3outline
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: (Memory.totalCount === 0)
                            ? qsTr("No memory cards yet. Distill conversations to extract cards.")
                            : qsTr("No cards match your filter criteria.")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3outline
                    }

                    TextButton {
                        visible: Memory.totalCount > 0
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Reset Filters")
                        type: TextButton.Tonal
                        onClicked: {
                            searchInput.text = ""
                            root.searchQuery = ""
                            root.debouncedSearchQuery = ""
                            root.statusFilter = "all"
                            root.selectedConcept = ""
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
                    selectedConcept: root.selectedConcept
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
                    onSelectConceptRequested: concept => {
                        root.selectedConcept = (root.selectedConcept === concept ? "" : concept)
                    }
                    onEditLinesTextChanged: text => {
                        root.editingLinesText = text
                    }
                }
            }
        }
    }
}
