pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.containers
import qs.components.effects
import qs.services

FocusScope {
    id: root

    property var windowRef: null
    property real maximumHudWidth: 1200
    property real maximumHudHeight: 980
    property string currentView: "assistant"

    Connections {
        target: Assistant
        function onRequestedViewChanged() {
            if (Assistant.requestedView.length > 0 && root.currentView !== Assistant.requestedView) {
                root.currentView = Assistant.requestedView
            }
        }
    }

    onCurrentViewChanged: {
        root.closeSelectionPopup()
        if (Assistant.requestedView !== currentView) Assistant.requestedView = currentView
        root.forceActiveFocus()
    }
    property bool askBoundToSelection: false
    property string activeSelectedText: ""
    property string selectionText: ""
    property string selectionContext: ""
    property string selectionMessageId: ""
    property var selectionEditor: null
    property real selectionAnchorX: 0
    property real selectionAnchorY: 0
    property real selectionLineHeight: 0
    property string selectionAction: ""
    property string selectionState: "idle"
    property string selectionOutput: ""
    property string selectionError: ""
    property string selectionRequestId: ""
    property string selectionSaveToken: ""
    property string selectionSaveState: "idle"
    property int selectionSerial: 0
    property var _selectionPending: null
    property var _selectionProcessPayload: ({})

    function closeSelectionPopup(): void {
        const editor = root.selectionEditor
        root.selectionEditor = null
        root.selectionSerial += 1
        root.selectionRequestId = ""
        root._selectionPending = null
        if (selectionProc.running) selectionProc.running = false
        root.selectionText = ""
        root.selectionContext = ""
        root.selectionMessageId = ""
        root.selectionState = "idle"
        root.selectionOutput = ""
        root.selectionError = ""
        root.selectionSaveState = "idle"
        root.selectionSaveToken = ""
        root.activeSelectedText = ""
        if (editor) {
            try { editor.deselect() } catch (e) { }
        }
    }

    function showSelection(text, context, messageId, editor, x, y, lineHeight): void {
        const selected = String(text || "").replace(/\u2029/g, "\n").trim()
        if (!selected) return
        if (root.selectionMessageId !== String(messageId) || root.selectionText !== selected) {
            root.selectionSerial += 1
            root.selectionRequestId = ""
            root._selectionPending = null
            if (selectionProc.running) selectionProc.running = false
            root.selectionState = "idle"
            root.selectionOutput = ""
            root.selectionError = ""
            root.selectionSaveState = "idle"
            root.selectionSaveToken = ""
        }
        root.selectionText = selected
        root.selectionEditor = editor
        root.selectionContext = String(context || "").slice(0, 500)
        root.selectionMessageId = String(messageId || "")
        root.selectionAnchorX = x
        root.selectionAnchorY = y
        root.selectionLineHeight = lineHeight
        root.activeSelectedText = selected
    }

    function _launchSelectionRequest(): void {
        if (selectionProc.running || !root._selectionPending) return
        const request = root._selectionPending
        root._selectionPending = null
        root._selectionProcessPayload = request.payload
        selectionProc.requestId = request.payload.request_id
        selectionProc.command = ["python3", Quickshell.shellPath("scripts/assistant_api.py"), request.action, "--stdin-json"]
        selectionProc.running = true
    }

    function runSelectionAction(action): void {
        if (!root.selectionText || (action !== "translate" && action !== "explain")) return
        if (root.selectionText.length > 4000) {
            root.selectionAction = action
            root.selectionError = qsTr("Select up to 4,000 characters for this action.")
            root.selectionState = "failed"
            return
        }
        root.selectionSerial += 1
        root.selectionRequestId = "selection_" + root.selectionSerial
        root.selectionAction = action
        root.selectionState = "waiting"
        root.selectionOutput = ""
        root.selectionError = ""
        root._selectionPending = {
            action: action,
            payload: {
                request_id: root.selectionRequestId,
                selection_only: true,
                text: root.selectionText,
                selection_context: root.selectionContext
            }
        }
        if (selectionProc.running) selectionProc.running = false
        else root._launchSelectionRequest()
    }

    Process {
        id: selectionProc
        property string requestId: ""
        stdinEnabled: true
        onStarted: write(JSON.stringify(root._selectionProcessPayload) + "\n")
        stdout: SplitParser {
            onRead: data => {
                try {
                    const msg = JSON.parse(data.trim())
                    if (!msg.request_id || msg.request_id !== root.selectionRequestId || msg.request_id !== selectionProc.requestId) return
                    if (msg.type === "chunk") {
                        root.selectionOutput += String(msg.text || "")
                        root.selectionState = "streaming"
                    } else if (msg.type === "done") {
                        root.selectionState = "done"
                    } else if (msg.type === "error") {
                        root.selectionError = msg.message || qsTr("Could not complete this action.")
                        root.selectionState = "failed"
                    }
                } catch (e) { }
            }
        }
        onExited: {
            if (root._selectionPending) {
                Qt.callLater(() => root._launchSelectionRequest())
                return
            }
            if (selectionProc.requestId === root.selectionRequestId
                    && (root.selectionState === "waiting" || root.selectionState === "streaming")) {
                root.selectionError = qsTr("The request ended unexpectedly.")
                root.selectionState = "failed"
            }
        }
    }

    Connections {
        target: Notes
        function onAssistantSelectionSaved(note, clientToken) {
            if (clientToken === root.selectionSaveToken) root.selectionSaveState = "saved"
        }
        function onAssistantSelectionSaveFailed(message, clientToken) {
            if (clientToken === root.selectionSaveToken) root.selectionSaveState = "failed"
        }
    }

    function requestStatusLabel() {
        switch (Assistant.requestState) {
        case "waiting": return qsTr("Thinking")
        case "streaming": return qsTr("Streaming")
        case "completed": return qsTr("Done")
        case "failed": return qsTr("Failed")
        case "cancelled": return qsTr("Cancelled")
        default: return ""
        }
    }

    function providerStatusLabel() {
        const provider = Assistant.providerUsed || ""
        if (!provider) return ""
        const actual = provider.toLowerCase()
        const preferred = (Assistant.preferredProvider || "").toLowerCase()
        const isFallback = (preferred === "gemini" && actual.indexOf("groq") >= 0)
            || (preferred === "groq" && actual.indexOf("gemini") >= 0)
        const label = isFallback ? qsTr("Fallback · %1").arg(provider) : provider
        return Assistant.latencyMs > 0 ? `${label} · ${(Assistant.latencyMs / 1000).toFixed(1)}s` : label
    }

    Connections {
        target: Assistant
        function onSelectedTextChanged() {
            if (!Assistant.selectedText || Assistant.selectedText.trim().length === 0) {
                root.askBoundToSelection = false
            }
            if (textSnippet.text !== Assistant.selectedText) {
                textSnippet.text = Assistant.selectedText;
            }
        }
    }

    Connections {
        target: Memory
        function onActiveChallengeChanged() {
            if (Memory.activeChallenge !== null) {
                root.currentView = "memory"
            }
        }
    }

    readonly property bool isHudActive: {
        const winActive = Window.active ?? false
        const hyprActive = Hypr.activeToplevel?.title === "Assistant HUD"
        return (winActive || hyprActive || root.activeFocus)
    }

    onIsHudActiveChanged: {
        Assistant.isWindowActive = isHudActive
        if (!isHudActive) root.closeSelectionPopup()
    }



    focus: true
    implicitWidth: Math.min(root.currentView === "assistant" ? 760 : 800, root.maximumHudWidth)
    implicitHeight: Math.min(mainCard.implicitHeight, root.maximumHudHeight)
    readonly property real assistantChromeHeight: headerContainer.implicitHeight
        + snippetCard.implicitHeight
        + actionSwitcher.implicitHeight
        + footerLayout.implicitHeight
        + cardLayout.spacing * (inlineErrorPanel.visible ? 5 : 4)
        + Tokens.padding.medium * 2
        + 2
        + (inlineErrorPanel.visible ? inlineErrorPanel.implicitHeight : 0)
    readonly property real maxResponseViewportHeight: Math.max(0, root.maximumHudHeight - root.assistantChromeHeight)
    readonly property real minimumResponseViewportHeight: Math.min(root.maxResponseViewportHeight,
        Math.max(180, root.maximumHudHeight * 0.32))
    readonly property real questionInputMaxHeight: Math.max(48, Math.min(160, root.maximumHudHeight * 0.18))
    readonly property real questionComposerHeight: Math.min(root.questionInputMaxHeight,
        Math.max(48, customQuestionInput.contentHeight
            + customQuestionInput.topPadding + customQuestionInput.bottomPadding))
    readonly property real preferredResponseViewportHeight: {
        if (Assistant.messages.length === 0)
            return Math.min(root.maxResponseViewportHeight, Math.max(root.minimumResponseViewportHeight,
                root.maximumHudHeight * (Assistant.isLoading ? 0.48 : 0.42)))
        if (Assistant.isGenerating)
            return Math.min(root.maxResponseViewportHeight, Math.max(root.minimumResponseViewportHeight,
                root.maximumHudHeight * 0.38))
        return Math.min(root.maxResponseViewportHeight,
            Math.max(root.minimumResponseViewportHeight, chatList.contentHeight + Tokens.padding.medium * 2))
    }
    readonly property real preferredAssistantHeight: Math.min(root.maximumHudHeight,
        root.assistantChromeHeight + Math.min(root.maxResponseViewportHeight, root.preferredResponseViewportHeight))
    readonly property real minimumHudHeight: Math.min(root.maximumHudHeight,
        root.currentView === "assistant"
            ? root.assistantChromeHeight + root.minimumResponseViewportHeight
            : Math.max(560, Math.min(640, root.maximumHudHeight)))

    Behavior on implicitHeight {
        enabled: root.currentView === "assistant"
        Anim { duration: Tokens.anim.durations.expressiveDefaultEffects }
    }

    signal closeRequested()

    function getRecommendedAction(text) {
        if (!text || text.trim().length === 0) return "explain"
        const clean = text.trim()
        if (/[\u0600-\u06FF]/.test(clean)) return "translate"
        if (/(?:error:|exception|fatal:|traceback|failed with exit code|syntaxerror|nullpointerexception|undefined is not a function|cannot read properties)/i.test(clean)) {
            return "fix"
        }
        const words = clean.split(/\s+/)
        if (words.length <= 3 && !/[{}();=<>]/.test(clean)) {
            return "translate"
        }
        return "explain"
    }

    Component.onCompleted: {
        if (Assistant.requestedView.length > 0 && Assistant.requestedView !== root.currentView)
            root.currentView = Assistant.requestedView
        Assistant.isWindowActive = root.isHudActive
        Qt.callLater(() => root.forceActiveFocus())
    }

    Component.onDestruction: {
        Assistant.isWindowActive = false
    }

    Keys.onEscapePressed: event => {
        if (root.selectionText.length > 0) {
            root.closeSelectionPopup()
            event.accepted = true
            return
        }
        if (root.currentView === "profile" && profileView.isEditing) {
            profileView.isEditing = false
            profileView.syncFromProfile()
            event.accepted = true
            return
        }
        if (root.currentView === "history" || root.currentView === "profile" || root.currentView === "memory") {
            root.currentView = "assistant"
            event.accepted = true
            return
        }
        if (customQuestionInput.activeFocus) {
            if (customQuestionInput.text.length > 0) {
                customQuestionInput.text = ""
                event.accepted = true
                return
            }
            if (root.askBoundToSelection) {
                root.askBoundToSelection = false
                root.forceActiveFocus()
                event.accepted = true
                return
            }
        }
        if (geminiInput.activeFocus || groqInput.activeFocus) {
            root.forceActiveFocus()
            event.accepted = true
            return
        }
        if (root.activeSelectedText.length > 0) {
            root.activeSelectedText = ""
            event.accepted = true
            return
        }
        root.closeRequested()
        event.accepted = true
    }

    Keys.onPressed: event => {
        if ((event.key === Qt.Key_N || event.key === Qt.Key_L) && (event.modifiers & Qt.ControlModifier)) {
            Assistant.startNewChat()
            event.accepted = true
            return
        }

        if (root.currentView === "history" || root.currentView === "profile" || root.currentView === "memory") {
            event.accepted = false
            return
        }
        if (customQuestionInput.activeFocus || geminiInput.activeFocus || groqInput.activeFocus) {
            event.accepted = false
            return
        }

        const actionMap = {
            [Qt.Key_1]: "translate",
            [Qt.Key_2]: "explain",
            [Qt.Key_3]: "tldr",
            [Qt.Key_4]: "rephrase",
            [Qt.Key_5]: "examples"
        }

        if (actionMap[event.key]) {
            root.askBoundToSelection = false
            Assistant.runAction(actionMap[event.key])
            event.accepted = true
            return
        }

        const hasSelection = Assistant.selectedText && Assistant.selectedText.trim().length > 0

        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !customQuestionInput.activeFocus) {
            if (hasSelection) {
                root.askBoundToSelection = false
                const autoAction = root.getRecommendedAction(Assistant.selectedText)
                Assistant.runAction(autoAction)
                event.accepted = true
                return
            }
        }
        if (event.key === Qt.Key_6 && hasSelection) {
            root.askBoundToSelection = true
            Assistant.activeAction = "ask"
            customQuestionInput.forceActiveFocus()
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
            if (root.activeSelectedText.length > 0) {
                Quickshell.clipboardText = root.activeSelectedText
                Assistant.lastSeenClipboard = root.activeSelectedText.trim()
                event.accepted = true
                return
            }
            if (Assistant.resultText.length > 0) {
                Quickshell.clipboardText = Assistant.resultText
                Assistant.lastSeenClipboard = Assistant.resultText.trim()
                event.accepted = true
                return
            }
        }

        if (event.key === Qt.Key_S && (event.modifiers & Qt.AltModifier)) {
            if (Assistant.resultText.length > 0 && !Assistant.isGenerating && !Memory.isCreatingQuickCard) {
                Memory.createCardFromAssistant(Assistant._activeRequest?.sourceText || Assistant.activePrompt, Assistant.resultText, Assistant.activeAction)
                event.accepted = true
                return
            }
        }

        if (event.key === Qt.Key_Slash) {
            if (root.currentView === "memory") {
                memoryView.focusSearch()
            } else if (root.currentView === "assistant") {
                customQuestionInput.forceActiveFocus()
            }
            event.accepted = true
            return
        }
    }

    Elevation {
        anchors.fill: mainCard
        radius: mainCard.radius
        level: 4
    }

    StyledRect {
        id: mainCard

        anchors.fill: parent
        radius: Tokens.rounding.medium
        color: Colours.tPalette.m3surfaceContainer
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

        implicitHeight: {
            if (root.currentView === "memory") return Math.min(root.maximumHudHeight, Math.max(root.minimumHudHeight, memoryView.implicitHeight + Tokens.padding.medium * 2))
            if (root.currentView === "history") return Math.min(root.maximumHudHeight, Math.max(root.minimumHudHeight, historyView.implicitHeight + Tokens.padding.medium * 2))
            if (root.currentView === "profile") return Math.min(root.maximumHudHeight, Math.max(root.minimumHudHeight, profileView.implicitHeight + Tokens.padding.medium * 2))
            return root.preferredAssistantHeight
        }

        ColumnLayout {
            id: cardLayout

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.small
            visible: root.currentView === "assistant"

            // ── 1. Header Row & Provider Badge ────────────────────────
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

                    MaterialIcon {
                        text: "auto_awesome"
                        fontStyle: Tokens.font.icon.medium
                        color: Colours.palette.m3primary
                    }

                    StyledText {
                        text: qsTr("Assistant")
                        font: Tokens.font.title.small
                        color: Colours.palette.m3onSurface
                    }

                    StyledRect {
                        id: activeChatBadge
                        readonly property var activeChat: (Assistant.chats || []).find(c => c && String(c.id) === String(Assistant.activeChatId))
                        visible: !!activeChat && !!activeChat.title
                        implicitHeight: 24
                        implicitWidth: titleRow.implicitWidth + Tokens.padding.small * 2
                        radius: Tokens.rounding.full
                        color: activeChatHover.hovered ? Colours.palette.m3surfaceContainerHigh : "transparent"

                        HoverHandler { id: activeChatHover }

                        RowLayout {
                            id: titleRow
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialIcon {
                                text: "forum"
                                fontStyle: Tokens.font.label.small
                                color: activeChatHover.hovered ? Colours.palette.m3primary : Colours.palette.m3outline
                            }

                            StyledText {
                                text: activeChatBadge.activeChat ? activeChatBadge.activeChat.title : ""
                                font: Tokens.font.body.small
                                color: activeChatHover.hovered ? Colours.palette.m3primary : Colours.palette.m3outline
                                elide: Text.ElideRight
                                Layout.maximumWidth: 240
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentView = "history"
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Word Count Badge in Header
                    StyledRect {
                        visible: Assistant.selectedText.trim().length > 0
                        implicitWidth: countText.implicitWidth + Tokens.padding.small * 2
                        implicitHeight: 24
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3surfaceContainerHigh

                        StyledText {
                            id: countText
                            anchors.centerIn: parent
                            text: {
                                const trimmed = Assistant.selectedText.trim()
                                if (!trimmed) return ""
                                const words = trimmed.split(/\s+/).length
                                return words === 1 ? qsTr("1 word") : qsTr("%1 words").arg(words)
                            }
                            font: Tokens.font.label.small
                            color: Colours.palette.m3outline
                        }
                    }

                    // Provider Badge with Live Dot & Latency (Click to open settings/dossier)
                    StyledRect {
                        visible: Assistant.providerUsed.length > 0
                        implicitWidth: badgeRow.implicitWidth + Tokens.padding.small * 2
                        implicitHeight: 24
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3surfaceContainerHigh

                        RowLayout {
                            id: badgeRow
                            anchors.centerIn: parent
                            spacing: 6

                            // Status dot
                            Rectangle {
                                width: 6
                                height: 6
                                radius: 3
                                color: Colours.palette.m3primary
                            }

                            StyledText {
                                Layout.maximumWidth: 180
                                text: root.providerStatusLabel()
                                font: Tokens.font.label.small
                                color: Colours.palette.m3onSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentView = "profile"
                        }
                    }

                    // Developer Dossier / Profile Button
                    IconButton {
                        type: IconButton.Text
                        icon: "badge"
                        font: Tokens.font.icon.small
                        implicitWidth: 28
                        implicitHeight: 28
                        onClicked: root.currentView = "profile"

                        // Pending proposed updates dot indicator
                        StyledRect {
                            visible: Assistant.proposedProfile !== null
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.topMargin: 2
                            anchors.rightMargin: 2
                            implicitWidth: 7
                            implicitHeight: 7
                            radius: Tokens.rounding.full
                            color: Colours.palette.m3primary
                        }
                    }

                    IconButton {
                        type: IconButton.Text
                        icon: "add"
                        font: Tokens.font.icon.small
                        implicitWidth: 28
                        implicitHeight: 28
                        onClicked: Assistant.startNewChat()
                    }

                    IconButton {
                        type: IconButton.Text
                        icon: "history"
                        font: Tokens.font.icon.small
                        implicitWidth: 28
                        implicitHeight: 28
                        onClicked: root.currentView = "history"
                    }

                    IconButton {
                        type: IconButton.Text
                        icon: "psychology"
                        font: Tokens.font.icon.small
                        implicitWidth: 28
                        implicitHeight: 28
                        onClicked: root.currentView = "memory"
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

            // ── 2. Snippet Preview ────────────────────────────────────
            StyledRect {
                id: snippetCard
                Layout.fillWidth: true
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.35)

                property bool isExpanded: false
                readonly property bool hasSelection: Assistant.selectedText.length > 0
                readonly property bool isCodeSnippet: {
                    const text = Assistant.selectedText;
                    if (!text || text.length < 5) return false;
                    return /[{};=()=>]|import\s+|class\s+|function\s+|def\s+|const\s+|let\s+|var\s+|package\s+|public\s+|private\s+/.test(text);
                }

                implicitHeight: snippetLayout.implicitHeight

                ColumnLayout {
                    id: snippetLayout
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 0

                    // ── Dedicated Sub-Header Bar ──────────────────────────────
                    Item {
                        id: snippetSubHeader
                        Layout.fillWidth: true
                        implicitHeight: 30

                        Rectangle {
                            anchors.fill: parent
                            color: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.45)
                            bottomLeftRadius: 0
                            bottomRightRadius: 0
                            topLeftRadius: snippetCard.radius
                            topRightRadius: snippetCard.radius
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: Qt.alpha(Colours.palette.m3outlineVariant, 0.25)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.small
                            anchors.rightMargin: 6
                            spacing: 6

                            MaterialIcon {
                                text: snippetCard.isCodeSnippet ? "data_object" : "subject"
                                fontStyle: Tokens.font.icon.small
                                color: Colours.palette.m3primary
                            }

                            StyledText {
                                text: qsTr("Context")
                                font: Tokens.font.label.builders.small.weight(Font.DemiBold).build()
                                color: Colours.palette.m3onSurface
                            }

                            // Truncated indicator badge
                            StyledRect {
                                visible: Assistant.isTruncated
                                radius: Tokens.rounding.full
                                color: Qt.alpha(Colours.palette.m3error, 0.2)
                                implicitWidth: truncText.implicitWidth + 8
                                implicitHeight: 18

                                StyledText {
                                    id: truncText
                                    anchors.centerIn: parent
                                    text: {
                                        const limit = Assistant.truncatedAt > 0 ? Assistant.truncatedAt : 12000
                                        const k = Math.round(limit / 1000)
                                        return qsTr("Truncated (%1k)").arg(k)
                                    }
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3error
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // Organized Toolbar: Copy, Toggle Listen, Expand/Collapse, Clear
                            IconButton {
                                type: IconButton.Text
                                icon: "content_copy"
                                font: Tokens.font.icon.small
                                visible: snippetCard.hasSelection
                                implicitWidth: 24
                                implicitHeight: 24
                                onClicked: {
                                    Quickshell.clipboardText = Assistant.selectedText
                                    Assistant.lastSeenClipboard = Assistant.selectedText.trim()
                                }
                            }

                            IconButton {
                                type: Assistant.listenClipboard ? IconButton.Text : IconButton.Tonal
                                icon: Assistant.listenClipboard ? "content_paste" : "content_paste_off"
                                font: Tokens.font.icon.small
                                implicitWidth: 24
                                implicitHeight: 24
                                onClicked: Assistant.listenClipboard = !Assistant.listenClipboard
                            }

                            IconButton {
                                type: IconButton.Text
                                icon: snippetCard.isExpanded ? "unfold_less" : "unfold_more"
                                font: Tokens.font.icon.small
                                visible: snippetCard.hasSelection && textSnippet.lineCount > 3
                                implicitWidth: 24
                                implicitHeight: 24
                                onClicked: snippetCard.isExpanded = !snippetCard.isExpanded
                            }

                            IconButton {
                                type: IconButton.Text
                                icon: "close"
                                visible: snippetCard.hasSelection
                                font: Tokens.font.icon.small
                                implicitWidth: 24
                                implicitHeight: 24
                                onClicked: Assistant.clearSelection()
                            }
                        }
                    }

                    // ── Content Area with No Text Clipping ────────────────────
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: {
                            if (!snippetCard.hasSelection) {
                                return 36;
                            }
                            const contentH = textSnippet.implicitHeight + Tokens.padding.small * 2;
                            if (snippetCard.isExpanded) {
                                return Math.min(240, Math.max(60, contentH));
                            }
                            return Math.min(96, Math.max(48, contentH));
                        }

                        Behavior on implicitHeight {
                            Anim { duration: Tokens.anim.durations.expressiveFastEffects }
                        }

                        Flickable {
                            id: snippetFlick
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.small
                            contentHeight: Math.max(snippetFlick.height, textSnippet.implicitHeight)
                            clip: true

                            StyledScrollBar.vertical: StyledScrollBar {
                                flickable: snippetFlick
                            }

                            TextEdit {
                                id: textSnippet
                                width: snippetFlick.width - Tokens.padding.small
                                text: Assistant.selectedText
                                selectByMouse: true
                                cursorVisible: activeFocus
                                renderType: TextEdit.NativeRendering
                                selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
                                selectedTextColor: Colours.palette.m3onSurface
                                wrapMode: TextEdit.Wrap
                                color: Colours.palette.m3onSurface
                                font: {
                                    const words = textSnippet.text.trim().split(/\s+/).length;
                                    if (snippetCard.isCodeSnippet)
                                        return Tokens.font.mono.small;
                                    return Tokens.font.body.small;
                                }
                                onTextChanged: {
                                    if (text !== Assistant.selectedText) {
                                        Assistant.selectedText = text;
                                    }
                                }

                                StyledText {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    visible: !textSnippet.text && !textSnippet.activeFocus
                                    text: qsTr("Type or paste context text here...")
                                    color: Colours.palette.m3outline
                                    font: Tokens.font.body.builders.small.size(11.5).build()
                                }
                            }
                        }
                    }
                }
            }

            // ── 3. Action Switcher (BtnSwitcher) ──────────────────────
            BtnSwitcher {
                id: actionSwitcher
                Layout.alignment: Qt.AlignHCenter
                givenHeight: 32
                radius: Tokens.rounding.full
                borderColor: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)
                backgroundColor: Colours.palette.m3surfaceContainerHigh
                font: Tokens.font.label.small
                // showOnlyActiveText: true
                allowReclick: true

                currentValue: {
                    if (root.askBoundToSelection) return "ask"
                    return Assistant.activeAction || ""
                }

                model: {
                    const isError = root.getRecommendedAction(Assistant.selectedText) === "fix"
                    const items = []
                    if (isError) {
                        items.push({ icon: "build", text: qsTr("Fix & Debug"), value: "fix" })
                    }
                    items.push(
                        { icon: "translate", text: qsTr("Translate"), value: "translate" },
                        { icon: "lightbulb",  text: qsTr("Explain"),   value: "explain" },
                        { icon: "notes",      text: qsTr("TL;DR"),     value: "tldr" },
                        { icon: "sync",       text: qsTr("Rephrase"),  value: "rephrase" },
                        { icon: "format_list_bulleted", text: qsTr("Examples"), value: "examples" }
                    )
                    if (Assistant.selectedText && Assistant.selectedText.trim().length > 0) {
                        items.push({ icon: "chat", text: qsTr("Ask"), value: "ask" })
                    }
                    return items
                }

                onActivated: value => {
                    if (value === "ask") {
                        root.askBoundToSelection = true
                        Assistant.activeAction = "ask"
                        customQuestionInput.forceActiveFocus()
                    } else {
                        root.askBoundToSelection = false
                        Assistant.runAction(value)
                    }
                }
            }



            // ── 4. Main Result View / Shimmer Skeleton ────────────────
            StyledRect {
                id: inlineErrorPanel
                visible: Assistant.messages.length > 0 && Assistant.errorMessage.length > 0
                Layout.fillWidth: true
                implicitHeight: inlineErrorRow.implicitHeight + 12
                radius: Tokens.rounding.small
                color: Colours.palette.m3errorContainer

                RowLayout {
                    id: inlineErrorRow
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    MaterialIcon {
                        text: "error_outline"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onErrorContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Assistant.errorMessage
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onErrorContainer
                        wrapMode: Text.Wrap
                    }

                    IconTextButton {
                        visible: Assistant.hasApiKey && Assistant.errorType !== "auth"
                        type: IconTextButton.Tonal
                        icon: "refresh"
                        text: qsTr("Retry")
                        font: Tokens.font.label.small
                        onClicked: Assistant.retryAction()
                    }

                    IconTextButton {
                        visible: !Assistant.hasApiKey || Assistant.errorType === "auth"
                        type: IconTextButton.Tonal
                        icon: "vpn_key"
                        text: qsTr("Settings")
                        font: Tokens.font.label.small
                        onClicked: root.currentView = "profile"
                    }
                }
            }

            StyledRect {
                id: resultContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: root.minimumResponseViewportHeight
                implicitHeight: Math.min(root.maxResponseViewportHeight, root.preferredResponseViewportHeight)
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerLowest
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.3)

                Behavior on implicitHeight {
                    enabled: !Assistant.isStreaming
                    Anim { duration: Tokens.anim.durations.expressiveDefaultEffects }
                }

                // 4A. Shimmer / Pulsing Skeleton Indicator
                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - Tokens.padding.large * 2
                    visible: Assistant.isLoading && Assistant.messages.length === 0
                    spacing: Tokens.spacing.medium

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: "progress_activity"
                            fontStyle: Tokens.font.icon.medium
                            color: Colours.palette.m3primary

                            RotationAnimation on rotation {
                                from: 0
                                to: 360
                                duration: 1100
                                loops: Animation.Infinite
                                running: Assistant.isLoading
                            }
                        }

                        StyledText {
                            text: qsTr("Synthesizing answer...")
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }

                    // Pulsing Skeleton Bars
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: [1.0, 0.85, 0.6]
                            delegate: StyledRect {
                                id: bar
                                required property real modelData
                                Layout.preferredWidth: (resultContainer.width - Tokens.padding.large * 2) * modelData
                                implicitHeight: 12
                                radius: Tokens.rounding.full
                                color: Colours.palette.m3surfaceContainerHigh

                                SequentialAnimation on opacity {
                                    running: Assistant.isLoading
                                    loops: Animation.Infinite
                                    Anim { target: bar; property: "opacity"; from: 0.35; to: 0.85; duration: 750 }
                                    Anim { target: bar; property: "opacity"; from: 0.85; to: 0.35; duration: 750 }
                                }
                            }
                        }
                    }
                }

                // 4B. Error / Missing API Key View
                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - Tokens.padding.medium * 2
                    visible: !Assistant.isLoading && Assistant.messages.length === 0 && (Assistant.errorMessage.length > 0 || !Assistant.hasApiKey)
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: {
                            if (!Assistant.hasApiKey || Assistant.errorType === "auth") return "vpn_key"
                            if (Assistant.errorType === "network") return "wifi_off"
                            if (Assistant.errorType === "rate_limit") return "hourglass_empty"
                            if (Assistant.errorType === "no_selection") return "content_paste_off"
                            return "error_outline"
                        }
                        fontStyle: Tokens.font.icon.large
                        color: {
                            if (Assistant.errorType === "rate_limit") return Colours.palette.m3tertiary
                            if (Assistant.errorType === "no_selection") return Colours.palette.m3outline
                            return Colours.palette.m3error
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: Assistant.errorMessage
                        font: Tokens.font.body.small
                        color: {
                            if (Assistant.errorType === "rate_limit") return Colours.palette.m3tertiary
                            if (Assistant.errorType === "no_selection") return Colours.palette.m3outline
                            return Colours.palette.m3error
                        }
                    }

                    // Error Action Row: Retry & Capture Clipboard
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        visible: Assistant.hasApiKey && Assistant.errorType !== "auth"
                        spacing: Tokens.spacing.small

                        IconTextButton {
                            type: IconTextButton.Filled
                            icon: "refresh"
                            text: qsTr("Retry")
                            font: Tokens.font.label.small
                            onClicked: Assistant.retryAction()
                        }

                        IconTextButton {
                            visible: Assistant.errorType === "no_selection"
                            type: IconTextButton.Tonal
                            icon: "content_paste"
                            text: qsTr("Capture Clipboard")
                            font: Tokens.font.label.small
                            onClicked: Assistant.checkClipboard()
                        }
                    }

                    // Key & Engine Configuration View
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !Assistant.hasApiKey || Assistant.errorType === "auth"
                        spacing: Tokens.spacing.extraSmall

                        property string setupProvider: Assistant.preferredProvider || "gemini"
                        property int setupTrunc: Assistant.maxChars || 12000

                        StyledTextField {
                            id: geminiInput
                            Layout.fillWidth: true
                            text: Assistant.geminiKey
                            placeholderText: "Google Gemini API Key..."
                        }

                        StyledTextField {
                            id: groqInput
                            Layout.fillWidth: true
                            text: Assistant.groqKey
                            placeholderText: "Groq API Key (Optional)..."
                        }

                        // Provider Selection Chips
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 6

                            StyledText {
                                text: qsTr("Provider:")
                                font: Tokens.font.label.small
                                color: Colours.palette.m3outline
                            }

                            StyledRect {
                                readonly property bool isGemini: parent.parent.setupProvider === "gemini"
                                implicitWidth: geminiChipText.implicitWidth + 16
                                implicitHeight: 24
                                radius: Tokens.rounding.full
                                color: isGemini ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                                StyledText {
                                    id: geminiChipText
                                    anchors.centerIn: parent
                                    text: "Gemini Flash"
                                    font: Tokens.font.label.small
                                    color: parent.isGemini ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                }

                                StateLayer {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: parent.parent.parent.setupProvider = "gemini"
                                }
                            }

                            StyledRect {
                                readonly property bool isGroq: parent.parent.setupProvider === "groq"
                                implicitWidth: groqChipText.implicitWidth + 16
                                implicitHeight: 24
                                radius: Tokens.rounding.full
                                color: isGroq ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                                StyledText {
                                    id: groqChipText
                                    anchors.centerIn: parent
                                    text: "Groq Llama 3.3"
                                    font: Tokens.font.label.small
                                    color: parent.isGroq ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                }

                                StateLayer {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: parent.parent.parent.setupProvider = "groq"
                                }
                            }
                        }

                        // Truncation Limit Chips
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 6

                            StyledText {
                                text: qsTr("Max Chars:")
                                font: Tokens.font.label.small
                                color: Colours.palette.m3outline
                            }

                            Repeater {
                                model: [
                                    { label: "12k", val: 12000 },
                                    { label: "50k", val: 50000 },
                                    { label: "100k", val: 100000 }
                                ]

                                delegate: StyledRect {
                                    id: truncChip
                                    required property var modelData
                                    readonly property bool isSel: parent.parent.setupTrunc === truncChip.modelData.val
                                    implicitWidth: truncChipText.implicitWidth + 14
                                    implicitHeight: 22
                                    radius: Tokens.rounding.full
                                    color: isSel ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                                    StyledText {
                                        id: truncChipText
                                        anchors.centerIn: parent
                                        text: truncChip.modelData.label
                                        font: Tokens.font.label.small
                                        color: truncChip.isSel ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                    }

                                    StateLayer {
                                        anchors.fill: parent
                                        radius: parent.radius
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: parent.parent.parent.setupTrunc = truncChip.modelData.val
                                    }
                                }
                            }
                        }

                        TextButton {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 4
                            text: qsTr("Save Settings")
                            onClicked: {
                                Assistant.saveSettings(
                                    geminiInput.text,
                                    groqInput.text,
                                    parent.setupProvider,
                                    parent.setupTrunc
                                )
                            }
                        }
                    }
                }

                // 4C. Idle State with Keyboard Badges
                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - Tokens.padding.large * 2
                    visible: !Assistant.isLoading && Assistant.errorMessage.length === 0 && Assistant.hasApiKey && Assistant.messages.length === 0
                    spacing: Tokens.spacing.medium

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8

                        MaterialIcon {
                            text: "touch_app"
                            fontStyle: Tokens.font.icon.medium
                            color: Colours.palette.m3primary
                        }

                        StyledText {
                            text: qsTr("Choose an action above or ask anything below")
                            font: Tokens.font.body.medium
                            color: Colours.palette.m3onSurface
                        }
                    }

                    // Keyboard Shortcuts Hint Badges
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Tokens.spacing.small

                        Repeater {
                            model: [
                                { key: (Assistant.selectedText && Assistant.selectedText.trim().length > 0) ? "1-6" : "1-5", label: qsTr("Actions") },
                                { key: "/",   label: qsTr("Question") },
                                { key: "Ctrl+C", label: qsTr("Copy") },
                                { key: "Esc", label: qsTr("Dismiss") }
                            ]

                            delegate: RowLayout {
                                id: badgeGroup
                                required property var modelData
                                spacing: 4

                                StyledRect {
                                    implicitWidth: keyLabel.implicitWidth + 8
                                    implicitHeight: 20
                                    radius: Tokens.rounding.extraSmall
                                    color: Colours.palette.m3surfaceContainerHigh
                                    border.width: 1
                                    border.color: Colours.palette.m3outlineVariant

                                    StyledText {
                                        id: keyLabel
                                        anchors.centerIn: parent
                                        text: badgeGroup.modelData.key
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3primary
                                    }
                                }

                                StyledText {
                                    text: badgeGroup.modelData.label
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3outline
                                }
                            }
                        }
                    }
                }

                // 4D. Scrollable Multi-Turn Conversation Stream
                Item {
                    id: chatStreamContainer
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    visible: Assistant.hasApiKey && Assistant.messages.length > 0

                    ListView {
                        id: chatList
                        anchors.fill: parent
                        clip: true
                        spacing: 12
                        model: Assistant.messages

                        property int lastMessageCount: 0
                        property bool userScrolledUp: false

                        TapHandler {
                            onTapped: {
                                if (root.selectionText.length > 0) root.closeSelectionPopup()
                            }
                        }

                        onContentYChanged: {
                            if (chatList.moving && root.selectionText.length > 0)
                                root.closeSelectionPopup()
                            if (chatList.moving && !chatList.atYEnd) {
                                chatList.userScrolledUp = true
                            } else if (chatList.atYEnd) {
                                chatList.userScrolledUp = false
                            }
                        }

                        Connections {
                            target: Assistant

                            function onResultTextChanged() {
                                if (Assistant.isStreaming && !chatList.userScrolledUp) {
                                    Qt.callLater(() => {
                                        if (!chatList.userScrolledUp) chatList.positionViewAtEnd()
                                    })
                                }
                            }

                            function onIsStreamingChanged() {
                                if (!Assistant.isStreaming && !chatList.userScrolledUp) {
                                    Qt.callLater(() => chatList.positionViewAtEnd())
                                }
                            }

                            function onMessagesChanged() {
                                const msgs = Assistant.messages
                                if (root.selectionMessageId && !(msgs || []).some(m => String(m.id || "") === root.selectionMessageId))
                                    root.closeSelectionPopup()
                                if (!msgs || msgs.length === 0) {
                                    chatList.lastMessageCount = 0
                                    chatList.userScrolledUp = false
                                    return
                                }
                                if (msgs.length > chatList.lastMessageCount) {
                                    chatList.userScrolledUp = false
                                    Qt.callLater(() => chatList.positionViewAtEnd())
                                }
                                chatList.lastMessageCount = msgs.length
                            }
                        }

                        StyledScrollBar.vertical: StyledScrollBar {
                            flickable: chatList
                        }

                        delegate: Item {
                            id: msgDelegate
                            required property var modelData
                            required property int index

                            width: chatList.width
                            implicitHeight: msgCol.implicitHeight

                            ColumnLayout {
                                id: msgCol
                                width: parent.width
                                spacing: 4

                                // 1. Topic Shift Divider
                                RowLayout {
                                    visible: modelData.type === "topic_divider"
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 1
                                        color: Colours.palette.m3outlineVariant
                                    }

                                    StyledRect {
                                        Layout.preferredHeight: 22
                                        Layout.preferredWidth: topicDivRow.implicitWidth + 18
                                        radius: Tokens.rounding.full
                                        color: Colours.palette.m3surfaceContainerHigh

                                        RowLayout {
                                            id: topicDivRow
                                            anchors.centerIn: parent
                                            spacing: 4

                                            MaterialIcon {
                                                text: "auto_awesome"
                                                fontStyle: Tokens.font.icon.small
                                                color: Colours.palette.m3primary
                                            }

                                            StyledText {
                                                id: topicDivText
                                                text: modelData.text || qsTr("New Context")
                                                font: Tokens.font.label.small
                                                color: Colours.palette.m3onSurfaceVariant
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 1
                                        color: Colours.palette.m3outlineVariant
                                    }
                                }

                                // 2. User Question Bubble
                                RowLayout {
                                    visible: modelData.role === "user"
                                    Layout.fillWidth: true

                                    Item { Layout.fillWidth: true }

                                    StyledRect {
                                        Layout.maximumWidth: Math.min(parent.width * 0.88, 520)
                                        implicitWidth: userMsgCol.implicitWidth + 16
                                        implicitHeight: userMsgCol.implicitHeight + 12
                                        radius: Tokens.rounding.medium
                                        color: Colours.palette.m3primaryContainer

                                        ColumnLayout {
                                            id: userMsgCol
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 4

                                            RowLayout {
                                                visible: modelData.action && modelData.action !== "ask"
                                                spacing: 4

                                                MaterialIcon {
                                                    text: "label"
                                                    fontStyle: Tokens.font.icon.small
                                                    color: Colours.palette.m3onPrimaryContainer
                                                }

                                                StyledText {
                                                    text: String(modelData.action).toUpperCase()
                                                    font: Tokens.font.label.small
                                                    color: Colours.palette.m3onPrimaryContainer
                                                }
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: modelData.text || ""
                                                font: Tokens.font.body.small
                                                color: Colours.palette.m3onPrimaryContainer
                                                wrapMode: Text.Wrap
                                            }

                                            StyledText {
                                                Layout.alignment: Qt.AlignRight
                                                text: modelData.timestamp || ""
                                                font: Tokens.font.label.small
                                                color: Qt.alpha(Colours.palette.m3onPrimaryContainer, 0.6)
                                            }
                                        }
                                    }
                                }

                                // 3. Assistant Answer Card
                                    StyledRect {
                                        id: assistantMessageCard
                                        visible: modelData.role === "assistant"
                                    Layout.fillWidth: true
                                    implicitHeight: assistantMsgCol.implicitHeight + 16
                                    radius: Tokens.rounding.medium
                                    color: Colours.palette.m3surfaceContainerLow
                                    border.width: 1
                                    border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

                                    readonly property bool isLastItem: (index === chatList.count - 1)
                                    readonly property bool isCurrentStreaming: (isLastItem && Assistant.isGenerating)
                                    readonly property string displayText: (isLastItem && Assistant.resultText.length > 0) ? Assistant.resultText : (modelData.text || "")

                                    ColumnLayout {
                                        id: assistantMsgCol
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 6

                                        TextEdit {
                                            id: msgTextEdit
                                            Layout.fillWidth: true
                                            text: assistantMessageCard.displayText
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

                                            onSelectedTextChanged: {
                                                if (selectedText && selectedText.trim().length > 0) {
                                                    root.activeSelectedText = selectedText.trim()
                                                    selectionRevealTimer.restart()
                                                } else {
                                                    selectionRevealTimer.stop()
                                                    if (root.selectionText.length === 0) root.activeSelectedText = ""
                                                }
                                            }

                                            Timer {
                                                id: selectionRevealTimer
                                                interval: 180
                                                onTriggered: {
                                                    if (!msgTextEdit.selectedText || assistantMessageCard.isCurrentStreaming) return
                                                    const start = Math.max(0, msgTextEdit.selectionStart - 170)
                                                    const end = Math.min(msgTextEdit.length, msgTextEdit.selectionEnd + 170)
                                                    let nearby = ""
                                                    if (typeof msgTextEdit.getText === "function")
                                                        nearby = msgTextEdit.getText(start, end)
                                                    const rect = msgTextEdit.positionToRectangle(msgTextEdit.selectionEnd)
                                                    const point = msgTextEdit.mapToItem(chatStreamContainer, rect.x, rect.y)
                                                    root.showSelection(msgTextEdit.selectedText, nearby,
                                                        msgDelegate.modelData.id || "", msgTextEdit, point.x, point.y, rect.height)
                                                }
                                            }
                                        }

                                        // Streaming Shimmer Indicator when waiting for first token
                                        RowLayout {
                                            visible: assistantMessageCard.isCurrentStreaming && (!msgTextEdit.text || msgTextEdit.text.length === 0)
                                            spacing: 6

                                            MaterialIcon {
                                                text: "progress_activity"
                                                fontStyle: Tokens.font.icon.small
                                                color: Colours.palette.m3primary

                                                RotationAnimation on rotation {
                                                    from: 0
                                                    to: 360
                                                    duration: 1000
                                                    loops: Animation.Infinite
                                                    running: assistantMessageCard.isCurrentStreaming
                                                }
                                            }

                                            StyledText {
                                                text: qsTr("Thinking...")
                                                font: Tokens.font.body.small
                                                color: Colours.palette.m3outline
                                            }
                                        }

                                        // Per-Message Action Toolbar
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            visible: !assistantMessageCard.isCurrentStreaming && Boolean(assistantMessageCard.displayText && assistantMessageCard.displayText.length > 0)

                                            StyledText {
                                                text: modelData.timestamp || ""
                                                font: Tokens.font.label.small
                                                color: Colours.palette.m3outline
                                            }

                                            Item { Layout.fillWidth: true }

                                            MessageActionBar {
                                                text: assistantMessageCard.displayText
                                                action: modelData.action || "ask"
                                                sourceText: modelData.sourceText || modelData.prompt || ""
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Actions on text selected inside an assistant answer. This overlay is a
                    // sibling of the clipped ListView, so it remains fully visible at its edges.
                    Item {
                        id: selectionPopup
                        visible: root.selectionText.length > 0 && root.currentView === "assistant"
                        z: 20
                        width: Math.min(420, chatStreamContainer.width - 12)
                        height: selectionPopupColumn.implicitHeight
                        x: Math.max(6, Math.min(root.selectionAnchorX, chatStreamContainer.width - width - 6))
                        y: {
                            const below = root.selectionAnchorY + root.selectionLineHeight + 6
                            if (below + height <= chatStreamContainer.height - 6) return below
                            return Math.max(6, Math.min(root.selectionAnchorY - height - 6,
                                chatStreamContainer.height - height - 6))
                        }

                        StyledRect {
                            anchors.fill: parent
                            radius: Tokens.rounding.medium
                            color: Colours.palette.m3surfaceContainerHigh
                            border.width: 1
                            border.color: Colours.palette.m3outlineVariant
                        }

                        ColumnLayout {
                            id: selectionPopupColumn
                            width: parent.width
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.margins: 4
                                spacing: 0

                                IconTextButton {
                                    type: IconTextButton.Text
                                    icon: "help_outline"
                                    text: qsTr("Explain")
                                    font: Tokens.font.label.small
                                    horizontalPadding: 5
                                    verticalPadding: 5
                                    onClicked: root.runSelectionAction("explain")
                                }
                                IconTextButton {
                                    type: IconTextButton.Text
                                    icon: "translate"
                                    text: qsTr("Translate")
                                    font: Tokens.font.label.small
                                    horizontalPadding: 5
                                    verticalPadding: 5
                                    onClicked: root.runSelectionAction("translate")
                                }
                                IconTextButton {
                                    type: IconTextButton.Text
                                    icon: root.selectionSaveState === "saved" ? "check" : "note_add"
                                    text: root.selectionSaveState === "saved" ? qsTr("Saved") : qsTr("Notes")
                                    font: Tokens.font.label.small
                                    horizontalPadding: 5
                                    verticalPadding: 5
                                    disabled: root.selectionSaveState === "saving" || root.selectionSaveState === "saved"
                                    onClicked: {
                                        const token = "selection_note_" + Date.now() + "_" + Math.random()
                                        root.selectionSaveToken = token
                                        if (Notes.saveAssistantSelection(root.selectionText, token))
                                            root.selectionSaveState = "saving"
                                    }
                                }
                                IconTextButton {
                                    type: IconTextButton.Text
                                    icon: "content_copy"
                                    text: qsTr("Copy")
                                    font: Tokens.font.label.small
                                    horizontalPadding: 5
                                    verticalPadding: 5
                                    onClicked: {
                                        Quickshell.clipboardText = root.selectionText
                                        Assistant.lastSeenClipboard = root.selectionText
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                IconButton {
                                    type: IconButton.Text
                                    icon: "close"
                                    implicitWidth: 24
                                    implicitHeight: 24
                                    onClicked: root.closeSelectionPopup()
                                }
                            }

                            Rectangle {
                                visible: root.selectionState !== "idle"
                                Layout.fillWidth: true
                                height: 1
                                color: Colours.palette.m3outlineVariant
                            }

                            Item {
                                visible: root.selectionState !== "idle"
                                Layout.fillWidth: true
                                implicitHeight: Math.min(142, Math.max(66, selectionResult.implicitHeight + 40))

                                StyledText {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.leftMargin: 12
                                    anchors.topMargin: 8
                                    text: root.selectionAction === "translate" ? qsTr("Translation") : qsTr("Explanation")
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3primary
                                }

                                Flickable {
                                    anchors.fill: parent
                                    anchors.topMargin: 30
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    anchors.bottomMargin: 8
                                    contentWidth: width
                                    contentHeight: selectionResult.implicitHeight
                                    clip: true

                                    TextEdit {
                                        id: selectionResult
                                        width: parent.width
                                        readOnly: true
                                        selectByMouse: true
                                        cursorVisible: false
                                        textFormat: TextEdit.MarkdownText
                                        wrapMode: TextEdit.Wrap
                                        font: Tokens.font.body.small
                                        color: root.selectionState === "failed" ? Colours.palette.m3error : Colours.palette.m3onSurface
                                        text: root.selectionState === "failed" ? root.selectionError
                                            : root.selectionOutput.length > 0 ? root.selectionOutput
                                            : root.selectionState === "done" ? qsTr("No response received.") : qsTr("Thinking…")
                                    }
                                }
                            }
                        }
                    }

                    // Floating "↓ Latest" button
                    StyledRect {
                        visible: chatList.userScrolledUp && Assistant.messages.length > 1
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 10
                        implicitWidth: jumpRow.implicitWidth + 14
                        implicitHeight: 26
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary
                        z: 10

                        RowLayout {
                            id: jumpRow
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialIcon {
                                text: "arrow_downward"
                                fontStyle: Tokens.font.icon.small
                                color: Colours.palette.m3onPrimary
                            }

                            StyledText {
                                text: qsTr("Latest")
                                font: Tokens.font.label.small
                                color: Colours.palette.m3onPrimary
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                chatList.userScrolledUp = false
                                chatList.positionViewAtEnd()
                            }
                        }
                    }
                }
            }

            // ── 5. Footer / Custom Question Bar ───────────────────────
            ColumnLayout {
                id: footerLayout
                Layout.fillWidth: true
                spacing: 6
                implicitHeight: contextChipRow.implicitHeight + questionInputRow.implicitHeight + spacing

                // Context Chip Row (above input row)
                RowLayout {
                    id: contextChipRow
                    Layout.fillWidth: true
                    spacing: 4

                    StyledRect {
                        visible: Assistant.requestState !== "idle"
                        implicitWidth: requestStatusText.implicitWidth + 16
                        implicitHeight: 22
                        radius: Tokens.rounding.full
                        color: Assistant.requestState === "failed"
                            ? Colours.palette.m3errorContainer
                            : Colours.palette.m3surfaceContainerHigh

                        StyledText {
                            id: requestStatusText
                            anchors.centerIn: parent
                            text: root.requestStatusLabel()
                            font: Tokens.font.label.small
                            color: Assistant.requestState === "failed"
                                ? Colours.palette.m3onErrorContainer
                                : (Assistant.requestState === "streaming" || Assistant.requestState === "waiting"
                                   ? Colours.palette.m3primary : Colours.palette.m3outline)
                        }
                    }

                    IconButton {
                        visible: Assistant.isGenerating
                        type: IconButton.Text
                        icon: "stop"
                        font: Tokens.font.icon.small
                        implicitWidth: 24
                        implicitHeight: 24
                        padding: 0
                        onClicked: Assistant.cancelCurrentRequest()
                    }

                    StyledRect {
                        id: contextChip
                        implicitHeight: 22
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3surfaceContainerHigh
                        implicitWidth: chipRow.implicitWidth + ((root.askBoundToSelection || Assistant.hasThread) ? 22 : 16)

                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 4

                            MouseArea {
                                implicitWidth: chipText.implicitWidth
                                implicitHeight: 22
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.askBoundToSelection) {
                                        root.askBoundToSelection = false
                                        return
                                    }
                                    if (Assistant.inputMode === "auto") {
                                        Assistant.inputMode = "followup"
                                    } else if (Assistant.inputMode === "followup") {
                                        Assistant.inputMode = "standalone"
                                    } else {
                                        Assistant.inputMode = "auto"
                                    }
                                }

                                StyledText {
                                    id: chipText
                                    anchors.centerIn: parent
                                    text: {
                                        let modeText = ""
                                        if (Assistant.inputMode === "followup") modeText = qsTr("↩ Follow-up")
                                        else if (Assistant.inputMode === "standalone") modeText = qsTr("🌐 Standalone")
                                        else modeText = qsTr("↻ Auto")
                                        if (root.askBoundToSelection) {
                                            return qsTr("📌 Selection · %1").arg(modeText)
                                        }
                                        return modeText
                                    }
                                    font: Tokens.font.label.small
                                    color: {
                                        if (Assistant.inputMode === "followup") {
                                            return Colours.palette.m3primary
                                        }
                                        return Assistant.inputMode === "standalone"
                                            ? Colours.palette.m3outline : Colours.palette.m3secondary
                                    }
                                }
                            }

                            // Small × on chip
                            MouseArea {
                                visible: root.askBoundToSelection || Assistant.hasThread
                                implicitWidth: 14
                                implicitHeight: 14
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.askBoundToSelection) {
                                        root.askBoundToSelection = false
                                    } else {
                                        Assistant.clearThread()
                                    }
                                }

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: "close"
                                    fontStyle: Tokens.font.label.small
                                    color: Colours.palette.m3outline
                                }
                            }
                        }
                    }

                    StyledRect {
                        implicitHeight: 22
                        implicitWidth: personalContextRow.implicitWidth + 14
                        radius: Tokens.rounding.full
                        opacity: Assistant.isGenerating ? 0.55 : 1
                        color: Assistant.personalContextEnabled
                            ? Colours.palette.m3surfaceContainerHigh
                            : Qt.alpha(Colours.palette.m3tertiary, 0.18)

                        RowLayout {
                            id: personalContextRow
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialIcon {
                                text: Assistant.personalContextEnabled ? "psychology" : "psychology_alt"
                                fontStyle: Tokens.font.label.small
                                color: Assistant.personalContextEnabled ? Colours.palette.m3primary : Colours.palette.m3tertiary
                            }

                            StyledText {
                                text: Assistant.personalContextEnabled ? qsTr("Personal on") : qsTr("Personal off")
                                font: Tokens.font.label.small
                                color: Assistant.personalContextEnabled ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3tertiary
                            }
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            enabled: !Assistant.isGenerating
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Assistant.personalContextEnabled = !Assistant.personalContextEnabled
                        }
                    }

                    // Token count & turn count metrics badge
                    StyledRect {
                        visible: (Assistant.messages || []).length > 0
                        implicitHeight: 22
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3surfaceContainerHigh
                        implicitWidth: metricsRow.implicitWidth + 14

                        RowLayout {
                            id: metricsRow
                            anchors.centerIn: parent
                            spacing: 4

                            StyledText {
                                readonly property int turnCount: Math.ceil(((Assistant.messages || []).filter(m => m.role === "user").length) || 0)
                                readonly property int charTotal: (Assistant.messages || []).reduce((acc, m) => acc + (m.text ? m.text.length : 0), 0)
                                readonly property int estTokens: Math.round(charTotal / 4)
                                text: {
                                    const tokenStr = estTokens >= 1000 ? (estTokens / 1000).toFixed(1) + "k" : estTokens
                                    return `${turnCount} ${turnCount === 1 ? 'turn' : 'turns'} · ~${tokenStr} tokens`
                                }
                                font: Tokens.font.label.small
                                color: Colours.palette.m3outline
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Export chat thread to Markdown
                    IconButton {
                        visible: (Assistant.messages || []).length > 0
                        type: IconButton.Text
                        icon: "content_copy"
                        font: Tokens.font.icon.small
                        implicitWidth: 22
                        implicitHeight: 22
                        padding: 0
                        onClicked: {
                            const msgs = Assistant.messages || []
                            const activeChat = (Assistant.chats || []).find(c => c && String(c.id) === String(Assistant.activeChatId))
                            let md = `# ${activeChat ? activeChat.title : "Assistant Chat"}\n\n`
                            md += `*Exported on ${new Date().toLocaleString()}*\n\n---\n\n`
                            for (let i = 0; i < msgs.length; i++) {
                                const m = msgs[i]
                                const role = m.role === "assistant" ? "**Assistant**" : "**You**"
                                md += `### ${role} (${m.timestamp || ""})\n\n${m.text}\n\n`
                            }
                            Quickshell.execDetached(["wl-copy", md])
                        }
                    }
                }

                // Input Row
                RowLayout {
                    id: questionInputRow
                    Layout.fillWidth: true
                    implicitHeight: Math.max(root.questionComposerHeight, sendQuestionButton.implicitHeight, 40)
                    spacing: Tokens.spacing.small

                    QQC.ScrollView {
                        id: questionScroll
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.questionComposerHeight
                        Layout.minimumHeight: 48
                        clip: true
                        contentWidth: availableWidth
                        background: StyledRect {
                            radius: Tokens.rounding.small
                            color: Colours.palette.m3surfaceContainerHigh
                            border.width: 1
                            border.color: customQuestionInput.activeFocus ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outlineVariant, 0.7)
                        }

                        QQC.TextArea {
                            id: customQuestionInput
                            width: questionScroll.availableWidth
                            implicitHeight: contentHeight + topPadding + bottomPadding
                            padding: Tokens.padding.small
                            wrapMode: TextEdit.Wrap
                            selectByMouse: true
                            color: Colours.palette.m3onSurface
                            placeholderTextColor: Colours.palette.m3onSurfaceVariant
                            selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
                            selectedTextColor: Colours.palette.m3onSurface
                            font: Tokens.font.body.small
                            background: null
                            placeholderText: root.askBoundToSelection
                                ? qsTr("Ask about this selection…")
                                : qsTr("Ask anything…  ·  Ctrl+Enter to send")

                            function submit(): void {
                                const prompt = text.trim()
                                if (Assistant.isGenerating || !prompt) return
                                if (root.askBoundToSelection) Assistant.clearThread()
                                Assistant.runAction("ask", prompt)
                                clear()
                                root.askBoundToSelection = false
                            }

                            Keys.onPressed: event => {
                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                        && (event.modifiers & Qt.ControlModifier)) {
                                    submit()
                                    event.accepted = true
                                }
                            }
                        }
                    }

                IconButton {
                    id: sendQuestionButton
                    Layout.alignment: Qt.AlignBottom
                    type: IconButton.Filled
                    icon: "send"
                    font: Tokens.font.icon.small
                    implicitWidth: 36
                    implicitHeight: 36
                    enabled: !Assistant.isGenerating && customQuestionInput.text.trim().length > 0
                    opacity: enabled ? 1.0 : 0.4
                    onClicked: customQuestionInput.submit()
                }
            }
            }
        }

        HistoryView {
            id: historyView
            windowRef: root.windowRef
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            visible: root.currentView === "history"
            onBackRequested: {
                root.askBoundToSelection = false
                root.currentView = "assistant"
                Qt.callLater(() => customQuestionInput.forceActiveFocus())
            }
            onCloseRequested: root.closeRequested()
        }

        ProfileView {
            id: profileView
            windowRef: root.windowRef
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            visible: root.currentView === "profile"
            onBackRequested: root.currentView = "assistant"
            onCloseRequested: root.closeRequested()
        }

        MemoryView {
            id: memoryView
            windowRef: root.windowRef
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            visible: root.currentView === "memory"
            onBackRequested: root.currentView = "assistant"
            onCloseRequested: root.closeRequested()
        }
    }
}
