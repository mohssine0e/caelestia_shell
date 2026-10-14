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

    focus: true
    width: 540
    implicitWidth: 540
    implicitHeight: mainCard.implicitHeight

    signal closeRequested()

    Component.onCompleted: Qt.callLater(() => root.forceActiveFocus())

    Keys.onEscapePressed: event => {
        if (customQuestionInput.activeFocus) {
            if (customQuestionInput.text.length > 0) {
                customQuestionInput.text = ""
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
            Assistant.runAction(actionMap[event.key])
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
            if (contentText.selectedText && contentText.selectedText.length > 0) {
                Quickshell.clipboardText = contentText.selectedText
                event.accepted = true
                return
            }
            if (Assistant.resultText.length > 0) {
                Quickshell.clipboardText = Assistant.resultText
                event.accepted = true
                return
            }
        }

        if (event.key === Qt.Key_Slash) {
            customQuestionInput.forceActiveFocus()
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

        implicitHeight: cardLayout.implicitHeight + Tokens.padding.medium * 2

        ColumnLayout {
            id: cardLayout

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.small

            // ── 1. Header Row & Provider Badge ────────────────────────
            RowLayout {
                Layout.fillWidth: true
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

                // Provider Badge with Live Dot & Latency
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

            // ── 2. Snippet Preview ────────────────────────────────────
            StyledRect {
                id: snippetCard
                Layout.fillWidth: true
                implicitHeight: Math.min(85, textSnippet.implicitHeight + Tokens.padding.small * 2)
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh

                // Snippet Actions: Truncated badge, Pause/Listen toggle, and Clear text button
                RowLayout {
                    id: snippetActions
                    z: 3
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 4
                    spacing: 4

                    // Truncated indicator badge
                    StyledRect {
                        visible: Assistant.isTruncated
                        radius: Tokens.rounding.full
                        color: Qt.alpha(Colours.palette.m3error, 0.2)
                        implicitWidth: truncText.implicitWidth + 8
                        implicitHeight: 22

                        StyledText {
                            id: truncText
                            anchors.centerIn: parent
                            text: qsTr("Truncated (4k)")
                            font: Tokens.font.label.small
                            color: Colours.palette.m3error
                        }
                    }

                    // Toggle clipboard listening
                    IconButton {
                        type: Assistant.listenClipboard ? IconButton.Filled : IconButton.Tonal
                        icon: Assistant.listenClipboard ? "content_paste" : "content_paste_off"
                        font: Tokens.font.icon.small
                        implicitWidth: 26
                        implicitHeight: 26
                        onClicked: Assistant.listenClipboard = !Assistant.listenClipboard
                    }

                    // Free / Clear copied text
                    IconButton {
                        type: IconButton.Tonal
                        icon: "clear"
                        visible: Assistant.selectedText.length > 0
                        font: Tokens.font.icon.small
                        implicitWidth: 26
                        implicitHeight: 26
                        onClicked: Assistant.clearSelection()
                    }
                }

                Flickable {
                    id: snippetFlick
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    anchors.rightMargin: snippetActions.width + Tokens.padding.small
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
                            const words = Assistant.selectedText.trim().split(/\s+/).length
                            return (words === 1 && Assistant.selectedText.trim().length > 0)
                                ? Tokens.font.title.small
                                : Tokens.font.body.small
                        }
                        color: Assistant.selectedText.length > 0
                            ? Colours.palette.m3onSurface
                            : Colours.palette.m3outline
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                    }
                }
            }

            // ── 3. Action Chips Row with StateLayer Hover Glow ────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                Repeater {
                    model: [
                        { id: "translate", key: "1", icon: "translate", label: qsTr("Translate") },
                        { id: "explain",   key: "2", icon: "lightbulb", label: qsTr("Explain") },
                        { id: "tldr",      key: "3", icon: "notes",     label: qsTr("TL;DR") },
                        { id: "rephrase",  key: "4", icon: "sync",      label: qsTr("Rephrase") },
                        { id: "examples",  key: "5", icon: "format_list_bulleted", label: qsTr("Examples") }
                    ]

                    delegate: StyledRect {
                        id: chip
                        required property var modelData

                        readonly property bool isSelected: Assistant.activeAction === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: Tokens.rounding.full
                        color: isSelected
                            ? Colours.palette.m3primary
                            : Colours.palette.m3surfaceContainerHighest

                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialIcon {
                                text: chip.modelData.icon
                                fontStyle: Tokens.font.icon.small
                                color: chip.isSelected
                                    ? Colours.palette.m3onPrimary
                                    : Colours.palette.m3onSurfaceVariant
                            }

                            StyledText {
                                text: chip.modelData.label
                                font: Tokens.font.label.small
                                color: chip.isSelected
                                    ? Colours.palette.m3onPrimary
                                    : Colours.palette.m3onSurfaceVariant
                            }
                        }

                        StateLayer {
                            id: stateLayer
                            anchors.fill: parent
                            radius: chip.radius
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Assistant.runAction(chip.modelData.id)
                        }
                    }
                }
            }

            // ── 4. Main Result View / Shimmer Skeleton ────────────────
            StyledRect {
                id: resultContainer
                Layout.fillWidth: true
                implicitHeight: {
                    if (Assistant.isLoading) return 220
                    if (Assistant.errorMessage.length > 0 || !Assistant.hasApiKey) return 220
                    if (Assistant.resultText.length === 0) return 160
                    // Dynamically fit content size, capped between 200px and 420px for a taller, comfortable reading area
                    const contentH = Math.max(contentText.contentHeight, contentText.implicitHeight) + Tokens.padding.medium * 2
                    return Math.max(200, Math.min(420, contentH))
                }
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerLowest
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.3)

                Behavior on implicitHeight {
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

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !Assistant.hasApiKey || Assistant.errorType === "auth"
                        spacing: Tokens.spacing.extraSmall

                        StyledTextField {
                            id: geminiInput
                            Layout.fillWidth: true
                            placeholderText: "Google Gemini API Key..."
                        }

                        StyledTextField {
                            id: groqInput
                            Layout.fillWidth: true
                            placeholderText: "Groq API Key (Optional)..."
                        }

                        TextButton {
                            Layout.alignment: Qt.AlignHCenter
                            text: qsTr("Save Keys")
                            onClicked: {
                                Assistant.saveKeys(geminiInput.text, groqInput.text)
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
                                { key: "1-5", label: qsTr("Actions") },
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
                        textFormat: TextEdit.MarkdownText
                        wrapMode: TextEdit.Wrap
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurface
                        selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
                        selectedTextColor: Colours.palette.m3onSurface
                        renderType: TextEdit.NativeRendering

                        // Detect Arabic script and automatically align right
                        horizontalAlignment: {
                            const isArabic = /[\u0600-\u06FF]/.test(text)
                            return isArabic ? TextEdit.AlignRight : TextEdit.AlignLeft
                        }
                    }
                }
            }

            // ── 5. Footer / Custom Question Bar ───────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledTextField {
                    id: customQuestionInput
                    Layout.fillWidth: true
                    placeholderText: qsTr("Ask a custom question...")

                    Keys.onReturnPressed: {
                        if (text.trim().length > 0) {
                            Assistant.runAction("ask", text.trim())
                            text = ""
                        }
                    }
                }

                IconButton {
                    type: IconButton.Filled
                    icon: "send"
                    font: Tokens.font.icon.small
                    implicitWidth: 36
                    implicitHeight: 36
                    onClicked: {
                        if (customQuestionInput.text.trim().length > 0) {
                            Assistant.runAction("ask", customQuestionInput.text.trim())
                            customQuestionInput.text = ""
                        }
                    }
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
                        } else if (Assistant.resultText.length > 0) {
                            Quickshell.clipboardText = Assistant.resultText
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
}
