pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root
    required property var conceptView
    property string highlightBlockId: ""
    property string highlightSourceId: ""
    property int highlightSourceStart: -1
    property int highlightSourceEnd: -1
    property string activeMode: "understand"
    property bool sourcesOpen: false
    property bool showExpandedBlocks: false
    signal backRequested()

    readonly property var concept: conceptView?.concept || ({})
    readonly property var blocks: {
        const all = conceptView?.blocks || []
        const definition = String(root.concept.definition || "").trim().replace(/\s+/g, " ")
        if (!definition) return all
        return all.filter(block => block.id === root.highlightBlockId
            || String(block.content || "").trim().replace(/\s+/g, " ") !== definition)
    }
    readonly property var expandableBlocks: conceptView?.expandable_blocks || []
    readonly property var sources: conceptView?.sources || []

    function sectionFor(kind): string {
        if (kind === "command") return qsTr("COMMANDS")
        if (kind === "code") return qsTr("CODE & EXAMPLES")
        if (kind === "caveat") return qsTr("WATCH OUT")
        if (kind === "mechanism" || kind === "problem") return qsTr("HOW IT WORKS")
        if (kind === "counterexample") return qsTr("COUNTEREXAMPLE")
        if (kind === "comparison") return qsTr("COMPARE")
        if (kind === "name") return qsTr("WHY THIS NAME")
        if (kind === "why") return qsTr("WHY IT MATTERS")
        if (kind === "unplaced") return qsTr("FROM THE SOURCE")
        return qsTr("KEY POINTS")
    }
    function scrollToHighlight(): void {
        if (!root.highlightBlockId) return
        const index = root.blocks.findIndex(b => b.id === root.highlightBlockId)
        if (index >= 0) Qt.callLater(() => blocksList.positionViewAtIndex(index, ListView.Center))
    }
    onConceptViewChanged: {
        activeMode = conceptView?.mode || "understand"
        showExpandedBlocks = conceptView?.show_expanded === true
        scrollToHighlight()
    }
    onHighlightBlockIdChanged: scrollToHighlight()
    onHighlightSourceIdChanged: {
        if (highlightSourceId) {
            sourcesOpen = true
            Qt.callLater(() => {
                const index = root.sources.findIndex(s => s.id === root.highlightSourceId)
                if (index >= 0) sourceList.positionViewAtIndex(index, ListView.Beginning)
            })
        }
    }

    ColumnLayout {
        width: Math.min(Math.max(0, parent.width - 52), 900)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 18
        anchors.bottomMargin: 16
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            IconButton {
                icon: "arrow_back"
                type: ButtonBase.Text
                onClicked: root.backRequested()
            }
            StyledText {
                Layout.fillWidth: true
                text: (root.concept.topic || "") + "  /  " + (root.concept.area || "")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
            TextButton {
                text: qsTr("Understand")
                type: root.activeMode === "understand" ? ButtonBase.Tonal : ButtonBase.Text
                horizontalPadding: 10
                verticalPadding: 6
                onClicked: {
                    if (root.activeMode === "understand") return
                    root.activeMode = "understand"
                    Notes.setConceptDepth(root.concept.id, "understand")
                    Notes.getConcept(root.concept.id, "understand")
                }
            }
            TextButton {
                text: qsTr("Recall")
                type: root.activeMode === "recall" ? ButtonBase.Tonal : ButtonBase.Text
                horizontalPadding: 10
                verticalPadding: 6
                onClicked: {
                    if (root.activeMode === "recall") return
                    root.activeMode = "recall"
                    Notes.setConceptDepth(root.concept.id, "recall")
                    Notes.getConcept(root.concept.id, "recall")
                }
            }
            IconButton {
                icon: "content_copy"
                type: ButtonBase.Text
                onClicked: Notes.copyConcept(root.concept.id)
            }
        }

        ListView {
            id: blocksList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 3
            model: root.blocks

            header: Column {
                width: blocksList.width
                spacing: 9
                StyledText {
                    width: parent.width
                    text: root.concept.title || qsTr("Untitled concept")
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.title.large
                    wrapMode: Text.WordWrap
                }
                SelectableText {
                    width: parent.width
                    visible: !!root.concept.definition
                    text: root.concept.definition || ""
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                    wrapMode: TextEdit.WordWrap
                }
                Row {
                    spacing: 12
                    TextButton {
                        text: qsTr("Sources (%1)").arg(root.sources.length)
                        type: ButtonBase.Text
                        horizontalPadding: 0
                        verticalPadding: 4
                        onClicked: root.sourcesOpen = true
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.activeMode === "recall" ? qsTr("Quick review") : qsTr("Full explanation")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
                ConceptDetailActions {
                    conceptId: root.concept.id || ""
                    onExplanationAccepted: {
                        Notes.getConcept(root.concept.id, "understand")
                        Notes.listConcepts("", "")
                    }
                }
                Rectangle {
                    width: parent.width
                    height: 1
                    color: Colours.palette.m3outlineVariant
                }
                Item { width: parent.width; height: 8 }
            }

            delegate: Item {
                id: blockRow
                required property var modelData
                required property int index
                readonly property string kind: modelData.kind || "rule"
                readonly property string section: root.sectionFor(kind)
                readonly property bool firstInSection: index === 0 ||
                    root.sectionFor(root.blocks[index - 1].kind || "rule") !== section
                readonly property bool highlighted: root.highlightBlockId === modelData.id
                width: blocksList.width
                height: blockColumn.implicitHeight + 9

                Rectangle {
                    anchors.fill: parent
                    visible: blockRow.highlighted
                    radius: Tokens.rounding.small
                    color: Qt.alpha(Colours.palette.m3primary, 0.13)
                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3primary, 0.55)
                }
                Column {
                    id: blockColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: blockRow.highlighted ? 7 : 0
                    anchors.rightMargin: blockRow.highlighted ? 7 : 0
                    spacing: 8

                    StyledText {
                        visible: blockRow.firstInSection
                        text: blockRow.section
                        color: Colours.palette.m3primary
                        font: Tokens.font.label.small
                    }

                    Rectangle {
                        visible: blockRow.kind === "code" || blockRow.kind === "command"
                        width: parent.width
                        height: visible ? Math.min(260, codeColumn.implicitHeight + 20) : 0
                        radius: Tokens.rounding.small
                        color: Colours.palette.m3surfaceContainerLow
                        border.width: 1
                        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)
                        Column {
                            id: codeColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 10
                            spacing: 8
                            RowLayout {
                                width: parent.width
                                spacing: 6
                                StyledText {
                                    Layout.fillWidth: true
                                    text: blockRow.modelData.label || blockRow.modelData.explanation
                                        || (blockRow.kind === "command" ? qsTr("Command") : qsTr("Example"))
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.small
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    text: String(blockRow.modelData.language || "").toUpperCase()
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.small
                                }
                                IconButton {
                                    icon: "content_copy"
                                    type: ButtonBase.Text
                                    onClicked: Quickshell.clipboardText = blockRow.modelData.content || ""
                                }
                            }
                            Flickable {
                                width: parent.width
                                height: Math.min(198, codeText.implicitHeight)
                                contentWidth: Math.max(width, codeText.implicitWidth)
                                contentHeight: codeText.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                SelectableText {
                                    id: codeText
                                    text: blockRow.modelData.content || ""
                                    font: Tokens.font.mono.small
                                    wrapMode: TextEdit.NoWrap
                                    textFormat: TextEdit.PlainText
                                }
                            }
                        }
                    }

                    Row {
                        visible: blockRow.kind !== "code" && blockRow.kind !== "command"
                        width: parent.width
                        height: visible ? Math.max(20, prose.implicitHeight) : 0
                        spacing: 9
                        Rectangle {
                            anchors.top: parent.top
                            anchors.topMargin: 7
                            width: blockRow.kind === "caveat" ? 3 : 5
                            height: blockRow.kind === "caveat" ? Math.max(17, prose.implicitHeight - 5) : 5
                            radius: 2
                            color: blockRow.kind === "caveat" ? Colours.palette.m3tertiary : Colours.palette.m3primary
                        }
                        SelectableText {
                            id: prose
                            width: Math.max(0, parent.width - 15)
                            text: blockRow.modelData.content || ""
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.body.medium
                            wrapMode: TextEdit.WordWrap
                        }
                    }
                }
            }

            footer: Column {
                width: blocksList.width
                spacing: 7
                visible: root.activeMode === "recall" && root.expandableBlocks.length > 0
                TextButton {
                    text: root.showExpandedBlocks ? qsTr("Hide details") :
                        qsTr("Show full explanation (%1)").arg(root.expandableBlocks.length)
                    type: ButtonBase.Text
                    horizontalPadding: 0
                    onClicked: {
                        root.showExpandedBlocks = !root.showExpandedBlocks
                        Notes.setConceptExpansion(root.concept.id, root.showExpandedBlocks)
                    }
                }
                Repeater {
                    model: root.showExpandedBlocks ? root.expandableBlocks : []
                    delegate: SelectableText {
                        required property var modelData
                        width: blocksList.width
                        text: "•  " + (modelData.content || "")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.medium
                        wrapMode: TextEdit.WordWrap
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.sourcesOpen
        z: 20
        color: Qt.alpha(Colours.palette.m3scrim, 0.48)
        MouseArea { anchors.fill: parent; onClicked: root.sourcesOpen = false }
        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 10
            width: Math.min(500, parent.width * 0.75)
            radius: Tokens.rounding.medium
            color: Colours.palette.m3surfaceContainerLow
            border.width: 1
            border.color: Colours.palette.m3outlineVariant
            MouseArea { anchors.fill: parent }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Original captures")
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.title.medium
                    }
                    IconButton {
                        icon: "close"
                        type: ButtonBase.Text
                        onClicked: root.sourcesOpen = false
                    }
                }
                ListView {
                    id: sourceList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: root.sources
                    spacing: 12
                    clip: true
                    delegate: Column {
                        id: sourceRow
                        required property var modelData
                        required property int index
                        width: sourceList.width
                        spacing: 8
                        StyledText {
                            text: qsTr("Capture %1").arg(sourceRow.index + 1)
                            color: sourceRow.modelData.id === root.highlightSourceId
                                ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }
                        SelectableText {
                            id: sourceText
                            width: parent.width
                            text: sourceRow.modelData.raw_content || ""
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.body.small
                            wrapMode: TextEdit.WordWrap
                            Component.onCompleted: {
                                if (sourceRow.modelData.id !== root.highlightSourceId || root.highlightSourceStart < 0) return
                                Qt.callLater(() => {
                                    sourceText.cursorPosition = root.highlightSourceStart
                                    sourceText.select(root.highlightSourceStart, root.highlightSourceEnd)
                                    sourceList.contentY = Math.max(0, Math.min(sourceList.contentHeight - sourceList.height,
                                        sourceRow.y + sourceText.y + sourceText.cursorRectangle.y - 50))
                                })
                            }
                        }
                        Rectangle {
                            width: parent.width
                            height: 1
                            color: Colours.palette.m3outlineVariant
                        }
                    }
                }
            }
        }
    }
}
