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
import "root:services"

FocusScope {
    id: root

    focus: true

    signal backRequested()
    signal closeRequested()

    Keys.onEscapePressed: event => {
        if (root.isEditing) {
            root.isEditing = false
            root.syncFromProfile()
            event.accepted = true
            return
        }
        root.backRequested()
        event.accepted = true
    }

    property bool isEditing: false

    // Edit form draft fields
    property string editOs: ""
    property string editLanguages: ""
    property string editStyle: ""
    property string editBilingual: ""
    property string editNotes: ""

    function syncFromProfile() {
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
    }

    Component.onCompleted: syncFromProfile()

    Connections {
        target: Assistant
        function onProfileChanged() {
            if (!root.isEditing) {
                root.syncFromProfile()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.small

        // ── 1. Profile Header ─────────────────────────────────────────
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
                text: "badge"
                fontStyle: Tokens.font.icon.medium
                color: Colours.palette.m3primary
            }

            StyledText {
                text: qsTr("Developer Dossier")
                font: Tokens.font.title.small
                color: Colours.palette.m3onSurface
            }

            // Last Updated Pill
            StyledRect {
                implicitWidth: updatedLabel.implicitWidth + Tokens.padding.small * 2
                implicitHeight: 22
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceContainerHigh

                StyledText {
                    id: updatedLabel
                    anchors.centerIn: parent
                    text: {
                        const date = (Assistant.profile && Assistant.profile.last_updated) ? Assistant.profile.last_updated : qsTr("Default")
                        return qsTr("Updated: %1").arg(date)
                    }
                    font: Tokens.font.label.small
                    color: Colours.palette.m3outline
                }
            }

            Item { Layout.fillWidth: true }

            // Edit / Done toggle
            IconButton {
                type: root.isEditing ? IconButton.Filled : IconButton.Tonal
                icon: root.isEditing ? "check" : "edit"
                font: Tokens.font.icon.small
                implicitWidth: 32
                implicitHeight: 32
                onClicked: {
                    if (root.isEditing) {
                        // Save edits
                        const langs = root.editLanguages.split(",").map(s => s.trim()).filter(s => s.length > 0)
                        const updated = {
                            "os": root.editOs.trim(),
                            "languages": langs,
                            "style_preference": root.editStyle.trim(),
                            "bilingual": root.editBilingual.trim(),
                            "custom_notes": root.editNotes.trim()
                        }
                        Assistant.saveProfile(updated)
                        root.isEditing = false
                    } else {
                        root.syncFromProfile()
                        root.isEditing = true
                    }
                }
            }

            // Reset to defaults
            IconButton {
                type: IconButton.Text
                icon: "restart_alt"
                font: Tokens.font.icon.small
                implicitWidth: 30
                implicitHeight: 30
                onClicked: {
                    Assistant.resetProfile()
                    root.syncFromProfile()
                    root.isEditing = false
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

        // ── 2. AI Proposal Banner (If pending) ────────────────────────
        StyledRect {
            id: proposalBanner
            Layout.fillWidth: true
            visible: Assistant.proposedProfile !== null
            implicitHeight: proposalCol.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.small
            color: Qt.alpha(Colours.palette.m3primary, 0.12)
            border.width: 1
            border.color: Colours.palette.m3primary

            ColumnLayout {
                id: proposalCol
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    MaterialIcon {
                        text: "auto_awesome"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3primary
                    }

                    StyledText {
                        text: qsTr("Suggested Profile Updates (from recent queries)")
                        font: Tokens.font.label.large
                        color: Colours.palette.m3primary
                    }

                    Item { Layout.fillWidth: true }
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurface
                    text: {
                        const prop = Assistant.proposedProfile || {}
                        const parts = []
                        if (prop.os) parts.push(`• OS: ${prop.os}`)
                        if (prop.languages) {
                            const l = Array.isArray(prop.languages) ? prop.languages.join(", ") : prop.languages
                            parts.push(`• Languages: ${l}`)
                        }
                        if (prop.style_preference) parts.push(`• Style: ${prop.style_preference}`)
                        if (prop.bilingual) parts.push(`• Language: ${prop.bilingual}`)
                        if (prop.custom_notes) parts.push(`• Notes: ${prop.custom_notes}`)
                        return parts.join("\n")
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Item { Layout.fillWidth: true }

                    IconTextButton {
                        type: IconTextButton.Filled
                        icon: "check"
                        text: qsTr("Accept Changes")
                        font: Tokens.font.label.small
                        onClicked: Assistant.acceptProposedProfile()
                    }

                    IconTextButton {
                        type: IconTextButton.Tonal
                        icon: "close"
                        text: qsTr("Discard")
                        font: Tokens.font.label.small
                        onClicked: Assistant.discardProposedProfile()
                    }
                }
            }
        }

        // ── 3. Profile Content Container ──────────────────────────────
        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Tokens.rounding.small
            color: Colours.palette.m3surfaceContainerLowest
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.3)
            clip: true

            Flickable {
                id: profileFlick
                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                clip: true
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds
                contentHeight: (root.isEditing ? editLayout.implicitHeight : viewLayout.implicitHeight) + Tokens.padding.medium * 2

                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: profileFlick
                }

                // ── A. View Mode (Clean Cards) ────────────────────────
                ColumnLayout {
                    id: viewLayout
                    visible: !root.isEditing
                    width: profileFlick.width - Tokens.padding.small
                    spacing: Tokens.spacing.small

                    // Card: OS & Environment
                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: osRow.implicitHeight + Tokens.padding.medium * 2
                        radius: Tokens.rounding.small
                        color: Colours.palette.m3surfaceContainer

                        RowLayout {
                            id: osRow
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.medium

                            MaterialIcon {
                                text: "desktop_windows"
                                fontStyle: Tokens.font.icon.medium
                                color: Colours.palette.m3primary
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    text: qsTr("Target OS & Desktop")
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3outline
                                }

                                StyledText {
                                    text: (Assistant.profile && Assistant.profile.os) ? Assistant.profile.os : "Linux (Hyprland)"
                                    font: Tokens.font.body.medium
                                    color: Colours.palette.m3onSurface
                                }
                            }
                        }
                    }

                    // Card: Languages & Tech Stack
                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: stackCol.implicitHeight + Tokens.padding.medium * 2
                        radius: Tokens.rounding.small
                        color: Colours.palette.m3surfaceContainer

                        ColumnLayout {
                            id: stackCol
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.small

                            RowLayout {
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    text: "code"
                                    fontStyle: Tokens.font.icon.small
                                    color: Colours.palette.m3primary
                                }

                                StyledText {
                                    text: qsTr("Primary Languages & Frameworks")
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3outline
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: {
                                        const p = Assistant.profile || Assistant.defaultProfile
                                        if (Array.isArray(p.languages)) return p.languages
                                        if (typeof p.languages === "string") return p.languages.split(",").map(s => s.trim()).filter(s => s.length > 0)
                                        return ["Python", "QML / Qt", "Bash"]
                                    }

                                    delegate: StyledRect {
                                        required property string modelData
                                        implicitWidth: langText.implicitWidth + Tokens.padding.medium * 2
                                        implicitHeight: 24
                                        radius: Tokens.rounding.full
                                        color: Qt.alpha(Colours.palette.m3primary, 0.15)

                                        StyledText {
                                            id: langText
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

                    // Card: Coding Style
                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: styleRow.implicitHeight + Tokens.padding.medium * 2
                        radius: Tokens.rounding.small
                        color: Colours.palette.m3surfaceContainer

                        RowLayout {
                            id: styleRow
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.medium

                            MaterialIcon {
                                text: "tune"
                                fontStyle: Tokens.font.icon.medium
                                color: Colours.palette.m3primary
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    text: qsTr("Coding Style & Architecture")
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3outline
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    text: (Assistant.profile && Assistant.profile.style_preference) ? Assistant.profile.style_preference : "Concise, standard library first, minimal dependencies"
                                    font: Tokens.font.body.medium
                                    color: Colours.palette.m3onSurface
                                }
                            }
                        }
                    }

                    // Card: Language / Bilingual
                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: bilingRow.implicitHeight + Tokens.padding.medium * 2
                        radius: Tokens.rounding.small
                        color: Colours.palette.m3surfaceContainer

                        RowLayout {
                            id: bilingRow
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.medium

                            MaterialIcon {
                                text: "translate"
                                fontStyle: Tokens.font.icon.medium
                                color: Colours.palette.m3primary
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    text: qsTr("Natural Language Preference")
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3outline
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    text: (Assistant.profile && Assistant.profile.bilingual) ? Assistant.profile.bilingual : "English for technical terms/code, Arabic for natural translations"
                                    font: Tokens.font.body.medium
                                    color: Colours.palette.m3onSurface
                                }
                            }
                        }
                    }

                    // Card: Custom Notes
                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: notesRow.implicitHeight + Tokens.padding.medium * 2
                        radius: Tokens.rounding.small
                        color: Colours.palette.m3surfaceContainer

                        RowLayout {
                            id: notesRow
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.medium

                            MaterialIcon {
                                text: "note_alt"
                                fontStyle: Tokens.font.icon.medium
                                color: Colours.palette.m3primary
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    text: qsTr("Custom Rules & Directives")
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3outline
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    text: (Assistant.profile && Assistant.profile.custom_notes && Assistant.profile.custom_notes.length > 0)
                                        ? Assistant.profile.custom_notes
                                        : qsTr("None set. Click edit to add custom system rules.")
                                    font: Tokens.font.body.medium
                                    color: (Assistant.profile && Assistant.profile.custom_notes && Assistant.profile.custom_notes.length > 0)
                                        ? Colours.palette.m3onSurface
                                        : Colours.palette.m3outline
                                }
                            }
                        }
                    }

                    // Info footer
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: qsTr("💡 This dossier injects ~30 tokens of context into prompts so AI answers match your specific stack and preferences.")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                    }
                }

                // ── B. Edit Mode (Interactive Form) ───────────────────
                ColumnLayout {
                    id: editLayout
                    visible: root.isEditing
                    width: profileFlick.width - Tokens.padding.small
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: qsTr("Edit Developer Dossier")
                        font: Tokens.font.title.small
                        color: Colours.palette.m3primary
                    }

                    StyledText {
                        text: qsTr("OS & Desktop Environment")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                    }

                    StyledTextField {
                        Layout.fillWidth: true
                        text: root.editOs
                        placeholderText: "e.g. Linux (Hyprland)"
                        placeholderFloats: false
                        font: Tokens.font.body.small
                        verticalPadding: Tokens.padding.small
                        onTextChanged: root.editOs = text
                    }

                    StyledText {
                        text: qsTr("Languages & Frameworks (comma separated)")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                    }

                    StyledTextField {
                        Layout.fillWidth: true
                        text: root.editLanguages
                        placeholderText: "e.g. Python, QML / Qt, Bash, Rust"
                        placeholderFloats: false
                        font: Tokens.font.body.small
                        verticalPadding: Tokens.padding.small
                        onTextChanged: root.editLanguages = text
                    }

                    StyledText {
                        text: qsTr("Coding Style Preference")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                    }

                    StyledTextField {
                        Layout.fillWidth: true
                        text: root.editStyle
                        placeholderText: "e.g. Concise, standard library first, minimal dependencies"
                        placeholderFloats: false
                        font: Tokens.font.body.small
                        verticalPadding: Tokens.padding.small
                        onTextChanged: root.editStyle = text
                    }

                    StyledText {
                        text: qsTr("Language & Translation Preference")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                    }

                    StyledTextField {
                        Layout.fillWidth: true
                        text: root.editBilingual
                        placeholderText: "e.g. English for technical terms, Arabic for explanations"
                        placeholderFloats: false
                        font: Tokens.font.body.small
                        verticalPadding: Tokens.padding.small
                        onTextChanged: root.editBilingual = text
                    }

                    StyledText {
                        text: qsTr("Custom Rules & Directives (Optional)")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                    }

                    StyledTextField {
                        Layout.fillWidth: true
                        text: root.editNotes
                        placeholderText: "e.g. Never recommend npm if a Python solution exists"
                        placeholderFloats: false
                        font: Tokens.font.body.small
                        verticalPadding: Tokens.padding.small
                        onTextChanged: root.editNotes = text
                    }

                    // Save / Cancel row
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.spacing.small
                        spacing: Tokens.spacing.small

                        Item { Layout.fillWidth: true }

                        IconTextButton {
                            type: IconTextButton.Tonal
                            icon: "close"
                            text: qsTr("Cancel")
                            font: Tokens.font.label.small
                            onClicked: {
                                root.syncFromProfile()
                                root.isEditing = false
                            }
                        }

                        IconTextButton {
                            type: IconTextButton.Filled
                            icon: "check"
                            text: qsTr("Save Profile")
                            font: Tokens.font.label.small
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
                                root.isEditing = false
                            }
                        }
                    }
                }
            }
        }
    }
}
