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

    signal closeRequested()
    signal moveRequested()

    property string viewMode: "index" // "index" | "concept" | "search" | "legacy"
    property string selectedTopic: "Java"
    property string selectedArea: "All"
    property string activeConceptId: ""
    property string highlightBlockId: ""
    property var historyStack: []

    // Distinct list of topics
    readonly property var availableTopics: {
        const set = new Set(["Java", "Git", "Docker", "RabbitMQ"])
        for (const c of Notes.concepts || []) {
            if (c.topic) set.add(c.topic)
        }
        for (const n of Notes.notes || []) {
            if (n.topic && n.category !== "noise" && n.keep_decision !== "skip") {
                set.add(n.topic)
            }
        }
        return Array.from(set)
    }

    // Distinct list of areas for current topic
    readonly property var availableAreas: {
        const set = new Set(["All"])
        for (const c of Notes.concepts || []) {
            if ((c.topic || "").toLowerCase() === win.selectedTopic.toLowerCase() && c.area) {
                set.add(c.area)
            }
        }
        return Array.from(set)
    }

    function pushHistory(): void {
        win.historyStack.push({
            viewMode: win.viewMode,
            topic: win.selectedTopic,
            area: win.selectedArea,
            conceptId: win.activeConceptId,
            highlightBlockId: win.highlightBlockId
        })
    }

    function popHistory(): void {
        if (win.historyStack.length > 0) {
            const prev = win.historyStack.pop()
            win.selectedTopic = prev.topic
            win.selectedArea = prev.area
            win.activeConceptId = prev.conceptId
            win.highlightBlockId = prev.highlightBlockId
            win.viewMode = prev.viewMode
            if (win.viewMode === "concept" && win.activeConceptId) {
                Notes.getConcept(win.activeConceptId, "")
            }
        } else {
            win.viewMode = "index"
            win.highlightBlockId = ""
        }
    }

    function openConcept(concept, blockId): void {
        win.pushHistory()
        win.activeConceptId = concept.id || concept.concept_id
        win.highlightBlockId = blockId || ""
        if (concept.topic) win.selectedTopic = concept.topic
        if (concept.area) win.selectedArea = concept.area
        Notes.getConcept(win.activeConceptId, "")
        win.viewMode = "concept"
    }

    Component.onCompleted: {
        Notes.syncLegacyNotes()
        Notes.listConcepts(win.selectedTopic, "")
    }

    onSelectedTopicChanged: {
        win.selectedArea = "All"
        Notes.listConcepts(win.selectedTopic, "")
        if (win.viewMode !== "search" && win.viewMode !== "legacy") {
            win.viewMode = "index"
        }
    }

    onSelectedAreaChanged: {
        if (win.viewMode !== "search" && win.viewMode !== "legacy") {
            win.viewMode = "index"
        }
    }

    // Focus & Global Keys Handling
    focus: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Slash && win.viewMode !== "search") {
            event.accepted = true
            win.pushHistory()
            win.viewMode = "search"
        } else if (event.key === Qt.Key_Escape) {
            event.accepted = true
            if (win.viewMode === "search" || win.viewMode === "concept") {
                win.popHistory()
            } else {
                win.closeRequested()
            }
        }
    }

    // Main Layout
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // 1. Top Handbook Navigation Strip
        HandbookNav {
            id: nav
            Layout.fillWidth: true
            selectedTopic: win.selectedTopic
            selectedArea: win.selectedArea
            topics: win.availableTopics
            areas: win.availableAreas
            searchActive: win.viewMode === "search"
            isLegacyActive: win.viewMode === "legacy"

            onTopicSelected: topic => win.selectedTopic = topic
            onAreaSelected: area => win.selectedArea = area
            onSearchToggled: {
                if (win.viewMode === "search") {
                    win.popHistory()
                } else {
                    win.pushHistory()
                    win.viewMode = "search"
                }
            }
            onLegacyToggled: {
                win.viewMode = (win.viewMode === "legacy") ? "index" : "legacy"
            }
            onCloseRequested: win.closeRequested()
            onMoveRequested: win.moveRequested()
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Colours.palette.m3outlineVariant
        }

        // 2. View Mode Content Container
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // View 1: Concept Index
            ConceptIndex {
                anchors.fill: parent
                visible: win.viewMode === "index"
                topic: win.selectedTopic
                area: win.selectedArea
                concepts: Notes.concepts
                onConceptSelected: concept => win.openConcept(concept, "")
            }

            // View 2: Concept Page (Understand vs Recall)
            ConceptPage {
                id: conceptPage
                anchors.fill: parent
                visible: win.viewMode === "concept" && Notes.currentConceptView !== null
                conceptView: Notes.currentConceptView
                highlightBlockId: win.highlightBlockId
                onBackRequested: win.popHistory()
            }

            // View 3: Search Results
            HandbookSearchResults {
                id: searchResultsView
                anchors.fill: parent
                visible: win.viewMode === "search"
                results: Notes.searchResults
                onResultSelected: result => win.openConcept({ id: result.concept_id, topic: result.topic, area: result.area }, result.block_id)
                onCloseSearchRequested: win.popHistory()
            }

            // View 4: Legacy Review Adapter (P0.4 fallback)
            NotesViewLegacy {
                id: legacyReview
                anchors.fill: parent
                visible: win.viewMode === "legacy"
                onCloseRequested: win.closeRequested()
                onMoveRequested: win.moveRequested()
            }
        }
    }
}
