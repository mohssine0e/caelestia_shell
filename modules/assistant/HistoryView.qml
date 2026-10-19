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
    property string expandedId: ""

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

    // Filter items based on selectedTag
    readonly property var filteredHistory: {
        const items = Assistant.history || []
        if (root.selectedTag === "starred") {
            return items.filter(item => !!item.starred)
        } else if (root.selectedTag !== "all") {
            return items.filter(item => {
                const tags = item.tags || []
                return tags.some(t => t.toLowerCase() === root.selectedTag.toLowerCase())
            })
        }
        return items
    }

    // Count items that have no tags or empty tags array
    readonly property int unorganizedCount: {
        const items = Assistant.history || []
        let count = 0
        for (let i = 0; i < items.length; i++) {
            const tags = items[i].tags
            if (!tags || tags.length === 0) {
                count++
            }
        }
        return count
    }

    property int visibleLimit: 30
    onSelectedTagChanged: visibleLimit = 30
    readonly property var displayedHistory: (root.filteredHistory || []).slice(0, root.visibleLimit)

    function focusSearch() {}

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

                // AI Organize Button with pending unorganized badge
                Item {
                    implicitWidth: 32
                    implicitHeight: 32

                    IconButton {
                        id: organizeBtn
                        anchors.fill: parent
                        type: IconButton.Tonal
                        icon: "auto_awesome"
                        font: Tokens.font.icon.small
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

                    // Badge showing count of unorganized / new chats
                    StyledRect {
                        visible: root.unorganizedCount > 0 && !Assistant.isOrganizing
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: -2
                        anchors.rightMargin: -2
                        implicitWidth: Math.max(14, organizeBadgeText.implicitWidth + 6)
                        implicitHeight: 14
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        StyledText {
                            id: organizeBadgeText
                            anchors.centerIn: parent
                            text: root.unorganizedCount > 99 ? "99+" : String(root.unorganizedCount)
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onPrimary
                        }
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

        // ── 2. Tag Filter Chips Row ───────────────────────────────────
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
        Item {
            id: listContainer
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: 400

            // Empty state view
            ColumnLayout {
                anchors.centerIn: parent
                visible: root.filteredHistory.length === 0
                spacing: Tokens.spacing.small
                width: parent.width - Tokens.padding.large * 2

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.selectedTag === "starred" ? "star_outline" : "history_toggle_off"
                    fontStyle: Tokens.font.icon.large
                    color: Colours.palette.m3outline
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: {
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
                        model: root.displayedHistory

                        delegate: StyledRect {
                            id: itemCard
                            required property var modelData
                            readonly property var itemData: modelData || ({})
                            readonly property bool expanded: itemData.id ? root.expandedId === String(itemData.id) : false

                            Layout.fillWidth: true
                            implicitHeight: cardContent.implicitHeight + Tokens.padding.small * 2
                            radius: Tokens.rounding.small
                            color: Colours.palette.m3surfaceContainerHigh
                            border.width: 1
                            border.color: {
                                if (itemCard.expanded || cardHover.hovered) return Qt.alpha(Colours.palette.m3primary, 0.5)
                                if (itemCard.itemData.context_excluded) return Qt.alpha(Colours.palette.m3error, 0.25)
                                return Qt.alpha(Colours.palette.m3outlineVariant, 0.2)
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
                                height: 42
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const sid = itemCard.itemData.id ? String(itemCard.itemData.id) : ""
                                    if (sid) {
                                        root.expandedId = (root.expandedId === sid) ? "" : sid
                                    }
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
                                            text: root.getActionIcon(itemCard.itemData.action)
                                            fontStyle: Tokens.font.icon.small
                                            color: Colours.palette.m3primary
                                        }
                                    }

                                    // Snippet Text (1 line)
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: {
                                            const t = (itemCard.itemData.text || itemCard.itemData.prompt || "").trim()
                                            return t.replace(/\s+/g, " ")
                                        }
                                        elide: Text.ElideRight
                                        font: Tokens.font.body.small
                                        color: Colours.palette.m3onSurface
                                    }

                                    // Timestamp
                                    StyledText {
                                        text: root.formatTime(itemCard.itemData.timestamp)
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3outline
                                    }

                                    // Context Recall Exclusion Toggle ("Forget this")
                                    IconButton {
                                        type: IconButton.Text
                                        icon: itemCard.itemData.context_excluded ? "visibility_off" : "visibility"
                                        font: Tokens.font.icon.small
                                        implicitWidth: 26
                                        implicitHeight: 26
                                        activeColour: "transparent"
                                        inactiveColour: "transparent"
                                        activeOnColour: itemCard.itemData.context_excluded ? Colours.palette.m3error : Colours.palette.m3primary
                                        inactiveOnColour: itemCard.itemData.context_excluded ? Colours.palette.m3error : Colours.palette.m3outline
                                        onClicked: {
                                            if (itemCard.itemData.id) Assistant.toggleContextExcluded(itemCard.itemData.id)
                                        }
                                    }

                                    // Star Button
                                    IconButton {
                                        type: IconButton.Text
                                        icon: itemCard.itemData.starred ? "star" : "star_outline"
                                        font: Tokens.font.icon.small
                                        implicitWidth: 26
                                        implicitHeight: 26
                                        onClicked: {
                                            if (itemCard.itemData.id) Assistant.toggleStar(itemCard.itemData.id)
                                        }
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
                                                color: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.45)

                                                StyledText {
                                                    id: promptText
                                                    anchors.fill: parent
                                                    anchors.margins: Tokens.padding.small
                                                    text: {
                                                        let str = ""
                                                        if (itemCard.itemData.prompt && itemCard.itemData.prompt.length > 0) {
                                                            str += "Q: " + itemCard.itemData.prompt + "\n\n"
                                                        }
                                                        if (itemCard.itemData.text && itemCard.itemData.text.length > 0) {
                                                            str += itemCard.itemData.text
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
                                                implicitHeight: answerText.implicitHeight + Tokens.padding.small * 2
                                                radius: Tokens.rounding.extraSmall
                                                color: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.45)

                                                TextEdit {
                                                    id: answerText
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    anchors.margins: Tokens.padding.small
                                                    text: Assistant.cleanMarkdown(itemCard.itemData.answer || "")
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
                                                        const act = itemCard.itemData.action || ""
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
                                                visible: itemCard.itemData.tags && itemCard.itemData.tags.length > 0
                                                spacing: 4

                                                Repeater {
                                                    model: itemCard.itemData.tags || []

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
                                                                onClicked: {
                                                                    if (itemCard.itemData.id) Assistant.removeTagFromItem(itemCard.itemData.id, tagBadge.modelData)
                                                                }
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
                                                    color: itemCard.itemData.context_excluded
                                                        ? Qt.alpha(Colours.palette.m3error, 0.15)
                                                        : Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.6)
                                                    border.width: 1
                                                    border.color: itemCard.itemData.context_excluded
                                                        ? Qt.alpha(Colours.palette.m3error, 0.4)
                                                        : Qt.alpha(Colours.palette.m3outlineVariant, 0.2)

                                                    RowLayout {
                                                        id: excludePillRow
                                                        anchors.centerIn: parent
                                                        spacing: 4

                                                        MaterialIcon {
                                                            text: itemCard.itemData.context_excluded ? "visibility_off" : "visibility"
                                                            fontStyle: Tokens.font.icon.small
                                                            color: itemCard.itemData.context_excluded ? Colours.palette.m3error : Colours.palette.m3primary
                                                        }

                                                        StyledText {
                                                            text: itemCard.itemData.context_excluded ? qsTr("Excluded from AI context") : qsTr("Active in AI context")
                                                            font: Tokens.font.label.small
                                                            color: itemCard.itemData.context_excluded ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                                                        }
                                                    }

                                                    StateLayer {
                                                        anchors.fill: parent
                                                        radius: parent.radius
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (itemCard.itemData.id) Assistant.toggleContextExcluded(itemCard.itemData.id)
                                                        }
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
                                                        const ans = itemCard.itemData.answer || ""
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
                                                        Assistant.reopenItem(itemCard.itemData)
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
                                                    onClicked: {
                                                        if (itemCard.itemData.id) Assistant.deleteHistoryItem(itemCard.itemData.id)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Load more button for pagination
                    StyledRect {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Tokens.spacing.small
                        Layout.bottomMargin: Tokens.spacing.medium
                        visible: root.filteredHistory.length > root.visibleLimit
                        implicitWidth: showMoreRow.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: 32
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3surfaceContainerHigh
                        border.width: 1
                        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

                        RowLayout {
                            id: showMoreRow
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialIcon {
                                text: "expand_more"
                                fontStyle: Tokens.font.icon.small
                                color: Colours.palette.m3primary
                            }

                            StyledText {
                                text: qsTr("Show More (%1 remaining)").arg(root.filteredHistory.length - root.visibleLimit)
                                font: Tokens.font.label.small
                                color: Colours.palette.m3primary
                            }
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.visibleLimit += 30
                        }
                    }
                }
            }
        }
    }
}
