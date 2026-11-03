pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

StyledRect {
    id: root

    property bool isExpanded: false
    property string activeNoteId: "today"
    property int activeGroupIndex: 0
    property var groups: []
    property bool addingGroup: false
    property string editingGroupId: ""
    property string deletingConfirmId: ""
    property bool isSyncing: false

    readonly property string dataPath: Paths.home + "/daily_focus.json"

    function findGroup(id) {
        if (!root.groups) return null
        for (var i = 0; i < root.groups.length; i++) {
            if (root.groups[i].id === id) return root.groups[i]
        }
        return null
    }

    readonly property var currentGroup: findGroup(root.activeNoteId) || (root.groups && root.groups.length > 0 ? root.groups[0] : null)
    readonly property string currentNoteText: currentGroup ? (currentGroup.note || "") : ""

    Layout.fillWidth: true
    radius: Tokens.rounding.small
    color: "#272325"
    border.width: 1
    border.color: root.isExpanded ? Qt.alpha("#ffca1b", 0.4)
                                  : Qt.alpha("#ffca1b", 0.16)
    clip: true

    implicitHeight: root.isExpanded
        ? Math.max(110, mainCol.implicitHeight + Tokens.padding.small * 2)
        : 40

    Behavior on implicitHeight {
        Anim { type: Anim.FastSpatial }
    }
    Behavior on border.color {
        CAnim {}
    }

    // ── Persistence ──────────────────────────────────────────────
    FileView {
        id: storage
        path: root.dataPath

        onLoaded: {
            try {
                var raw = JSON.parse(text())
                root.isExpanded = false // Always collapsed by default on open

                if (Array.isArray(raw.groups) && raw.groups.length > 0) {
                    root.groups = raw.groups
                } else if (raw.note !== undefined) {
                    root.groups = [
                        { id: "today", title: "Today", note: raw.note || "" },
                        { id: "work", title: "Work", note: "" }
                    ]
                } else {
                    root.groups = [
                        { id: "today", title: "Today", note: "Deploy staging before 3 PM\nReview auth PR\nStandup at 10 AM" },
                        { id: "work", title: "Work", note: "• Fix Docker volume\n• Prepare migration script" }
                    ]
                }

                if (raw.activeNoteId && root.findGroup(raw.activeNoteId)) {
                    root.activeNoteId = raw.activeNoteId
                } else {
                    var idx = typeof raw.activeGroup === "number" ? Math.max(0, Math.min(raw.activeGroup, root.groups.length - 1)) : 0
                    root.activeNoteId = root.groups[idx] ? root.groups[idx].id : "today"
                }
                root.activeGroupIndex = Math.max(0, root.groups.findIndex(g => g.id === root.activeNoteId))

                syncEditorText()
            } catch (e) {
                console.warn("[DailyFocusBanner] parse error:", e)
                root.initDefaultGroups()
            }
        }

        onLoadFailed: function(err) {
            root.initDefaultGroups()
            if (err === FileViewError.FileNotFound) {
                root.requestSave()
            }
        }
    }

    function initDefaultGroups() {
        root.groups = [
            { id: "today", title: "Today", note: "Deploy staging before 3 PM\nReview auth PR\nStandup at 10 AM" },
            { id: "work", title: "Work", note: "• Fix Docker volume\n• Prepare migration script" }
        ]
        root.activeNoteId = "today"
        root.activeGroupIndex = 0
        root.isExpanded = false
        syncEditorText()
    }

    function syncEditorText() {
        if (!scratchpadInput) return
        var g = root.findGroup(root.activeNoteId)
        var targetText = (g && g.note) ? g.note : ""
        root.isSyncing = true
        scratchpadInput.text = targetText
        root.isSyncing = false
    }

    function switchToNote(targetId) {
        if (!targetId || targetId === root.activeNoteId) return

        // 1. Commit whatever was in the editor to the old note before switching
        if (scratchpadInput && root.activeNoteId) {
            var oldGrp = root.findGroup(root.activeNoteId)
            if (oldGrp && oldGrp.note !== scratchpadInput.text) {
                oldGrp.note = scratchpadInput.text
            }
        }

        // 2. Set new active ID
        root.activeNoteId = targetId
        var idx = root.groups.findIndex(g => g.id === targetId)
        if (idx !== -1) root.activeGroupIndex = idx

        root.editingGroupId = ""
        root.deletingConfirmId = ""

        // 3. Atomically load new note text into editor with sync guard
        var newGrp = root.findGroup(targetId)
        var newText = (newGrp && newGrp.note) ? newGrp.note : ""
        if (scratchpadInput) {
            root.isSyncing = true
            scratchpadInput.text = newText
            root.isSyncing = false
        }

        requestSave()
    }

    onIsExpandedChanged: {
        if (root.isExpanded) {
            syncEditorText()
        } else {
            root.editingGroupId = ""
            root.deletingConfirmId = ""
            root.addingGroup = false
        }
        requestSave()
    }

    Timer {
        id: saveTimer
        interval: 350
        onTriggered: {
            var payload = {
                date: new Date().toISOString().slice(0, 10),
                activeNoteId: root.activeNoteId,
                activeGroup: root.activeGroupIndex,
                expanded: root.isExpanded,
                groups: root.groups
            }
            storage.setText(JSON.stringify(payload, null, 2))
        }
    }

    function requestSave() {
        saveTimer.restart()
    }

    function updateActiveNote(newText) {
        var g = root.findGroup(root.activeNoteId)
        if (!g) return
        if (g.note === newText) return
        g.note = newText
        requestSave()
    }

    function addGroup(title) {
        var t = (title || "").trim()
        if (!t) {
            root.addingGroup = false
            return
        }
        var newId = String(Date.now())
        var newGrp = {
            id: newId,
            title: t,
            note: ""
        }
        var copy = root.groups.slice()
        copy.push(newGrp)
        root.groups = copy

        root.addingGroup = false
        root.isExpanded = true
        root.switchToNote(newId)

        Qt.callLater(() => {
            if (scratchpadInput) scratchpadInput.forceActiveFocus()
        })
    }

    function renameGroup(id, newTitle) {
        var t = (newTitle || "").trim()
        if (!t || !id) {
            root.editingGroupId = ""
            return
        }
        var g = root.findGroup(id)
        if (g) {
            g.title = t
            // Trigger property update
            root.groups = root.groups.slice()
            requestSave()
        }
        root.editingGroupId = ""
    }

    function requestRemoveGroup(id) {
        if (root.groups.length <= 1) return
        var grp = root.findGroup(id)
        if (!grp) return

        // If the note is empty, delete immediately without prompt
        if (!grp.note || grp.note.trim().length === 0) {
            removeGroup(id)
            return
        }

        // If it has content, require confirmation click
        if (root.deletingConfirmId === id) {
            root.deletingConfirmId = ""
            removeGroup(id)
        } else {
            root.deletingConfirmId = id
        }
    }

    function removeGroup(id) {
        if (root.groups.length <= 1) return
        var copy = root.groups.filter(g => g.id !== id)
        root.groups = copy

        if (root.activeNoteId === id) {
            var nextGrp = copy[0]
            root.activeNoteId = nextGrp ? nextGrp.id : "today"
            root.activeGroupIndex = 0
            syncEditorText()
        } else {
            root.activeGroupIndex = Math.max(0, root.groups.findIndex(g => g.id === root.activeNoteId))
        }

        root.deletingConfirmId = ""
        root.editingGroupId = ""
        requestSave()
    }

    // ── Main Layout ──────────────────────────────────────────────
    ColumnLayout {
        id: mainCol
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: Tokens.padding.small
            leftMargin: Tokens.padding.medium
            rightMargin: Tokens.padding.small
        }
        spacing: 6

        // ── Single Persistent Header ─────────────────────────────
        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            spacing: 8

            // Notebook Icon (Style A)
            MaterialIcon {
                text: "edit_note"
                fontStyle: Tokens.font.icon.small
                color: "#ffca1b"
                fill: 1
                Layout.alignment: Qt.AlignVCenter

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.isExpanded = !root.isExpanded
                }
            }

            // Horizontally Scrollable Pills Area
            Flickable {
                id: pillsFlick
                Layout.preferredHeight: 28
                Layout.fillWidth: true
                contentWidth: Math.max(width, pillsRow.implicitWidth)
                contentHeight: 28
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                Layout.alignment: Qt.AlignVCenter

                MouseArea {
                    anchors.fill: parent
                    z: -1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.editingGroupId = ""
                        root.deletingConfirmId = ""
                        root.isExpanded = !root.isExpanded
                    }
                }

                WheelHandler {
                    target: pillsFlick
                    orientation: Qt.Horizontal
                    property: "contentX"
                }

                WheelHandler {
                    target: pillsFlick
                    orientation: Qt.Vertical
                    onWheel: event => {
                        pillsFlick.contentX = Math.max(0, Math.min(pillsFlick.contentWidth - pillsFlick.width, pillsFlick.contentX - event.angleDelta.y))
                    }
                }

                RowLayout {
                    id: pillsRow
                    height: 28
                    spacing: 4

                    Repeater {
                        model: root.groups

                        delegate: StyledRect {
                            id: pillCard
                            required property var modelData
                            required property int index
                            readonly property bool isActive: root.activeNoteId === pillCard.modelData.id
                            readonly property bool isEditing: root.editingGroupId === pillCard.modelData.id
                            readonly property bool hasNoteContent: !!(pillCard.modelData.note && pillCard.modelData.note.trim().length > 0)
                            readonly property bool canDelete: root.groups.length > 1 && pillCard.modelData.id !== "today"

                            implicitHeight: 26
                            implicitWidth: pillInnerRow.implicitWidth + 16
                            radius: Tokens.rounding.full
                            color: isActive ? Qt.alpha("#ffca1b", 0.22) : "#302b2d"

                            border.width: 1
                            border.color: isActive ? "#ffca1b" : Qt.alpha("#ffca1b", 0.18)

                            Behavior on color { CAnim {} }
                            Behavior on border.color { CAnim {} }

                            RowLayout {
                                id: pillInnerRow
                                anchors.centerIn: parent
                                spacing: 5

                                // Content indicator dot (shows when note contains text)
                                StyledRect {
                                    visible: pillCard.hasNoteContent && !pillCard.isEditing
                                    implicitWidth: 5
                                    implicitHeight: 5
                                    radius: Tokens.rounding.full
                                    color: pillCard.isActive ? "#ffca1b" : Qt.alpha("#ede6df", 0.45)
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // Note title text
                                StyledText {
                                    visible: !pillCard.isEditing
                                    text: pillCard.modelData.title || qsTr("Untitled")
                                    font: Tokens.font.label.medium
                                    color: pillCard.isActive ? "#ffca1b" : "#ede6df"
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // Inline rename field
                                TextInput {
                                    id: renameInput
                                    visible: pillCard.isEditing
                                    text: pillCard.modelData.title || ""
                                    font: Tokens.font.label.medium
                                    color: "#ede6df"
                                    selectionColor: Qt.alpha("#ffca1b", 0.4)
                                    selectedTextColor: "#ffffff"
                                    verticalAlignment: TextInput.AlignVCenter
                                    Layout.preferredWidth: Math.max(65, contentWidth + 10)

                                    onAccepted: {
                                        root.renameGroup(pillCard.modelData.id, text)
                                    }

                                    Keys.onEscapePressed: {
                                        root.editingGroupId = ""
                                    }
                                }

                                // Rename confirm checkmark
                                MaterialIcon {
                                    visible: pillCard.isEditing
                                    text: "check"
                                    fontStyle: Tokens.font.icon.small
                                    color: "#ffca1b"
                                    Layout.alignment: Qt.AlignVCenter

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.renameGroup(pillCard.modelData.id, renameInput.text)
                                    }
                                }
                            }

                            TapHandler {
                                onTapped: {
                                    if (pillCard.isEditing) return
                                    root.deletingConfirmId = ""
                                    if (root.activeNoteId === pillCard.modelData.id) {
                                        // Clicking active group toggles expand/shrink
                                        root.isExpanded = !root.isExpanded
                                    } else {
                                        root.switchToNote(pillCard.modelData.id)
                                    }
                                }
                                onDoubleTapped: {
                                    if (!pillCard.isEditing) {
                                        root.editingGroupId = pillCard.modelData.id
                                        Qt.callLater(() => {
                                            renameInput.forceActiveFocus()
                                            renameInput.selectAll()
                                        })
                                    }
                                }
                            }

                            TapHandler {
                                acceptedButtons: Qt.MiddleButton | Qt.RightButton
                                onTapped: {
                                    if (pillCard.canDelete) {
                                        root.requestRemoveGroup(pillCard.modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    // Quick Add Pill (+ New)
                    StyledRect {
                        visible: !root.addingGroup
                        implicitHeight: 26
                        implicitWidth: addPillRow.implicitWidth + 16
                        radius: Tokens.rounding.full
                        color: "#302b2d"
                        border.width: 1
                        border.color: Qt.alpha("#ffca1b", 0.22)

                        Behavior on color { CAnim {} }
                        Behavior on border.color { CAnim {} }

                        RowLayout {
                            id: addPillRow
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialIcon {
                                text: "add"
                                fontStyle: Tokens.font.icon.small
                                color: "#ffca1b"
                            }

                            StyledText {
                                text: qsTr("New")
                                font: Tokens.font.label.medium
                                color: "#ffca1b"
                            }
                        }

                        HoverHandler { id: addHover }

                        TapHandler {
                            onTapped: {
                                root.addingGroup = true
                                root.editingGroupId = ""
                                root.deletingConfirmId = ""
                                Qt.callLater(() => newGroupTitleInput.forceActiveFocus())
                            }
                        }
                    }

                    // Inline input when adding new group
                    StyledRect {
                        id: newGroupInputPill
                        visible: root.addingGroup
                        implicitHeight: 26
                        implicitWidth: 160
                        radius: Tokens.rounding.full
                        color: "#3b3437"
                        border.width: 1.5
                        border.color: "#ffca1b"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            spacing: 4

                            TextInput {
                                id: newGroupTitleInput
                                Layout.fillWidth: true
                                font: Tokens.font.label.medium
                                color: "#ede6df"
                                selectionColor: Qt.alpha("#ffca1b", 0.4)
                                selectedTextColor: "#ffffff"
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true

                                StyledText {
                                    anchors.fill: parent
                                    visible: !newGroupTitleInput.text && !newGroupTitleInput.activeFocus
                                    text: qsTr("Note name...")
                                    font: newGroupTitleInput.font
                                    color: Qt.alpha("#ede6df", 0.45)
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onAccepted: {
                                    if (text.trim().length > 0) {
                                        root.addGroup(text.trim())
                                        text = ""
                                    } else {
                                        root.addingGroup = false
                                    }
                                }

                                Keys.onEscapePressed: {
                                    root.addingGroup = false
                                    text = ""
                                }
                            }

                            // Confirm
                            MaterialIcon {
                                text: "check"
                                fontStyle: Tokens.font.icon.small
                                color: Colours.palette.m3primary
                                visible: newGroupTitleInput.text.trim().length > 0
                                Layout.alignment: Qt.AlignVCenter

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (newGroupTitleInput.text.trim().length > 0) {
                                            root.addGroup(newGroupTitleInput.text.trim())
                                            newGroupTitleInput.text = ""
                                        }
                                    }
                                }
                            }

                            // Cancel
                            MaterialIcon {
                                text: "close"
                                fontStyle: Tokens.font.icon.small
                                color: Colours.palette.m3outline
                                Layout.alignment: Qt.AlignVCenter

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.addingGroup = false
                                        newGroupTitleInput.text = ""
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Delete active note button (Shown only when active note is custom / deletable)
            StyledRect {
                id: deleteNoteBtn
                readonly property bool canDelete: root.groups.length > 1 && root.activeNoteId !== "today"
                readonly property bool isConfirming: root.deletingConfirmId === root.activeNoteId

                visible: canDelete
                implicitWidth: isConfirming ? 74 : 26
                implicitHeight: 26
                radius: Tokens.rounding.full
                Layout.alignment: Qt.AlignVCenter
                color: isConfirming ? Qt.alpha(Colours.palette.m3error, 0.22) : "transparent"
                border.width: isConfirming ? 1 : 0
                border.color: Colours.palette.m3error

                Behavior on implicitWidth { Anim { type: Anim.FastSpatial } }
                Behavior on color { CAnim {} }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 3

                    MaterialIcon {
                        text: deleteNoteBtn.isConfirming ? "delete_forever" : "delete_outline"
                        fontStyle: Tokens.font.icon.small
                        color: deleteNoteBtn.isConfirming ? Colours.palette.m3error : Qt.alpha("#ede6df", 0.55)
                    }

                    StyledText {
                        visible: deleteNoteBtn.isConfirming
                        text: qsTr("Delete?")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3error
                    }
                }

                TapHandler {
                    onTapped: {
                        root.requestRemoveGroup(root.activeNoteId)
                    }
                }
            }

            // Chevron toggle button (Smoothly rotates 180° when expanded)
            StyledRect {
                implicitWidth: 26
                implicitHeight: 26
                radius: Tokens.rounding.full
                color: chevronHover.hovered ? Colours.tPalette.m3surfaceContainerHigh : "transparent"
                Layout.alignment: Qt.AlignVCenter

                Behavior on color { CAnim {} }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "keyboard_arrow_down"
                    fontStyle: Tokens.font.icon.small
                    color: chevronHover.hovered ? "#ffca1b" : Qt.alpha("#ede6df", 0.6)
                    rotation: root.isExpanded ? 180 : 0

                    Behavior on rotation {
                        Anim { type: Anim.FastSpatial }
                    }
                    Behavior on color { CAnim {} }
                }

                HoverHandler { id: chevronHover }

                TapHandler {
                    onTapped: {
                        root.editingGroupId = ""
                        root.deletingConfirmId = ""
                        root.isExpanded = !root.isExpanded
                    }
                }
            }
        }

        // Faint horizontal separator line (visible only when expanded)
        StyledRect {
            id: sep
            Layout.fillWidth: true
            implicitHeight: 1
            color: "#ffca1b"
            opacity: root.isExpanded ? 0.2 : 0
            visible: root.isExpanded

            Behavior on opacity { CAnim {} }
        }

        // ── Active Group Multi-Line Scratchpad (Expanded Only) ───
        Flickable {
            id: flick
            Layout.fillWidth: true
            implicitHeight: Math.min(320, Math.max(70, scratchpadInput.contentHeight + 16))
            contentWidth: width
            contentHeight: Math.max(implicitHeight, scratchpadInput.contentHeight + 16)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            visible: root.isExpanded

            function ensureVisible(r) {
                if (contentY >= r.y)
                    contentY = r.y
                else if (contentY + height <= r.y + r.height + 8)
                    contentY = r.y + r.height + 8 - height
            }

            TextEdit {
                id: scratchpadInput
                width: flick.width
                color: "#ede6df"
                font: Tokens.font.body.small
                selectionColor: Qt.alpha("#ffca1b", 0.35)
                selectedTextColor: "#ffffff"
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                renderType: TextEdit.NativeRendering

                Component.onCompleted: {
                    root.syncEditorText()
                }

                StyledText {
                    anchors.fill: parent
                    visible: !scratchpadInput.text && !scratchpadInput.activeFocus
                    text: qsTr("• Write notes for %1 here...").arg(root.currentGroup ? root.currentGroup.title : "this note")
                    font: scratchpadInput.font
                    color: Qt.alpha("#ede6df", 0.45)
                    opacity: 0.6
                }

                onCursorRectangleChanged: {
                    flick.ensureVisible(cursorRectangle)
                }

                onTextEdited: {
                    if (root.isSyncing) return
                    root.updateActiveNote(text)
                }

                onActiveFocusChanged: {
                    if (!activeFocus && root.isExpanded) {
                        root.isExpanded = false
                    }
                }

                Keys.onEscapePressed: event => {
                    focus = false
                    root.isExpanded = false
                    event.accepted = true
                }
            }
        }
    }
}
