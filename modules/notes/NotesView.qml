pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: win
    signal closeRequested()
    signal moveRequested()

    property string viewMode: "index" // index | concept | search | legacy
    property string selectedTopic: "All"
    property string selectedArea: "All"
    property string activeConceptId: ""
    property string highlightBlockId: ""
    property string highlightSourceId: ""
    property int highlightSourceStart: -1
    property int highlightSourceEnd: -1
    property string searchQuery: ""
    property var historyStack: []

    readonly property var availableTopics: {
        const names = new Map()
        for (const c of Notes.concepts || []) {
            const name = String(c.topic || "").trim()
            if (name) names.set(name.toLowerCase(), name)
        }
        return ["All"].concat(Array.from(names.values()).sort((a, b) => a.localeCompare(b)))
    }
    readonly property var availableAreas: {
        if (win.selectedTopic === "All") return ["All"]
        const names = new Map()
        for (const c of Notes.concepts || []) {
            if (String(c.topic || "").toLowerCase() !== win.selectedTopic.toLowerCase()) continue
            const name = String(c.area || "").trim()
            if (name) names.set(name.toLowerCase(), name)
        }
        return ["All"].concat(Array.from(names.values()).sort((a, b) => a.localeCompare(b)))
    }
    readonly property var unseenMap: {
        const map = ({})
        for (const c of Notes.concepts || [])
            if (c.unseen) map[String(c.topic || "").toLowerCase()] = true
        return map
    }
    readonly property var unseenAreas: {
        const map = ({})
        for (const c of Notes.concepts || []) {
            if (c.unseen && String(c.topic || "").toLowerCase() === win.selectedTopic.toLowerCase())
                map[String(c.area || "").toLowerCase()] = true
        }
        return map
    }

    function pushHistory(): void {
        win.historyStack = win.historyStack.concat([{
            viewMode: win.viewMode, topic: win.selectedTopic, area: win.selectedArea,
            conceptId: win.activeConceptId, blockId: win.highlightBlockId,
            sourceId: win.highlightSourceId,
            sourceStart: win.highlightSourceStart, sourceEnd: win.highlightSourceEnd
        }])
    }
    function popHistory(): void {
        if (!win.historyStack.length) {
            win.viewMode = "index"
            return
        }
        const stack = win.historyStack.slice()
        const previous = stack.pop()
        win.historyStack = stack
        win.selectedTopic = previous.topic
        win.selectedArea = previous.area
        win.activeConceptId = previous.conceptId
        win.highlightBlockId = previous.blockId
        win.highlightSourceId = previous.sourceId
        win.highlightSourceStart = previous.sourceStart
        win.highlightSourceEnd = previous.sourceEnd
        win.viewMode = previous.viewMode
        if (previous.viewMode === "concept" && previous.conceptId)
            Notes.getConcept(previous.conceptId, "")
    }
    function chooseTopic(topic): void {
        win.selectedTopic = topic
        win.selectedArea = "All"
        win.viewMode = "index"
    }
    function openConcept(concept, blockId, sourceId, sourceStart, sourceEnd): void {
        const id = String(concept.id || concept.concept_id || "")
        if (!id) return
        win.pushHistory()
        win.activeConceptId = id
        win.highlightBlockId = blockId || ""
        win.highlightSourceId = sourceId || ""
        win.highlightSourceStart = sourceStart === undefined ? -1 : sourceStart
        win.highlightSourceEnd = sourceEnd === undefined ? -1 : sourceEnd
        if (concept.topic) win.selectedTopic = concept.topic
        if (concept.area) win.selectedArea = concept.area
        win.viewMode = "concept"
        Notes.getConcept(id, blockId ? "understand" : "")
    }
    function startSearch(): void {
        if (win.viewMode !== "search") {
            win.pushHistory()
            win.viewMode = "search"
        }
    }

    focus: true
    Component.onCompleted: Notes.listConcepts("", "")
    onVisibleChanged: if (visible) Notes.listConcepts("", "")

    Connections {
        target: Notes
        function onConceptViewLoaded(view): void {
            if (win.viewMode === "concept" && view.concept?.id === win.activeConceptId)
                Notes.markConceptSeen(win.activeConceptId)
        }
    }

    Timer {
        id: searchDebounce
        interval: 180
        onTriggered: Notes.searchConcepts(win.searchQuery)
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Slash && win.viewMode !== "legacy") {
            nav.focusSearch()
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            if (conceptPage.sourcesOpen) {
                conceptPage.sourcesOpen = false
            } else if (nav.releaseSearchFocus()) {
                // The next Escape leaves search or closes the window.
            } else if (win.viewMode === "concept" || win.viewMode === "search" || win.viewMode === "legacy") {
                win.popHistory()
            } else {
                win.closeRequested()
            }
            event.accepted = true
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Tokens.rounding.medium
        color: Colours.palette.m3surface
        border.width: 1
        border.color: Colours.palette.m3outlineVariant
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        HandbookNav {
            id: nav
            Layout.fillWidth: true
            selectedTopic: win.selectedTopic
            selectedArea: win.selectedArea
            topics: win.availableTopics
            areas: win.availableAreas
            unseenMap: win.unseenMap
            unseenAreas: win.unseenAreas
            searchText: win.searchQuery
            isLegacyActive: win.viewMode === "legacy"
            onTopicSelected: topic => win.chooseTopic(topic)
            onAreaSelected: area => {
                win.selectedArea = area
                win.viewMode = "index"
            }
            onSearchRequested: win.startSearch()
            onSearchEdited: query => {
                win.searchQuery = query
                win.startSearch()
                searchDebounce.restart()
            }
            onLegacyToggled: {
                if (win.viewMode === "legacy") win.popHistory()
                else {
                    win.pushHistory()
                    win.viewMode = "legacy"
                }
            }
            onCloseRequested: win.closeRequested()
            onMoveRequested: win.moveRequested()
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Colours.palette.m3outlineVariant
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            ConceptIndex {
                anchors.fill: parent
                visible: win.viewMode === "index"
                topic: win.selectedTopic
                area: win.selectedArea
                concepts: Notes.concepts
                onConceptSelected: concept => win.openConcept(concept, "", "")
            }
            ConceptPage {
                id: conceptPage
                anchors.fill: parent
                visible: win.viewMode === "concept" && Notes.currentConceptView?.concept?.id === win.activeConceptId
                conceptView: Notes.currentConceptView
                highlightBlockId: win.highlightBlockId
                highlightSourceId: win.highlightSourceId
                highlightSourceStart: win.highlightSourceStart
                highlightSourceEnd: win.highlightSourceEnd
                onBackRequested: win.popHistory()
            }
            HandbookSearchResults {
                anchors.fill: parent
                visible: win.viewMode === "search"
                query: win.searchQuery
                results: Notes.searchResults
                onResultSelected: result => win.openConcept({
                    id: result.concept_id, topic: result.topic, area: result.area
                }, result.block_id, result.source_note_id, result.source_start, result.source_end)
            }
            Loader {
                anchors.fill: parent
                active: win.viewMode === "legacy"
                sourceComponent: NotesViewLegacy {
                    onCloseRequested: win.closeRequested()
                    onMoveRequested: win.moveRequested()
                }
            }
            Column {
                anchors.centerIn: parent
                spacing: 8
                visible: win.viewMode === "index" && Notes.concepts.length === 0 &&
                    Notes.notes.some(n => n.category === "technical" || n.category === "reference")
                TextButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Build handbook from saved captures")
                    type: ButtonBase.Tonal
                    onClicked: Notes.syncLegacyNotes()
                }
            }
        }
    }
}
