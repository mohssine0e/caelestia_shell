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
    property int activeGroupIndex: 0
    property var groups: []
    property bool addingGroup: false

    readonly property string dataPath: Paths.home + "/daily_focus.json"

    readonly property var currentGroup: {
        if (root.groups.length === 0) return null
        var idx = Math.max(0, Math.min(root.activeGroupIndex, root.groups.length - 1))
        return root.groups[idx]
    }

    readonly property string currentNoteText: currentGroup ? (currentGroup.note || "") : ""

    // Single-line preview when collapsed (joins lines with •)
    readonly property string singleLineSummary: {
        var trimmed = root.currentNoteText.trim()
        if (!trimmed) return qsTr("Click to jot down notes for this group...")
        var lines = trimmed.split("\n").map(function(l) {
            return l.replace(/^[\s•\-\*]+/, "").trim()
        }).filter(function(l) { return l.length > 0 })
        return lines.join("  •  ")
    }

    Layout.fillWidth: true
    radius: Tokens.rounding.small
    color: Colours.tPalette.m3surfaceContainerLow
    border.width: 1
    border.color: root.isExpanded ? Qt.alpha(Colours.palette.m3primary, 0.35)
                                  : Qt.alpha(Colours.palette.m3outlineVariant, 0.3)

    implicitHeight: root.isExpanded
        ? Math.max(105, editorCol.implicitHeight + Tokens.padding.small * 2)
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
                root.isExpanded = !!raw.expanded
                root.activeGroupIndex = typeof raw.activeGroup === "number" ? raw.activeGroup : 0

                if (Array.isArray(raw.groups) && raw.groups.length > 0) {
                    root.groups = raw.groups
                } else if (raw.note !== undefined) {
                    // Backward compatibility: migrate single note
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
        root.activeGroupIndex = 0
        root.isExpanded = false
        syncEditorText()
    }

    function syncEditorText() {
        if (scratchpadInput) {
            scratchpadInput.text = root.currentNoteText
        }
    }

    onActiveGroupIndexChanged: {
        syncEditorText()
        requestSave()
    }

    Timer {
        id: saveTimer
        interval: 350
        onTriggered: {
            var payload = {
                date: new Date().toISOString().slice(0, 10),
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

    function updateCurrentGroupNote(newText) {
        if (!currentGroup) return
        var idx = Math.max(0, Math.min(root.activeGroupIndex, root.groups.length - 1))
        var copy = root.groups.slice()
        copy[idx] = Object.assign({}, copy[idx], { note: newText })
        root.groups = copy
        requestSave()
    }

    function addGroup(title) {
        var t = (title || "").trim()
        if (!t) {
            root.addingGroup = false
            return
        }
        var newGrp = {
            id: String(Date.now()),
            title: t,
            note: ""
        }
        var copy = root.groups.slice()
        copy.push(newGrp)
        root.groups = copy
        root.activeGroupIndex = copy.length - 1
        root.addingGroup = false
        root.isExpanded = true
        requestSave()
        Qt.callLater(() => {
            if (scratchpadInput) scratchpadInput.forceActiveFocus()
        })
    }

    function removeGroup(idx) {
        if (root.groups.length <= 1) return // Keep at least one
        var copy = []
        for (var i = 0; i < root.groups.length; i++) {
            if (i !== idx) copy.push(root.groups[i])
        }
        root.groups = copy
        if (root.activeGroupIndex >= root.groups.length) {
            root.activeGroupIndex = root.groups.length - 1
        }
        syncEditorText()
        requestSave()
    }

    // ═══════════════════════════════════════════════════════════════
    // COLLAPSED VIEW (Group Pills + Note Summary on 1 Line)
    // ═══════════════════════════════════════════════════════════════
    RowLayout {
        anchors {
            fill: parent
            leftMargin: Tokens.padding.medium
            rightMargin: Tokens.padding.small
        }
        visible: !root.isExpanded
        spacing: Tokens.spacing.small

        // ── Group Pills List ───────────────────────────────────────
        RowLayout {
            spacing: 4
            Layout.alignment: Qt.AlignVCenter

            MaterialIcon {
                text: "push_pin"
                fontStyle: Tokens.font.icon.small
                color: "#ffca1b"
                fill: 1
                Layout.alignment: Qt.AlignVCenter
            }

            Repeater {
                model: root.groups

                delegate: StyledRect {
                    id: pillCard
                    required property var modelData
                    required property int index
                    readonly property bool isActive: root.activeGroupIndex === index

                    implicitHeight: 26
                    implicitWidth: pillRow.implicitWidth + 16
                    radius: Tokens.rounding.full
                    color: isActive ? Qt.alpha(Colours.palette.m3primary, 0.22)
                                    : pillHover.hovered ? Colours.tPalette.m3surfaceContainerHigh
                                    : Colours.tPalette.m3surfaceContainer

                    border.width: 1
                    border.color: isActive ? Colours.palette.m3primary
                                           : Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

                    Behavior on color { CAnim {} }

                    RowLayout {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: 4

                        StyledText {
                            text: pillCard.modelData.title || qsTr("Untitled")
                            font: Tokens.font.label.medium
                            color: pillCard.isActive ? Colours.palette.m3primary
                                                     : Colours.palette.m3onSurface
                        }
                    }

                    HoverHandler { id: pillHover }

                    TapHandler {
                        onTapped: {
                            root.activeGroupIndex = pillCard.index
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
                color: addHover.hovered ? Colours.tPalette.m3surfaceContainerHigh : Colours.tPalette.m3surfaceContainer
                border.width: 1
                border.color: addHover.hovered ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

                Behavior on color { CAnim {} }
                Behavior on border.color { CAnim {} }

                RowLayout {
                    id: addPillRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialIcon {
                        text: "add"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3primary
                    }

                    StyledText {
                        text: qsTr("New")
                        font: Tokens.font.label.medium
                        color: Colours.palette.m3primary
                    }
                }

                HoverHandler { id: addHover }

                TapHandler {
                    onTapped: {
                        root.addingGroup = true
                        Qt.callLater(() => newGroupTitleInput.forceActiveFocus())
                    }
                }
            }

            // Inline input when adding new group
            StyledRect {
                id: newGroupInputPill
                visible: root.addingGroup
                implicitHeight: 26
                implicitWidth: 155
                radius: Tokens.rounding.full
                color: Colours.tPalette.m3surfaceContainerHigh
                border.width: 1.5
                border.color: Colours.palette.m3primary

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 6
                    spacing: 4

                    TextInput {
                        id: newGroupTitleInput
                        Layout.fillWidth: true
                        font: Tokens.font.label.medium
                        color: Colours.palette.m3onSurface
                        selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
                        selectedTextColor: Colours.palette.m3onSurface
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true

                        StyledText {
                            anchors.fill: parent
                            visible: !newGroupTitleInput.text && !newGroupTitleInput.activeFocus
                            text: qsTr("Group name...")
                            font: newGroupTitleInput.font
                            color: Colours.palette.m3outline
                            opacity: 0.6
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

        // Faint vertical divider
        StyledRect {
            Layout.preferredHeight: 16
            implicitWidth: 1
            color: Colours.palette.m3outlineVariant
            opacity: 0.3
            Layout.alignment: Qt.AlignVCenter
        }

        // ── Single-Line Note Preview ───────────────────────────────
        StyledText {
            Layout.fillWidth: true
            text: root.singleLineSummary
            font: Tokens.font.body.medium
            color: root.currentNoteText.trim().length > 0
                ? Colours.palette.m3onSurface
                : Colours.palette.m3outline
            opacity: root.currentNoteText.trim().length > 0 ? 1 : 0.6
            elide: Text.ElideRight
            maximumLineCount: 1
            Layout.alignment: Qt.AlignVCenter

            TapHandler {
                onTapped: {
                    root.isExpanded = true
                    root.requestSave()
                    Qt.callLater(() => scratchpadInput.forceActiveFocus())
                }
            }
        }

        // Chevron expand button
        IconButton {
            type: ButtonBase.Text
            icon: "keyboard_arrow_down"
            Layout.alignment: Qt.AlignVCenter
            onClicked: {
                root.isExpanded = true
                root.requestSave()
                Qt.callLater(() => scratchpadInput.forceActiveFocus())
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // EXPANDED VIEW (Group Switcher on Top + Seamless Scratchpad)
    // ═══════════════════════════════════════════════════════════════
    ColumnLayout {
        id: editorCol
        anchors {
            fill: parent
            margins: Tokens.padding.small
            leftMargin: Tokens.padding.medium
            rightMargin: Tokens.padding.medium
        }
        visible: root.isExpanded
        spacing: 4

        // ── Header: Group Switcher + Chevron ───────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialIcon {
                text: "push_pin"
                fontStyle: Tokens.font.icon.small
                color: "#ffca1b"
                fill: 1
                Layout.alignment: Qt.AlignVCenter
            }

            // Group pills inside expanded mode
            RowLayout {
                spacing: 4
                Layout.alignment: Qt.AlignVCenter

                Repeater {
                    model: root.groups

                    delegate: StyledRect {
                        id: expPillCard
                        required property var modelData
                        required property int index
                        readonly property bool isActive: root.activeGroupIndex === index

                        implicitHeight: 26
                        implicitWidth: expPillRow.implicitWidth + (expPillCard.modelData.id !== "today" && root.groups.length > 1 ? 24 : 16)
                        radius: Tokens.rounding.full
                        color: isActive ? Qt.alpha(Colours.palette.m3primary, 0.22)
                                        : expPillHover.hovered ? Colours.tPalette.m3surfaceContainerHigh
                                        : Colours.tPalette.m3surfaceContainer

                        border.width: 1
                        border.color: isActive ? Colours.palette.m3primary
                                               : Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

                        Behavior on color { CAnim {} }

                        RowLayout {
                            id: expPillRow
                            anchors.centerIn: parent
                            spacing: 4

                            StyledText {
                                text: expPillCard.modelData.title || qsTr("Untitled")
                                font: Tokens.font.label.medium
                                color: expPillCard.isActive ? Colours.palette.m3primary
                                                            : Colours.palette.m3onSurface
                            }

                            // Delete group button (shows for non-default groups when hovered or active)
                            MaterialIcon {
                                visible: root.groups.length > 1 && expPillCard.modelData.id !== "today" && (expPillHover.hovered || expPillCard.isActive)
                                text: "close"
                                fontStyle: Tokens.font.icon.small
                                color: Colours.palette.m3outline
                                opacity: 0.7

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.removeGroup(expPillCard.index)
                                }
                            }
                        }

                        HoverHandler { id: expPillHover }

                        TapHandler {
                            onTapped: {
                                root.activeGroupIndex = expPillCard.index
                            }
                        }
                    }
                }

                // Add button (+ New) in expanded mode
                StyledRect {
                    visible: !root.addingGroup
                    implicitHeight: 26
                    implicitWidth: expAddPillRow.implicitWidth + 16
                    radius: Tokens.rounding.full
                    color: expAddHover.hovered ? Colours.tPalette.m3surfaceContainerHigh : Colours.tPalette.m3surfaceContainer
                    border.width: 1
                    border.color: expAddHover.hovered ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

                    Behavior on color { CAnim {} }
                    Behavior on border.color { CAnim {} }

                    RowLayout {
                        id: expAddPillRow
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            text: "add"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3primary
                        }

                        StyledText {
                            text: qsTr("New")
                            font: Tokens.font.label.medium
                            color: Colours.palette.m3primary
                        }
                    }

                    HoverHandler { id: expAddHover }

                    TapHandler {
                        onTapped: {
                            root.addingGroup = true
                            Qt.callLater(() => expNewGroupTitleInput.forceActiveFocus())
                        }
                    }
                }

                // Inline input when adding new group in expanded mode
                StyledRect {
                    id: expNewGroupInputPill
                    visible: root.addingGroup
                    implicitHeight: 26
                    implicitWidth: 155
                    radius: Tokens.rounding.full
                    color: Colours.tPalette.m3surfaceContainerHigh
                    border.width: 1.5
                    border.color: Colours.palette.m3primary

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 6
                        spacing: 4

                        TextInput {
                            id: expNewGroupTitleInput
                            Layout.fillWidth: true
                            font: Tokens.font.label.medium
                            color: Colours.palette.m3onSurface
                            selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
                            selectedTextColor: Colours.palette.m3onSurface
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true

                            StyledText {
                                anchors.fill: parent
                                visible: !expNewGroupTitleInput.text && !expNewGroupTitleInput.activeFocus
                                text: qsTr("Group name...")
                                font: expNewGroupTitleInput.font
                                color: Colours.palette.m3outline
                                opacity: 0.6
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
                            visible: expNewGroupTitleInput.text.trim().length > 0
                            Layout.alignment: Qt.AlignVCenter

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (expNewGroupTitleInput.text.trim().length > 0) {
                                        root.addGroup(expNewGroupTitleInput.text.trim())
                                        expNewGroupTitleInput.text = ""
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
                                    expNewGroupTitleInput.text = ""
                                }
                            }
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            IconButton {
                type: ButtonBase.Text
                icon: "keyboard_arrow_up"
                Layout.alignment: Qt.AlignVCenter
                onClicked: {
                    root.isExpanded = false
                    root.requestSave()
                }
            }
        }

        // Faint Separator
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Colours.palette.m3outlineVariant
            opacity: 0.2
        }

        // ── Active Group Multi-Line Scratchpad ─────────────────────
        Flickable {
            id: flick
            Layout.fillWidth: true
            implicitHeight: Math.min(320, Math.max(65, scratchpadInput.contentHeight + 12))
            contentWidth: width
            contentHeight: Math.max(implicitHeight, scratchpadInput.contentHeight + 12)
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            function ensureVisible(r) {
                if (contentY >= r.y)
                    contentY = r.y
                else if (contentY + height <= r.y + r.height + 8)
                    contentY = r.y + r.height + 8 - height
            }

            TextEdit {
                id: scratchpadInput
                width: flick.width
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.medium
                selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
                selectedTextColor: Colours.palette.m3onSurface
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                renderType: TextEdit.NativeRendering

                StyledText {
                    anchors.fill: parent
                    visible: !scratchpadInput.text && !scratchpadInput.activeFocus
                    text: qsTr("• Write notes for %1 here...").arg(root.currentGroup ? root.currentGroup.title : "this group")
                    font: scratchpadInput.font
                    color: Colours.palette.m3outline
                    opacity: 0.5
                }

                onCursorRectangleChanged: {
                    flick.ensureVisible(cursorRectangle)
                }

                onTextEdited: {
                    root.updateCurrentGroupNote(text)
                }

                Keys.onEscapePressed: {
                    focus = false
                }
            }
        }
    }
}
