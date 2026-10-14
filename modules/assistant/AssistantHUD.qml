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
        root.closeRequested()
        event.accepted = true
    }

    Keys.onPressed: event => {
        // If a text input inside is active, don't hijack its typing
        if (customQuestionInput.activeFocus || geminiInput.activeFocus || groqInput.activeFocus) {
            event.accepted = false
            return
        }

        // Quick action switching with 1-5
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

        // 'c' or Ctrl+C to copy output
        if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier || !event.modifiers)) {
            if (Assistant.resultText.length > 0) {
                Quickshell.clipboardText = Assistant.resultText
                event.accepted = true
                return
            }
        }

        // '/' to focus question input
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

            // ── Header Row ───────────────────────────────────────────
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

                StyledText {
                    visible: Assistant.providerUsed.length > 0
                    text: Assistant.providerUsed
                    font: Tokens.font.label.small
                    color: Colours.palette.m3primary
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

            // ── Selected Text Preview ─────────────────────────────────
            StyledRect {
                Layout.fillWidth: true
                implicitHeight: Math.min(70, textSnippet.implicitHeight + Tokens.padding.small * 2)
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh

                Flickable {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    contentHeight: textSnippet.implicitHeight
                    clip: true

                    StyledText {
                        id: textSnippet
                        width: parent.width
                        text: Assistant.selectedText.length > 0
                            ? Assistant.selectedText
                            : qsTr("No text captured. Highlight text anywhere and press Super+H.")
                        font: Tokens.font.body.small
                        color: Assistant.selectedText.length > 0
                            ? Colours.palette.m3onSurfaceVariant
                            : Colours.palette.m3outline
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                    }
                }
            }

            // ── Action Chips Row ──────────────────────────────────────
            Flow {
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
                        required property var modelData

                        readonly property bool isSelected: Assistant.activeAction === modelData.id
                        implicitWidth: chipRow.implicitWidth + Tokens.padding.small * 2
                        implicitHeight: 28
                        radius: Tokens.rounding.full
                        color: isSelected
                            ? Colours.palette.m3primary
                            : Colours.palette.m3surfaceContainerHighest

                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialIcon {
                                text: modelData.icon
                                fontStyle: Tokens.font.icon.small
                                color: isSelected
                                    ? Colours.palette.m3onPrimary
                                    : Colours.palette.m3onSurfaceVariant
                            }

                            StyledText {
                                text: `${modelData.key}. ${modelData.label}`
                                font: Tokens.font.label.small
                                color: isSelected
                                    ? Colours.palette.m3onPrimary
                                    : Colours.palette.m3onSurfaceVariant
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Assistant.runAction(modelData.id)
                        }
                    }
                }
            }

            // ── Result Content View ───────────────────────────────────
            StyledRect {
                Layout.fillWidth: true
                implicitHeight: 340
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerLowest
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.3)

                // Loading Spinner / Indicator
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: Assistant.isLoading
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "progress_activity"
                        fontStyle: Tokens.font.icon.large
                        color: Colours.palette.m3primary

                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 1200
                            loops: Animation.Infinite
                            running: Assistant.isLoading
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Thinking...")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }

                // Error / Missing API Key View
                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - Tokens.padding.medium * 2
                    visible: !Assistant.isLoading && (Assistant.errorMessage.length > 0 || !Assistant.hasApiKey)
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: !Assistant.hasApiKey ? "key" : "warning"
                        fontStyle: Tokens.font.icon.large
                        color: Colours.palette.m3error
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: Assistant.errorMessage
                        font: Tokens.font.body.small
                        color: Colours.palette.m3error
                    }

                    // Key setup mini inputs
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !Assistant.hasApiKey || Assistant.errorMessage.length > 0
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
                                Assistant.runAction(Assistant.activeAction)
                            }
                        }
                    }
                }

                // Idle / Waiting for user choice
                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - Tokens.padding.large * 2
                    visible: !Assistant.isLoading && Assistant.errorMessage.length === 0 && Assistant.hasApiKey && Assistant.resultText.length === 0
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "touch_app"
                        fontStyle: Tokens.font.icon.large
                        color: Colours.palette.m3outline
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: qsTr("Select an action above (1-5) or ask a question below")
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3outline
                        wrapMode: Text.Wrap
                    }
                }

                // Result Text
                Flickable {
                    id: flick
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    visible: !Assistant.isLoading && Assistant.errorMessage.length === 0 && Assistant.hasApiKey && Assistant.resultText.length > 0
                    contentHeight: contentText.implicitHeight
                    clip: true

                    StyledScrollBar.vertical: StyledScrollBar {
                        flickable: flick
                    }

                    StyledText {
                        id: contentText
                        width: flick.width - Tokens.padding.small
                        text: Assistant.resultText
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                        wrapMode: Text.Wrap
                        textFormat: Text.MarkdownText

                        // Detect Arabic script and automatically align right
                        horizontalAlignment: {
                            const isArabic = /[\u0600-\u06FF]/.test(text)
                            return isArabic ? Text.AlignRight : Text.AlignLeft
                        }
                    }
                }
            }

            // ── Footer / Custom Question Bar ──────────────────────────
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
                    type: IconButton.Tonal
                    property bool copied: false
                    icon: copied ? "check" : "content_copy"
                    font: Tokens.font.icon.small
                    implicitWidth: 36
                    implicitHeight: 36
                    visible: Assistant.resultText.length > 0
                    onClicked: {
                        Quickshell.clipboardText = Assistant.resultText
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
