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
    property var proposals: []
    readonly property string proposalsPath: Quickshell.env("HOME") + "/.config/caelestia/assistant_memory_proposals.json"
    property string memoryStoreState: "checking" // checking | healthy | backup_pending | blocked | backup_failed
    property string memoryBackupPath: ""
    property string memoryRecoveryError: ""
    readonly property bool memoryWritesAllowed: memoryStoreState === "healthy"
    readonly property string memoryPath: Quickshell.env("HOME") + "/.config/caelestia/assistant_memory.json"
    readonly property string learnerProfilePath: Quickshell.env("HOME") + "/.config/caelestia/learner_profile.json"
    readonly property string enginePath: Quickshell.env("HOME") + "/.config/quickshell/caelestia/scripts/memory_engine.py"

    property var learnerProfile: null

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
    readonly property int dueCount: {
        if (!cards || cards.length === 0) return 0
        const now = Date.now()
        let cnt = 0
        for (let i = 0; i < cards.length; i++) {
            const c = cards[i]
            if (!c || c.type !== "knowledge") continue
            const nr = (c.srs_data && c.srs_data.next_review) || c.next_review
            if (nr) {
                const t = Date.parse(nr)
                if (!isNaN(t) && t <= now) cnt++
            }
        }
        return cnt
    }

    function startDueChallenge() {
        const now = Date.now()
        let targetId = ""
        for (let i = 0; i < cards.length; i++) {
            const c = cards[i]
            if (!c || c.type !== "knowledge") continue
            const nr = (c.srs_data && c.srs_data.next_review) || c.next_review
            if (nr) {
                const t = Date.parse(nr)
                if (!isNaN(t) && t <= now) {
                    targetId = c.id
                    break
                }
            }
        }
        if (targetId) {
            root.startChallenge(targetId)
        } else {
            root.startDailyGauntlet()
        }
    }

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
                    root.memoryStoreState = "healthy"
                    root.memoryBackupPath = ""
                    root.memoryRecoveryError = ""
                } else {
                    root.cards = []
                    root.beginMemoryRecovery()
                }
            } catch (e) {
                root.cards = []
                root.beginMemoryRecovery()
            }
        }
        onLoadFailed: err => {
            if (root._isSaving) return
            root.cards = []
            if (err === FileViewError.FileNotFound) {
                root.memoryStoreState = "healthy"
                Qt.callLater(() => memoryStorage.setText("[]"))
            } else {
                root.beginMemoryRecovery()
            }
        }
    }

    function beginMemoryRecovery() {
        if (root.memoryStoreState === "backup_pending" || root.memoryStoreState === "blocked") return
        root.memoryStoreState = "backup_pending"
        root.memoryRecoveryError = ""
        memoryRecoveryProc.command = ["python3", root.enginePath, "inspect_memory"]
        memoryRecoveryProc.running = true
    }

    function handleMemoryRecoveryResult(raw) {
        try {
            const result = JSON.parse(String(raw || "").trim())
            if (result.status === "ok") {
                root.memoryStoreState = "healthy"
                root.memoryStorage.reload()
            } else if (result.status === "corrupt" && result.backup_path) {
                root.memoryBackupPath = result.backup_path
                root.memoryStoreState = "blocked"
            } else {
                root.memoryRecoveryError = result.error || qsTr("Could not preserve the unreadable memory file.")
                root.memoryStoreState = "backup_failed"
            }
        } catch (e) {
            root.memoryRecoveryError = qsTr("Could not verify or back up the unreadable memory file.")
            root.memoryStoreState = "backup_failed"
        }
    }

    function acceptMemoryRecovery() {
        if (root.memoryStoreState !== "blocked" || !root.memoryBackupPath) return
        root.cards = []
        root.memoryStoreState = "healthy"
        root.saveNow()
    }

    Process {
        id: memoryRecoveryProc
        stdout: StdioCollector {
            id: memoryRecoveryOutput
            onStreamFinished: root.handleMemoryRecoveryResult(memoryRecoveryOutput.text)
        }
        onExited: code => {
            if (code !== 0 && root.memoryStoreState === "backup_pending") {
                root.memoryRecoveryError = qsTr("The backup helper could not complete.")
                root.memoryStoreState = "backup_failed"
            }
        }
    }

    FileView {
        id: learnerProfileStorage
        printErrors: false
        path: root.learnerProfilePath
        onLoaded: {
            try {
                root.learnerProfile = JSON.parse(text())
            } catch (e) {
                root.learnerProfile = null
            }
        }
        onLoadFailed: {
            root.learnerProfile = null
        }
    }

    FileView {
        id: proposalsStorage
        printErrors: false
        path: root.proposalsPath
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                root.proposals = Array.isArray(parsed) ? parsed : []
            } catch (e) { root.proposals = [] }
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                root.proposals = []
                Qt.callLater(() => proposalsStorage.setText("[]"))
            } else root.proposals = []
        }
    }

    function saveProposals() {
        proposalsStorage.setText(JSON.stringify(root.proposals, null, 2))
    }

    function reviewProposal(id, accept) {
        if (!root.memoryWritesAllowed) return
        const all = (root.proposals || []).slice()
        const idx = all.findIndex(p => String(p.id) === String(id))
        if (idx < 0) return
        const proposal = all[idx]
        if (accept) {
            const card = Object.assign({}, proposal)
            delete card.review_status; delete card.proposed_at
            card.id = "card_" + Date.now().toString(36)
            card.status = "learning"
            card.created = new Date().toISOString(); card.updated = card.created; card._ts = Date.now()
            card.scope = proposal.scope === "project" ? "project" : "general"
            if (card.type === "fact") {
                card.front = card.front || card.title; card.back = card.back || ""
                card.topic = card.title = card.front; card.lines = [card.back]
            } else if (card.type === "context") {
                card.scope = "project"
                card.domain = "workspace"
            } else {
                card.type = "knowledge"
                card.topic = card.title
                card.summary = card.mental_model || card.summary || ""
                card.lines = card.invariants || card.lines || []
            }
            root.cards = root.cards.concat([card])
            root.save()
            all.splice(idx, 1)
        } else {
            // Keep dismissed source IDs so automatic extraction does not ask again.
            all[idx].review_status = "dismissed"
        }
        root.proposals = all
        root.saveProposals()
    }

    function reload() {
        if (memoryStorage) memoryStorage.reload()
        if (learnerProfileStorage) learnerProfileStorage.reload()
        if (proposalsStorage) proposalsStorage.reload()
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
        if (!memoryStorage || !root.memoryWritesAllowed) return
        root._isSaving = true
        memoryStorage.setText(JSON.stringify(root.cards, null, 2))
        Qt.callLater(() => { root._isSaving = false })
    }

    function updateCard(id, updatedLines, updatedTopic) {
        if (!root.memoryWritesAllowed || !root.cards) return
        const list = root.cards.slice()
        for (let i = 0; i < list.length; i++) {
            if (String(list[i].id) === String(id)) {
                list[i].lines = updatedLines
                if (list[i].type === "knowledge") {
                    list[i].invariants = updatedLines
                } else if (list[i].type === "fact") {
                    list[i].back = updatedLines.join("\n")
                }
                if (updatedTopic !== undefined && updatedTopic.trim().length > 0) {
                    list[i].topic = updatedTopic.trim()
                    list[i].title = updatedTopic.trim()
                    if (list[i].type === "fact") {
                        list[i].front = updatedTopic.trim()
                    }
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
        if (!root.memoryWritesAllowed || !root.cards) return
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
        if (!root.memoryWritesAllowed || !root.cards || !cardId || !trapText) return
        const list = root.cards.slice()
        for (let i = 0; i < list.length; i++) {
            if (String(list[i].id) === String(cardId)) {
                const traps = list[i].personal_traps || list[i].user_traps || []
                list[i].personal_traps = traps.filter(t => t.trim() !== trapText.trim())
                list[i].user_traps = list[i].personal_traps
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
        const queryLower = query.toLowerCase()
        for (let i = 0; i < root.cards.length; i++) {
            const card = root.cards[i]
            if (!card || card.review_status === "pending" || card.type === "context") continue
            if (card.scope === "project") {
                const projectLabel = String(card.title || card.topic || card.project_path || "").toLowerCase()
                if (!projectLabel || !queryLower.includes(projectLabel)) continue
            }
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

        // Chat-to-Card Exposure: update last_touched for matched KnowledgeNodes in background
        let touched = false
        const nowIso = new Date().toISOString()
        for (let i = 0; i < topCards.length; i++) {
            if (topCards[i] && (topCards[i].type === "knowledge" || (!topCards[i].type && topCards[i].tier !== "primitive"))) {
                topCards[i].last_touched = nowIso
                touched = true
            }
        }
        if (touched) root.save()

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
        if (!root.memoryWritesAllowed || !sourceText || !answerText || quickCardProc.running) return
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
        if (!root.memoryWritesAllowed || !cardId || enrichProc.running) return
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
        if (!root.memoryWritesAllowed || distillProc.running) return
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
                    root.distillMessage = (res.new_cards || 0) > 0
                        ? "Found " + res.new_cards + " memory suggestion(s) for review."
                        : (res.message || "No new memory suggestions.")
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
        if (!root.memoryWritesAllowed || consolidateProc.running || root.isConsolidating) return
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
        if (!root.memoryWritesAllowed || !cardId || !answersData || gradeProc.running) return
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
}
