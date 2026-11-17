pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Review and manage facts about the user. Imported facts arrive as
// candidates and are never used in a reply until they are approved here.
FocusScope {
    id: root

    property var windowRef: null
    property string filter: "candidate" // candidate | approved | archived | rejected | all
    property string editingId: ""
    property string editText: ""
    property string newText: ""
    property string newCategory: "preference"
    property string importPath: ""
    property string importSource: ""
    property string confirmDeleteSource: ""
    readonly property var categories: ["preference", "goal", "skill", "project", "background", "constraint"]
    readonly property var filtered: (UserFacts.facts || []).filter(f => root.filter === "all" || f.status === root.filter)

    signal backRequested()
    signal closeRequested()

    function categoryLabel(c) {
        const labels = {
            preference: qsTr("Preference"), goal: qsTr("Goal"), skill: qsTr("Skill"),
            project: qsTr("Project"), background: qsTr("Background"), constraint: qsTr("Constraint")
        }
        return labels[c] || c
    }

    function metaLine(f) {
        const parts = [root.categoryLabel(f.category)]
        const src = f.source || {}
        parts.push(src.kind === "manual" ? qsTr("added by you") : qsTr("from %1").arg(src.ai || src.kind))
        if (src.date_learned) parts.push(src.date_learned)
        parts.push(qsTr("%1 confidence").arg(f.confidence))
        if (f.review_after) parts.push(f.stale ? qsTr("review due since %1").arg(f.review_after) : qsTr("review %1").arg(f.review_after))
        if (f.sensitive) parts.push(qsTr("sensitive"))
        if (f.pinned) parts.push(qsTr("always used"))
        if (f.use_in_replies === false) parts.push(qsTr("not used in replies"))
        return parts.join(" · ")
    }

    function factText(id) {
        const f = (UserFacts.facts || []).find(x => x.id === id)
        return f ? f.text : id
    }

    focus: true
    implicitHeight: factsLayout.implicitHeight

    Component.onCompleted: UserFacts.reload()

    ColumnLayout {
        id: factsLayout

        anchors.fill: parent
        spacing: Tokens.spacing.medium

        // ── Header ───────────────────────────────────────────────
        Item {
            id: headerContainer
            Layout.fillWidth: true

            implicitHeight: headerRow.implicitHeight

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onPressed: if (root.windowRef) root.windowRef.startSystemMove()
            }

            RowLayout {
                id: headerRow

                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Tokens.spacing.small

                IconButton {
                    type: IconButton.Text
                    icon: "arrow_back"
                    font: Tokens.font.icon.small
                    implicitWidth: 32
                    implicitHeight: 32
                    onClicked: root.backRequested()
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Back to chat")
                }

                MaterialIcon {
                    text: "person_book"
                    fontStyle: Tokens.font.icon.medium
                    color: Colours.palette.m3primary
                }

                StyledText {
                    text: qsTr("About you")
                    font: Tokens.font.title.small
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    text: qsTr("%1 in use · %2 to review").arg(UserFacts.counts.approved || 0).arg(UserFacts.counts.candidate || 0)
                    font: Tokens.font.label.small
                    color: Colours.palette.m3outline
                }

                Item { Layout.fillWidth: true }

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

        Flickable {
            id: factsFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 200

            implicitHeight: Math.min(body.implicitHeight, 620)
            contentWidth: width
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: factsFlick
            }

            ColumnLayout {
                id: body

                width: factsFlick.width
                spacing: 10

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: qsTr("Approved facts are sent only when they fit the question, as background notes rather than instructions. Personal off sends none of them.")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                // Error / recovery
                StyledRect {
                    Layout.fillWidth: true
                    visible: UserFacts.lastError.length > 0
                    implicitHeight: errorRow.implicitHeight + 16
                    radius: Tokens.rounding.small
                    color: Qt.alpha(Colours.palette.m3error, 0.12)

                    RowLayout {
                        id: errorRow

                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: UserFacts.lastError
                            font: Tokens.font.body.small
                            color: Colours.palette.m3error
                        }

                        IconTextButton {
                            visible: UserFacts.storeState === "corrupt"
                            type: IconTextButton.Tonal
                            icon: "restore"
                            text: qsTr("Keep a copy and start fresh")
                            implicitHeight: 28
                            onClicked: UserFacts.recover()
                        }
                    }
                }

                // Filters
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { key: "candidate", label: qsTr("To review"), count: UserFacts.counts.candidate || 0 },
                            { key: "approved", label: qsTr("In use"), count: UserFacts.counts.approved || 0 },
                            { key: "archived", label: qsTr("Archived"), count: UserFacts.counts.archived || 0 },
                            { key: "rejected", label: qsTr("Rejected"), count: UserFacts.counts.rejected || 0 },
                            { key: "all", label: qsTr("All"), count: (UserFacts.facts || []).length }
                        ]

                        TextButton {
                            required property var modelData

                            type: TextButton.Tonal
                            isToggle: true
                            checked: root.filter === modelData.key
                            text: `${modelData.label} ${modelData.count}`
                            font: Tokens.font.label.small
                            onClicked: root.filter = modelData.key
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: UserFacts.staleCount > 0
                    wrapMode: Text.Wrap
                    text: qsTr("%n fact(s) in use passed their review date and are left out of replies until you confirm or edit them.", "", UserFacts.staleCount)
                    font: Tokens.font.body.small
                    color: Colours.palette.m3tertiary
                }

                // Fact list
                Repeater {
                    model: root.filtered

                    StyledRect {
                        id: factCard

                        required property var modelData
                        readonly property bool editing: root.editingId === modelData.id
                        Layout.fillWidth: true

                        implicitHeight: factCol.implicitHeight + 16
                        radius: Tokens.rounding.small
                        color: modelData.stale ? Qt.alpha(Colours.palette.m3tertiary, 0.10) : Colours.palette.m3surfaceContainerLow

                        ColumnLayout {
                            id: factCol

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 8
                            spacing: 6

                            StyledText {
                                Layout.fillWidth: true
                                visible: !factCard.editing
                                wrapMode: Text.Wrap
                                text: factCard.modelData.text
                                font: Tokens.font.body.medium
                                color: Colours.palette.m3onSurface
                            }

                            StyledTextField {
                                Layout.fillWidth: true
                                visible: factCard.editing
                                text: root.editText
                                placeholderText: qsTr("Fact text")
                                placeholderFloats: false
                                font: Tokens.font.body.small
                                onTextChanged: if (factCard.editing) root.editText = text
                            }

                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: root.metaLine(factCard.modelData)
                                font: Tokens.font.label.small
                                color: Colours.palette.m3outline
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: !!factCard.modelData.evidence
                                wrapMode: Text.Wrap
                                text: qsTr("Why: %1").arg(factCard.modelData.evidence || "")
                                font: Tokens.font.label.small
                                color: Colours.palette.m3outline
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: (factCard.modelData.conflicts_with || []).length > 0
                                wrapMode: Text.Wrap
                                text: qsTr("Disagrees with: \"%1\". Approving this one archives the old fact.")
                                    .arg((factCard.modelData.conflicts_with || []).map(id => root.factText(id)).join("\", \""))
                                font: Tokens.font.label.small
                                color: Colours.palette.m3tertiary
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                IconTextButton {
                                    visible: factCard.editing
                                    type: IconTextButton.Filled
                                    icon: "check"
                                    text: qsTr("Save")
                                    implicitHeight: 28
                                    onClicked: {
                                        UserFacts.editFact(factCard.modelData.id, { text: root.editText })
                                        root.editingId = ""
                                    }
                                }
                                IconTextButton {
                                    visible: factCard.editing
                                    type: IconTextButton.Tonal
                                    icon: "close"
                                    text: qsTr("Cancel")
                                    implicitHeight: 28
                                    onClicked: root.editingId = ""
                                }
                                IconTextButton {
                                    visible: !factCard.editing && factCard.modelData.status !== "approved"
                                    type: IconTextButton.Filled
                                    icon: "check"
                                    text: qsTr("Approve")
                                    implicitHeight: 28
                                    onClicked: UserFacts.setStatus(factCard.modelData.id, "approved")
                                }
                                IconTextButton {
                                    visible: !factCard.editing && factCard.modelData.status === "approved" && factCard.modelData.stale
                                    type: IconTextButton.Filled
                                    icon: "event_available"
                                    text: qsTr("Still true")
                                    implicitHeight: 28
                                    onClicked: UserFacts.confirmFact(factCard.modelData.id)
                                }
                                IconTextButton {
                                    visible: !factCard.editing
                                    type: IconTextButton.Tonal
                                    icon: "edit"
                                    text: qsTr("Edit")
                                    implicitHeight: 28
                                    onClicked: {
                                        root.editText = factCard.modelData.text
                                        root.editingId = factCard.modelData.id
                                    }
                                }
                                IconTextButton {
                                    visible: !factCard.editing && factCard.modelData.status === "candidate"
                                    type: IconTextButton.Tonal
                                    icon: "block"
                                    text: qsTr("Reject")
                                    implicitHeight: 28
                                    onClicked: UserFacts.setStatus(factCard.modelData.id, "rejected")
                                }
                                IconTextButton {
                                    visible: !factCard.editing && factCard.modelData.status === "approved"
                                    type: IconTextButton.Tonal
                                    icon: "archive"
                                    text: qsTr("Archive")
                                    implicitHeight: 28
                                    onClicked: UserFacts.setStatus(factCard.modelData.id, "archived")
                                }
                                IconTextButton {
                                    visible: !factCard.editing && factCard.modelData.status === "approved"
                                    type: IconTextButton.Tonal
                                    icon: factCard.modelData.use_in_replies === false ? "visibility" : "visibility_off"
                                    text: factCard.modelData.use_in_replies === false ? qsTr("Use in replies") : qsTr("Don't use")
                                    implicitHeight: 28
                                    onClicked: UserFacts.editFact(factCard.modelData.id, { use_in_replies: factCard.modelData.use_in_replies === false })
                                }
                                IconTextButton {
                                    visible: !factCard.editing && factCard.modelData.category === "preference"
                                    type: IconTextButton.Tonal
                                    icon: "push_pin"
                                    text: factCard.modelData.pinned ? qsTr("Unpin") : qsTr("Always use")
                                    implicitHeight: 28
                                    onClicked: UserFacts.editFact(factCard.modelData.id, { pinned: !factCard.modelData.pinned })
                                }
                                IconTextButton {
                                    visible: !factCard.editing
                                    type: IconTextButton.Tonal
                                    icon: "delete"
                                    text: qsTr("Delete")
                                    implicitHeight: 28
                                    onClicked: UserFacts.deleteFact(factCard.modelData.id)
                                }
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.filtered.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: root.filter === "candidate" ? qsTr("Nothing to review.") : qsTr("No facts here yet.")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3outline
                }

                // Add a fact
                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: addCol.implicitHeight + 16
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3surfaceContainer

                    ColumnLayout {
                        id: addCol

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        spacing: 6

                        StyledText {
                            text: qsTr("Add a fact")
                            font: Tokens.font.label.large
                            color: Colours.palette.m3onSurface
                        }

                        StyledTextField {
                            Layout.fillWidth: true
                            text: root.newText
                            placeholderText: qsTr("For example: Looking for a backend PFE from February 2027")
                            placeholderFloats: false
                            font: Tokens.font.body.small
                            onTextChanged: root.newText = text
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: root.categories

                                TextButton {
                                    required property string modelData

                                    type: TextButton.Tonal
                                    isToggle: true
                                    checked: root.newCategory === modelData
                                    text: root.categoryLabel(modelData)
                                    font: Tokens.font.label.small
                                    onClicked: root.newCategory = modelData
                                }
                            }

                            IconTextButton {
                                type: IconTextButton.Filled
                                icon: "add"
                                text: qsTr("Add")
                                implicitHeight: 28
                                enabled: root.newText.trim().length >= 3
                                onClicked: {
                                    UserFacts.addFact(root.newText.trim(), root.newCategory)
                                    root.newText = ""
                                }
                            }
                        }
                    }
                }

                // Import from another AI
                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: importCol.implicitHeight + 16
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3surfaceContainer

                    ColumnLayout {
                        id: importCol

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        spacing: 6

                        StyledText {
                            text: qsTr("Import from another AI")
                            font: Tokens.font.label.large
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: qsTr("A .jsonl file with one fact per line. Imported facts wait here for your review; lines that look like instructions, secrets or contact details are skipped.")
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            StyledTextField {
                                Layout.fillWidth: true
                                text: root.importPath
                                placeholderText: qsTr("~/Downloads/chatgpt_facts.jsonl")
                                placeholderFloats: false
                                font: Tokens.font.body.small
                                onTextChanged: root.importPath = text
                            }

                            StyledTextField {
                                Layout.preferredWidth: 130
                                text: root.importSource
                                placeholderText: qsTr("Source (chatgpt)")
                                placeholderFloats: false
                                font: Tokens.font.body.small
                                onTextChanged: root.importSource = text
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            IconTextButton {
                                type: IconTextButton.Tonal
                                icon: "preview"
                                text: qsTr("Check file")
                                implicitHeight: 28
                                enabled: root.importPath.trim().length > 0 && !UserFacts.busy
                                onClicked: UserFacts.previewImport(root.importPath.trim(), root.importSource.trim())
                            }

                            IconTextButton {
                                type: IconTextButton.Filled
                                icon: "download"
                                text: qsTr("Import for review")
                                implicitHeight: 28
                                enabled: !!UserFacts.lastImport && UserFacts.lastImport.success && UserFacts.lastImport.dry_run
                                    && UserFacts.lastImport.accepted > 0 && !UserFacts.busy
                                onClicked: {
                                    UserFacts.applyImport(root.importPath.trim(), root.importSource.trim())
                                    root.filter = "candidate"
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: !!UserFacts.lastImport && !!UserFacts.lastImport.success
                            wrapMode: Text.Wrap
                            text: {
                                const r = UserFacts.lastImport
                                if (!r || !r.success) return ""
                                const head = r.dry_run ? qsTr("Check: %1 new, %2 already saved, %3 disagree with approved facts, %4 skipped.")
                                                       : qsTr("Imported %1 for review. %2 already saved, %3 disagree with approved facts, %4 skipped.")
                                let line = head.arg(r.accepted).arg((r.duplicates || []).length).arg((r.conflicts || []).length).arg((r.rejected || []).length)
                                const reasons = {}
                                for (const item of (r.rejected || [])) reasons[item.reason] = (reasons[item.reason] || 0) + 1
                                const keys = Object.keys(reasons)
                                if (keys.length > 0) line += " " + qsTr("Skipped: %1.").arg(keys.map(k => `${k.replace(/_/g, " ")} ${reasons[k]}`).join(", "))
                                return line
                            }
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }

                // Per-source actions and the sensitive opt-in
                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: sourceCol.implicitHeight + 16
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3surfaceContainer

                    ColumnLayout {
                        id: sourceCol

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: qsTr("Use sensitive facts (health, relationships, feelings, money) when they fit the question")
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurface
                            }

                            StyledSwitch {
                                checked: UserFacts.includeSensitive
                                onToggled: UserFacts.setIncludeSensitive(checked)
                            }
                        }

                        Repeater {
                            model: UserFacts.sources

                            RowLayout {
                                id: sourceRow

                                required property string modelData
                                readonly property int pending: (UserFacts.facts || []).filter(f => (f.source || {}).ai === modelData && f.status === "candidate").length
                                readonly property int total: (UserFacts.facts || []).filter(f => (f.source || {}).ai === modelData).length
                                Layout.fillWidth: true

                                spacing: 6

                                StyledText {
                                    Layout.fillWidth: true
                                    text: qsTr("From %1: %2 facts, %3 to review").arg(sourceRow.modelData).arg(sourceRow.total).arg(sourceRow.pending)
                                    font: Tokens.font.body.small
                                    color: Colours.palette.m3onSurfaceVariant
                                    elide: Text.ElideRight
                                }

                                IconTextButton {
                                    visible: sourceRow.pending > 0
                                    type: IconTextButton.Tonal
                                    icon: "done_all"
                                    text: qsTr("Approve all")
                                    implicitHeight: 28
                                    onClicked: UserFacts.approveSource(sourceRow.modelData)
                                }

                                IconTextButton {
                                    type: IconTextButton.Tonal
                                    icon: "delete_sweep"
                                    text: root.confirmDeleteSource === sourceRow.modelData ? qsTr("Confirm delete") : qsTr("Delete all")
                                    implicitHeight: 28
                                    onClicked: {
                                        if (root.confirmDeleteSource === sourceRow.modelData) {
                                            UserFacts.deleteSource(sourceRow.modelData)
                                            root.confirmDeleteSource = ""
                                        } else {
                                            root.confirmDeleteSource = sourceRow.modelData
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
