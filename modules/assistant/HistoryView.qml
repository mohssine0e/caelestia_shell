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
    property string searchQuery: ""
    property string editingChatId: ""
    property string editingTitleText: ""
    implicitHeight: historyLayout.implicitHeight

    function formatTime(isoStr) {
        if (!isoStr) return ""
        const ts = new Date(isoStr).getTime()
        if (isNaN(ts) || ts <= 0) return ""
        const diff = Math.floor((Date.now() - ts) / 1000)
        if (diff < 60) return qsTr("just now")
        if (diff < 3600) return qsTr("%1m ago").arg(Math.floor(diff / 60))
        if (diff < 86400) return qsTr("%1h ago").arg(Math.floor(diff / 3600))
        if (diff < 604800) return qsTr("%1d ago").arg(Math.floor(diff / 86400))
        return new Date(ts).toLocaleDateString(Qt.locale(), "MMM d")
    }

    function exportChatToMarkdown(chat) {
        if (!chat || !chat.messages) return
        let md = `# ${chat.title || "Chat"}\n\n`
        md += `*Exported on ${new Date().toLocaleString()}*\n\n---\n\n`
        for (let i = 0; i < chat.messages.length; i++) {
            const m = chat.messages[i]
            const role = m.role === "assistant" ? "**Assistant**" : "**You**"
            md += `### ${role} (${m.timestamp || ""})\n\n${m.text}\n\n`
        }
        Quickshell.execDetached(["wl-copy", md])
    }

    // Extract unique tags from all chat sessions
    readonly property var allTags: {
        const set = {}
        const items = Assistant.chats || []
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

    // Filter chat sessions based on selectedTag and searchQuery
    readonly property var filteredChats: {
        let list = Assistant.chats || []
        if (root.selectedTag === "starred") {
            list = list.filter(c => !!c.starred || !!c.pinned)
        } else if (root.selectedTag !== "all") {
            const tag = root.selectedTag.toLowerCase()
            list = list.filter(c => (c.tags || []).some(t => t.toLowerCase() === tag))
        }

        const q = root.searchQuery.trim().toLowerCase()
        if (q.length > 0) {
            list = list.filter(c => {
                if ((c.title || "").toLowerCase().includes(q)) return true
                if ((c.tags || []).some(t => t.toLowerCase().includes(q))) return true
                const msgs = c.messages || []
                return msgs.some(m => (m.text || "").toLowerCase().includes(q))
            })
        }
        return list
    }

    property int visibleLimit: 30
    onSelectedTagChanged: visibleLimit = 30
    readonly property var displayedChats: (root.filteredChats || []).slice(0, root.visibleLimit)

    ColumnLayout {
        id: historyLayout
        anchors.fill: parent
        spacing: Tokens.spacing.small

        // ── 1. Header Bar ─────────────────────────────────────────────
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
                    implicitWidth: 28
                    implicitHeight: 28
                    onClicked: root.backRequested()
                }

                MaterialIcon {
                    text: "forum"
                    fontStyle: Tokens.font.icon.medium
                    color: Colours.palette.m3primary
                }

                ColumnLayout {
                    spacing: 0
                    StyledText {
                        text: qsTr("Chats & History")
                        font: Tokens.font.title.small
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        text: {
                            const count = (Assistant.chats || []).length
                            return count === 1 ? qsTr("1 conversation") : qsTr("%1 conversations").arg(count)
                        }
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                    }
                }

                Item { Layout.fillWidth: true }

                // New Chat Button
                IconTextButton {
                    type: IconTextButton.Tonal
                    icon: "add"
                    text: qsTr("New Chat")
                    font: Tokens.font.label.small
                    onClicked: {
                        Assistant.startNewChat()
                        root.backRequested()
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

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Deleting a chat removes its saved conversation only. Assistant history and saved memory are managed separately.")
            font: Tokens.font.label.small
            color: Colours.palette.m3outline
            wrapMode: Text.Wrap
        }

        // ── 2. Search & Tag Filter Bar ────────────────────────────────
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 36
            radius: Tokens.rounding.full
            color: Colours.palette.m3surfaceContainerHigh
            border.width: 1
            border.color: searchInput.activeFocus ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outlineVariant, 0.25)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                MaterialIcon {
                    text: "search"
                    fontStyle: Tokens.font.icon.small
                    color: searchInput.text.length > 0 ? Colours.palette.m3primary : Colours.palette.m3outline
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    clip: true
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurface
                    text: root.searchQuery
                    onTextChanged: root.searchQuery = text

                    Text {
                        anchors.fill: parent
                        visible: !parent.text && !parent.activeFocus
                        text: qsTr("Search chats by title, content, or tag...")
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
                    padding: 0
                    onClicked: {
                        root.searchQuery = ""
                        searchInput.text = ""
                    }
                }
            }
        }

        // ── 3. Horizontal Tags Filter Row ─────────────────────────────
        Flickable {
            id: tagsFlick
            Layout.fillWidth: true
            implicitHeight: 28
            contentWidth: tagsRow.implicitWidth
            flickableDirection: Flickable.HorizontalFlick
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            RowLayout {
                id: tagsRow
                spacing: Tokens.spacing.extraSmall

                // "All" filter chip
                StyledRect {
                    id: allChip
                    readonly property bool isSelected: root.selectedTag === "all"
                    implicitWidth: allText.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: 28
                    radius: Tokens.rounding.full
                    color: isSelected ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                    StyledText {
                        id: allText
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

                // "★ Pinned" filter chip
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
                            text: qsTr("Pinned")
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

                // Dynamic Tags
                Repeater {
                    model: root.allTags

                    delegate: StyledRect {
                        id: tagChip
                        required property string modelData
                        readonly property bool isSelected: root.selectedTag === tagChip.modelData
                        implicitWidth: tagChipText.implicitWidth + Tokens.padding.small * 2
                        implicitHeight: 28
                        radius: Tokens.rounding.full
                        color: isSelected ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

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
                }
            }
        }

        // ── 4. Scrollable Chat Cards List ─────────────────────────────
        Item {
            id: listContainer
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 180
            implicitHeight: 400

            // Empty state
            ColumnLayout {
                anchors.centerIn: parent
                visible: (root.displayedChats || []).length === 0
                spacing: Tokens.spacing.small

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.selectedTag === "starred" ? "star_outline" : "chat_bubble_outline"
                    fontStyle: Tokens.font.icon.large
                    color: Colours.palette.m3outline
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: {
                        if ((Assistant.chats || []).length === 0) {
                            return qsTr("No conversations yet. Start chatting to save sessions here.")
                        }
                        if (root.selectedTag === "starred") {
                            return qsTr("No pinned conversations yet.")
                        }
                        return qsTr("No conversations matching \"%1\"").arg(root.searchQuery || root.selectedTag)
                    }
                    font: Tokens.font.body.small
                    color: Colours.palette.m3outline
                }
            }

            // Chat List
            Flickable {
                id: historyFlick
                anchors.fill: parent
                clip: true
                visible: (root.displayedChats || []).length > 0
                contentWidth: width
                contentHeight: chatColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: historyFlick
                }

                ColumnLayout {
                    id: chatColumn
                    width: historyFlick.width - Tokens.padding.small
                    spacing: 8

                    Repeater {
                        model: root.displayedChats

                        delegate: StyledRect {
                            id: chatCard
                            required property var modelData
                            readonly property var chatData: modelData || ({})
                            readonly property bool isCurrent: String(Assistant.activeChatId) === String(chatCard.chatData.id)
                            readonly property bool isEditing: root.editingChatId === String(chatCard.chatData.id)

                            Layout.fillWidth: true
                            implicitHeight: cardLayout.implicitHeight + Tokens.padding.small * 2
                            radius: Tokens.rounding.small
                            color: isCurrent ? Qt.alpha(Colours.palette.m3primary, 0.08) : Colours.palette.m3surfaceContainerHigh
                            border.width: isCurrent ? 1.5 : 1
                            border.color: {
                                if (isCurrent) return Colours.palette.m3primary
                                if (cardHover.hovered) return Qt.alpha(Colours.palette.m3primary, 0.4)
                                return Qt.alpha(Colours.palette.m3outlineVariant, 0.2)
                            }

                            Behavior on border.color { CAnim {} }
                            Behavior on color { CAnim {} }

                            HoverHandler { id: cardHover }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !chatCard.isEditing
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Assistant.loadChat(chatCard.chatData.id)
                                    root.backRequested()
                                }
                            }

                            ColumnLayout {
                                id: cardLayout
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: Tokens.padding.small
                                spacing: 6

                                // Row 1: Title, Time & Pinned Star
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    // Chat Icon Pill
                                    StyledRect {
                                        implicitWidth: 26
                                        implicitHeight: 26
                                        radius: Tokens.rounding.full
                                        color: chatCard.isCurrent ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            text: chatCard.chatData.pinned ? "star" : "chat"
                                            fontStyle: Tokens.font.icon.small
                                            color: chatCard.isCurrent ? Colours.palette.m3onPrimary : (chatCard.chatData.pinned ? Colours.palette.m3tertiary : Colours.palette.m3primary)
                                        }
                                    }

                                    // Editable or Normal Title
                                    Item {
                                        Layout.fillWidth: true
                                        implicitHeight: 26

                                        StyledText {
                                            visible: !chatCard.isEditing
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: chatCard.chatData.title || qsTr("Untitled Chat")
                                            font: Tokens.font.title.small
                                            color: chatCard.isCurrent ? Colours.palette.m3primary : Colours.palette.m3onSurface
                                            elide: Text.ElideRight
                                        }

                                        RowLayout {
                                            visible: chatCard.isEditing
                                            anchors.fill: parent
                                            spacing: 4

                                            TextInput {
                                                id: renameField
                                                Layout.fillWidth: true
                                                font: Tokens.font.title.small
                                                color: Colours.palette.m3onSurface
                                                text: root.editingTitleText
                                                onTextChanged: root.editingTitleText = text
                                                onAccepted: {
                                                    Assistant.renameChat(chatCard.chatData.id, renameField.text)
                                                    root.editingChatId = ""
                                                }
                                            }

                                            IconButton {
                                                type: IconButton.Text
                                                icon: "check"
                                                font: Tokens.font.icon.small
                                                implicitWidth: 22
                                                implicitHeight: 22
                                                onClicked: {
                                                    Assistant.renameChat(chatCard.chatData.id, renameField.text)
                                                    root.editingChatId = ""
                                                }
                                            }

                                            IconButton {
                                                type: IconButton.Text
                                                icon: "close"
                                                font: Tokens.font.icon.small
                                                implicitWidth: 22
                                                implicitHeight: 22
                                                onClicked: root.editingChatId = ""
                                            }
                                        }
                                    }

                                    // Time Elapsed
                                    StyledText {
                                        text: root.formatTime(chatCard.chatData.updatedAt || chatCard.chatData.createdAt)
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3outline
                                    }

                                    // Pin / Star Button
                                    IconButton {
                                        type: IconButton.Text
                                        icon: chatCard.chatData.pinned ? "star" : "star_outline"
                                        font: Tokens.font.icon.small
                                        implicitWidth: 24
                                        implicitHeight: 24
                                        padding: 0
                                        activeOnColour: Colours.palette.m3tertiary
                                        inactiveOnColour: Colours.palette.m3outline
                                        onClicked: Assistant.togglePinChat(chatCard.chatData.id)
                                    }
                                }

                                // Row 2: Snippet preview of last message
                                StyledText {
                                    Layout.fillWidth: true
                                    text: {
                                        const msgs = chatCard.chatData.messages || []
                                        if (msgs.length === 0) return qsTr("Empty conversation")
                                        const last = msgs[msgs.length - 1]
                                        const clean = (last.text || "").replace(/[\n\r`#*]+/g, " ").trim()
                                        return (last.role === "assistant" ? "AI: " : "You: ") + (clean.slice(0, 110) + (clean.length > 110 ? "..." : ""))
                                    }
                                    font: Tokens.font.body.small
                                    color: Colours.palette.m3onSurfaceVariant
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                // Row 3: Turn count badge, Tags & Quick Action Bar
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    // Turn Counter Badge
                                    StyledRect {
                                        implicitWidth: turnCountText.implicitWidth + 12
                                        implicitHeight: 20
                                        radius: Tokens.rounding.full
                                        color: Colours.palette.m3surfaceContainerHighest

                                        StyledText {
                                            id: turnCountText
                                            anchors.centerIn: parent
                                            text: {
                                                const len = (chatCard.chatData.messages || []).length
                                                const turns = Math.max(1, Math.floor(len / 2))
                                                return turns === 1 ? qsTr("1 turn") : qsTr("%1 turns").arg(turns)
                                            }
                                            font: Tokens.font.label.small
                                            color: Colours.palette.m3outline
                                        }
                                    }

                                    // Tags (up to 3)
                                    Repeater {
                                        model: (chatCard.chatData.tags || []).slice(0, 3)

                                        delegate: StyledRect {
                                            required property string modelData
                                            implicitWidth: chatTagText.implicitWidth + 10
                                            implicitHeight: 20
                                            radius: Tokens.rounding.full
                                            color: Colours.palette.m3surfaceContainerHighest

                                            StyledText {
                                                id: chatTagText
                                                anchors.centerIn: parent
                                                text: `#${modelData}`
                                                font: Tokens.font.label.small
                                                color: Colours.palette.m3primary
                                            }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Quick Action Buttons
                                    RowLayout {
                                        spacing: 2
                                        visible: cardHover.hovered || chatCard.isCurrent

                                        // Resume Action Pill
                                        StyledRect {
                                            implicitWidth: resumeRow.implicitWidth + 10
                                            implicitHeight: 24
                                            radius: Tokens.rounding.full
                                            color: Colours.palette.m3primary

                                            RowLayout {
                                                id: resumeRow
                                                anchors.centerIn: parent
                                                spacing: 4

                                                MaterialIcon {
                                                    text: "play_arrow"
                                                    fontStyle: Tokens.font.icon.small
                                                    color: Colours.palette.m3onPrimary
                                                }

                                                StyledText {
                                                    text: qsTr("Resume")
                                                    font: Tokens.font.label.small
                                                    color: Colours.palette.m3onPrimary
                                                }
                                            }

                                            StateLayer {
                                                anchors.fill: parent
                                                radius: parent.radius
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    Assistant.loadChat(chatCard.chatData.id)
                                                    root.backRequested()
                                                }
                                            }
                                        }

                                        // Rename Button
                                        IconButton {
                                            type: IconButton.Text
                                            icon: "edit"
                                            font: Tokens.font.icon.small
                                            implicitWidth: 24
                                            implicitHeight: 24
                                            padding: 0
                                            onClicked: {
                                                root.editingChatId = String(chatCard.chatData.id)
                                                root.editingTitleText = chatCard.chatData.title || ""
                                            }
                                        }

                                        // Copy Markdown Button
                                        IconButton {
                                            type: IconButton.Text
                                            icon: "content_copy"
                                            font: Tokens.font.icon.small
                                            implicitWidth: 24
                                            implicitHeight: 24
                                            padding: 0
                                            onClicked: root.exportChatToMarkdown(chatCard.chatData)
                                        }

                                        // Delete Button
                                        IconButton {
                                            type: IconButton.Text
                                            icon: "delete_outline"
                                            font: Tokens.font.icon.small
                                            implicitWidth: 24
                                            implicitHeight: 24
                                            padding: 0
                                            activeOnColour: Colours.palette.m3error
                                            inactiveOnColour: Colours.palette.m3outline
                                            onClicked: Assistant.deleteChat(chatCard.chatData.id)
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
