pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.services

Singleton {
    id: root

    // ── State ────────────────────────────────────────────────────
    property string selectedText: ""
    property string activeAction: "" // translate, explain, tldr, rephrase, examples, ask
    property string resultText: ""
    property string providerUsed: ""
    property int latencyMs: 0
    property bool isLoading: false
    property string errorMessage: ""
    property string errorType: "" // "network", "auth", "rate_limit", "no_selection", "generic"
    property bool hasApiKey: true
    property bool isTruncated: false
    property int truncatedAt: 12000

    // History & Memory
    property var history: []
    property bool isOrganizing: false
    property string activePrompt: ""
    property var recalledContext: null
    readonly property string historyPath: Quickshell.env("HOME") + "/.config/caelestia/assistant_history.json"

    // Developer Dossier / Profile
    readonly property var defaultProfile: ({
        "os": "Linux (Hyprland)",
        "languages": ["Python", "QML / Qt", "Bash"],
        "style_preference": "Concise, standard library first, minimal dependencies",
        "bilingual": "English for technical terms/code, Arabic for natural translation/explanation",
        "custom_notes": "",
        "last_updated": "2026-10-14"
    })
    property var profile: defaultProfile
    property var proposedProfile: null
    readonly property string profilePath: Quickshell.env("HOME") + "/.config/caelestia/assistant_profile.json"

    FileView {
        id: profileStorage
        printErrors: false
        path: root.profilePath
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                if (parsed && typeof parsed === "object") {
                    root.profile = parsed
                }
            } catch (e) {
                root.profile = root.defaultProfile
            }
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                Qt.callLater(() => root.saveProfile(root.defaultProfile))
            }
        }
    }

    FileView {
        id: historyStorage
        printErrors: false
        path: root.historyPath
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                if (Array.isArray(parsed)) {
                    root.history = parsed
                }
            } catch (e) {
                root.history = []
            }
        }
        onLoadFailed: err => {
            root.history = []
            if (err === FileViewError.FileNotFound) {
                Qt.callLater(() => historyStorage.setText("[]"))
            }
        }
    }

    // In-memory query response cache
    property var responseCache: ({})

    readonly property string configPath: Quickshell.env("HOME") + "/.config/caelestia/assistant.json"
    property string preferredProvider: "gemini"
    property int maxChars: 12000
    property string geminiKey: ""
    property string groqKey: ""

    FileView {
        id: configStorage
        printErrors: false
        path: root.configPath
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                if (parsed && typeof parsed === "object") {
                    root.preferredProvider = parsed.primary || "gemini"
                    root.maxChars = parsed.max_chars || 12000
                    root.geminiKey = parsed.gemini_key || ""
                    root.groqKey = parsed.groq_key || ""
                    root.hasApiKey = !!(root.geminiKey || root.groqKey)
                }
            } catch (e) {}
        }
    }

    // ── Clipboard polling & update ──────────────────────────────
    property bool isWatching: false
    property bool listenClipboard: true
    property string lastSeenClipboard: ""

    onListenClipboardChanged: {
        if (listenClipboard && isWatching) {
            checkClipboard()
        }
    }

    function clearSelection() {
        if (root.selectedText && root.selectedText.length > 0) {
            root.lastSeenClipboard = root.selectedText
        }
        root.selectedText = ""
        root.isTruncated = false
        root.recalledContext = null
    }

    Process {
        id: clipProc
        command: ["wl-paste", "-p", "--type", "text"]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = text ? text.trim() : ""
                if (txt.length > 0) {
                    root.handleNewSelection(txt)
                } else {
                    clipFallbackProc.running = true
                }
            }
        }
        onExited: (code) => {
            if (code !== 0 && !clipFallbackProc.running) {
                clipFallbackProc.running = true
            }
        }
    }

    Process {
        id: clipFallbackProc
        command: ["wl-paste", "--type", "text"]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = text ? text.trim() : ""
                if (txt.length > 0) {
                    root.handleNewSelection(txt)
                }
            }
        }
    }

    function handleNewSelection(txt) {
        if (!root.listenClipboard) return
        if (!txt || txt === root.lastSeenClipboard) return
        
        root.lastSeenClipboard = txt
        root.selectedText = txt
        root.isTruncated = false

        // Cancel any pending in-flight streaming
        root.cancelCurrentRequest()
        root.errorMessage = ""
        root.errorType = ""
    }

    function checkClipboard() {
        if (!root.listenClipboard) return
        if (!clipProc.running && !clipFallbackProc.running) {
            clipProc.running = true
        }
    }

    Timer {
        id: clipWatchTimer
        interval: 800
        repeat: true
        running: root.isWatching && root.listenClipboard
        onTriggered: root.checkClipboard()
    }

    // ── Streaming AI Worker Process via SplitParser ──────────────
    Process {
        id: apiProc
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (!line) return
                try {
                    const msg = JSON.parse(line)
                    if (msg.type === "start") {
                        root.providerUsed = msg.provider || ""
                        if (msg.truncated !== undefined) {
                            root.isTruncated = !!msg.truncated
                        }
                        if (msg.truncated_at !== undefined) {
                            root.truncatedAt = msg.truncated_at
                        }
                        if (msg.recalled_from !== undefined) {
                            root.recalledContext = msg.recalled_from
                        }
                    } else if (msg.type === "chunk") {
                        root.isLoading = false
                        root.resultText += msg.text
                    } else if (msg.type === "done") {
                        root.isLoading = false
                        root.providerUsed = msg.provider || root.providerUsed
                        root.latencyMs = msg.latency_ms || 0
                        if (msg.truncated !== undefined) {
                            root.isTruncated = !!msg.truncated
                        }
                        if (msg.truncated_at !== undefined) {
                            root.truncatedAt = msg.truncated_at
                        }
                        if (msg.recalled_from !== undefined) {
                            root.recalledContext = msg.recalled_from
                        }
                        root.errorMessage = ""
                        root.errorType = ""
                        root.hasApiKey = true

                        // Cache completed response
                        const cacheKey = root.getCacheKey(root.activeAction, root.selectedText, "")
                        root.responseCache[cacheKey] = {
                            resultText: root.resultText,
                            provider: root.providerUsed,
                            latencyMs: root.latencyMs,
                            isTruncated: root.isTruncated,
                            truncatedAt: root.truncatedAt
                        }

                        // Save to persistent history
                        root.addToHistory(root.activeAction, root.selectedText, root.resultText, root.activePrompt)
                    } else if (msg.type === "error") {
                        root.isLoading = false
                        root.errorMessage = msg.message || "An error occurred."
                        root.errorType = msg.error_type || "generic"
                        if (msg.error_type === "auth") {
                            root.hasApiKey = false
                        }
                    }
                } catch (e) {
                    // Ignore malformed chunks
                }
            }
        }
        onExited: {
            root.isLoading = false
        }
    }

    function getCacheKey(action, text, customPrompt) {
        return `${action}:::${text.trim()}:::${(customPrompt || "").trim()}`
    }

    function cancelCurrentRequest() {
        if (apiProc.running) {
            apiProc.running = false
        }
        if (ttsProc.running) {
            ttsProc.running = false
        }
        root.isSpeaking = false
        root.isLoading = false
    }

    function retryAction() {
        if (root.activeAction && root.activeAction.length > 0) {
            root.runAction(root.activeAction, root.activePrompt)
        } else if (root.selectedText && root.selectedText.length > 0) {
            root.runAction("explain", "")
        }
    }

    // ── Speech / TTS (Arabic & English Pronunciation) ─────────────
    property bool isSpeaking: false

    Process {
        id: ttsProc
        onExited: {
            root.isSpeaking = false
        }
    }

    function speakText(txt) {
        if (root.isSpeaking) {
            ttsProc.running = false
            root.isSpeaking = false
            return
        }
        if (!txt || txt.trim().length === 0) return

        let clean = txt.replace(/```[\s\S]*?```/g, " ")
                       .replace(/[`#*_~\[\]\(\)]/g, " ")
                       .replace(/\s+/g, " ")
                       .trim()
        if (!clean) return

        const hasArabic = /[\u0600-\u06FF]/.test(clean)
        const voice = hasArabic ? "ar" : "en-us"
        clean = clean.slice(0, 450)

        ttsProc.command = ["espeak-ng", "-v", voice, clean]
        root.isSpeaking = true
        ttsProc.running = true
    }

    // ── Config write process (Safe argv execution) ────────────────
    Process {
        id: saveConfigProc
        onExited: {
            configStorage.reload()
            if (root.activeAction) {
                root.runAction(root.activeAction, root.activePrompt)
            }
        }
    }

    function saveSettings(geminiKey, groqKey, provider, maxChars) {
        const scriptPath = Quickshell.env("HOME") + "/.config/quickshell/caelestia/scripts/assistant_api.py"
        const gKey = (geminiKey !== undefined ? geminiKey : root.geminiKey || "").trim()
        const qKey = (groqKey !== undefined ? groqKey : root.groqKey || "").trim()
        const prov = (provider || root.preferredProvider || "gemini").toLowerCase()
        const mChars = String(maxChars || root.maxChars || 12000)

        root.geminiKey = gKey
        root.groqKey = qKey
        root.preferredProvider = prov
        root.maxChars = parseInt(mChars) || 12000
        root.hasApiKey = !!(gKey || qKey)

        saveConfigProc.command = [
            "python3", scriptPath, "save_config",
            gKey,
            qKey,
            prov,
            mChars
        ]
        saveConfigProc.running = true
        root.errorMessage = ""
        root.errorType = ""
    }

    function saveKeys(geminiKey, groqKey) {
        root.saveSettings(geminiKey, groqKey, root.preferredProvider, root.maxChars)
    }

    // ── Trigger HUD & grab current selection ──────────────────────
    function trigger() {
        const st = ShellState.forActive()
        if (st) {
            st.assistant = true
        }
        root.isWatching = true
        root.errorMessage = ""
        root.errorType = ""
        if (root.listenClipboard) {
            root.checkClipboard()
        }
    }

    function toggle() {
        const st = ShellState.forActive()
        if (st) {
            if (st.assistant) {
                st.assistant = false
                root.isWatching = false
                root.cancelCurrentRequest()
            } else {
                root.trigger()
            }
        }
    }

    // ── History Persistence & Management ────────────────────────
    function saveHistory() {
        if (historyStorage) {
            historyStorage.setText(JSON.stringify(root.history, null, 2))
        }
    }

    function addToHistory(action, text, answer, prompt) {
        if (!answer || answer.trim().length === 0) return
        if ((!text || text.trim().length === 0) && (!prompt || prompt.trim().length === 0)) return

        const list = root.history ? root.history.slice() : []
        const cleanText = (text || "").trim()
        const cleanPrompt = (prompt || "").trim()
        const cleanAnswer = answer.trim()

        if (list.length > 0) {
            const first = list[0]
            if (first.action === action && first.text === cleanText && (first.prompt || "") === cleanPrompt) {
                first.answer = cleanAnswer
                first.timestamp = Date.now()
                root.history = list
                root.saveHistory()
                return
            }
        }

        const newItem = {
            id: String(Date.now()),
            timestamp: Date.now(),
            action: action,
            prompt: cleanPrompt,
            text: cleanText,
            answer: cleanAnswer,
            starred: false,
            context_excluded: false,
            tags: []
        }

        list.unshift(newItem)
        if (list.length > 300) {
            list.length = 300
        }
        root.history = list
        root.saveHistory()
    }

    function deleteHistoryItem(id) {
        if (!root.history) return
        root.history = root.history.filter(item => String(item.id) !== String(id))
        root.saveHistory()
    }

    function toggleStar(id) {
        if (!root.history) return
        const list = root.history.slice()
        for (let i = 0; i < list.length; i++) {
            if (String(list[i].id) === String(id)) {
                list[i].starred = !list[i].starred
                break
            }
        }
        root.history = list
        root.saveHistory()
    }

    function toggleContextExcluded(id) {
        if (!root.history) return
        const list = root.history.slice()
        for (let i = 0; i < list.length; i++) {
            if (String(list[i].id) === String(id)) {
                list[i].context_excluded = !list[i].context_excluded
                break
            }
        }
        root.history = list
        root.saveHistory()
    }

    function clearHistory() {
        root.history = []
        root.saveHistory()
    }

    function removeTagFromItem(itemId, tagToRemove) {
        if (!root.history || !tagToRemove) return
        const list = root.history.slice()
        const lower = tagToRemove.trim().toLowerCase()
        for (let i = 0; i < list.length; i++) {
            if (String(list[i].id) === String(itemId)) {
                const currentTags = list[i].tags || []
                list[i].tags = currentTags.filter(t => t.trim().toLowerCase() !== lower)
                break
            }
        }
        root.history = list
        root.saveHistory()
    }

    function deleteTagEntirely(tagToDelete) {
        if (!root.history || !tagToDelete) return
        const list = root.history.slice()
        const lower = tagToDelete.trim().toLowerCase()
        for (let i = 0; i < list.length; i++) {
            if (list[i].tags && list[i].tags.length > 0) {
                list[i].tags = list[i].tags.filter(t => t.trim().toLowerCase() !== lower)
            }
        }
        root.history = list
        root.saveHistory()
    }

    function clearAllTags() {
        if (!root.history) return
        const list = root.history.slice()
        for (let i = 0; i < list.length; i++) {
            list[i].tags = []
        }
        root.history = list
        root.saveHistory()
    }

    function reopenItem(item) {
        if (!item) return
        root.selectedText = item.text || ""
        root.resultText = item.answer || ""
        root.activeAction = item.action || ""
        root.errorMessage = ""
        root.errorType = ""
    }

    Process {
        id: organizeProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/caelestia/scripts/assistant_api.py", "organize"]
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (!line) return
                try {
                    const msg = JSON.parse(line)
                    if (msg.type === "organize_done") {
                        root.isOrganizing = false
                        if (msg.mapping) {
                            const updated = root.history.slice()
                            for (let i = 0; i < updated.length; i++) {
                                const id = String(updated[i].id)
                                if (msg.mapping[id]) {
                                    updated[i].tags = msg.mapping[id]
                                }
                            }
                            root.history = updated
                        }
                        if (msg.proposed_profile) {
                            root.proposedProfile = msg.proposed_profile
                        }
                    } else if (msg.type === "error") {
                        root.isOrganizing = false
                    }
                } catch (e) {
                    root.isOrganizing = false
                }
            }
        }
        onExited: {
            root.isOrganizing = false
        }
    }

    function organizeHistory() {
        if (root.isOrganizing) return
        root.isOrganizing = true
        organizeProc.running = true
    }

    Process {
        id: saveProfileProc
        onExited: {
            profileStorage.reload()
        }
    }

    function saveProfile(profileData) {
        if (!profileData) return
        profileData.last_updated = new Date().toISOString().slice(0, 10)
        root.profile = profileData

        const scriptPath = Quickshell.env("HOME") + "/.config/quickshell/caelestia/scripts/assistant_api.py"
        saveProfileProc.command = [
            "python3", scriptPath, "save_profile",
            JSON.stringify(profileData)
        ]
        saveProfileProc.running = true
    }

    function acceptProposedProfile() {
        if (!root.proposedProfile) return
        const merged = Object.assign({}, root.profile || root.defaultProfile, root.proposedProfile)
        merged.last_updated = new Date().toISOString().slice(0, 10)
        root.saveProfile(merged)
        root.proposedProfile = null
    }

    function discardProposedProfile() {
        root.proposedProfile = null
    }

    function resetProfile() {
        const def = Object.assign({}, root.defaultProfile)
        def.last_updated = new Date().toISOString().slice(0, 10)
        root.saveProfile(def)
        root.proposedProfile = null
    }

    // ── Starred Concept Challenge (Active Recall) ─────────────────
    property var challengeCache: ({})
    property bool isChallenging: false
    property string activeChallengeItemId: ""
    property int challengeCooldownSec: 0

    Timer {
        id: challengeCooldownTimer
        interval: 1000
        repeat: true
        running: root.challengeCooldownSec > 0
        onTriggered: {
            if (root.challengeCooldownSec > 0) {
                root.challengeCooldownSec -= 1
            }
        }
    }

    Process {
        id: challengeProc
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (!line) return
                try {
                    const msg = JSON.parse(line)
                    if (msg.type === "challenge_done") {
                        root.isChallenging = false
                        root.activeChallengeItemId = ""
                        const cache = Object.assign({}, root.challengeCache)
                        cache[msg.item_id] = {
                            question: msg.question,
                            hint: msg.hint,
                            solution: msg.solution
                        }
                        root.challengeCache = cache
                        root.challengeCooldownSec = 15
                    } else if (msg.type === "error") {
                        root.isChallenging = false
                        root.activeChallengeItemId = ""
                    }
                } catch (e) {
                    root.isChallenging = false
                    root.activeChallengeItemId = ""
                }
            }
        }
        onExited: {
            root.isChallenging = false
            root.activeChallengeItemId = ""
        }
    }

    function requestChallenge(item) {
        if (!item || !item.id) return
        if (root.challengeCache[String(item.id)]) return
        if (root.isChallenging) return
        if (root.challengeCooldownSec > 0) return

        root.isChallenging = true
        root.activeChallengeItemId = String(item.id)

        const scriptPath = Quickshell.env("HOME") + "/.config/quickshell/caelestia/scripts/assistant_api.py"
        challengeProc.command = [
            "python3", scriptPath, "challenge",
            JSON.stringify(item)
        ]
        challengeProc.running = true
    }

    function runAction(action, customPrompt) {
        customPrompt = customPrompt || ""
        root.activeAction = action
        root.activePrompt = customPrompt

        const isAsk = (action === "ask" && customPrompt && customPrompt.trim().length > 0)
        const hasText = (root.selectedText && root.selectedText.trim().length > 0)

        if (!hasText && !isAsk) {
            root.errorType = "no_selection"
            root.errorMessage = "No text selected or copied."
            root.isLoading = false
            return
        }

        // Check in-memory cache for instant replay
        const cacheKey = root.getCacheKey(action, root.selectedText, customPrompt)
        const cached = root.responseCache[cacheKey]
        if (cached && !customPrompt) {
            root.cancelCurrentRequest()
            root.resultText = cached.resultText
            root.providerUsed = cached.provider + " (cached)"
            root.latencyMs = 0
            root.isTruncated = !!cached.isTruncated
            root.truncatedAt = cached.truncatedAt || 12000
            root.errorMessage = ""
            root.errorType = ""
            root.isLoading = false
            return
        }

        // Cancel previous request if still running
        root.cancelCurrentRequest()

        root.isLoading = true
        root.errorMessage = ""
        root.errorType = ""
        root.resultText = ""
        root.isTruncated = false
        root.recalledContext = null

        const scriptPath = Quickshell.env("HOME") + "/.config/quickshell/caelestia/scripts/assistant_api.py"
        const args = ["python3", "-u", scriptPath, action, root.selectedText]
        if (customPrompt.length > 0) {
            args.push(customPrompt)
        }
        apiProc.command = args
        apiProc.running = true
    }
}
