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
    property string selectedTag: "all"
    property bool reviewMode: false
    property int reviewIndex: 0
    property bool reviewRevealed: false
    property bool reviewShowHint: false
    property bool reviewShowSolution: false
    property var shuffledOrder: []
    property string expandedId: ""

    readonly property var starredItems: {
        if (root.shuffledOrder.length > 0) return root.shuffledOrder
        const items = Assistant.history || []
        return items.filter(item => !!item.starred)
    }

    function shuffleStarred() {
        const arr = (Assistant.history || []).filter(item => !!item.starred)
        for (let i = arr.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1))
            const temp = arr[i]
            arr[i] = arr[j]
            arr[j] = temp
        }
        root.shuffledOrder = arr
        root.reviewIndex = 0
        root.reviewRevealed = false
        root.reviewShowHint = false
        root.reviewShowSolution = false
    }

    focus: true

    Keys.onEscapePressed: event => {
        if (root.reviewMode) {
            root.reviewMode = false
            root.shuffledOrder = []
            event.accepted = true
            return
        }
        root.backRequested()
        event.accepted = true
    }

    function formatTime(ts) {
        if (!ts) return ""
        const diff = Math.floor((Date.now() - ts) / 1000)
        if (diff < 60) return qsTr("just now")
        if (diff < 3600) return qsTr("%1m ago").arg(Math.floor(diff / 60))
        if (diff < 86400) return qsTr("%1h ago").arg(Math.floor(diff / 3600))
        if (diff < 604800) return qsTr("%1d ago").arg(Math.floor(diff / 86400))
        return new Date(ts).toLocaleDateString(Qt.locale(), "MMM d")
    }

    function getActionIcon(action) {
        switch (action) {
            case "translate": return "translate"
            case "explain": return "lightbulb"
            case "tldr": return "notes"
            case "rephrase": return "sync"
            case "examples": return "format_list_bulleted"
            case "ask": return "chat"
            default: return "auto_awesome"
        }
    }

    function getActionLabel(action) {
        switch (action) {
            case "translate": return qsTr("Translate")
            case "explain": return qsTr("Explain")
            case "tldr": return qsTr("TL;DR")
            case "rephrase": return qsTr("Rephrase")
            case "examples": return qsTr("Examples")
            case "ask": return qsTr("Question")
            default: return qsTr("AI")
        }
    }

    // Extract unique tags from all history items
    readonly property var allTags: {
        const set = {}
        const items = Assistant.history || []
        for (let i = 0; i < items.length; i++) {
            const tags = items[i].tags || []
            for (let j = 0; j < tags.length; j++) {
                if (tags[j] && tags[j].trim().length > 0) {
                    set[tags[j].trim().toLowerCase()] = true
                }
            }
        }
        return Object.keys(set).sort()
    }

    property string searchQuery: ""

    // Filter items based on selectedTag and searchQuery
    readonly property var filteredHistory: {
        let items = Assistant.history || []
        if (root.selectedTag === "starred") {
            items = items.filter(item => !!item.starred)
        } else if (root.selectedTag !== "all") {
            items = items.filter(item => {
                const tags = item.tags || []
                return tags.some(t => t.toLowerCase() === root.selectedTag.toLowerCase())
            })
        }

        const q = root.searchQuery.trim().toLowerCase()
        if (q.length > 0) {
            items = items.filter(item => {
                const textMatch = (item.text || "").toLowerCase().includes(q)
                const promptMatch = (item.prompt || "").toLowerCase().includes(q)
                const answerMatch = (item.answer || "").toLowerCase().includes(q)
                const actionMatch = root.getActionLabel(item.action).toLowerCase().includes(q)
                const tagsMatch = (item.tags || []).some(t => t.toLowerCase().includes(q))
                return textMatch || promptMatch || answerMatch || actionMatch || tagsMatch
            })
        }

        return items
    }

    function focusSearch() {
        searchInput.forceActiveFocus()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.small

        // ── 1. History Header ─────────────────────────────────────────
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
                    text: "history"
                    fontStyle: Tokens.font.icon.medium
                    color: Colours.palette.m3primary
                }

                StyledText {
                    text: qsTr("Memory")
                    font: Tokens.font.title.small
                    color: Colours.palette.m3onSurface
                }

                // Total count pill
                StyledRect {
                    implicitWidth: countText.implicitWidth + Tokens.padding.small * 2
                    implicitHeight: 22
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3surfaceContainerHigh

                    StyledText {
                        id: countText
                        anchors.centerIn: parent
                        text: {
                            const count = (Assistant.history || []).length
                            return count === 1 ? qsTr("1 item") : qsTr("%1 items").arg(count)
                        }
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                    }
                }

                Item { Layout.fillWidth: true }

                // Review Starred Mode Button (School icon)
                IconButton {
                    id: reviewBtn
                    type: root.reviewMode ? IconButton.Filled : IconButton.Tonal
                    icon: "school"
                    font: Tokens.font.icon.small
                    implicitWidth: 32
                    implicitHeight: 32
                    enabled: root.starredItems.length > 0
                    opacity: enabled ? 1.0 : 0.4
                    onClicked: {
                        if (root.starredItems.length > 0) {
                            root.reviewIndex = 0
                            root.reviewRevealed = false
                            root.reviewShowHint = false
                            root.reviewShowSolution = false
                            root.shuffledOrder = []
                            root.reviewMode = !root.reviewMode
                        }
                    }

                    // Star count badge if starred items exist
                    StyledRect {
                        visible: root.starredItems.length > 0 && !root.reviewMode
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: -2
                        anchors.rightMargin: -2
                        implicitWidth: 14
                        implicitHeight: 14
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3tertiary

                        StyledText {
                            anchors.centerIn: parent
                            text: String(root.starredItems.length)
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onTertiary
                        }
                    }
                }

                // AI Organize Button
                IconButton {
                    id: organizeBtn
                    type: IconButton.Tonal
                    icon: "auto_awesome"
                    font: Tokens.font.icon.small
                    implicitWidth: 32
                    implicitHeight: 32
                    enabled: !Assistant.isOrganizing && (Assistant.history || []).length > 0
                    opacity: enabled ? 1.0 : 0.4
                    onClicked: Assistant.organizeHistory()

                    RotationAnimation on rotation {
                        from: 0
                        to: 360
                        duration: 1000
                        loops: Animation.Infinite
                        running: Assistant.isOrganizing
                    }
                }

                IconButton {
                    type: IconButton.Text
                    icon: "close"
                    font: Tokens.font.icon.small
                    implicitWidth: 28
                    implicitHeight: 28
                    onClicked: root.closeRequested()
                }
            }
        }

        // ── 2. Search Field ───────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            visible: !root.reviewMode
            spacing: Tokens.spacing.small

            StyledTextField {
                id: searchInput
                Layout.fillWidth: true
                placeholderText: qsTr("Search memory (queries, code, tags)...")
                placeholderFloats: false
                leadingIcon: "search"
                font: Tokens.font.body.small
                verticalPadding: Tokens.padding.small
                text: root.searchQuery
                onTextChanged: root.searchQuery = text

                Keys.onEscapePressed: {
                    if (text.length > 0) {
                        text = ""
                        root.searchQuery = ""
                    } else {
                        root.backRequested()
                    }
                }
            }

            IconButton {
                visible: searchInput.text.length > 0
                type: IconButton.Text
                icon: "close"
                font: Tokens.font.icon.small
                implicitWidth: 28
                implicitHeight: 28
                onClicked: {
                    searchInput.text = ""
                    root.searchQuery = ""
                }
            }
        }

        // ── 3. Tag Filter Chips Row ───────────────────────────────────
        Flickable {
            id: tagFlick
            Layout.fillWidth: true
            visible: !root.reviewMode
            implicitHeight: 30
            contentWidth: tagRow.implicitWidth
            contentHeight: 30
            clip: true

            RowLayout {
                id: tagRow
                spacing: 6

                // "All" filter chip
                StyledRect {
                    id: allChip
                    readonly property bool isSelected: root.selectedTag === "all"
                    implicitWidth: allChipText.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: 28
                    radius: Tokens.rounding.full
                    color: isSelected ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                    StyledText {
                        id: allChipText
                        anchors.centerIn: parent
                        text: qsTr("All")
                        font: Tokens.font.label.small
                        color: allChip.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectedTag = "all"
                    }
                }

                // "★ Starred" filter chip
                StyledRect {
                    id: starChip
                    readonly property bool isSelected: root.selectedTag === "starred"
                    implicitWidth: starRow.implicitWidth + Tokens.padding.small * 2
                    implicitHeight: 28
                    radius: Tokens.rounding.full
                    color: isSelected ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                    RowLayout {
                        id: starRow
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            text: "star"
                            fontStyle: Tokens.font.icon.small
                            color: starChip.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3tertiary
                        }

                        StyledText {
                            text: qsTr("Starred")
                            font: Tokens.font.label.small
                            color: starChip.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                        }
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectedTag = "starred"
                    }
                }

                // Dynamic AI Organized Tags
                Repeater {
                    model: root.allTags

                    delegate: StyledRect {
                        id: tagChip
                        required property string modelData
                        readonly property bool isSelected: root.selectedTag === tagChip.modelData
                        implicitWidth: tagChipRow.implicitWidth + Tokens.padding.small * 2
                        implicitHeight: 28
                        radius: Tokens.rounding.full
                        color: isSelected ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                        RowLayout {
                            id: tagChipRow
                            anchors.centerIn: parent
                            spacing: 2

                            Item {
                                implicitWidth: tagChipText.implicitWidth + Tokens.padding.extraSmall
                                implicitHeight: 28

                                StyledText {
                                    id: tagChipText
                                    anchors.centerIn: parent
                                    text: `#${tagChip.modelData}`
                                    font: Tokens.font.label.small
                                    color: tagChip.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                }

                                StateLayer {
                                    anchors.fill: parent
                                    radius: Tokens.rounding.full
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.selectedTag = (tagChip.isSelected ? "all" : tagChip.modelData)
                                }
                            }

                            // Delete tag entirely from all items
                            IconButton {
                                type: IconButton.Text
                                icon: "close"
                                font: Tokens.font.icon.small
                                implicitWidth: 18
                                implicitHeight: 18
                                padding: 0
                                activeColour: "transparent"
                                inactiveColour: "transparent"
                                activeOnColour: tagChip.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3error
                                inactiveOnColour: tagChip.isSelected ? Qt.alpha(Colours.palette.m3onPrimary, 0.7) : Colours.palette.m3outline
                                onClicked: {
                                    if (root.selectedTag === tagChip.modelData) {
                                        root.selectedTag = "all"
                                    }
                                    Assistant.deleteTagEntirely(tagChip.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── 4. Scrollable History Items (Accordion List) ──────────────
        StyledRect {
            id: listContainer
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.reviewMode
            implicitHeight: 400
            radius: Tokens.rounding.small
            color: Colours.palette.m3surfaceContainerLowest
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.3)

            // Empty state view
            ColumnLayout {
                anchors.centerIn: parent
                visible: root.filteredHistory.length === 0
                spacing: Tokens.spacing.small
                width: parent.width - Tokens.padding.large * 2

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.searchQuery ? "search_off" : (root.selectedTag === "starred" ? "star_outline" : "history_toggle_off")
                    fontStyle: Tokens.font.icon.large
                    color: Colours.palette.m3outline
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: {
                        if (root.searchQuery) {
                            return qsTr("No memory items found matching '%1'.").arg(root.searchQuery)
                        }
                        if ((Assistant.history || []).length === 0) {
                            return qsTr("No history saved yet. Completed answers will be stored here.")
                        }
                        if (root.selectedTag === "starred") {
                            return qsTr("No starred items yet. Star any answer with the star icon.")
                        }
                        return qsTr("No items found under tag '#%1'.").arg(root.selectedTag)
                    }
                    font: Tokens.font.body.small
                    color: Colours.palette.m3outline
                }
            }

            // History List
            Flickable {
                id: historyFlick
                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                visible: root.filteredHistory.length > 0
                contentHeight: historyColumn.implicitHeight
                clip: true

                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: historyFlick
                }

                ColumnLayout {
                    id: historyColumn
                    width: historyFlick.width - Tokens.padding.small
                    spacing: 8

                    Repeater {
                        model: root.filteredHistory

                        delegate: StyledRect {
                            id: itemCard
                            required property var modelData
                            readonly property bool expanded: root.expandedId === String(itemCard.modelData.id)

                            Layout.fillWidth: true
                            implicitHeight: cardContent.implicitHeight + Tokens.padding.small * 2
                            radius: Tokens.rounding.small
                            color: Colours.palette.m3surfaceContainerHigh
                            border.width: 1
                            border.color: {
                                if (itemCard.expanded) return Qt.alpha(Colours.palette.m3primary, 0.5)
                                if (itemCard.modelData.context_excluded) return Qt.alpha(Colours.palette.m3error, 0.25)
                                return Qt.alpha(Colours.palette.m3outlineVariant, 0.2)
                            }

                            Behavior on implicitHeight {
                                Anim { duration: Tokens.anim.durations.expressiveDefaultEffects }
                            }

                            StateLayer {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 42
                                radius: itemCard.radius
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const sid = String(itemCard.modelData.id)
                                    root.expandedId = (root.expandedId === sid) ? "" : sid
                                }
                            }

                            ColumnLayout {
                                id: cardContent
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: Tokens.padding.small
                                spacing: Tokens.spacing.small

                                // Header Summary (Always Visible)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    // Action Icon
                                    StyledRect {
                                        implicitWidth: 26
                                        implicitHeight: 26
                                        radius: Tokens.rounding.full
                                        color: Colours.palette.m3surfaceContainerHighest

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            text: root.getActionIcon(itemCard.modelData.action)
                                            fontStyle: Tokens.font.icon.small
                                            color: Colours.palette.m3primary
                                        }
                                    }

                                    // Snippet Text (1 line)
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: {
                                            const t = (itemCard.modelData.text || itemCard.modelData.prompt || "").trim()
                                            return t.replace(/\s+/g, " ")
                                        }
                                        elide: Text.ElideRight
                                        font: Tokens.font.body.small
                                        color: Colours.palette.m3onSurface
                                    }

                                    // Timestamp
                                    StyledText {
                                        text: root.formatTime(itemCard.modelData.timestamp)
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3outline
                                    }

                                    // Context Recall Exclusion Toggle ("Forget this")
                                    IconButton {
                                        type: IconButton.Text
                                        icon: itemCard.modelData.context_excluded ? "visibility_off" : "visibility"
                                        font: Tokens.font.icon.small
                                        implicitWidth: 26
                                        implicitHeight: 26
                                        activeColour: "transparent"
                                        inactiveColour: "transparent"
                                        activeOnColour: itemCard.modelData.context_excluded ? Colours.palette.m3error : Colours.palette.m3primary
                                        inactiveOnColour: itemCard.modelData.context_excluded ? Colours.palette.m3error : Colours.palette.m3outline
                                        onClicked: Assistant.toggleContextExcluded(itemCard.modelData.id)
                                    }

                                    // Star Button
                                    IconButton {
                                        type: IconButton.Text
                                        icon: itemCard.modelData.starred ? "star" : "star_outline"
                                        font: Tokens.font.icon.small
                                        implicitWidth: 26
                                        implicitHeight: 26
                                        onClicked: Assistant.toggleStar(itemCard.modelData.id)
                                    }

                                    // Expand Chevron
                                    MaterialIcon {
                                        text: itemCard.expanded ? "expand_less" : "expand_more"
                                        fontStyle: Tokens.font.icon.small
                                        color: Colours.palette.m3onSurfaceVariant
                                    }
                                }

                                // Expanded Content (Collapsible Details - Loaded on demand for instant performance)
                                Loader {
                                    Layout.fillWidth: true
                                    active: itemCard.expanded
                                    visible: itemCard.expanded

                                    sourceComponent: Component {
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Tokens.spacing.small

                                            // Divider Line
                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 1
                                                color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)
                                            }

                                            // Original Text / Question Box
                                            StyledRect {
                                                Layout.fillWidth: true
                                                implicitHeight: promptText.implicitHeight + Tokens.padding.small * 2
                                                radius: Tokens.rounding.extraSmall
                                                color: Colours.palette.m3surfaceContainerLowest

                                                StyledText {
                                                    id: promptText
                                                    anchors.fill: parent
                                                    anchors.margins: Tokens.padding.small
                                                    text: {
                                                        let str = ""
                                                        if (itemCard.modelData.prompt && itemCard.modelData.prompt.length > 0) {
                                                            str += "Q: " + itemCard.modelData.prompt + "\n\n"
                                                        }
                                                        if (itemCard.modelData.text && itemCard.modelData.text.length > 0) {
                                                            str += itemCard.modelData.text
                                                        }
                                                        return str.trim()
                                                    }
                                                    wrapMode: Text.Wrap
                                                    font: Tokens.font.body.small
                                                    color: Colours.palette.m3onSurfaceVariant
                                                }
                                            }

                                            // Full AI Answer (Selectable Markdown)
                                            StyledRect {
                                                Layout.fillWidth: true
                                                implicitHeight: answerText.contentHeight + Tokens.padding.small * 2
                                                radius: Tokens.rounding.extraSmall
                                                color: Colours.palette.m3surfaceContainerLowest

                                                TextEdit {
                                                    id: answerText
                                                    anchors.fill: parent
                                                    anchors.margins: Tokens.padding.small
                                                    text: Assistant.cleanMarkdown(itemCard.modelData.answer || "")
                                                    readOnly: true
                                                    selectByMouse: true
                                                    selectByKeyboard: true
                                                    cursorVisible: false
                                                    textFormat: TextEdit.MarkdownText
                                                    wrapMode: TextEdit.Wrap
                                                    font: Tokens.font.body.small
                                                    color: Colours.palette.m3onSurface
                                                    selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
                                                    selectedTextColor: Colours.palette.m3onSurface
                                                    renderType: TextEdit.NativeRendering
                                                    readonly property bool isArabicResult: {
                                                        const act = itemCard.modelData ? itemCard.modelData.action : ""
                                                        if (act !== "translate" || !text) return false
                                                        const arabicMatches = text.match(/[\u0600-\u06FF]/g)
                                                        const latinMatches = text.match(/[A-Za-z]/g)
                                                        const arabicCount = arabicMatches ? arabicMatches.length : 0
                                                        const latinCount = latinMatches ? latinMatches.length : 0
                                                        return arabicCount > latinCount
                                                    }
                                                    horizontalAlignment: isArabicResult ? TextEdit.AlignRight : TextEdit.AlignLeft
                                                }
                                            }

                                            // Tags Pills (if present)
                                            RowLayout {
                                                Layout.fillWidth: true
                                                visible: itemCard.modelData.tags && itemCard.modelData.tags.length > 0
                                                spacing: 4

                                                Repeater {
                                                    model: itemCard.modelData.tags || []

                                                    delegate: StyledRect {
                                                        id: tagBadge
                                                        required property string modelData
                                                        implicitWidth: tagBadgeRow.implicitWidth + 8
                                                        implicitHeight: 22
                                                        radius: Tokens.rounding.full
                                                        color: Qt.alpha(Colours.palette.m3primary, 0.15)

                                                        RowLayout {
                                                            id: tagBadgeRow
                                                            anchors.centerIn: parent
                                                            spacing: 2

                                                            StyledText {
                                                                id: tagBadgeText
                                                                text: `#${tagBadge.modelData}`
                                                                font: Tokens.font.label.small
                                                                color: Colours.palette.m3primary
                                                            }

                                                            IconButton {
                                                                type: IconButton.Text
                                                                icon: "close"
                                                                font: Tokens.font.icon.small
                                                                implicitWidth: 16
                                                                implicitHeight: 16
                                                                padding: 0
                                                                activeColour: "transparent"
                                                                inactiveColour: "transparent"
                                                                activeOnColour: Colours.palette.m3error
                                                                inactiveOnColour: Qt.alpha(Colours.palette.m3primary, 0.7)
                                                                onClicked: Assistant.removeTagFromItem(itemCard.modelData.id, tagBadge.modelData)
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // Per-Item Actions Footer
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: Tokens.spacing.small

                                                // Context Exclusion Toggle Pill ("Forget this")
                                                StyledRect {
                                                    implicitWidth: excludePillRow.implicitWidth + Tokens.padding.small * 2
                                                    implicitHeight: 28
                                                    radius: Tokens.rounding.full
                                                    color: itemCard.modelData.context_excluded
                                                        ? Qt.alpha(Colours.palette.m3error, 0.15)
                                                        : Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.6)
                                                    border.width: 1
                                                    border.color: itemCard.modelData.context_excluded
                                                        ? Qt.alpha(Colours.palette.m3error, 0.4)
                                                        : Qt.alpha(Colours.palette.m3outlineVariant, 0.2)

                                                    RowLayout {
                                                        id: excludePillRow
                                                        anchors.centerIn: parent
                                                        spacing: 4

                                                        MaterialIcon {
                                                            text: itemCard.modelData.context_excluded ? "visibility_off" : "visibility"
                                                            fontStyle: Tokens.font.icon.small
                                                            color: itemCard.modelData.context_excluded ? Colours.palette.m3error : Colours.palette.m3primary
                                                        }

                                                        StyledText {
                                                            text: itemCard.modelData.context_excluded ? qsTr("Excluded from AI context") : qsTr("Active in AI context")
                                                            font: Tokens.font.label.small
                                                            color: itemCard.modelData.context_excluded ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                                                        }
                                                    }

                                                    StateLayer {
                                                        anchors.fill: parent
                                                        radius: parent.radius
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: Assistant.toggleContextExcluded(itemCard.modelData.id)
                                                    }
                                                }

                                                Item { Layout.fillWidth: true }

                                                // Copy Answer
                                                IconButton {
                                                    id: itemCopyBtn
                                                    property bool copied: false
                                                    type: IconButton.Tonal
                                                    icon: copied ? "check" : "content_copy"
                                                    font: Tokens.font.icon.small
                                                    implicitWidth: 30
                                                    implicitHeight: 30
                                                    onClicked: {
                                                        const ans = itemCard.modelData.answer || ""
                                                        Quickshell.clipboardText = ans
                                                        Assistant.lastSeenClipboard = ans.trim()
                                                        copied = true
                                                        resetItemCopy.restart()
                                                    }

                                                    Timer {
                                                        id: resetItemCopy
                                                        interval: 1800
                                                        onTriggered: itemCopyBtn.copied = false
                                                    }
                                                }

                                                // Re-open in Assistant View
                                                IconButton {
                                                    type: IconButton.Tonal
                                                    icon: "open_in_new"
                                                    font: Tokens.font.icon.small
                                                    implicitWidth: 30
                                                    implicitHeight: 30
                                                    onClicked: {
                                                        Assistant.reopenItem(itemCard.modelData)
                                                        root.backRequested()
                                                    }
                                                }

                                                // Delete Item
                                                IconButton {
                                                    type: IconButton.Tonal
                                                    icon: "delete"
                                                    font: Tokens.font.icon.small
                                                    implicitWidth: 30
                                                    implicitHeight: 30
                                                    onClicked: Assistant.deleteHistoryItem(itemCard.modelData.id)
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
        }

        // ── 5. Active Recall Review Flashcard View ────────────────────
        StyledRect {
            id: reviewContainer
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.reviewMode
            radius: Tokens.rounding.small
            color: Colours.palette.m3surfaceContainerLowest
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.3)
            clip: true

            readonly property var currentItem: (root.starredItems && root.starredItems.length > root.reviewIndex)
                ? root.starredItems[root.reviewIndex]
                : null
            readonly property var challengeData: currentItem ? Assistant.challengeCache[String(currentItem.id)] : null
            readonly property bool isChallengingThis: currentItem && Assistant.isChallenging && Assistant.activeChallengeItemId === String(currentItem.id)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                // Sub-header: Card X of Y + Action Badge + Star + Shuffle
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledRect {
                        implicitWidth: actionBadgeRow.implicitWidth + 16
                        implicitHeight: 24
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3surfaceContainerHigh

                        RowLayout {
                            id: actionBadgeRow
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialIcon {
                                text: reviewContainer.currentItem ? root.getActionIcon(reviewContainer.currentItem.action) : "auto_awesome"
                                fontStyle: Tokens.font.icon.small
                                color: Colours.palette.m3primary
                            }

                            StyledText {
                                text: reviewContainer.currentItem ? root.getActionLabel(reviewContainer.currentItem.action) : "AI"
                                font: Tokens.font.label.small
                                color: Colours.palette.m3onSurface
                            }
                        }
                    }

                    StyledText {
                        text: qsTr("Card %1 of %2").arg(root.reviewIndex + 1).arg(root.starredItems.length)
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                    }

                    Item { Layout.fillWidth: true }

                    IconButton {
                        type: IconButton.Text
                        icon: "shuffle"
                        font: Tokens.font.icon.small
                        implicitWidth: 28
                        implicitHeight: 28
                        onClicked: root.shuffleStarred()
                    }

                    IconButton {
                        type: IconButton.Text
                        icon: (reviewContainer.currentItem && reviewContainer.currentItem.starred) ? "star" : "star_outline"
                        font: Tokens.font.icon.small
                        implicitWidth: 28
                        implicitHeight: 28
                        onClicked: {
                            if (reviewContainer.currentItem) {
                                Assistant.toggleStar(reviewContainer.currentItem.id)
                            }
                        }
                    }
                }

                // Scrollable Flashcard Content
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: cardContentCol.implicitHeight + Tokens.padding.large
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    ColumnLayout {
                        id: cardContentCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: Tokens.spacing.medium

                        // Question / Prompt Box
                        StyledRect {
                            Layout.fillWidth: true
                            implicitHeight: questionCol.implicitHeight + Tokens.padding.medium * 2
                            radius: Tokens.rounding.small
                            color: Colours.palette.m3surfaceContainer

                            ColumnLayout {
                                id: questionCol
                                anchors.fill: parent
                                anchors.margins: Tokens.padding.medium
                                spacing: 4

                                StyledText {
                                    text: qsTr("Question / Source Highlight:")
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3outline
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    text: {
                                        if (!reviewContainer.currentItem) return ""
                                        return (reviewContainer.currentItem.prompt || reviewContainer.currentItem.text || "").trim()
                                    }
                                    font: Tokens.font.body.medium
                                    color: Colours.palette.m3onSurface
                                }
                            }
                        }

                        // Tags Pills (if present)
                        RowLayout {
                            Layout.fillWidth: true
                            visible: reviewContainer.currentItem && reviewContainer.currentItem.tags && reviewContainer.currentItem.tags.length > 0
                            spacing: 4

                            Repeater {
                                model: (reviewContainer.currentItem && reviewContainer.currentItem.tags) ? reviewContainer.currentItem.tags : []

                                delegate: StyledRect {
                                    required property string modelData
                                    implicitWidth: tagPillText.implicitWidth + 8
                                    implicitHeight: 20
                                    radius: Tokens.rounding.full
                                    color: Qt.alpha(Colours.palette.m3primary, 0.15)

                                    StyledText {
                                        id: tagPillText
                                        anchors.centerIn: parent
                                        text: `#${parent.modelData}`
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3primary
                                    }
                                }
                            }
                        }

                        // Recall Actions (Reveal Stored Answer / Challenge Me)
                        RowLayout {
                            Layout.fillWidth: true
                            visible: !root.reviewRevealed && !reviewContainer.challengeData
                            spacing: Tokens.spacing.small

                            IconTextButton {
                                type: IconTextButton.Filled
                                icon: "visibility"
                                text: qsTr("Reveal Answer")
                                font: Tokens.font.label.small
                                onClicked: root.reviewRevealed = true
                            }

                            IconTextButton {
                                type: IconTextButton.Tonal
                                icon: reviewContainer.isChallengingThis ? "hourglass_top" : "psychology"
                                text: {
                                    if (reviewContainer.isChallengingThis) return qsTr("Thinking...")
                                    if (Assistant.challengeCooldownSec > 0) return qsTr("Wait %1s").arg(Assistant.challengeCooldownSec)
                                    return qsTr("Challenge Me")
                                }
                                font: Tokens.font.label.small
                                enabled: !Assistant.isChallenging && Assistant.challengeCooldownSec === 0
                                opacity: enabled ? 1.0 : 0.5
                                onClicked: {
                                    if (reviewContainer.currentItem) {
                                        Assistant.requestChallenge(reviewContainer.currentItem)
                                    }
                                }
                            }
                        }

                        // Stored Answer Card (Revealed)
                        StyledRect {
                            Layout.fillWidth: true
                            visible: root.reviewRevealed && !reviewContainer.challengeData
                            implicitHeight: storedAnswerCol.implicitHeight + Tokens.padding.medium * 2
                            radius: Tokens.rounding.small
                            color: Colours.palette.m3surfaceContainerLow

                            ColumnLayout {
                                id: storedAnswerCol
                                anchors.fill: parent
                                anchors.margins: Tokens.padding.medium
                                spacing: Tokens.spacing.small

                                RowLayout {
                                    Layout.fillWidth: true
                                    StyledText {
                                        text: qsTr("Stored Answer:")
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3primary
                                    }

                                    Item { Layout.fillWidth: true }

                                    IconButton {
                                        type: IconButton.Text
                                        icon: reviewContainer.isChallengingThis ? "hourglass_top" : "psychology"
                                        font: Tokens.font.icon.small
                                        implicitHeight: 26
                                        implicitWidth: Assistant.challengeCooldownSec > 0 ? 130 : 120
                                        enabled: !Assistant.isChallenging && Assistant.challengeCooldownSec === 0
                                        opacity: enabled ? 1.0 : 0.5
                                        onClicked: {
                                            if (reviewContainer.currentItem) {
                                                Assistant.requestChallenge(reviewContainer.currentItem)
                                            }
                                        }

                                        StyledText {
                                            anchors.centerIn: parent
                                            anchors.leftMargin: 18
                                            text: {
                                                if (reviewContainer.isChallengingThis) return qsTr("Thinking...")
                                                if (Assistant.challengeCooldownSec > 0) return qsTr("Wait %1s").arg(Assistant.challengeCooldownSec)
                                                return qsTr("Challenge Me")
                                            }
                                            font: Tokens.font.label.small
                                            color: Colours.palette.m3primary
                                        }
                                    }
                                }

                                TextEdit {
                                    Layout.fillWidth: true
                                    text: reviewContainer.currentItem ? Assistant.cleanMarkdown(reviewContainer.currentItem.answer || "") : ""
                                    readOnly: true
                                    selectByMouse: true
                                    textFormat: TextEdit.MarkdownText
                                    wrapMode: TextEdit.Wrap
                                    font: Tokens.font.body.small
                                    color: Colours.palette.m3onSurface
                                    selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
                                    selectedTextColor: Colours.palette.m3onSurface
                                    renderType: TextEdit.NativeRendering
                                    readonly property bool isArabicResult: {
                                        const act = (reviewContainer.currentItem && reviewContainer.currentItem.action) ? reviewContainer.currentItem.action : ""
                                        if (act !== "translate" || !text) return false
                                        const arabicMatches = text.match(/[\u0600-\u06FF]/g)
                                        const latinMatches = text.match(/[A-Za-z]/g)
                                        const arabicCount = arabicMatches ? arabicMatches.length : 0
                                        const latinCount = latinMatches ? latinMatches.length : 0
                                        return arabicCount > latinCount
                                    }
                                    horizontalAlignment: isArabicResult ? TextEdit.AlignRight : TextEdit.AlignLeft
                                }
                            }
                        }

                        // AI Concept Challenge Card (if generated)
                        StyledRect {
                            Layout.fillWidth: true
                            visible: reviewContainer.challengeData !== null
                            implicitHeight: challengeCol.implicitHeight + Tokens.padding.medium * 2
                            radius: Tokens.rounding.small
                            color: Qt.alpha(Colours.palette.m3primary, 0.08)
                            border.width: 1
                            border.color: Qt.alpha(Colours.palette.m3primary, 0.5)

                            ColumnLayout {
                                id: challengeCol
                                anchors.fill: parent
                                anchors.margins: Tokens.padding.medium
                                spacing: Tokens.spacing.small

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    MaterialIcon {
                                        text: "psychology"
                                        fontStyle: Tokens.font.icon.small
                                        color: Colours.palette.m3primary
                                    }

                                    StyledText {
                                        text: qsTr("Concept Mastery Challenge")
                                        font: Tokens.font.label.large
                                        color: Colours.palette.m3primary
                                    }

                                    Item { Layout.fillWidth: true }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    text: reviewContainer.challengeData ? reviewContainer.challengeData.question : ""
                                    font: Tokens.font.body.medium
                                    color: Colours.palette.m3onSurface
                                }

                                // Hint toggle & content
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: !!(reviewContainer.challengeData && reviewContainer.challengeData.hint)
                                    spacing: Tokens.spacing.small

                                    IconTextButton {
                                        type: IconTextButton.Text
                                        icon: root.reviewShowHint ? "lightbulb" : "lightbulb_outline"
                                        text: root.reviewShowHint ? qsTr("Hide Hint") : qsTr("Hint")
                                        font: Tokens.font.label.small
                                        onClicked: root.reviewShowHint = !root.reviewShowHint
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: root.reviewShowHint
                                        wrapMode: Text.Wrap
                                        font: Tokens.font.body.small
                                        color: Colours.palette.m3outline
                                        text: reviewContainer.challengeData ? reviewContainer.challengeData.hint : ""
                                    }
                                }

                                // Solution Reveal Button / Solution Content
                                IconTextButton {
                                    visible: !root.reviewShowSolution
                                    type: IconTextButton.Filled
                                    icon: "check_circle"
                                    text: qsTr("Reveal Solution")
                                    font: Tokens.font.label.small
                                    onClicked: root.reviewShowSolution = true
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: root.reviewShowSolution
                                    spacing: 4

                                    StyledText {
                                        text: qsTr("Solution & Explanation:")
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3primary
                                    }

                                    TextEdit {
                                        Layout.fillWidth: true
                                        text: reviewContainer.challengeData ? Assistant.cleanMarkdown(reviewContainer.challengeData.solution || "") : ""
                                        readOnly: true
                                        selectByMouse: true
                                        textFormat: TextEdit.MarkdownText
                                        wrapMode: TextEdit.Wrap
                                        font: Tokens.font.body.small
                                        color: Colours.palette.m3onSurface
                                        selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
                                        selectedTextColor: Colours.palette.m3onSurface
                                        renderType: TextEdit.NativeRendering
                                        horizontalAlignment: TextEdit.AlignLeft
                                    }
                                }
                            }
                        }
                    }
                }

                // Bottom Navigation Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    IconTextButton {
                        type: IconTextButton.Tonal
                        icon: "arrow_back"
                        text: qsTr("Previous")
                        font: Tokens.font.label.small
                        enabled: root.reviewIndex > 0
                        opacity: enabled ? 1.0 : 0.4
                        onClicked: {
                            if (root.reviewIndex > 0) {
                                root.reviewIndex -= 1
                                root.reviewRevealed = false
                                root.reviewShowHint = false
                                root.reviewShowSolution = false
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    IconTextButton {
                        type: IconTextButton.Filled
                        icon: (root.reviewIndex >= root.starredItems.length - 1) ? "done_all" : "arrow_forward"
                        text: (root.reviewIndex >= root.starredItems.length - 1) ? qsTr("Done") : qsTr("Next")
                        font: Tokens.font.label.small
                        onClicked: {
                            if (root.reviewIndex < root.starredItems.length - 1) {
                                root.reviewIndex += 1
                                root.reviewRevealed = false
                                root.reviewShowHint = false
                                root.reviewShowSolution = false
                            } else {
                                root.reviewMode = false
                            }
                        }
                    }
                }
            }
        }
    }
}
