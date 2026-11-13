pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: win

    readonly property bool narrow: width < 720
    property string selectedId: ""
    property string query: ""
    property string categoryFilter: "kept"
    property bool editing: false
    property bool showRaw: false
    property string recentlyDeletedId: ""

    readonly property var filteredNotes: {
                    const source = Notes.notes || []
                    const needle = win.query.trim().toLowerCase()
                    const categoryOrder = { unclassified: 0, technical: 1, reference: 2, personal: 3, idea: 4, noise: 5 }
                    return source.filter(note => {
                        if (win.categoryFilter === "kept" && note.keep_decision === "skip") return false
                        if (win.categoryFilter === "skipped" && note.keep_decision !== "skip") return false
                        if (win.categoryFilter === "technical" && note.category !== "technical" && note.category !== "reference") return false
                        if (["personal", "idea"].includes(win.categoryFilter) && note.category !== win.categoryFilter) return false
                        if (!needle) return true
                        const tags = (note.tags || []).join(" ")
                        return String(note.raw_content || "").toLowerCase().includes(needle)
                            || String(note.formatted_content || "").toLowerCase().includes(needle)
                            || tags.toLowerCase().includes(needle)
                    }).slice().sort((a, b) => {
                        const categoryDiff = (categoryOrder[a.category] ?? 9) - (categoryOrder[b.category] ?? 9)
                        if (categoryDiff !== 0) return categoryDiff
                        return String(b.updated_at || "").localeCompare(String(a.updated_at || ""))
                    })
    }

    readonly property var selectedNote: {
                    const source = Notes.notes || []
                    for (let i = 0; i < source.length; i++)
                        if (source[i].id === win.selectedId) return source[i]
                    return null
    }

    signal closeRequested()

    function closeView(): void {
        win.editing = false
        win.closeRequested()
    }

    function categoryLabel(category): string {
        if (category === "technical") return qsTr("Technical")
        if (category === "reference") return qsTr("Reference")
        if (category === "personal") return qsTr("Personal")
        if (category === "idea") return qsTr("Ideas")
        if (category === "noise") return qsTr("Skipped")
        return qsTr("Inbox")
    }

    function beginEdit(): void {
                    if (!win.selectedNote) return
                    rawEditor.text = win.selectedNote.raw_content || ""
                    tagsEditor.text = (win.selectedNote.tags || []).join(" ")
                    win.editing = true
                    Qt.callLater(() => rawEditor.forceActiveFocus())
    }

    function saveEdit(): void {
                    if (!win.selectedNote || !rawEditor.text.trim()) return
                    const tags = tagsEditor.text.split(/[\s,]+/).filter(value => value.length > 0)
                    if (Notes.update(win.selectedNote.id, rawEditor.text, tags))
                        win.editing = false
    }

    focus: true

    Component.onCompleted: {
        Notes.refresh()
        Notes.refreshProviderStatus()
        win.forceActiveFocus()
    }

    onFilteredNotesChanged: {
                    let selectedVisible = false
                    for (let i = 0; i < filteredNotes.length; i++) {
                        if (filteredNotes[i].id === win.selectedId) {
                            selectedVisible = true
                            break
                        }
                    }
                    if (!selectedVisible)
                        win.selectedId = filteredNotes.length > 0 ? filteredNotes[0].id : ""
    }

    Keys.onEscapePressed: event => {
                    if (win.editing) {
                        win.editing = false
                    } else if (win.narrow && win.selectedId) {
                        win.selectedId = ""
                    } else {
                        win.closeView()
                    }
                    event.accepted = true
    }

    Connections {
                    function onNoteDeleted(noteId): void {
                        if (win.selectedId === noteId) win.selectedId = ""
                        win.recentlyDeletedId = noteId
                        undoTimer.restart()
                    }

                    function onNoteChanged(note): void {
                        if (note && note.id === win.selectedId) win.editing = false
                        if (note && note.id === win.recentlyDeletedId) {
                            win.recentlyDeletedId = ""
                            undoTimer.stop()
                        }
                    }

                    target: Notes
    }

    Timer {
                    id: undoTimer

                    interval: 8000
                    onTriggered: win.recentlyDeletedId = ""
    }

    Rectangle {
                    anchors.fill: parent
                    radius: Tokens.rounding.medium
                    color: Colours.tPalette.m3surfaceContainer
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        spacing: Tokens.spacing.medium

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            IconButton {
                                visible: win.narrow && !!win.selectedId
                                type: IconButton.Text
                                icon: "arrow_back"
                                onClicked: win.selectedId = ""
                            }

                            MaterialIcon {
                                text: "note_stack"
                                color: Colours.palette.m3primary
                                fontStyle: Tokens.font.icon.medium
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    text: qsTr("Quick Notes")
                                    font: Tokens.font.title.medium
                                }
                                StyledText {
                                    text: {
                                        const count = (Notes.notes || []).filter(note => note.keep_decision !== "skip").length
                                        return count === 1 ? qsTr("1 saved note") : qsTr("%1 saved notes").arg(count)
                                    }
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.small
                                }
                            }

                            CircularIndicator {
                                visible: Notes.loading
                                running: visible
                                implicitSize: 22
                            }

                            IconButton {
                                type: IconButton.Text
                                icon: "refresh"
                                enabled: !Notes.loading
                                onClicked: Notes.refresh()
                            }

                            IconButton {
                                type: IconButton.Text
                                icon: "close"
                                onClicked: win.closeView()
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: Tokens.spacing.medium

                            Rectangle {
                                id: sidebar

                                visible: !win.narrow || !win.selectedId
                                Layout.fillWidth: win.narrow
                                Layout.preferredWidth: win.narrow ? -1 : 292
                                Layout.fillHeight: true
                                radius: Tokens.rounding.small
                                color: Colours.palette.m3surfaceContainerLow
                                border.width: 1
                                border.color: Colours.palette.m3outlineVariant

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Tokens.padding.small
                                    spacing: Tokens.spacing.small

                                    SearchBar {
                                        Layout.fillWidth: true
                                        implicitHeight: 42
                                        placeholderText: qsTr("Search notes or #tags")
                                        text: win.query
                                        onTextChanged: win.query = text
                                    }

                                    Flickable {
                                        Layout.fillWidth: true
                                        implicitHeight: filterRow.implicitHeight
                                        contentWidth: filterRow.implicitWidth
                                        contentHeight: height
                                        clip: true

                                        Row {
                                            id: filterRow

                                            spacing: Tokens.spacing.extraSmall

                                            Repeater {
                                                model: [
                                                    { key: "kept", label: qsTr("Notes") },
                                                    { key: "technical", label: qsTr("Technical") },
                                                    { key: "personal", label: qsTr("Personal") },
                                                    { key: "idea", label: qsTr("Ideas") },
                                                    { key: "skipped", label: qsTr("Skipped") }
                                                ]
                                                delegate: Rectangle {
                                                    id: filterChip

                                                    required property var modelData

                                                    implicitWidth: filterLabel.implicitWidth + Tokens.padding.medium * 2
                                                    implicitHeight: 28
                                                    radius: Tokens.rounding.full
                                                    color: win.categoryFilter === modelData.key
                                                        ? Colours.palette.m3secondaryContainer
                                                        : Colours.palette.m3surfaceContainerHigh

                                                    StyledText {
                                                        id: filterLabel

                                                        anchors.centerIn: parent
                                                        text: filterChip.modelData.label
                                                        color: Colours.palette.m3onSecondaryContainer
                                                        font: Tokens.font.label.small
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: win.categoryFilter = filterChip.modelData.key
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    ListView {
                                        id: notesList

                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        spacing: Tokens.spacing.extraSmall
                                        model: win.filteredNotes
                                        section.property: "category"
                                        section.criteria: ViewSection.FullString
                                        section.delegate: StyledText {
                                            required property string section

                                            width: notesList.width
                                            topPadding: Tokens.padding.small
                                            bottomPadding: Tokens.padding.extraSmall
                                            text: win.categoryLabel(section)
                                            color: Colours.palette.m3primary
                                            font: Tokens.font.label.medium
                                        }
                                        delegate: Rectangle {
                                            id: noteRow

                                            required property var modelData

                                            width: notesList.width
                                            implicitHeight: noteSummary.implicitHeight + Tokens.padding.medium * 2
                                            radius: Tokens.rounding.small
                                            color: win.selectedId === modelData.id
                                                ? Colours.palette.m3secondaryContainer
                                                : Colours.palette.m3surfaceContainer

                                            Column {
                                                id: noteSummary

                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.margins: Tokens.padding.medium
                                                spacing: Tokens.spacing.extraSmall

                                                StyledText {
                                                    width: parent.width
                                                    text: noteRow.modelData.raw_content.replace(/\s+/g, " ")
                                                    color: win.selectedId === noteRow.modelData.id
                                                        ? Colours.palette.m3onSecondaryContainer
                                                        : Colours.palette.m3onSurface
                                                    font: Tokens.font.body.small
                                                    maximumLineCount: 2
                                                    elide: Text.ElideRight
                                                    wrapMode: Text.Wrap
                                                }
                                                StyledText {
                                                    width: parent.width
                                                    text: (noteRow.modelData.tags || []).join(" ") || noteRow.modelData.created_at.replace("T", " ").slice(0, 16)
                                                    color: Colours.palette.m3onSurfaceVariant
                                                    font: Tokens.font.label.small
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    win.selectedId = noteRow.modelData.id
                                                    win.showRaw = false
                                                    win.editing = false
                                                }
                                            }
                                        }

                                        StyledText {
                                            anchors.centerIn: parent
                                            visible: notesList.count === 0 && !Notes.loading
                                            width: Math.min(parent.width - Tokens.padding.large * 2, implicitWidth)
                                            horizontalAlignment: Text.AlignHCenter
                                            wrapMode: Text.Wrap
                                            text: win.query || win.categoryFilter !== "kept"
                                                ? qsTr("No notes match this filter.")
                                                : qsTr("Your captured notes will appear here.")
                                            color: Colours.palette.m3onSurfaceVariant
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                id: detail

                                visible: !win.narrow || !!win.selectedId
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Tokens.rounding.small
                                color: Colours.palette.m3surfaceContainerLow
                                border.width: 1
                                border.color: Colours.palette.m3outlineVariant

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Tokens.padding.medium
                                    spacing: Tokens.spacing.small

                                    RowLayout {
                                        Layout.fillWidth: true
                                        visible: !!win.selectedNote
                                        spacing: Tokens.spacing.small

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: {
                                                if (!win.selectedNote) return ""
                                                if (win.selectedNote.status === "formatting" || Notes.isFormatting(win.selectedNote.id)) return qsTr("Analyzing…")
                                                if (win.selectedNote.status === "format_failed") return qsTr("Analysis needs attention")
                                                if (win.selectedNote.keep_decision === "skip") return qsTr("Skipped by AI · recoverable")
                                                return win.categoryLabel(win.selectedNote.category)
                                            }
                                            color: win.selectedNote?.status === "format_failed"
                                                ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                                            font: Tokens.font.label.medium
                                        }

                                        IconButton {
                                            type: IconButton.Text
                                            icon: win.showRaw ? "auto_awesome" : "article"
                                            enabled: !!win.selectedNote?.formatted_content
                                            onClicked: win.showRaw = !win.showRaw
                                        }
                                        IconButton {
                                            type: IconButton.Text
                                            icon: "content_copy"
                                            onClicked: {
                                                const note = win.selectedNote
                                                if (!note) return
                                                Quickshell.clipboardText = win.showRaw || !note.formatted_content
                                                    ? note.raw_content : note.formatted_content
                                                Toaster.toast(qsTr("Copied"), qsTr("Note copied to the clipboard"), "content_copy")
                                            }
                                        }
                                        IconButton {
                                            type: IconButton.Text
                                            icon: "edit"
                                            enabled: !Notes.mutating
                                            onClicked: win.beginEdit()
                                        }
                                        IconButton {
                                            type: IconButton.Text
                                            icon: "delete"
                                            enabled: !Notes.mutating
                                            onClicked: Notes.remove(win.selectedNote.id)
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        visible: !!win.selectedNote && !win.editing
                                        spacing: Tokens.spacing.small

                                        IconTextButton {
                                            icon: Notes.isFormatting(win.selectedNote?.id || "") ? "hourglass_top" : "auto_awesome"
                                            text: win.selectedNote?.status === "format_failed" ? qsTr("Retry analysis") : qsTr("Analyze again")
                                            type: IconTextButton.Tonal
                                            enabled: !!win.selectedNote && !Notes.isFormatting(win.selectedNote.id)
                                                && Notes.providerConfigured
                                            onClicked: Notes.queueOrganization(win.selectedNote.id)
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: Notes.providerConfigured
                                                ? qsTr("%1 · sent only when you request formatting").arg(Notes.providerDisclosure)
                                                : qsTr("Configure Gemini or Groq in Assistant settings to format notes")
                                            color: Colours.palette.m3onSurfaceVariant
                                            font: Tokens.font.label.small
                                            wrapMode: Text.Wrap
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        visible: win.editing && !!win.selectedNote
                                        spacing: Tokens.spacing.small

                                        TextArea {
                                            id: rawEditor

                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            wrapMode: TextEdit.Wrap
                                            selectByMouse: true
                                            color: Colours.palette.m3onSurface
                                            selectionColor: Qt.alpha(Colours.palette.m3primary, 0.35)
                                            font: Tokens.font.body.small
                                            background: Rectangle {
                                                color: Colours.palette.m3surfaceContainer
                                                radius: Tokens.rounding.small
                                                border.width: rawEditor.activeFocus ? 2 : 1
                                                border.color: rawEditor.activeFocus ? Colours.palette.m3primary : Colours.palette.m3outlineVariant
                                            }
                                        }
                                        StyledTextField {
                                            id: tagsEditor

                                            Layout.fillWidth: true
                                            placeholderText: qsTr("Tags, for example #docker #linux")
                                            placeholderFloats: false
                                            verticalPadding: Tokens.padding.small
                                        }
                                        RowLayout {
                                            Layout.alignment: Qt.AlignRight
                                            TextButton {
                                                text: qsTr("Cancel")
                                                type: TextButton.Text
                                                onClicked: win.editing = false
                                            }
                                            TextButton {
                                                text: qsTr("Save changes")
                                                type: TextButton.Filled
                                                enabled: rawEditor.text.trim().length > 0 && !Notes.mutating
                                                onClicked: win.saveEdit()
                                            }
                                        }
                                    }

                                    Flickable {
                                        id: noteScroll

                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        visible: !win.editing && !!win.selectedNote
                                        clip: true
                                        contentWidth: width
                                        contentHeight: noteBody.implicitHeight + Tokens.padding.medium * 2
                                        boundsBehavior: Flickable.StopAtBounds

                                        StyledText {
                                            id: noteBody

                                            x: Tokens.padding.small
                                            y: Tokens.padding.small
                                            width: noteScroll.width - Tokens.padding.medium
                                            text: {
                                                const note = win.selectedNote
                                                if (!note) return ""
                                                if (win.showRaw || !note.formatted_content) return note.raw_content || ""
                                                return note.formatted_content
                                            }
                                            textFormat: win.showRaw || !win.selectedNote?.formatted_content
                                                ? Text.PlainText : Text.MarkdownText
                                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                            color: Colours.palette.m3onSurface
                                            font: Tokens.font.body.medium
                                            onLinkActivated: link => Qt.openUrlExternally(link)
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: !!(win.selectedNote?.triage_error || win.selectedNote?.format_error) && !win.editing
                                        text: win.selectedNote?.triage_error || win.selectedNote?.format_error || ""
                                        color: Colours.palette.m3error
                                        font: Tokens.font.label.small
                                        wrapMode: Text.Wrap
                                    }

                                    StyledText {
                                        Layout.alignment: Qt.AlignCenter
                                        visible: !win.selectedNote
                                        text: qsTr("Select a note to review it")
                                        color: Colours.palette.m3onSurfaceVariant
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Tokens.padding.large
                        z: 10
                        visible: !!win.recentlyDeletedId
                        implicitWidth: undoRow.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: undoRow.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3inverseSurface

                        RowLayout {
                            id: undoRow

                            anchors.centerIn: parent
                            spacing: Tokens.spacing.medium

                            StyledText {
                                text: qsTr("Note moved to trash")
                                color: Colours.palette.m3inverseOnSurface
                                font: Tokens.font.body.small
                            }

                            TextButton {
                                text: qsTr("Undo")
                                type: TextButton.Text
                                onClicked: Notes.restore(win.recentlyDeletedId)
                            }
                        }
                    }
    }
}
