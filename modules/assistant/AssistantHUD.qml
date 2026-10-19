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

    property var windowRef: null
    property string currentView: "assistant" // "assistant", "history", "profile", "memory"
    property bool askBoundToSelection: false

    Connections {
        target: Assistant
        function onSelectedTextChanged() {
            if (!Assistant.selectedText || Assistant.selectedText.trim().length === 0) {
                root.askBoundToSelection = false
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
    }

    focus: true
    width: {
        if (root.currentView === "memory") return 680
        if (root.currentView === "profile" || root.currentView === "history") return 680
        return 640
    }
    implicitWidth: width
    implicitHeight: mainCard.implicitHeight

    signal closeRequested()

    Component.onCompleted: {
        Assistant.isWindowActive = root.isHudActive
        Qt.callLater(() => root.forceActiveFocus())
    }

    Component.onDestruction: {
        Assistant.isWindowActive = false
    }

    Keys.onEscapePressed: event => {
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
        if (contentText.activeFocus && contentText.selectedText.length > 0) {
            contentText.deselect()
            event.accepted = true
            return
        }
        root.closeRequested()
        event.accepted = true
    }

    Keys.onPressed: event => {
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
        if (event.key === Qt.Key_6 && hasSelection) {
            root.askBoundToSelection = true
            Assistant.activeAction = "ask"
            customQuestionInput.forceActiveFocus()
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
            if (contentText.selectedText && contentText.selectedText.length > 0) {
                Quickshell.clipboardText = contentText.selectedText
                Assistant.lastSeenClipboard = contentText.selectedText.trim()
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

        if (event.key === Qt.Key_Slash) {
            if (root.currentView === "memory") {
                memoryView.focusSearch()
            } else if (root.currentView === "main") {
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
            if (root.currentView === "memory") return 620
            if (root.currentView === "history" || root.currentView === "profile") return 680
            return cardLayout.implicitHeight + Tokens.padding.medium * 2
        }

        Behavior on implicitHeight {
            enabled: !Assistant.isStreaming
            Anim { duration: Tokens.anim.durations.expressiveDefaultEffects }
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
                                text: Assistant.latencyMs > 0
                                    ? `${Assistant.providerUsed} • ${(Assistant.latencyMs / 1000).toFixed(1)}s`
                                    : Assistant.providerUsed
                                font: Tokens.font.label.small
                                color: Colours.palette.m3onSurfaceVariant
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
                            contentHeight: textSnippet.implicitHeight
                            clip: true

                            StyledScrollBar.vertical: StyledScrollBar {
                                flickable: snippetFlick
                            }

                            StyledText {
                                id: textSnippet
                                width: snippetFlick.width - Tokens.padding.small
                                text: Assistant.selectedText.length > 0
                                    ? Assistant.selectedText
                                    : (Assistant.listenClipboard
                                        ? qsTr("No text captured. Highlight text anywhere and press Super+H.")
                                        : qsTr("Clipboard listening paused. Click clipboard icon to resume."))
                                font: {
                                    const words = Assistant.selectedText.trim().split(/\s+/).length;
                                    if (words === 1 && Assistant.selectedText.trim().length > 0)
                                        return Tokens.font.title.small;
                                    if (snippetCard.isCodeSnippet)
                                        return Tokens.font.mono.builders.small.size(11).build();
                                    return Tokens.font.body.builders.small.size(11.5).build();
                                }
                                color: Assistant.selectedText.length > 0
                                    ? Colours.palette.m3onSurface
                                    : Colours.palette.m3outline
                                wrapMode: Text.Wrap
                                elide: Text.ElideNone
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
                    const items = [
                        { icon: "translate", text: qsTr("Translate"), value: "translate" },
                        { icon: "lightbulb",  text: qsTr("Explain"),   value: "explain" },
                        { icon: "notes",      text: qsTr("TL;DR"),     value: "tldr" },
                        { icon: "sync",       text: qsTr("Rephrase"),  value: "rephrase" },
                        { icon: "format_list_bulleted", text: qsTr("Examples"), value: "examples" }
                    ]
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
                id: resultContainer
                Layout.fillWidth: true
                implicitHeight: {
                    if (Assistant.isLoading || Assistant.isStreaming) return 360
                    if (Assistant.errorMessage.length > 0 || !Assistant.hasApiKey) return 240
                    if (Assistant.resultText.length === 0) return 180
                    // Dynamically fit content size, capped between 200px and 540px for a taller, comfortable reading area
                    const contentH = Math.max(contentText.contentHeight, contentText.implicitHeight) + Tokens.padding.medium * 2
                    return Math.max(200, Math.min(540, contentH))
                }
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
                    visible: Assistant.isLoading
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
                    visible: !Assistant.isLoading && (Assistant.errorMessage.length > 0 || !Assistant.hasApiKey)
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
                    visible: !Assistant.isLoading && Assistant.errorMessage.length === 0 && Assistant.hasApiKey && Assistant.resultText.length === 0
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

                // 4D. Result Markdown Output (Selectable & Copyable)
                Flickable {
                    id: flick
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    visible: !Assistant.isLoading && Assistant.errorMessage.length === 0 && Assistant.hasApiKey && Assistant.resultText.length > 0
                    contentHeight: contentText.contentHeight
                    clip: true

                    onContentHeightChanged: {
                        if (Assistant.isStreaming) {
                            flick.contentY = Math.max(0, flick.contentHeight - flick.height)
                        }
                    }

                    StyledScrollBar.vertical: StyledScrollBar {
                        flickable: flick
                    }

                    TextEdit {
                        id: contentText
                        width: flick.width - Tokens.padding.small
                        text: Assistant.resultText
                        readOnly: true
                        selectByMouse: true
                        selectByKeyboard: true
                        mouseSelectionMode: TextEdit.SelectCharacters
                        cursorVisible: false
                        textFormat: Assistant.isStreaming ? TextEdit.PlainText : TextEdit.MarkdownText
                        wrapMode: TextEdit.Wrap
                        font: Tokens.font.body.builders.small.size(11).build()
                        color: Colours.palette.m3onSurface
                        selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
                        selectedTextColor: Colours.palette.m3onSurface
                        renderType: TextEdit.NativeRendering

                        // Show Arabic way (RTL) ONLY when translating and result is Arabic; all other text is strictly LTR
                        readonly property bool isArabicResult: {
                            if (Assistant.activeAction !== "translate" || !text) return false
                            const arabicMatches = text.match(/[\u0600-\u06FF]/g)
                            const latinMatches = text.match(/[A-Za-z]/g)
                            const arabicCount = arabicMatches ? arabicMatches.length : 0
                            const latinCount = latinMatches ? latinMatches.length : 0
                            return arabicCount > latinCount
                        }

                        horizontalAlignment: isArabicResult ? TextEdit.AlignRight : TextEdit.AlignLeft

                        onSelectedTextChanged: {
                            if (selectedText && selectedText.trim().length > 0) {
                                Assistant.lastSeenClipboard = selectedText.trim()
                            }
                        }
                    }
                }
            }

            // ── 5. Footer / Custom Question Bar ───────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                // Context Chip Row (above input row)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

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
                                        if (root.askBoundToSelection) {
                                            return "📌 Selection"
                                        }
                                        if (!Assistant.hasThread || Assistant.inputMode === "standalone") {
                                            return "🌐 Standalone"
                                        }
                                        if (Assistant.inputMode === "followup") {
                                            return "↩ Follow-up"
                                        }
                                        return "↩ Auto (Follow-up)"
                                    }
                                    font: Tokens.font.label.small
                                    color: {
                                        if (root.askBoundToSelection) {
                                            return Colours.palette.m3primary
                                        }
                                        if (!Assistant.hasThread || Assistant.inputMode === "standalone") {
                                            return Colours.palette.m3outline
                                        }
                                        if (Assistant.inputMode === "followup") {
                                            return Colours.palette.m3primary
                                        }
                                        return Colours.palette.m3secondary
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

                    Item { Layout.fillWidth: true }
                }

                // Input Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                StyledTextField {
                    id: customQuestionInput
                    Layout.fillWidth: true
                    placeholderText: root.askBoundToSelection ? qsTr("Ask about this selection...") : qsTr("Ask a custom question...")
                    placeholderFloats: false

                    Keys.onReturnPressed: {
                        if (!Assistant.isGenerating && text.trim().length > 0) {
                            if (root.askBoundToSelection) {
                                Assistant.clearThread()
                            }
                            Assistant.runAction("ask", text.trim())
                            text = ""
                            root.askBoundToSelection = false
                        }
                    }
                }

                IconButton {
                    type: IconButton.Filled
                    icon: "send"
                    font: Tokens.font.icon.small
                    implicitWidth: 36
                    implicitHeight: 36
                    enabled: !Assistant.isGenerating && customQuestionInput.text.trim().length > 0
                    opacity: enabled ? 1.0 : 0.4
                    onClicked: {
                        if (!Assistant.isGenerating && customQuestionInput.text.trim().length > 0) {
                            if (root.askBoundToSelection) {
                                Assistant.clearThread()
                            }
                            Assistant.runAction("ask", customQuestionInput.text.trim())
                            customQuestionInput.text = ""
                            root.askBoundToSelection = false
                        }
                    }
                }

                // Arabic / Text TTS Audio Pronunciation Button
                IconButton {
                    id: ttsBtn
                    type: IconButton.Tonal
                    icon: Assistant.isSpeaking ? "volume_off" : "volume_up"
                    font: Tokens.font.icon.small
                    implicitWidth: 36
                    implicitHeight: 36
                    enabled: Assistant.resultText.length > 0
                    opacity: enabled ? 1.0 : 0.4
                    onClicked: Assistant.speakText(Assistant.resultText)
                }

                IconButton {
                    id: copyBtn
                    type: IconButton.Filled
                    property bool copied: false
                    icon: copied ? "check" : "content_copy"
                    font: Tokens.font.icon.small
                    implicitWidth: 36
                    implicitHeight: 36
                    enabled: Assistant.resultText.length > 0 || (contentText.selectedText && contentText.selectedText.length > 0)
                    opacity: enabled ? 1.0 : 0.4
                    onClicked: {
                        if (contentText.selectedText && contentText.selectedText.length > 0) {
                            Quickshell.clipboardText = contentText.selectedText
                            Assistant.lastSeenClipboard = contentText.selectedText.trim()
                        } else if (Assistant.resultText.length > 0) {
                            Quickshell.clipboardText = Assistant.resultText
                            Assistant.lastSeenClipboard = Assistant.resultText.trim()
                        }
                        copied = true
                        resetCopyTimer.restart()
                    }

                    Timer {
                        id: resetCopyTimer
                        interval: 1800
                        onTriggered: copyBtn.copied = false
                    }
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
            onBackRequested: root.currentView = "assistant"
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
