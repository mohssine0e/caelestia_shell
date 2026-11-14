pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Scope {
    id: root

    Variants {
        model: Screens.screens

        LazyLoader {
            id: loader

            required property ShellScreen modelData

            activeAsync: true

            FloatingWindow {
                id: win

                readonly property ScreenState st: ShellState.forScreen(loader.modelData)
                readonly property string mode: win.st?.notesMode || "capture"
                readonly property bool reviewMode: mode === "review"
                readonly property int preferredWidth: reviewMode
                    ? Math.min(900, Math.round(loader.modelData.width * 0.94))
                    : Math.min(600, Math.round(loader.modelData.width * 0.92))
                readonly property int preferredHeight: reviewMode
                    ? Math.min(620, Math.round(loader.modelData.height * 0.88))
                    : Math.min(150, Math.round(loader.modelData.height * 0.4))
                property string saveError: ""
                property bool modeTransitioning: false
                property int resizeAttempts: 0
                property string draftNoteId: ""
                property string draftSessionToken: ""
                property string lastSavedText: ""
                property bool resettingEditor: false

                function beginCapture(): void {
                    localSaveTimer.stop()
                    analysisTimer.stop()
                    win.draftNoteId = ""
                    win.lastSavedText = ""
                    win.draftSessionToken = "draft_" + Date.now() + "_" + Math.random()
                    win.resettingEditor = true
                    noteEditor.clear()
                    win.resettingEditor = false
                    win.saveError = ""
                    Qt.callLater(() => noteEditor.forceActiveFocus())
                }

                function saveDraft(analyze): void {
                    const content = noteEditor.text.trim()
                    if (!content || content === win.lastSavedText && analyze !== true) return
                    Notes.saveDraft(win.draftNoteId, content, win.draftSessionToken, analyze === true)
                }

                function closeCapture(): void {
                    localSaveTimer.stop()
                    analysisTimer.stop()
                    win.saveDraft(true)
                    win.resettingEditor = true
                    noteEditor.clear()
                    win.resettingEditor = false
                    if (win.st) win.st.quickNote = false
                }

                function closeWindow(): void {
                    win.saveError = ""
                    if (win.st) win.st.quickNote = false
                }

                screen: loader.modelData
                visible: win.st?.quickNote ?? false
                title: win.reviewMode ? qsTr("Quick Notes") : qsTr("Quick Note")
                color: "transparent"
                surfaceFormat.opaque: false

                implicitWidth: preferredWidth
                implicitHeight: preferredHeight
                minimumSize.width: preferredWidth
                minimumSize.height: preferredHeight
                maximumSize.width: preferredWidth
                maximumSize.height: preferredHeight

                contentItem.Config.screen: loader.modelData.name
                contentItem.Tokens.screen: loader.modelData.name

                onClosed: {
                    if (!win.modeTransitioning && !win.reviewMode) win.saveDraft(true)
                    if (win.st && !win.modeTransitioning) win.st.quickNote = false
                }

                onVisibleChanged: {
                    if (visible) {
                        win.saveError = ""
                        Qt.callLater(() => {
                            if (win.reviewMode) reviewView.forceActiveFocus()
                            else win.beginCapture()
                        })
                    }
                }

                onModeChanged: {
                    if (win.reviewMode) win.saveDraft(true)
                    win.modeTransitioning = true
                    win.resizeAttempts = 0
                    resizeTimer.restart()
                    if (visible) {
                        Qt.callLater(() => {
                            if (win.reviewMode) reviewView.forceActiveFocus()
                            else win.beginCapture()
                        })
                    }
                }

                Timer {
                    id: resizeTimer

                    interval: 80
                    onTriggered: {
                        win.resizeAttempts += 1
                        if (win.resizeAttempts < 3) {
                            resizeTimer.restart()
                        } else {
                            win.modeTransitioning = false
                        }
                    }
                }

                Timer {
                    id: localSaveTimer

                    interval: 600
                    onTriggered: win.saveDraft(false)
                }

                Timer {
                    id: analysisTimer

                    interval: 2800
                    onTriggered: win.saveDraft(true)
                }

                Connections {
                    function onDraftSaved(note, clientToken): void {
                        if (clientToken !== win.draftSessionToken) return
                        win.draftNoteId = note.id || win.draftNoteId
                        win.lastSavedText = note.raw_content || ""
                        win.saveError = ""
                    }

                    function onDraftSaveFailed(message, clientToken): void {
                        if (clientToken !== win.draftSessionToken) return
                        win.saveError = message
                        Toaster.toast(qsTr("Note save failed"), message, "error")
                    }

                    target: Notes
                }

                Rectangle {
                    visible: !win.reviewMode
                    anchors.fill: parent
                    color: Colours.tPalette.m3surfaceContainer
                    radius: Tokens.rounding.medium
                    border.width: 1
                    border.color: win.saveError ? Colours.palette.m3error : Colours.palette.m3outlineVariant

                    TextArea {
                        id: noteEditor

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.large

                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        placeholderText: ""
                        color: Colours.palette.m3onSurface
                        placeholderTextColor: Colours.palette.m3onSurfaceVariant
                        selectionColor: Qt.alpha(Colours.palette.m3primary, 0.35)
                        selectedTextColor: Colours.palette.m3onSurface
                        font: Tokens.font.body.medium
                        background: null
                        padding: 0

                        onTextChanged: {
                            if (win.resettingEditor || win.reviewMode) return
                            if (!text.trim()) {
                                localSaveTimer.stop()
                                analysisTimer.stop()
                                return
                            }
                            localSaveTimer.restart()
                            analysisTimer.restart()
                        }

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                event.accepted = true
                                win.closeCapture()
                            }
                        }
                    }
                }

                NotesView {
                    id: reviewView

                    visible: win.reviewMode
                    anchors.fill: parent
                    onCloseRequested: win.closeWindow()
                    onMoveRequested: win.startSystemMove()
                }
            }
        }
    }
}
