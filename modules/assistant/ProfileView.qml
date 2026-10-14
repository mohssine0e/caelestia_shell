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

    focus: true

    signal backRequested()
    signal closeRequested()

    property int activeTab: 0 // 0: AI Engine & Keys, 1: Developer Dossier

    // Draft properties synced with Assistant service
    property string editOs: ""
    property string editLanguages: ""
    property string editStyle: ""
    property string editBilingual: ""
    property string editNotes: ""
    property string editGeminiKey: ""
    property string editGroqKey: ""
    property string editProvider: "gemini"
    property int editMaxChars: 12000
    property bool showGeminiKey: false
    property bool showGroqKey: false

    property bool savedFeedback: false

    function syncFromService() {
        const p = Assistant.profile || Assistant.defaultProfile || {}
        root.editOs = p.os || ""
        if (Array.isArray(p.languages)) {
            root.editLanguages = p.languages.join(", ")
        } else {
            root.editLanguages = p.languages || ""
        }
        root.editStyle = p.style_preference || ""
        root.editBilingual = p.bilingual || ""
        root.editNotes = p.custom_notes || ""
        root.editGeminiKey = Assistant.geminiKey || ""
        root.editGroqKey = Assistant.groqKey || ""
        root.editProvider = (Assistant.preferredProvider || "gemini").toLowerCase()
        root.editMaxChars = Assistant.maxChars || 12000
    }

    Component.onCompleted: syncFromService()

    Connections {
        target: Assistant
        function onProfileChanged() {
            root.syncFromService()
        }
    }

    Timer {
        id: feedbackTimer
        interval: 2200
        onTriggered: root.savedFeedback = false
    }

    function triggerSavedFeedback() {
        root.savedFeedback = true
        feedbackTimer.restart()
    }

    Keys.onEscapePressed: event => {
        root.backRequested()
        event.accepted = true
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.medium

        // ── 1. Top Header ─────────────────────────────────────────────
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
                text: "settings"
                fontStyle: Tokens.font.icon.medium
                color: Colours.palette.m3primary
            }

            StyledText {
                text: qsTr("Settings & Profile")
                font: Tokens.font.title.small
                color: Colours.palette.m3onSurface
            }

            Item { Layout.fillWidth: true }

            // Live Saved Confirmation Pill
            StyledRect {
                visible: root.savedFeedback
                implicitWidth: savedRow.implicitWidth + 16
                implicitHeight: 26
                radius: Tokens.rounding.full
                color: Qt.alpha(Colours.palette.m3primary, 0.15)
                border.width: 1
                border.color: Colours.palette.m3primary

                RowLayout {
                    id: savedRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialIcon {
                        text: "check"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3primary
                    }

                    StyledText {
                        text: qsTr("Saved")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3primary
                    }
                }
            }

            IconButton {
                type: IconButton.Text
                icon: "close"
                font: Tokens.font.icon.small
                implicitWidth: 32
                implicitHeight: 32
                onClicked: root.closeRequested()
            }
        }

        // ── 2. Segmented Navigation Tabs ──────────────────────────────
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 38
            radius: Tokens.rounding.full
            color: Colours.palette.m3surfaceContainerHigh
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.25)

            RowLayout {
                anchors.fill: parent
                anchors.margins: 3
                spacing: 4

                // Tab 0: AI Engine & Keys
                StyledRect {
                    id: tab0
                    readonly property bool isSelected: root.activeTab === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Tokens.rounding.full
                    color: isSelected ? Colours.palette.m3primary : "transparent"

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialIcon {
                            text: "tune"
                            fontStyle: Tokens.font.icon.small
                            color: tab0.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                        }

                        StyledText {
                            text: qsTr("AI Engine & Keys")
                            font: Tokens.font.label.medium
                            color: tab0.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                        }
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activeTab = 0
                    }
                }

                // Tab 1: Developer Dossier
                StyledRect {
                    id: tab1
                    readonly property bool isSelected: root.activeTab === 1
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Tokens.rounding.full
                    color: isSelected ? Colours.palette.m3primary : "transparent"

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialIcon {
                            text: "badge"
                            fontStyle: Tokens.font.icon.small
                            color: tab1.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                        }

                        StyledText {
                            text: qsTr("Developer Dossier")
                            font: Tokens.font.label.medium
                            color: tab1.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                        }
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activeTab = 1
                    }
                }
            }
        }

        // ── 3. Main Content Scrollable Area ───────────────────────────
        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentHeight: root.activeTab === 0 ? engineLayout.implicitHeight + 12 : dossierLayout.implicitHeight + 12

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: flick
            }

            // ──────────────────────────────────────────────────────────
            // TAB 0: AI Engine & Keys
            // ──────────────────────────────────────────────────────────
            ColumnLayout {
                id: engineLayout
                visible: root.activeTab === 0
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: Tokens.padding.small
                spacing: 14

                // Section 1: Default Model Engine Segmented Bar
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialIcon {
                            text: "auto_awesome"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3primary
                        }

                        StyledText {
                            text: qsTr("PRIMARY LLM ENGINE")
                            font: Tokens.font.label.medium
                            color: Colours.palette.m3primary
                        }
                    }

                    // Segmented Button Bar
                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3surfaceContainerHigh
                        border.width: 1
                        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.25)

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 4

                            // Gemini Option
                            StyledRect {
                                id: segGemini
                                readonly property bool isSelected: root.editProvider === "gemini"
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Tokens.rounding.full
                                color: isSelected ? Colours.palette.m3primary : "transparent"

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 8

                                    MaterialIcon {
                                        text: "smart_toy"
                                        fontStyle: Tokens.font.icon.small
                                        color: segGemini.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                    }

                                    StyledText {
                                        text: qsTr("Google Gemini Flash")
                                        font: Tokens.font.label.large
                                        color: segGemini.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                    }
                                }

                                StateLayer {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.editProvider = "gemini"
                                        Assistant.saveSettings(root.editGeminiKey, root.editGroqKey, "gemini", root.editMaxChars)
                                        root.triggerSavedFeedback()
                                    }
                                }
                            }

                            // Groq Option
                            StyledRect {
                                id: segGroq
                                readonly property bool isSelected: root.editProvider === "groq"
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Tokens.rounding.full
                                color: isSelected ? Colours.palette.m3primary : "transparent"

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 8

                                    MaterialIcon {
                                        text: "bolt"
                                        fontStyle: Tokens.font.icon.small
                                        color: segGroq.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                    }

                                    StyledText {
                                        text: qsTr("Groq Llama 3.3")
                                        font: Tokens.font.label.large
                                        color: segGroq.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                    }
                                }

                                StateLayer {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.editProvider = "groq"
                                        Assistant.saveSettings(root.editGeminiKey, root.editGroqKey, "groq", root.editMaxChars)
                                        root.triggerSavedFeedback()
                                    }
                                }
                            }
                        }
                    }

                    // Dynamic Subtitle Caption
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.editProvider === "gemini"
                            ? qsTr("Gemini 2.0 / 2.5 Flash • High context window & multimodal reasoning")
                            : qsTr("Groq Llama 3.3 70B • Ultra-low latency & fast streaming")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                    }
                }

                // Section 2: Input Truncation Limit Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: qsTr("Input Truncation Ceiling")
                            font: Tokens.font.label.large
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            text: qsTr("Caps clipboard text sent to LLM")
                            font: Tokens.font.label.small
                            color: Colours.palette.m3outline
                        }
                    }

                    // Segmented Chips
                    RowLayout {
                        spacing: 6

                        Repeater {
                            model: [
                                { label: "12k",  val: 12000 },
                                { label: "50k",  val: 50000 },
                                { label: "100k", val: 100000 },
                                { label: "200k", val: 200000 }
                            ]

                            delegate: StyledRect {
                                id: chipItem
                                required property var modelData
                                readonly property bool isSelected: root.editMaxChars === chipItem.modelData.val
                                implicitWidth: pillLabel.implicitWidth + 20
                                implicitHeight: 30
                                radius: Tokens.rounding.full
                                color: isSelected ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh
                                border.width: isSelected ? 0 : 1
                                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.25)

                                StyledText {
                                    id: pillLabel
                                    anchors.centerIn: parent
                                    text: chipItem.modelData.label
                                    font: Tokens.font.label.medium
                                    color: chipItem.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                }

                                StateLayer {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.editMaxChars = chipItem.modelData.val
                                        Assistant.saveSettings(root.editGeminiKey, root.editGroqKey, root.editProvider, chipItem.modelData.val)
                                        root.triggerSavedFeedback()
                                    }
                                }
                            }
                        }
                    }
                }

                // Subtle Divider
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Qt.alpha(Colours.palette.m3outlineVariant, 0.25)
                }

                // Section 3: Authentication Keys
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialIcon {
                            text: "vpn_key"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3primary
                        }

                        StyledText {
                            text: qsTr("AUTHENTICATION KEYS")
                            font: Tokens.font.label.medium
                            color: Colours.palette.m3primary
                        }
                    }

                    // Google Gemini Key
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            StyledText {
                                text: qsTr("Google Gemini API Key")
                                font: Tokens.font.label.medium
                                color: Colours.palette.m3onSurface
                            }

                            Item { Layout.fillWidth: true }

                            StyledRect {
                                implicitWidth: gemStatusText.implicitWidth + 14
                                implicitHeight: 20
                                radius: Tokens.rounding.full
                                color: root.editGeminiKey
                                    ? Qt.alpha(Colours.palette.m3primary, 0.15)
                                    : Qt.alpha(Colours.palette.m3error, 0.15)

                                StyledText {
                                    id: gemStatusText
                                    anchors.centerIn: parent
                                    text: root.editGeminiKey ? qsTr("Configured ✓") : qsTr("Missing")
                                    font: Tokens.font.label.small
                                    color: root.editGeminiKey ? Colours.palette.m3primary : Colours.palette.m3error
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            StyledTextField {
                                Layout.fillWidth: true
                                text: root.editGeminiKey
                                placeholderText: qsTr("Google AI Studio key (AIzaSy...)")
                                placeholderFloats: false
                                verticalPadding: Tokens.padding.medium
                                font: Tokens.font.body.small
                                echoMode: root.showGeminiKey ? TextInput.Normal : TextInput.Password
                                onTextChanged: root.editGeminiKey = text
                            }

                            IconButton {
                                type: IconButton.Tonal
                                icon: root.showGeminiKey ? "visibility_off" : "visibility"
                                font: Tokens.font.icon.small
                                implicitWidth: 38
                                implicitHeight: 38
                                onClicked: root.showGeminiKey = !root.showGeminiKey
                            }
                        }
                    }

                    // Groq Key
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            StyledText {
                                text: qsTr("Groq API Key (Optional)")
                                font: Tokens.font.label.medium
                                color: Colours.palette.m3onSurface
                            }

                            Item { Layout.fillWidth: true }

                            StyledRect {
                                implicitWidth: groqStatusText.implicitWidth + 14
                                implicitHeight: 20
                                radius: Tokens.rounding.full
                                color: root.editGroqKey
                                    ? Qt.alpha(Colours.palette.m3primary, 0.15)
                                    : Colours.palette.m3surfaceContainerHighest

                                StyledText {
                                    id: groqStatusText
                                    anchors.centerIn: parent
                                    text: root.editGroqKey ? qsTr("Configured ✓") : qsTr("Optional")
                                    font: Tokens.font.label.small
                                    color: root.editGroqKey ? Colours.palette.m3primary : Colours.palette.m3outline
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            StyledTextField {
                                Layout.fillWidth: true
                                text: root.editGroqKey
                                placeholderText: qsTr("Groq Console key (gsk_...)")
                                placeholderFloats: false
                                verticalPadding: Tokens.padding.medium
                                font: Tokens.font.body.small
                                echoMode: root.showGroqKey ? TextInput.Normal : TextInput.Password
                                onTextChanged: root.editGroqKey = text
                            }

                            IconButton {
                                type: IconButton.Tonal
                                icon: root.showGroqKey ? "visibility_off" : "visibility"
                                font: Tokens.font.icon.small
                                implicitWidth: 38
                                implicitHeight: 38
                                onClicked: root.showGroqKey = !root.showGroqKey
                            }
                        }
                    }

                    // Save Row
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 8

                        MaterialIcon {
                            text: "lock"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3outline
                        }

                        StyledText {
                            text: qsTr("Stored in ~/.config/caelestia/assistant.json")
                            font: Tokens.font.label.small
                            color: Colours.palette.m3outline
                        }

                        Item { Layout.fillWidth: true }

                        IconTextButton {
                            type: IconTextButton.Filled
                            icon: "check"
                            text: qsTr("Save Keys")
                            font: Tokens.font.label.medium
                            onClicked: {
                                Assistant.saveSettings(
                                    root.editGeminiKey,
                                    root.editGroqKey,
                                    root.editProvider,
                                    root.editMaxChars
                                )
                                root.triggerSavedFeedback()
                            }
                        }
                    }
                }
            }

            // ──────────────────────────────────────────────────────────
            // TAB 1: Developer Dossier
            // ──────────────────────────────────────────────────────────
            ColumnLayout {
                id: dossierLayout
                visible: root.activeTab === 1
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: Tokens.padding.small
                spacing: 14

                // AI Proposed Profile Banner (if present)
                StyledRect {
                    Layout.fillWidth: true
                    visible: Assistant.proposedProfile !== null
                    implicitHeight: propCol.implicitHeight + 20
                    radius: Tokens.rounding.small
                    color: Qt.alpha(Colours.palette.m3primary, 0.12)
                    border.width: 1
                    border.color: Colours.palette.m3primary

                    ColumnLayout {
                        id: propCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            MaterialIcon {
                                text: "auto_awesome"
                                fontStyle: Tokens.font.icon.small
                                color: Colours.palette.m3primary
                            }

                            StyledText {
                                text: qsTr("AI Proposed Profile Updates")
                                font: Tokens.font.label.large
                                color: Colours.palette.m3primary
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: {
                                if (!Assistant.proposedProfile) return ""
                                const p = Assistant.proposedProfile
                                const parts = []
                                if (p.os) parts.push(`OS: ${p.os}`)
                                if (p.languages) parts.push(`Languages: ${Array.isArray(p.languages) ? p.languages.join(", ") : p.languages}`)
                                if (p.style_preference) parts.push(`Style: ${p.style_preference}`)
                                if (p.bilingual) parts.push(`Language Directives: ${p.bilingual}`)
                                return parts.join("\n")
                            }
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurface
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Item { Layout.fillWidth: true }

                            IconTextButton {
                                type: IconTextButton.Tonal
                                icon: "close"
                                text: qsTr("Discard")
                                font: Tokens.font.label.small
                                onClicked: Assistant.discardProposedProfile()
                            }

                            IconTextButton {
                                type: IconTextButton.Filled
                                icon: "check"
                                text: qsTr("Accept Changes")
                                font: Tokens.font.label.small
                                onClicked: {
                                    Assistant.acceptProposedProfile()
                                    root.syncFromService()
                                    root.triggerSavedFeedback()
                                }
                            }
                        }
                    }
                }

                // Section 1: Developer Environment
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialIcon {
                            text: "terminal"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3primary
                        }

                        StyledText {
                            text: qsTr("DEVELOPER ENVIRONMENT")
                            font: Tokens.font.label.medium
                            color: Colours.palette.m3primary
                        }
                    }

                    // Target OS Field
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        StyledText {
                            text: qsTr("Operating System & Shell")
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        StyledTextField {
                            Layout.fillWidth: true
                            text: root.editOs
                            placeholderText: qsTr("e.g. Linux (Hyprland, Arch)")
                            placeholderFloats: false
                            verticalPadding: Tokens.padding.medium
                            font: Tokens.font.body.small
                            onTextChanged: root.editOs = text
                        }
                    }

                    // Languages & Frameworks Field
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true

                            StyledText {
                                text: qsTr("Languages & Frameworks")
                                font: Tokens.font.label.small
                                color: Colours.palette.m3onSurfaceVariant
                            }

                            Item { Layout.fillWidth: true }

                            StyledText {
                                text: qsTr("comma separated")
                                font: Tokens.font.label.small
                                color: Colours.palette.m3outline
                            }
                        }

                        StyledTextField {
                            Layout.fillWidth: true
                            text: root.editLanguages
                            placeholderText: qsTr("e.g. Python, QML / Qt, Bash, Rust")
                            placeholderFloats: false
                            verticalPadding: Tokens.padding.medium
                            font: Tokens.font.body.small
                            onTextChanged: root.editLanguages = text
                        }

                        // Live chips preview
                        Flow {
                            Layout.fillWidth: true
                            visible: root.editLanguages.trim().length > 0
                            spacing: 6

                            Repeater {
                                model: root.editLanguages.split(",").map(s => s.trim()).filter(s => s.length > 0)

                                delegate: StyledRect {
                                    required property string modelData
                                    implicitWidth: tagText.implicitWidth + 14
                                    implicitHeight: 22
                                    radius: Tokens.rounding.full
                                    color: Qt.alpha(Colours.palette.m3primary, 0.12)

                                    StyledText {
                                        id: tagText
                                        anchors.centerIn: parent
                                        text: parent.modelData
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3primary
                                    }
                                }
                            }
                        }
                    }
                }

                // Subtle Divider
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Qt.alpha(Colours.palette.m3outlineVariant, 0.25)
                }

                // Section 2: AI Directives & Style
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialIcon {
                            text: "lightbulb"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3primary
                        }

                        StyledText {
                            text: qsTr("RESPONSE DIRECTIVES")
                            font: Tokens.font.label.medium
                            color: Colours.palette.m3primary
                        }
                    }

                    // Coding Style Field
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        StyledText {
                            text: qsTr("Coding Style Preference")
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        StyledTextField {
                            Layout.fillWidth: true
                            text: root.editStyle
                            placeholderText: qsTr("e.g. Concise, standard library first, minimal dependencies")
                            placeholderFloats: false
                            verticalPadding: Tokens.padding.medium
                            font: Tokens.font.body.small
                            onTextChanged: root.editStyle = text
                        }
                    }

                    // Language Directives Field
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        StyledText {
                            text: qsTr("Language & Explanation Directives")
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        StyledTextField {
                            Layout.fillWidth: true
                            text: root.editBilingual
                            placeholderText: qsTr("e.g. Pure English explanations with Arabic translation in parentheses ()")
                            placeholderFloats: false
                            verticalPadding: Tokens.padding.medium
                            font: Tokens.font.body.small
                            onTextChanged: root.editBilingual = text
                        }
                    }

                    // Custom Notes Field
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        StyledText {
                            text: qsTr("Custom Directives & Guidelines")
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        StyledTextField {
                            Layout.fillWidth: true
                            text: root.editNotes
                            placeholderText: qsTr("e.g. Prefer Wayland and modern CLI tools")
                            placeholderFloats: false
                            verticalPadding: Tokens.padding.medium
                            font: Tokens.font.body.small
                            onTextChanged: root.editNotes = text
                        }
                    }

                    // Actions Row
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: Tokens.spacing.small

                        IconTextButton {
                            type: IconTextButton.Tonal
                            icon: "restart_alt"
                            text: qsTr("Reset Defaults")
                            font: Tokens.font.label.medium
                            onClicked: {
                                Assistant.resetProfile()
                                root.syncFromService()
                                root.triggerSavedFeedback()
                            }
                        }

                        Item { Layout.fillWidth: true }

                        IconTextButton {
                            type: IconTextButton.Filled
                            icon: "check"
                            text: qsTr("Save Dossier")
                            font: Tokens.font.label.medium
                            onClicked: {
                                const langs = root.editLanguages.split(",").map(s => s.trim()).filter(s => s.length > 0)
                                const updated = {
                                    "os": root.editOs.trim(),
                                    "languages": langs,
                                    "style_preference": root.editStyle.trim(),
                                    "bilingual": root.editBilingual.trim(),
                                    "custom_notes": root.editNotes.trim()
                                }
                                Assistant.saveProfile(updated)
                                root.triggerSavedFeedback()
                            }
                        }
                    }
                }
            }
        }
    }
}
