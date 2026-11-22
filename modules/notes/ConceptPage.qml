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

    function displayArea(value): string {
        return String(value || "").trim()
    }

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

    component SectionHeading: RowLayout {
        id: sectionHeading
        required property string text
        width: parent ? parent.width : implicitWidth
        spacing: 9
        StyledText {
            text: sectionHeading.text
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.alpha(Colours.palette.m3outlineVariant, 0.42)
        }
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
        width: Math.min(Math.max(0, parent.width - 44), 1120)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            IconButton {
                icon: "arrow_back"
                type: ButtonBase.Text
                onClicked: root.backRequested()
            }
            StyledText {
                Layout.fillWidth: true
                text: (root.concept.topic || "") + "  /  " + root.displayArea(root.concept.area)
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
            spacing: 2
            model: root.blocks

            header: Column {
                width: blocksList.width
                    spacing: 7
                StyledText {
                    width: parent.width
                    text: root.concept.title || qsTr("Untitled concept")
                    color: Colours.palette.m3onSurface
                    font: Qt.font({ family: Tokens.font.title.large.family, pixelSize: 24,
                        weight: Font.DemiBold })
                    wrapMode: Text.WordWrap
                }
                SelectableText {
                    width: parent.width
                    visible: !!root.concept.definition
                    text: root.concept.definition || ""
                    color: Colours.palette.m3onSurfaceVariant
                    font: Qt.font({ family: Tokens.font.body.medium.family, pixelSize: 14,
                        weight: Tokens.font.body.medium.weight })
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
                GapSuggestions {
                    scope: "concept"
                    topic: root.concept.topic || ""
                    area: root.concept.area || ""
                    conceptId: root.concept.id || ""
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
                property bool codeExpanded: false
                property bool copied: false
                width: blocksList.width
                height: blockColumn.implicitHeight + 9
                onHighlightedChanged: {
                    if (highlighted && kind === "code") codeExpanded = true
                }

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

                    SectionHeading {
                        visible: blockRow.firstInSection
                        text: blockRow.section
                    }

                    Rectangle {
                        visible: blockRow.kind === "code" || blockRow.kind === "command"
                        width: parent.width
                        height: visible ? codeColumn.implicitHeight + 14 : 0
                        radius: 7
                        color: Colours.palette.m3surfaceContainerLow
                        Column {
                            id: codeColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 7
                            spacing: 4
                            RowLayout {
                                id: snippetHeader
                                width: parent.width
                                spacing: 7
                                Rectangle {
                                    visible: !!blockRow.modelData.language
                                    radius: 4
                                    color: Qt.alpha(Colours.palette.m3primary, 0.15)
                                    implicitWidth: codeLanguage.implicitWidth + 10
                                    implicitHeight: 20
                                    StyledText {
                                        id: codeLanguage
                                        anchors.centerIn: parent
                                        text: String(blockRow.modelData.language || "").toUpperCase()
                                        color: Colours.palette.m3primary
                                        font: Qt.font({ family: Tokens.font.mono.small.family, pixelSize: 10,
                                            weight: Font.Bold })
                                    }
                                }
                                SelectableText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: blockRow.modelData.explanation || blockRow.modelData.label
                                        || (blockRow.kind === "command" ? qsTr("Command") : qsTr("Example"))
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Qt.font({ family: Tokens.font.body.small.family, pixelSize: 12,
                                        weight: Tokens.font.body.small.weight })
                                    wrapMode: TextEdit.NoWrap
                                }
                                Item {
                                    id: snippetCopy
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    opacity: snippetCopyMouse.containsMouse || blockRow.copied ? 1 : 0.45
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        text: blockRow.copied ? "check" : "content_copy"
                                        color: Colours.palette.m3onSurfaceVariant
                                        fill: 0
                                        fontStyle: Tokens.font.icon.size(12).build()
                                    }
                                    MouseArea {
                                        id: snippetCopyMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            Quickshell.clipboardText = blockRow.modelData.content || ""
                                            blockRow.copied = true
                                        }
                                    }
                                    Timer {
                                        interval: 1200
                                        running: blockRow.copied
                                        onTriggered: blockRow.copied = false
                                    }
                                }
                                TapHandler {
                                    target: null
                                    enabled: blockRow.kind === "code"
                                    onTapped: point => {
                                        if (point.position.x < snippetHeader.width - snippetCopy.width - 7)
                                            blockRow.codeExpanded = !blockRow.codeExpanded
                                    }
                                }
                            }
                            Flickable {
                                visible: blockRow.kind !== "code" || blockRow.codeExpanded
                                width: parent.width
                                height: visible ? Math.min(198, codeText.implicitHeight) : 0
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
                            font: Qt.font({ family: Tokens.font.body.medium.family, pixelSize: 14,
                                weight: Tokens.font.body.medium.weight })
                            wrapMode: TextEdit.WordWrap
                        }
                    }
                    StyledText {
                        width: parent.width
                        visible: blockRow.modelData.evidence_status === "unverified"
                            || !!blockRow.modelData.applicability
                        text: (blockRow.modelData.evidence_status === "unverified"
                            ? qsTr("Unverified") : "")
                            + (blockRow.modelData.applicability
                                ? (blockRow.modelData.evidence_status === "unverified" ? " · " : "")
                                    + blockRow.modelData.applicability : "")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                        wrapMode: Text.WordWrap
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
                        font: Qt.font({ family: Tokens.font.body.medium.family, pixelSize: 14,
                            weight: Tokens.font.body.medium.weight })
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
