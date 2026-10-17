pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.services

Singleton {
    id: root

    // ── State ────────────────────────────────────────────────────
    property var cards: []
    readonly property string memoryPath: Quickshell.env("HOME") + "/.config/caelestia/assistant_memory.json"
    readonly property string enginePath: Quickshell.env("HOME") + "/.config/quickshell/caelestia/scripts/memory_engine.py"

    property bool isDistilling: false
    property string distillMessage: ""
    property string distillError: ""

    property bool isGeneratingChallenge: false
    property string challengeError: ""
    property var activeChallenge: null // { card_id, topic, type, question, criteria }

    property bool isGrading: false
    property string gradeError: ""
    property var lastGradeResult: null // { verdict, score, strengths, blindspots, explanation, card_id, status }

    property bool _isSaving: false

    // Statistics
    readonly property int totalCount: cards ? cards.length : 0
    readonly property int masteredCount: {
        if (!cards) return 0
        let c = 0
        for (let i = 0; i < cards.length; i++) {
            if (cards[i] && cards[i].status === "mastered") c++
        }
        return c
    }
    readonly property int learningCount: totalCount - masteredCount

    // ── Persistent Storage ───────────────────────────────────────
    FileView {
        id: memoryStorage
        printErrors: false
        path: root.memoryPath
        onLoaded: {
            if (root._isSaving) return
            try {
                const parsed = JSON.parse(text())
                if (Array.isArray(parsed)) {
                    for (let i = 0; i < parsed.length; i++) {
                        const c = parsed[i]
                        let ts = 0
                        if (c.updated) {
                            const t = Date.parse(c.updated)
                            if (!isNaN(t)) ts = Math.max(ts, t)
                        }
                        if (c.created) {
                            const t = Date.parse(c.created)
                            if (!isNaN(t)) ts = Math.max(ts, t)
                        }
                        c._ts = ts
                    }
                    root.cards = parsed
                }
            } catch (e) {
                root.cards = []
            }
        }
        onLoadFailed: err => {
            if (root._isSaving) return
            root.cards = []
            if (err === FileViewError.FileNotFound) {
                Qt.callLater(() => memoryStorage.setText("[]"))
            }
        }
    }

    function reload() {
        if (memoryStorage) memoryStorage.reload()
    }

    function save() {
        if (!memoryStorage) return
        root._isSaving = true
        memoryStorage.setText(JSON.stringify(root.cards, null, 2))
        Qt.callLater(() => { root._isSaving = false })
    }

    function updateCard(id, updatedLines, updatedTopic) {
        if (!root.cards) return
        const list = root.cards.slice()
        for (let i = 0; i < list.length; i++) {
            if (String(list[i].id) === String(id)) {
                list[i].lines = updatedLines
                if (updatedTopic !== undefined && updatedTopic.trim().length > 0) {
                    list[i].topic = updatedTopic.trim()
                }
                list[i].updated = new Date().toISOString()
                list[i]._ts = Date.now()
                break
            }
        }
        root.cards = list
        root.save()
    }

    function deleteCard(id) {
        if (!root.cards) return
        root.cards = root.cards.filter(c => String(c.id) !== String(id))
        root.save()
    }

    // ── Instant Zero-Latency Keyword Matching (0ms) ──────────────
    function getPromptInjection(query) {
        if (!root.cards || root.cards.length === 0 || !query || query.trim().length < 3) {
            return ""
        }
        const qWords = query.toLowerCase().match(/[a-z0-9_]{3,}/g) || []
        if (qWords.length === 0) return ""

        let bestCard = null
        let bestScore = 0

        for (let i = 0; i < root.cards.length; i++) {
            const card = root.cards[i]
            if (!card) continue
            const topic = (card.topic || "").toLowerCase()
            const tags = (card.tags || []).join(" ").toLowerCase()
            const lines = (card.lines || []).slice(0, 3).join(" ").toLowerCase()
            const combined = topic + " " + tags + " " + lines

            let shared = 0
            for (let w = 0; w < qWords.length; w++) {
                if (combined.indexOf(qWords[w]) !== -1) shared++
            }
            const score = shared / qWords.length
            if (score > bestScore && score >= 0.4) {
                bestScore = score
                bestCard = card
            }
        }

        if (!bestCard) return ""

        const status = (bestCard.status || "learning").toUpperCase()
        const topic = bestCard.topic || ""
        const summary = (bestCard.lines && bestCard.lines.length > 0) ? bestCard.lines[0] : ""

        if (status === "MASTERED") {
            return "[Mastery Grounding: User has MASTERED '" + topic + "'. Principle: '" + summary + "'. Skip introductory basics; provide concise, advanced code.]"
        } else {
            return "[Learning Grounding: User is LEARNING '" + topic + "'. Active concept: '" + summary + "'. Provide clear intuitive breakdown.]"
        }
    }

    // ── Process Operations (CLI Bridge) ──────────────────────────
    property string _distillBuffer: ""
    property string _challengeBuffer: ""
    property string _gradeBuffer: ""
    property string _enrichBuffer: ""

    property bool isEnriching: false
    property string enrichingCardId: ""
    property string enrichError: ""

    function enrichCard(cardId) {
        if (!cardId || enrichProc.running) return
        root.isEnriching = true
        root.enrichingCardId = String(cardId)
        root.enrichError = ""
        root._enrichBuffer = ""
        enrichProc.command = ["python3", root.enginePath, "enrich", String(cardId)]
        enrichProc.running = true
    }

    Process {
        id: enrichProc
        stdout: SplitParser {
            onRead: data => {
                root._enrichBuffer += data
            }
        }
        onExited: exitCode => {
            root.isEnriching = false
            root.enrichingCardId = ""
            const fullText = root._enrichBuffer.trim()
            root._enrichBuffer = ""
            if (!fullText) {
                if (exitCode !== 0 && !root.enrichError) {
                    root.enrichError = "Enrich process exited with code " + exitCode
                }
                return
            }
            try {
                const res = JSON.parse(fullText)
                if (res.success) {
                    root.reload()
                } else {
                    root.enrichError = res.error || "Failed to enrich card."
                }
            } catch (e) {
                root.enrichError = "Failed to parse enrich JSON: " + e.message
            }
        }
    }

    function distill() {
        if (distillProc.running) return
        root.isDistilling = true
        root.distillMessage = "Distilling new cards..."
        root.distillError = ""
        root._distillBuffer = ""
        distillProc.command = ["python3", root.enginePath, "distill"]
        distillProc.running = true
    }

    Process {
        id: distillProc
        stdout: SplitParser {
            onRead: data => {
                root._distillBuffer += data
            }
        }
        onExited: exitCode => {
            root.isDistilling = false
            const fullText = root._distillBuffer.trim()
            root._distillBuffer = ""
            if (!fullText) {
                if (exitCode !== 0 && !root.distillError) {
                    root.distillError = "Distill process exited with code " + exitCode
                }
                return
            }
            try {
                const res = JSON.parse(fullText)
                if (res.success) {
                    root.distillMessage = "Distilled " + (res.new_cards || 0) + " new, " + (res.updated_cards || 0) + " updated."
                    root.reload()
                } else {
                    root.distillError = res.error || "Distill failed."
                }
            } catch (e) {
                root.distillError = "Failed to parse distill output: " + e.message
            }
            root.reload()
        }
    }

    function startChallenge(cardId) {
        if (!cardId || challengeProc.running) return
        root.isGeneratingChallenge = true
        root.challengeError = ""
        root.activeChallenge = null
        root.lastGradeResult = null
        root._challengeBuffer = ""
        challengeProc.command = ["python3", root.enginePath, "challenge", String(cardId)]
        challengeProc.running = true
    }

    Process {
        id: challengeProc
        stdout: SplitParser {
            onRead: data => {
                root._challengeBuffer += data
            }
        }
        onExited: exitCode => {
            root.isGeneratingChallenge = false
            const fullText = root._challengeBuffer.trim()
            root._challengeBuffer = ""
            if (!fullText) {
                if (exitCode !== 0 && !root.challengeError) {
                    root.challengeError = "Challenge process exited with code " + exitCode
                }
                return
            }
            try {
                const res = JSON.parse(fullText)
                if (res.success) {
                    root.activeChallenge = res
                } else {
                    root.challengeError = res.error || "Failed to generate challenge."
                }
            } catch (e) {
                root.challengeError = "Failed to parse challenge JSON: " + e.message
            }
        }
    }

    function submitAnswer(cardId, answersData) {
        if (!cardId || !answersData || gradeProc.running) return
        root.isGrading = true
        root.gradeError = ""
        root.lastGradeResult = null
        root._gradeBuffer = ""
        const arg = (typeof answersData === "string") ? answersData : JSON.stringify(answersData)
        gradeProc.command = ["python3", root.enginePath, "grade", String(cardId), arg]
        gradeProc.running = true
    }

    Process {
        id: gradeProc
        stdout: SplitParser {
            onRead: data => {
                root._gradeBuffer += data
            }
        }
        onExited: exitCode => {
            root.isGrading = false
            const fullText = root._gradeBuffer.trim()
            root._gradeBuffer = ""
            if (!fullText) {
                if (exitCode !== 0 && !root.gradeError) {
                    root.gradeError = "Grading process exited with code " + exitCode
                }
                return
            }
            try {
                const res = JSON.parse(fullText)
                if (res.success) {
                    root.lastGradeResult = res
                    root.reload()
                } else {
                    root.gradeError = res.error || "Grading failed."
                }
            } catch (e) {
                root.gradeError = "Failed to parse grade JSON: " + e.message
            }
            root.reload()
        }
    }

    function clearChallenge() {
        root.activeChallenge = null
        root.lastGradeResult = null
        root.challengeError = ""
        root.gradeError = ""
    }
}

