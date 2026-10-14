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

    property string selectedTag: "all"

    focus: true

    Keys.onEscapePressed: event => {
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
        RowLayout {
            Layout.fillWidth: true
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

        // ── 2. Search Field ───────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
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
                            property bool expanded: false

                            Layout.fillWidth: true
                            implicitHeight: cardContent.implicitHeight + Tokens.padding.small * 2
                            radius: Tokens.rounding.small
                            color: Colours.palette.m3surfaceContainerHigh
                            border.width: 1
                            border.color: itemCard.expanded
                                ? Qt.alpha(Colours.palette.m3primary, 0.5)
                                : Qt.alpha(Colours.palette.m3outlineVariant, 0.2)

                            Behavior on implicitHeight {
                                Anim { duration: Tokens.anim.durations.expressiveDefaultEffects }
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

                                // Interactive Header Click Area
                                StateLayer {
                                    anchors.fill: parent
                                    radius: itemCard.radius
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: itemCard.expanded = !itemCard.expanded
                                }

                                // Expanded Content (Collapsible Details)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: itemCard.expanded
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
                                            text: itemCard.modelData.answer || ""
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
                                                Quickshell.clipboardText = itemCard.modelData.answer || ""
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
