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

    property bool isConsolidating: false
    property string consolidateMessage: ""
    property string consolidateError: ""

    property bool isGeneratingChallenge: false
    property string challengeError: ""
    property var activeChallenge: null // { card_id, topic, type, question, criteria }

    property bool isDailyGauntletLoading: false
    property string dailyGauntletError: ""

    property bool isGrading: false
    property string gradeError: ""
    property var lastGradeResult: null // { verdict, score, strengths, blindspots, explanation, card_id, status }

    property var lastInjectedCardIds: []

    property bool isSyncingGraph: false
    property string syncGraphMessage: ""
    property string syncGraphError: ""

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

    // ── Persistent Storage & Debounced I/O ───────────────────────
    Timer {
        id: saveDebounceTimer
        interval: 300
        repeat: false
        onTriggered: root._doSave()
    }

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

    // Debounced disk save (300ms) to eliminate file I/O churn
    function save() {
        if (!memoryStorage) return
        saveDebounceTimer.restart()
    }

    function saveNow() {
        saveDebounceTimer.stop()
        root._doSave()
    }

    function _doSave() {
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

    function getCardById(id) {
        if (!root.cards || !id) return null
        const target = String(id)
        for (let i = 0; i < root.cards.length; i++) {
            if (String(root.cards[i].id) === target) return root.cards[i]
        }
        return null
    }

    function removeTrap(cardId, trapText) {
        if (!root.cards || !cardId || !trapText) return
        const list = root.cards.slice()
        for (let i = 0; i < list.length; i++) {
            if (String(list[i].id) === String(cardId)) {
                const traps = list[i].personal_traps || []
                list[i].personal_traps = traps.filter(t => t.trim() !== trapText.trim())
                list[i].updated = new Date().toISOString()
                list[i]._ts = Date.now()
                break
            }
        }
        root.cards = list
        root.save()
    }

    // ── Instant Zero-Latency Multi-Card Retrieval (0ms BM25 Ranker) ──────────────
    function getPromptInjection(query) {
        if (!root.cards || root.cards.length === 0 || !query || query.trim().length < 3) {
            root.lastInjectedCardIds = []
            return ""
        }
        const stopWords = new Set(["the", "and", "for", "with", "that", "this", "from", "how", "what", "can", "you", "does", "have", "into", "your", "code", "text", "make"])
        const rawWords = query.toLowerCase().match(/[a-z0-9_]{3,}/g) || []
        const qWords = rawWords.filter(w => !stopWords.has(w))
        if (qWords.length === 0) {
            root.lastInjectedCardIds = []
            return ""
        }

        const scored = []
        for (let i = 0; i < root.cards.length; i++) {
            const card = root.cards[i]
            if (!card) continue
            const topic = (card.topic || "").toLowerCase()
            const tags = (card.tags || []).join(" ").toLowerCase()
            const summary = (card.summary || "").toLowerCase()
            const lines = (card.lines || []).join(" ").toLowerCase()

            let score = 0
            for (let w = 0; w < qWords.length; w++) {
                const word = qWords[w]
                if (topic.indexOf(word) !== -1) score += 4
                else if (tags.indexOf(word) !== -1) score += 3
                else if (summary.indexOf(word) !== -1) score += 2
                else if (lines.indexOf(word) !== -1) score += 1
            }

            if (score >= 2) {
                scored.push({ card, score })
            }
        }

        if (scored.length === 0) {
            root.lastInjectedCardIds = []
            return ""
        }

        scored.sort((a, b) => b.score - a.score)
        const topCards = scored.slice(0, 3).map(s => s.card)
        root.lastInjectedCardIds = topCards.map(c => String(c.id))

        let context = "[ACTIVE DEVELOPER MEMORY & MASTERED CARDS - Align your response with these exact project idioms & rules]:\n"
        for (let i = 0; i < topCards.length; i++) {
            const c = topCards[i]
            const st = (c.status || "learning").toUpperCase()
            context += `• [${st}] ${c.topic}:\n`
            if (c.summary) context += `  - Core: ${c.summary}\n`
            if (c.lines && c.lines.length > 0) {
                for (let j = 0; j < Math.min(2, c.lines.length); j++) {
                    context += `  - Rule: ${c.lines[j]}\n`
                }
            }
            if (c.personal_traps && c.personal_traps.length > 0) {
                context += `  - Known trap: ${c.personal_traps[0]}\n`
            }
        }
        return context
    }

    // ── Quick Flash Card Creation from Assistant Interaction ──────
    property bool isCreatingQuickCard: false
    property string quickCardMessage: ""
    property string _quickCardBuffer: ""

    function createCardFromAssistant(sourceText, answerText, actionType) {
        if (!sourceText || !answerText || quickCardProc.running) return
        root.isCreatingQuickCard = true
        root.quickCardMessage = ""
        root._quickCardBuffer = ""
        quickCardProc.command = [
            "python3", root.enginePath, "quick_card",
            String(sourceText).slice(0, 2000),
            String(answerText).slice(0, 4000),
            String(actionType || "explain")
        ]
        quickCardProc.running = true
    }

    Process {
        id: quickCardProc
        stdout: SplitParser {
            onRead: data => {
                root._quickCardBuffer += data
            }
        }
        onExited: exitCode => {
            root.isCreatingQuickCard = false
            const fullText = root._quickCardBuffer.trim()
            root._quickCardBuffer = ""
            if (!fullText) return
            try {
                const res = JSON.parse(fullText)
                if (res.success) {
                    root.reload()
                    Toaster.toast("Flash Card Created", res.card.topic, "psychology")
                } else {
                    Toaster.toast("Card Creation Failed", res.error || "Unknown error", "error")
                }
            } catch (e) {
                console.log("[Memory] Quick card parse error:", e)
            }
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

    property string _consolidateBuffer: ""

    function consolidate(domain) {
        if (consolidateProc.running || root.isConsolidating) return
        root.isConsolidating = true
        root.consolidateMessage = "Consolidating domain knowledge..."
        root.consolidateError = ""
        root._consolidateBuffer = ""
        const cmd = ["python3", root.enginePath, "consolidate"]
        if (domain && domain.trim().length > 0) {
            cmd.push(domain.trim())
        }
        consolidateProc.command = cmd
        consolidateProc.running = true
    }

    Process {
        id: consolidateProc
        stdout: SplitParser {
            onRead: data => {
                root._consolidateBuffer += data
            }
        }
        onExited: exitCode => {
            root.isConsolidating = false
            const fullText = root._consolidateBuffer.trim()
            root._consolidateBuffer = ""
            if (!fullText) {
                if (exitCode !== 0 && !root.consolidateError) {
                    root.consolidateError = "Consolidate process exited with code " + exitCode
                }
                return
            }
            try {
                const res = JSON.parse(fullText)
                if (res.success) {
                    root.consolidateMessage = res.message || ("Consolidated into " + (res.hub_id || "hub") + " (" + (res.merged_cards_count || 0) + " merged)")
                    root.reload()
                } else {
                    root.consolidateError = res.error || "Consolidation failed."
                }
            } catch (e) {
                root.consolidateError = "Failed to parse consolidate output: " + e.message
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

    function startDailyGauntlet() {
        if (dailyGauntletProc.running || root.isGeneratingChallenge || root.isDailyGauntletLoading) return
        root.isDailyGauntletLoading = true
        root.dailyGauntletError = ""
        root._dailyGauntletBuffer = ""
        root.activeChallenge = null
        root.lastGradeResult = null
        dailyGauntletProc.command = ["python3", root.enginePath, "daily_challenge"]
        dailyGauntletProc.running = true
    }

    property string _dailyGauntletBuffer: ""

    Process {
        id: dailyGauntletProc
        stdout: SplitParser {
            onRead: data => {
                root._dailyGauntletBuffer += data
            }
        }
        onExited: exitCode => {
            root.isDailyGauntletLoading = false
            const fullText = root._dailyGauntletBuffer.trim()
            root._dailyGauntletBuffer = ""
            if (!fullText) {
                if (exitCode !== 0 && !root.dailyGauntletError) {
                    root.dailyGauntletError = "Daily gauntlet exited with code " + exitCode
                }
                return
            }
            try {
                const res = JSON.parse(fullText)
                if (res.success) {
                    root.activeChallenge = res
                } else {
                    root.dailyGauntletError = res.error || "Failed to start daily gauntlet."
                }
            } catch (e) {
                root.dailyGauntletError = "Failed to parse gauntlet JSON: " + e.message
            }
        }
    }

    function clearChallenge() {
        root.activeChallenge = null
        root.lastGradeResult = null
        root.challengeError = ""
        root.gradeError = ""
        root.dailyGauntletError = ""
    }

    // ── Knowledge Graph Synchronization ──────────────────────────
    property string _syncGraphBuffer: ""

    function syncGraph() {
        if (syncGraphProc.running || root.isSyncingGraph) return
        root.isSyncingGraph = true
        root.syncGraphError = ""
        root.syncGraphMessage = ""
        root._syncGraphBuffer = ""
        syncGraphProc.command = ["python3", root.enginePath, "sync_graph"]
        syncGraphProc.running = true
    }

    Process {
        id: syncGraphProc
        stdout: SplitParser {
            onRead: data => {
                root._syncGraphBuffer += data
            }
        }
        onExited: exitCode => {
            root.isSyncingGraph = false
            const fullText = root._syncGraphBuffer.trim()
            root._syncGraphBuffer = ""
            if (!fullText) {
                if (exitCode !== 0 && !root.syncGraphError) {
                    root.syncGraphError = "Knowledge graph sync exited with code " + exitCode
                }
                return
            }
            try {
                const res = JSON.parse(fullText)
                if (res.success) {
                    root.syncGraphMessage = res.message || "Knowledge graph synchronized."
                    root.reload()
                } else {
                    root.syncGraphError = res.error || "Failed to sync knowledge graph."
                }
            } catch (e) {
                root.syncGraphError = "Failed to parse graph JSON: " + e.message
            }
            root.reload()
        }
    }
}


