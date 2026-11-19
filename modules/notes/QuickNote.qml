pragma ComponentBehavior: Bound

import QtQuick
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
                    if (isObviousNoise(content)) {
                        localSaveTimer.stop()
                        analysisTimer.stop()
                        return
                    }
                    if (!content || content === win.lastSavedText && analyze !== true) return
                    Notes.saveDraft(win.draftNoteId, content, win.draftSessionToken, analyze === true)
                }

                function isObviousNoise(value): bool {
                    const text = String(value || "").trim()
                    if (!text) return false
                    if (!/[A-Za-zÀ-ÖØ-öø-ÿ\u0600-\u06FF0-9]/.test(text)) return true

                    const words = text.toLowerCase().match(/[A-Za-zÀ-ÖØ-öø-ÿ\u0600-\u06FF0-9]+/g) || []
                    if (words.length >= 5 && words.every(word => word === words[0])) return true
                    if (/^(?:asdf+|qwerty+|zxcv+|test(?:ing)?|lorem\s+ipsum)[.!?\s]*$/i.test(text)) return true

                    // Catch obvious unspaced keyboard mash such as "a;ldsja;ljdf"
                    // while preserving normal Darija phrases and technical commands.
                    const pieces = text.split(/[;,]+/)
                    if (pieces.length >= 3 && !/\s/.test(text)
                            && pieces.every(piece => /^[A-Za-z]{1,10}$/.test(piece))) {
                        const latin = pieces.join("").toLowerCase()
                        const hasCommandShape = /^(?:git|docker|kubectl|npm|pnpm|yarn|sudo|cd|ls|cat|grep|python|pip|systemctl|pacman)/i.test(latin)
                        const vowelCount = (latin.match(/[aeiouy]/g) || []).length
                        if (!hasCommandShape && latin.length >= 7 && vowelCount / latin.length < 0.34) return true
                    }
                    return false
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

                function resetWindowSize(): void {
                    win.width = win.preferredWidth
                    win.height = win.preferredHeight
                }

                screen: loader.modelData
                visible: win.st?.quickNote ?? false
                title: win.reviewMode ? qsTr("Quick Notes") : qsTr("Quick Note")
                color: "transparent"
                surfaceFormat.opaque: false

                implicitWidth: preferredWidth
                implicitHeight: preferredHeight
                minimumSize.width: win.reviewMode
                    ? Math.min(600, Math.round(loader.modelData.width * 0.8))
                    : Math.min(400, Math.round(loader.modelData.width * 0.8))
                minimumSize.height: win.reviewMode
                    ? Math.min(400, Math.round(loader.modelData.height * 0.6))
                    : Math.min(120, Math.round(loader.modelData.height * 0.3))
                maximumSize.width: Math.round(loader.modelData.width * 0.96)
                maximumSize.height: Math.round(loader.modelData.height * 0.92)

                contentItem.Config.screen: loader.modelData.name
                contentItem.Tokens.screen: loader.modelData.name

                onClosed: {
                    if (!win.modeTransitioning && !win.reviewMode) win.saveDraft(true)
                    if (win.st && !win.modeTransitioning) win.st.quickNote = false
                }

                onVisibleChanged: {
                    if (visible) {
                        win.saveError = ""
                        win.modeTransitioning = true
                        win.resizeAttempts = 0
                        win.resetWindowSize()
                        resizeTimer.restart()
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
                    win.resetWindowSize()
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
                        if (win.visible) {
                            win.resetWindowSize()
                        }
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
                    border.color: win.saveError
                        ? Colours.palette.m3error
                        : Qt.alpha(noteEditor.activeFocus ? Colours.palette.m3primary : Colours.palette.m3outlineVariant,
                            noteEditor.activeFocus ? 0.5 : 0.35)

                    Flickable {
                        id: noteScroll
                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        contentWidth: width
                        contentHeight: Math.max(height, noteEditor.contentHeight)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        function ensureVisible(cursorRect): void {
                            const margin = Tokens.padding.small
                            if (cursorRect.y < contentY + margin) {
                                contentY = Math.max(0, cursorRect.y - margin)
                            } else if (cursorRect.y + cursorRect.height > contentY + height - margin) {
                                contentY = Math.min(contentHeight - height,
                                    cursorRect.y + cursorRect.height - height + margin)
                            }
                        }

                        StyledScrollBar.vertical: StyledScrollBar {
                            flickable: noteScroll
                        }

                        TextEdit {
                            id: noteEditor
                            width: noteScroll.width
                            height: Math.max(noteScroll.height, contentHeight)
                            wrapMode: TextEdit.Wrap
                            selectByMouse: true
                            selectByKeyboard: true
                            color: Colours.palette.m3onSurface
                            selectionColor: Qt.alpha(Colours.palette.m3primary, 0.35)
                            selectedTextColor: Colours.palette.m3onSurface
                            font: Tokens.font.body.small
                            renderType: TextEdit.NativeRendering

                            onCursorRectangleChanged: noteScroll.ensureVisible(cursorRectangle)

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
