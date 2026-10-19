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

    // Multi-Question Gauntlet State
    property int activeQuestionIndex: 0
    property var userAnswers: ({})

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

    component SelectableText: TextEdit {
        readOnly: true
        selectByMouse: true
        cursorVisible: false
        wrapMode: TextEdit.Wrap
        textFormat: TextEdit.PlainText
        font.family: Tokens.font.body.small.family
        font.pointSize: Tokens.font.body.small.pointSize
        color: Colours.palette.m3onSurface
        selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
        selectedTextColor: Colours.palette.m3onSurface
        renderType: TextEdit.NativeRendering
    }

    Keys.onEscapePressed: event => {
        if (root.isInChallengeMode) {
            Memory.clearChallenge()
            root.activeQuestionIndex = 0
            root.userAnswers = ({})
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

    readonly property var currentQuestions: {
        if (!Memory.activeChallenge) return []
        if (Array.isArray(Memory.activeChallenge.questions)) {
            return Memory.activeChallenge.questions
        }
        return [{
            "id": "q1",
            "type": Memory.activeChallenge.type || "edge_case",
            "title": "Technical Challenge",
            "question": Memory.activeChallenge.question || "",
            "criteria": Memory.activeChallenge.criteria || []
        }]
    }

    readonly property var activeQuestion: {
        const qList = root.currentQuestions
        if (!qList || qList.length === 0) return null
        const idx = Math.min(Math.max(0, root.activeQuestionIndex), qList.length - 1)
        return qList[idx]
    }

    function setAnswer(qId, val) {
        const updated = Object.assign({}, root.userAnswers)
        updated[qId] = val
        root.userAnswers = updated
    }

    function getAnswer(qId) {
        return (root.userAnswers && root.userAnswers[qId]) ? root.userAnswers[qId] : ""
    }

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
                            root.activeQuestionIndex = 0
                            root.userAnswers = ({})
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
                        root.activeQuestionIndex = 0
                        root.userAnswers = ({})
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
                        root.activeQuestionIndex = 0
                        root.userAnswers = ({})
                    }
                }
            }
        }

        // ═════════════════════════════════════════════════════════
        // DISTILL NOTIFICATIONS
        // ═════════════════════════════════════════════════════════
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 28
            radius: Tokens.rounding.small
            color: Qt.alpha(Colours.palette.m3primary, 0.15)
            visible: Memory.distillMessage.length > 0 && !root.isInChallengeMode

            RowLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 6

                MaterialIcon {
                    text: "check_circle"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3primary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Memory.distillMessage
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                }
            }
        }

        // ═════════════════════════════════════════════════════════
        // CONSOLIDATION NOTIFICATIONS
        // ═════════════════════════════════════════════════════════
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 28
            radius: Tokens.rounding.small
            color: Qt.alpha(Colours.palette.m3tertiary, 0.15)
            visible: Memory.consolidateMessage.length > 0 && !root.isInChallengeMode

            RowLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 6

                MaterialIcon {
                    text: "merge_type"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3tertiary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Memory.consolidateMessage
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                }
            }
        }

        // ═════════════════════════════════════════════════════════
        // KNOWLEDGE GRAPH NOTIFICATIONS
        // ═════════════════════════════════════════════════════════
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 28
            radius: Tokens.rounding.small
            color: Qt.alpha(Colours.palette.m3secondary, 0.15)
            visible: Memory.syncGraphMessage.length > 0 && !root.isInChallengeMode

            RowLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 6

                MaterialIcon {
                    text: "hub"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3secondary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Memory.syncGraphMessage
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                }
            }
        }

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 28
            radius: Tokens.rounding.small
            color: Qt.alpha(Colours.palette.m3error, 0.15)
            visible: Memory.syncGraphError.length > 0 && !root.isInChallengeMode

            RowLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 6

                MaterialIcon {
                    text: "error"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3error
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Memory.syncGraphError
                    font: Tokens.font.label.small
                    color: Colours.palette.m3error
                }
            }
        }

        // ═════════════════════════════════════════════════════════
        // VIEW 1: CHALLENGE / GAUNTLET MODE (Multi-Question)
        // ═════════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6
            visible: root.isInChallengeMode

            // Error state
            StyledRect {
                Layout.fillWidth: true
                implicitHeight: errCol.implicitHeight + 16
                radius: Tokens.rounding.medium
                color: Qt.alpha(Colours.palette.m3error, 0.15)
                border.width: 1
                border.color: Colours.palette.m3error
                visible: (Memory.challengeError.length > 0 || Memory.dailyGauntletError.length > 0)

                ColumnLayout {
                    id: errCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        spacing: 6
                        MaterialIcon {
                            text: "error"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3error
                        }
                        StyledText {
                            text: qsTr("Challenge Engine Error")
                            font: Tokens.font.label.large
                            color: Colours.palette.m3onSurface
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Memory.challengeError || Memory.dailyGauntletError
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurface
                        wrapMode: Text.Wrap
                    }

                    RowLayout {
                        Item { Layout.fillWidth: true }
                        TextButton {
                            text: qsTr("Dismiss")
                            type: TextButton.Tonal
                            onClicked: Memory.clearChallenge()
                        }
                    }
                }
            }

            // Loading state while generating challenge
            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Tokens.rounding.medium
                color: Colours.palette.m3surfaceContainerLow
                visible: Memory.isGeneratingChallenge || Memory.isDailyGauntletLoading

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "progress_activity"
                        fontStyle: Tokens.font.icon.medium
                        color: Colours.palette.m3primary

                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 1000
                            loops: Animation.Infinite
                            running: Memory.isGeneratingChallenge || Memory.isDailyGauntletLoading
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Memory.isDailyGauntletLoading ? qsTr("Crafting Daily Gauntlet…") : qsTr("Generating Mastery Assessment…")
                        font: Tokens.font.title.small
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Adaptive Concept Checks • Bug Hunts • Architectural Edge Cases")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                    }
                }
            }

            // ─────────────────────────────────────────────────────
            // ACTIVE GAUNTLET (Question Stepper)
            // ─────────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6
                visible: !Memory.isGeneratingChallenge && Memory.activeChallenge !== null && Memory.lastGradeResult === null

                // Top Stepper Navigation Tabs
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: root.currentQuestions

                        delegate: StyledRect {
                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            implicitHeight: 28
                            radius: Tokens.rounding.small
                            color: (root.activeQuestionIndex === index) 
                                ? Colours.palette.m3primaryContainer 
                                : Colours.palette.m3surfaceContainerLow
                            border.width: 1
                            border.color: (root.activeQuestionIndex === index) 
                                ? Colours.palette.m3primary 
                                : Colours.palette.m3outlineVariant

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeQuestionIndex = index
                            }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 4

                                MaterialIcon {
                                    text: {
                                        if (modelData.type === "qcm") return "radio_button_checked"
                                        if (modelData.type === "bug_hunt") return "bug_report"
                                        return "bolt"
                                    }
                                    fontStyle: Tokens.font.icon.small
                                    color: (root.activeQuestionIndex === index) ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3outline
                                }

                                StyledText {
                                    text: qsTr("%1. %2").arg(index + 1).arg(modelData.title || (modelData.type === "qcm" ? "QCM" : modelData.type === "bug_hunt" ? "Bug Hunt" : "Edge Case"))
                                    font: Tokens.font.label.small
                                    color: (root.activeQuestionIndex === index) ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                                }

                                MaterialIcon {
                                    visible: (root.getAnswer(modelData.id).trim().length > 0)
                                    text: "check"
                                    fontStyle: Tokens.font.icon.small
                                    color: Colours.palette.m3primary
                                }
                            }
                        }
                    }
                }

                // Active Question View Container
                StyledRect {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Tokens.rounding.medium
                    color: Colours.palette.m3surfaceContainerLow
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 10
                        contentWidth: width
                        contentHeight: questionContentCol.implicitHeight + 10
                        clip: true

                        ColumnLayout {
                            id: questionContentCol
                            width: parent.width
                            spacing: 8

                            // Question Title & Type Badge
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                StyledRect {
                                    implicitWidth: qTypeBadge.implicitWidth + 10
                                    implicitHeight: 18
                                    radius: Tokens.rounding.full
                                    color: Colours.palette.m3tertiaryContainer

                                    StyledText {
                                        id: qTypeBadge
                                        anchors.centerIn: parent
                                        text: root.activeQuestion ? String(root.activeQuestion.type).toUpperCase() : ""
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3onTertiaryContainer
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.activeQuestion ? root.activeQuestion.title : ""
                                    font: Tokens.font.label.large
                                    color: Colours.palette.m3onSurface
                                }
                            }

                            // Question Text / Scenario
                            SelectableText {
                                Layout.fillWidth: true
                                text: root.activeQuestion ? root.activeQuestion.question : ""
                                textFormat: TextEdit.MarkdownText
                                color: Colours.palette.m3onSurface
                            }

                            // ── Case A: Multiple Choice (QCM) Options ──────────
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 5
                                visible: root.activeQuestion && root.activeQuestion.type === "qcm"

                                Repeater {
                                    model: (root.activeQuestion && root.activeQuestion.options) ? root.activeQuestion.options : []

                                    delegate: StyledRect {
                                        required property var modelData
                                        required property int index

                                        readonly property string optLetter: ["A", "B", "C", "D"][index] || "A"
                                        readonly property bool isSelected: root.getAnswer(root.activeQuestion ? root.activeQuestion.id : "q1") === optLetter

                                        Layout.fillWidth: true
                                        implicitHeight: optRow.implicitHeight + 8
                                        radius: Tokens.rounding.small
                                        color: isSelected ? Qt.alpha(Colours.palette.m3primary, 0.18) : Colours.palette.m3surfaceContainerLowest
                                        border.width: isSelected ? 2 : 1
                                        border.color: isSelected ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.activeQuestion) {
                                                    root.setAnswer(root.activeQuestion.id, optLetter)
                                                }
                                            }
                                        }

                                        RowLayout {
                                            id: optRow
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 8

                                            StyledRect {
                                                implicitWidth: 20
                                                implicitHeight: 20
                                                radius: Tokens.rounding.full
                                                color: isSelected ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh

                                                StyledText {
                                                    anchors.centerIn: parent
                                                    text: optLetter
                                                    font: Tokens.font.label.small
                                                    color: isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                                }
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: String(modelData)
                                                font: Tokens.font.body.small
                                                color: Colours.palette.m3onSurface
                                                wrapMode: Text.Wrap
                                            }

                                            MaterialIcon {
                                                visible: isSelected
                                                text: "check_circle"
                                                fontStyle: Tokens.font.icon.small
                                                color: Colours.palette.m3primary
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Case B: Open-Ended / Bug Hunt Answer Box ───────
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                visible: root.activeQuestion && root.activeQuestion.type !== "qcm"

                                StyledRect {
                                    Layout.fillWidth: true
                                    implicitHeight: 85
                                    radius: Tokens.rounding.small
                                    color: Colours.palette.m3surfaceContainerLowest
                                    border.width: 1
                                    border.color: answerEditArea.activeFocus ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

                                    Flickable {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        contentWidth: width
                                        contentHeight: answerEditArea.implicitHeight
                                        clip: true

                                        TextEdit {
                                            id: answerEditArea
                                            width: parent.width
                                            text: root.activeQuestion ? root.getAnswer(root.activeQuestion.id) : ""
                                            font.family: Tokens.font.body.small.family
                                            font.pointSize: Tokens.font.body.small.pointSize
                                            color: Colours.palette.m3onSurface
                                            wrapMode: TextEdit.Wrap
                                            selectByMouse: true
                                            onTextChanged: {
                                                if (root.activeQuestion) {
                                                    root.setAnswer(root.activeQuestion.id, text)
                                                }
                                            }

                                            StyledText {
                                                visible: answerEditArea.text.length === 0
                                                text: qsTr("Explain the flaw/fix (or speak using Super+Alt+V)...")
                                                font: Tokens.font.body.small
                                                color: Colours.palette.m3outline
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Bottom Stepper Controls
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    StyledText {
                        text: qsTr("🎙️ Super+Alt+V works on all text areas.")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                    }

                    Item { Layout.fillWidth: true }

                    TextButton {
                        enabled: root.activeQuestionIndex > 0
                        text: qsTr("← Back")
                        type: TextButton.Tonal
                        onClicked: root.activeQuestionIndex = Math.max(0, root.activeQuestionIndex - 1)
                    }

                    StyledText {
                        text: qsTr("%1 / %2").arg(root.activeQuestionIndex + 1).arg(root.currentQuestions.length)
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    IconTextButton {
                        visible: root.activeQuestionIndex < root.currentQuestions.length - 1
                        text: qsTr("Next →")
                        icon: "arrow_forward"
                        type: IconTextButton.Tonal
                        onClicked: root.activeQuestionIndex = Math.min(root.currentQuestions.length - 1, root.activeQuestionIndex + 1)
                    }

                    IconTextButton {
                        visible: root.activeQuestionIndex === root.currentQuestions.length - 1
                        enabled: !Memory.isGrading
                        text: Memory.isGrading ? qsTr("Grading…") : qsTr("Submit Trial 🚀")
                        icon: Memory.isGrading ? "progress_activity" : "verified"
                        type: IconTextButton.Filled
                        onClicked: {
                            if (Memory.activeChallenge && Memory.activeChallenge.card_id) {
                                Memory.submitAnswer(Memory.activeChallenge.card_id, root.userAnswers)
                            }
                        }
                    }
                }
            }

            // ─────────────────────────────────────────────────────
            // GAUNTLET REPORT CARD (Results View with Correct Answers)
            // ─────────────────────────────────────────────────────
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: reportCardCol.implicitHeight + 10
                clip: true
                visible: Memory.lastGradeResult !== null

                ColumnLayout {
                    id: reportCardCol
                    width: parent.width
                    spacing: 6

                    // Overall Verdict Banner
                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: verdictRow.implicitHeight + 14
                        radius: Tokens.rounding.medium
                        color: {
                            if (!Memory.lastGradeResult) return "transparent"
                            return Memory.lastGradeResult.verdict === "pass" 
                                ? Qt.alpha(Colours.palette.m3primary, 0.15) 
                                : Qt.alpha(Colours.palette.m3error, 0.15)
                        }
                        border.width: 1
                        border.color: {
                            if (!Memory.lastGradeResult) return "transparent"
                            return Memory.lastGradeResult.verdict === "pass" 
                                ? Colours.palette.m3primary 
                                : Colours.palette.m3error
                        }

                        RowLayout {
                            id: verdictRow
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8

                            MaterialIcon {
                                text: (Memory.lastGradeResult && Memory.lastGradeResult.verdict === "pass") ? "verified" : "error"
                                fontStyle: Tokens.font.icon.medium
                                color: (Memory.lastGradeResult && Memory.lastGradeResult.verdict === "pass") ? Colours.palette.m3primary : Colours.palette.m3error
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    text: {
                                        if (!Memory.lastGradeResult) return ""
                                        const score = Math.round((Memory.lastGradeResult.score || 0) * 100)
                                        return (Memory.lastGradeResult.verdict === "pass")
                                            ? qsTr("🟢 TRIAL PASSED (%1%) — CONCEPT MASTERED").arg(score)
                                            : qsTr("❌ TRIAL FAILED (%1%) — REMAINS IN LEARNING").arg(score)
                                    }
                                    font: Tokens.font.label.large
                                    color: Colours.palette.m3onSurface
                                }

                                StyledText {
                                    text: (Memory.lastGradeResult && Memory.lastGradeResult.verdict === "pass")
                                        ? qsTr("All criteria satisfied. Topic promoted to Mastered.")
                                        : qsTr("Study the canonical solutions below before retrying.")
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3onSurfaceVariant
                                }
                            }
                        }
                    }

                    // Per-Question Breakdown with Canonical Answers
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: Memory.lastGradeResult && Memory.lastGradeResult.q_results

                        Repeater {
                            model: {
                                if (!Memory.lastGradeResult || !Memory.lastGradeResult.q_results) return []
                                const res = Memory.lastGradeResult.q_results
                                return Object.keys(res).map(k => ({ "id": k, "info": res[k] }))
                            }

                            delegate: StyledRect {
                                required property var modelData
                                required property int index

                                readonly property bool isPassed: modelData.info.verdict === "pass"

                                Layout.fillWidth: true
                                implicitHeight: qResCol.implicitHeight + 12
                                radius: Tokens.rounding.small
                                color: Colours.palette.m3surfaceContainerLow
                                border.width: 1
                                border.color: isPassed ? Qt.alpha(Colours.palette.m3primary, 0.4) : Qt.alpha(Colours.palette.m3error, 0.4)

                                ColumnLayout {
                                    id: qResCol
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        MaterialIcon {
                                            text: isPassed ? "check_circle" : "cancel"
                                            fontStyle: Tokens.font.icon.small
                                            color: isPassed ? Colours.palette.m3primary : Colours.palette.m3error
                                        }

                                        StyledText {
                                            text: qsTr("Question %1: %2").arg(index + 1).arg(isPassed ? qsTr("Passed") : qsTr("Incorrect / Needs Work"))
                                            font: Tokens.font.label.large
                                            color: isPassed ? Colours.palette.m3primary : Colours.palette.m3error
                                        }
                                    }

                                    // Evaluation comment
                                    SelectableText {
                                        Layout.fillWidth: true
                                        text: String(modelData.info.comment || "")
                                        color: Colours.palette.m3onSurfaceVariant
                                    }

                                    // Canonical Correct Solution Box (Crucial for Learning!)
                                    StyledRect {
                                        visible: modelData.info.correct_solution && modelData.info.correct_solution.length > 0
                                        Layout.fillWidth: true
                                        implicitHeight: solCol.implicitHeight + 8
                                        radius: Tokens.rounding.small
                                        color: Qt.alpha(Colours.palette.m3primary, 0.08)
                                        border.width: 1
                                        border.color: Qt.alpha(Colours.palette.m3primary, 0.3)

                                        ColumnLayout {
                                            id: solCol
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            spacing: 2

                                            RowLayout {
                                                spacing: 4
                                                MaterialIcon {
                                                    text: "lightbulb"
                                                    fontStyle: Tokens.font.icon.small
                                                    color: Colours.palette.m3primary
                                                }
                                                StyledText {
                                                    text: qsTr("Canonical Correct Solution:")
                                                    font: Tokens.font.label.small
                                                    color: Colours.palette.m3primary
                                                }
                                            }

                                            SelectableText {
                                                Layout.fillWidth: true
                                                text: String(modelData.info.correct_solution || "")
                                                textFormat: TextEdit.MarkdownText
                                                color: Colours.palette.m3onSurface
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Strengths & Blindspots
                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: feedbackCol.implicitHeight + 12
                        radius: Tokens.rounding.medium
                        color: Colours.palette.m3surfaceContainerLow

                        ColumnLayout {
                            id: feedbackCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            SelectableText {
                                Layout.fillWidth: true
                                text: qsTr("**Strengths:** %1").arg(Memory.lastGradeResult ? Memory.lastGradeResult.strengths : "")
                                textFormat: TextEdit.MarkdownText
                                color: Colours.palette.m3onSurface
                            }

                            SelectableText {
                                Layout.fillWidth: true
                                text: qsTr("**Blindspots:** %1").arg(Memory.lastGradeResult ? Memory.lastGradeResult.blindspots : "")
                                textFormat: TextEdit.MarkdownText
                                color: Colours.palette.m3onSurface
                            }

                            SelectableText {
                                Layout.fillWidth: true
                                text: qsTr("**Mastery Rule:** %1").arg(Memory.lastGradeResult ? (Memory.lastGradeResult.compressed_summary || Memory.lastGradeResult.explanation) : "")
                                textFormat: TextEdit.MarkdownText
                                color: Colours.palette.m3primary
                            }
                        }
                    }

                    // Return Button
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }

                        IconTextButton {
                            text: qsTr("Return to Cards")
                            icon: "check"
                            type: IconTextButton.Filled
                            onClicked: {
                                Memory.clearChallenge()
                                root.activeQuestionIndex = 0
                                root.userAnswers = ({})
                            }
                        }
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

                delegate: Item {
                    id: cardItem
                    required property var modelData
                    property bool showArchived: false

                    width: ListView.view ? ListView.view.width : parent ? parent.width : 0
                    implicitHeight: cardRect.implicitHeight
                    height: cardRect.implicitHeight

                    readonly property var cardData: (cardItem && cardItem.modelData) ? cardItem.modelData : ({})
                    readonly property var cardPrimer: cardData ? (cardData.primer || null) : null
                    readonly property string cardId: String(cardData ? (cardData.id || "") : "")
                    readonly property bool isEditing: root.editingCardId.length > 0 && root.editingCardId === cardId
                    readonly property bool isMastered: cardData ? (cardData.status === "mastered") : false
                    readonly property bool hasFailFeedback: !!(cardData && cardData.last_fail_feedback && cardData.last_fail_feedback.length > 0)
                    readonly property bool isEnrichingThis: (Memory.isEnriching && Memory.enrichingCardId === cardId)
                    readonly property var cardSections: cardData ? (cardData.sections || []) : []
                    readonly property bool isCodeHub: cardData ? (cardData.type === "code_hub" || cardSections.length > 0) : false
                    property int activeSectionIndex: 0
                    readonly property var currentSection: (cardSections && cardSections.length > 0 && activeSectionIndex >= 0 && activeSectionIndex < cardSections.length) ? cardSections[activeSectionIndex] : null
                    readonly property bool expanded: (cardId.length > 0 && root.expandedCardId === cardId) || isEditing
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
                                    root.expandedCardId = (root.expandedCardId === sid) ? "" : sid
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
                                StyledRect {
                                    visible: cardItem.isCodeHub
                                    implicitWidth: hubPillRow.implicitWidth + 8
                                    implicitHeight: 18
                                    radius: Tokens.rounding.full
                                    color: Qt.alpha(Colours.palette.m3primary, 0.12)
                                    border.width: 1
                                    border.color: Qt.alpha(Colours.palette.m3primary, 0.3)

                                    RowLayout {
                                        id: hubPillRow
                                        anchors.centerIn: parent
                                        spacing: 3

                                        MaterialIcon {
                                            text: "code"
                                            fontStyle: Tokens.font.icon.small
                                            color: Colours.palette.m3primary
                                        }

                                        StyledText {
                                            text: cardItem.cardSections.length > 0
                                                ? qsTr("%1 modules").arg(cardItem.cardSections.length)
                                                : qsTr("Code Hub")
                                            font: Tokens.font.label.small
                                            color: Colours.palette.m3primary
                                        }
                                    }
                                }

                                // Active In-Context Badge (HUD Prompt Injection)
                                StyledRect {
                                    visible: cardItem.isInjectedInPrompt
                                    implicitWidth: injectedRow.implicitWidth + 10
                                    implicitHeight: 20
                                    radius: Tokens.rounding.full
                                    color: Qt.alpha(Colours.palette.m3secondary, 0.16)
                                    border.width: 1
                                    border.color: Colours.palette.m3secondary

                                    RowLayout {
                                        id: injectedRow
                                        anchors.centerIn: parent
                                        spacing: 4

                                        MaterialIcon {
                                            text: "psychology"
                                            fontStyle: Tokens.font.icon.small
                                            color: Colours.palette.m3secondary
                                        }

                                        StyledText {
                                            text: qsTr("In Context")
                                            font: Tokens.font.label.small
                                            color: Colours.palette.m3secondary
                                        }
                                    }
                                }

                                // Spaced Repetition: Review Due Badge (> 14 days)
                                StyledRect {
                                    visible: cardItem.isReviewDue
                                    implicitWidth: reviewDueRow.implicitWidth + 10
                                    implicitHeight: 20
                                    radius: Tokens.rounding.full
                                    color: Qt.alpha(Colours.palette.m3tertiary, 0.16)
                                    border.width: 1
                                    border.color: Colours.palette.m3tertiary

                                    RowLayout {
                                        id: reviewDueRow
                                        anchors.centerIn: parent
                                        spacing: 4

                                        MaterialIcon {
                                            text: "schedule"
                                            fontStyle: Tokens.font.icon.small
                                            color: Colours.palette.m3tertiary
                                        }

                                        StyledText {
                                            text: qsTr("Review Due")
                                            font: Tokens.font.label.small
                                            color: Colours.palette.m3tertiary
                                        }
                                    }
                                }

                                StyledText {
                                    text: root.formatCardTime(cardItem.cardData)
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
                                                readonly property bool isTagSelected: root.selectedConcept === tagStr

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
                                                        if (root.selectedConcept === cardTagChip.tagStr) {
                                                            root.selectedConcept = ""
                                                        } else {
                                                            root.selectedConcept = cardTagChip.tagStr
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
                                    onClicked: root.startEditing(cardItem.cardData)
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
                                            if (root.expandedCardId === cardItem.cardId) {
                                                root.expandedCardId = ""
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
                                        root.activeQuestionIndex = 0
                                        root.userAnswers = ({})
                                        Memory.startChallenge(cardItem.cardId)
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
                                        text: root.editingLinesText
                                        font.family: Tokens.font.body.small.family
                                        font.pointSize: Tokens.font.body.small.pointSize
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
                                spacing: 8

                                Item { Layout.fillWidth: true }

                                TextButton {
                                    text: qsTr("Cancel")
                                    type: TextButton.Tonal
                                    implicitHeight: 32
                                    onClicked: root.cancelEditing()
                                }

                                IconTextButton {
                                    text: qsTr("Save")
                                    icon: "check"
                                    type: IconTextButton.Filled
                                    implicitHeight: 32
                                    onClicked: root.saveEditing(cardItem.cardId)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
