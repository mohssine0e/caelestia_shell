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
    property string rawResultText: ""
    property string resultText: ""
    property string providerUsed: ""
    property int latencyMs: 0
    property bool isLoading: false
    property bool isStreaming: false
    readonly property bool isGenerating: isLoading || isStreaming || apiProc.running
    property string errorMessage: ""
    property string errorType: "" // "network", "auth", "rate_limit", "no_selection", "generic"
    property bool hasApiKey: true
    property bool geminiConfigured: false
    property bool groqConfigured: false
    property string credentialBackend: "unknown"
    property bool isTruncated: false
    property int truncatedAt: 12000
    property bool isWindowActive: false
    property bool _forceNextSelection: false
    property string requestedView: ""

    // Multi-turn Thread & Mode
    property var thread: []              // {role, content} pairs for LLM context
    property var messages: []            // Scrollable session conversation feed: [{id, role, text, timestamp, action, isStreaming}]
    property string inputMode: "auto"    // "auto" | "followup" | "standalone"
    readonly property bool hasThread: thread.length > 0 || messages.length > 0

    // Chats & Multi-turn Sessions (File 1.5)
    property var chats: []
    property string activeChatId: ""
    readonly property string chatsPath: Quickshell.env("HOME") + "/.config/caelestia/chats.json"
    property string _lastSavedChatsJson: ""
    property bool _isSavingChats: false

    // History & Raw Log (File 1)
    property var history: []
    property int unDistilledCount: 0
    property string activePrompt: ""
    property var _activeRequest: null
    property int _requestSerial: 0
    property string requestState: "idle" // idle | waiting | streaming | completed | failed | cancelled
    property var recalledContext: null
    readonly property string historyPath: Quickshell.env("HOME") + "/.config/caelestia/assistant_history.json"

    // Delegated to Memory.qml singleton
    readonly property var memory: Memory.cards
    readonly property bool isDistilling: Memory.isDistilling
    readonly property string distillError: Memory.distillError

    function loadMemory() {
        Memory.reload()
    }

    function saveMemory() {
        Memory.save()
    }

    function updateMemoryCard(id, updatedLines, updatedTopic) {
        Memory.updateCard(id, updatedLines, updatedTopic)
    }

    function deleteMemoryCard(id) {
        Memory.deleteCard(id)
    }

    function distill() {
        Memory.distill()
    }

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

    property string _lastSavedHistoryJson: ""
    property bool _isSavingHistory: false

    FileView {
        id: historyStorage
        printErrors: false
        path: root.historyPath
        onLoaded: {
            const raw = text()
            if (root._isSavingHistory || raw === root._lastSavedHistoryJson) return
            try {
                const parsed = JSON.parse(raw)
                if (Array.isArray(parsed)) {
                    let needsSave = false
                    for (let i = 0; i < parsed.length; i++) {
                        const it = parsed[i]
                        if (!it.tags || it.tags.length === 0) {
                            it.tags = root.getAutonomousTags(it.action, it.text, it.prompt)
                            needsSave = true
                        }
                    }
                    root.history = parsed
                    if (needsSave) {
                        Qt.callLater(() => root.saveHistory())
                    }
                }
            } catch (e) {
                root.history = []
            }
        }
        onLoadFailed: err => {
            if (root._isSavingHistory) return
            root.history = []
            if (err === FileViewError.FileNotFound) {
                Qt.callLater(() => historyStorage.setText("[]"))
            }
        }
    }

    FileView {
        id: chatsStorage
        printErrors: false
        path: root.chatsPath
        onLoaded: {
            const raw = text()
            if (root._isSavingChats || raw === root._lastSavedChatsJson) return
            try {
                const parsed = JSON.parse(raw)
                if (Array.isArray(parsed)) {
                    root.chats = parsed
                }
            } catch (e) {
                root.chats = []
            }
        }
        onLoadFailed: err => {
            if (root._isSavingChats) return
            root.chats = []
            if (err === FileViewError.FileNotFound) {
                Qt.callLater(() => chatsStorage.setText("[]"))
            }
        }
    }

    readonly property string configPath: Quickshell.env("HOME") + "/.config/caelestia/assistant.json"
    property string preferredProvider: "gemini"
    property int maxChars: 12000
    property string geminiKey: ""
    property string groqKey: ""
    property var _pendingApiInput: ({})
    property var _pendingSettingsInput: ({})

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
                }
            } catch (e) {}
        }
    }

    Process {
        id: credentialStatusProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/caelestia/scripts/assistant_api.py", "credential_status", "--stdin-json"]
        stdinEnabled: true
        running: true
        onStarted: write("{\"include_values\":true}\n")
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const status = JSON.parse(text.trim())
                    const values = status.values || ({})
                    root.geminiKey = values.gemini || ""
                    root.groqKey = values.groq || ""
                    root.geminiConfigured = !!status.gemini_configured
                    root.groqConfigured = !!status.groq_configured
                    root.credentialBackend = status.backend || "unknown"
                    root.hasApiKey = root.geminiConfigured || root.groqConfigured
                } catch (e) {}
            }
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
        root.currentThreadId = ""
        root.clearThread()
    }

    // ── Multi-turn Thread Management & Essential Working Memory ──
    property string currentThreadId: ""
    property string topicAnchor: ""

    // ── Markdown LaTeX & Symbol Sanitizer ────────────────────────
    readonly property var _symbolMap: ({
        "longleftrightarrow": "⟷", "longleftarrow": "⟵", "longrightarrow": "⟶",
        "leftrightarrow": "↔", "Leftrightarrow": "⇔",
        "rightarrow": "→", "leftarrow": "←",
        "Rightarrow": "⇒", "Leftarrow": "⇐",
        "uparrow": "↑", "downarrow": "↓",
        "updownarrow": "↕", "mapsto": "↦",
        "implies": "⇒", "iff": "⇔",
        "to": "→", "gets": "←",
        "approx": "≈", "neq": "≠", "ne": "≠",
        "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥",
        "pm": "±", "mp": "∓", "times": "×", "div": "÷",
        "cdot": "·", "bullet": "•", "circ": "○",
        "dots": "…", "cdots": "…", "ldots": "…",
        "infty": "∞", "equiv": "≡", "degree": "°",
        "forall": "∀", "exists": "∃", "notin": "∉", "in": "∈",
        "subseteq": "⊆", "subset": "⊂", "supseteq": "⊃", "supset": "⊃",
        "cup": "∪", "cap": "∩", "land": "∧", "lor": "∨", "neg": "¬", "emptyset": "∅",
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "Delta": "Δ",
        "lambda": "λ", "mu": "μ", "pi": "π", "sigma": "σ", "tau": "τ",
        "theta": "θ", "omega": "ω", "Omega": "Ω"
    })

    function cleanMarkdown(text) {
        if (!text) return ""
        // Split text by fenced code blocks and inline code so code content is strictly preserved
        const parts = text.split(/(```[\s\S]*?```|`[^`\n]*`)/)
        const result = []

        for (let i = 0; i < parts.length; i++) {
            const part = parts[i]
            if (!part) continue
            // If it starts with backtick, it is inline code or code block: keep verbatim
            if (part.startsWith("`")) {
                result.push(part)
            } else {
                let p = part

                // 1. Unescape common escaped markdown/LaTeX characters: \$, \_, \#, \&, \%
                p = p.replace(/\\([$_#&%])/g, "$1")

                // 2. Text & Font macros: \text{...}, \textbf{...}, \textit{...}
                p = p.replace(/\\textbf\{([^{}]+)\}/g, "**$1**")
                p = p.replace(/\\textit\{([^{}]+)\}/g, "*$1*")
                p = p.replace(/\\text\{([^{}]+)\}/g, "$1")
                p = p.replace(/\\frac\{([^{}]+)\}\{([^{}]+)\}/g, "($1)/($2)")

                // 3. Replace LaTeX symbols (both dollar-wrapped and naked macros)
                for (let key in root._symbolMap) {
                    const sym = root._symbolMap[key]
                    p = p.replace(new RegExp("\\$\\s*\\\\" + key + "\\s*\\$", "g"), sym)
                    p = p.replace(new RegExp("\\\\" + key + "(?![a-zA-Z])", "g"), sym)
                }

                // 4. Clean up dollar signs around math expressions containing symbols
                p = p.replace(/\$([^$\n]+)\$/g, (match, inner) => {
                    if (/[\u2190-\u21FF\u2200-\u22FF\u0370-\u03FF=<>+\-±×÷·]/.test(inner)) {
                        return inner.trim()
                    }
                    return match
                })

                // 5. Common ASCII arrows in plain text with surrounding spaces
                p = p.replace(/\s+-->\s+/g, " → ")
                p = p.replace(/\s+<--\s+/g, " ← ")
                p = p.replace(/\s+<->\s+/g, " ↔ ")
                p = p.replace(/\s+->\s+/g, " → ")
                p = p.replace(/\s+<-\s+/g, " ← ")
                p = p.replace(/\s+=>\s+/g, " ⇒ ")
                p = p.replace(/\s+<=\s+/g, " ⇐ ")
                p = p.replace(/\s+<=>\s+/g, " ⇔ ")

                result.push(p)
            }
        }
        return result.join("")
    }

    function distillEssentials(text) {
        if (!text) return ""
        const cleaned = text.trim()
        if (cleaned.length <= 600) return cleaned

        const lines = cleaned.split("\n")
        const keyLines = []
        let totalLen = 0

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim()
            if (!line) continue
            if (line.startsWith("```") || line.startsWith("|---") || line.startsWith("---")) continue

            // Keep bullet points, headings, or numbered items
            if (line.startsWith("*") || line.startsWith("-") || line.startsWith("#") || /^\d+\./.test(line)) {
                keyLines.push(line)
                totalLen += line.length
            } else if (keyLines.length < 3) {
                keyLines.push(line)
                totalLen += line.length
            }
            if (totalLen >= 650) break
        }

        if (keyLines.length > 0) {
            return keyLines.join("\n").slice(0, 750)
        }
        return cleaned.slice(0, 650) + "..."
    }

    function pushTurn(userText, assistantText) {
        if (!userText && !assistantText) return
        const updated = (root.thread || []).slice()
        const distilled = root.distillEssentials(assistantText)
        updated.push({ role: "user", content: (userText || "").trim() })
        updated.push({ role: "assistant", content: distilled })
        while (updated.length > 6) {
            updated.shift()
            updated.shift()
        }
        root.thread = updated
    }

    function isTopicShift(newQuestion, threadList, anchor) {
        if (!threadList || threadList.length === 0) return false
        const q = String(newQuestion || "").trim().toLowerCase()
        const words = q.match(/[a-z0-9_\-\.]+/g) || []
        if (words.length <= 4) return false

        const followupWords = [
            "it", "this", "that", "these", "those", "they", "them", "why", "how",
            "what", "which", "instead", "more", "example", "examples", "explain",
            "expand", "clarify", "difference", "vs", "versus", "better", "worse",
            "and", "but", "so", "can", "could", "would", "should", "does", "is", "are"
        ]

        const earlyWords = words.slice(0, 3)
        for (let i = 0; i < earlyWords.length; i++) {
            if (["it", "this", "that", "these", "those", "they", "them"].indexOf(earlyWords[i]) !== -1) {
                return false
            }
        }

        let threadText = anchor || ""
        for (let i = 0; i < threadList.length; i++) {
            threadText += " " + (threadList[i].content || "")
        }
        const threadTokens = new Set((threadText.toLowerCase().match(/[a-z0-9_\-\.]{3,}/g) || []))

        const contentTokens = words.filter(w => w.length >= 3 && followupWords.indexOf(w) === -1)
        if (contentTokens.length < 3) return false

        let overlap = 0
        for (let i = 0; i < contentTokens.length; i++) {
            if (threadTokens.has(contentTokens[i])) overlap++
        }

        const ratio = overlap / contentTokens.length
        return ratio < 0.12 && contentTokens.length >= 3
    }

    function clearThread(resetMessages) {
        root.thread = []
        root.inputMode = "auto"
        root.currentThreadId = ""
        root.topicAnchor = ""
        if (resetMessages !== false) {
            root.messages = []
            root.rawResultText = ""
            root.resultText = ""
        }
    }

    function resolveMode(question) {
        if (root.inputMode === "followup" || root.inputMode === "standalone") {
            return root.inputMode
        }
        if (!root.thread || root.thread.length === 0) {
            return "standalone"
        }
        if (root.isTopicShift(question, root.thread, root.topicAnchor)) {
            return "standalone"
        }
        return "followup"
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
        const force = root._forceNextSelection
        root._forceNextSelection = false

        if (!root.listenClipboard) return
        if (!force && root.isWindowActive) return
        if (!txt || txt === root.lastSeenClipboard) return
        
        root.lastSeenClipboard = txt
        root.selectedText = txt
        root.isTruncated = false

        // Cancel any pending in-flight streaming
        root.cancelCurrentRequest()
        root._activeRequest = null
        root.errorMessage = ""
        root.errorType = ""
        root.clearThread()
    }

    function checkClipboard(force = false) {
        if (!root.listenClipboard) return
        if (!force && root.isWindowActive) return
        if (force) {
            root._forceNextSelection = true
        }
        if (!clipProc.running && !clipFallbackProc.running) {
            clipProc.running = true
        }
    }

    Timer {
        id: clipWatchTimer
        interval: 800
        repeat: true
        running: root.isWatching && root.listenClipboard && !root.isWindowActive
        onTriggered: root.checkClipboard(false)
    }

    // ── High-Performance Stream Batching (~16.6 updates/sec) ────
    property string _streamBuffer: ""

    Timer {
        id: streamBatchTimer
        interval: 60
        repeat: false
        onTriggered: root._flushStreamBuffer()
    }

    function _flushStreamBuffer() {
        if (!root._streamBuffer || root._streamBuffer.length === 0) return
        root.rawResultText += root._streamBuffer
        root._streamBuffer = ""
        root.resultText = root.rawResultText
    }

    // ── Streaming AI Worker Process via SplitParser ──────────────
    Process {
        id: apiProc
        stdinEnabled: true
        onStarted: write(JSON.stringify(root._pendingApiInput) + "\n")
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (!line) return
                try {
                    const msg = JSON.parse(line)
                    // Every generation event belongs to the request that produced it.
                    // Ignore output from a process that was cancelled or superseded.
                    if (!root._activeRequest || !msg.request_id || msg.request_id !== root._activeRequest.id) return
                    if (msg.type === "topic_shift") {
                        root.thread = []
                        root.currentThreadId = "t_" + Date.now().toString(36)
                        root.topicAnchor = msg.topic || ""
                        const msgs = (root.messages || []).slice()
                        msgs.push({
                            id: "shift_" + Date.now(),
                            type: "topic_divider",
                            text: qsTr("New Context: %1").arg(msg.topic ? msg.topic.slice(0, 45) : qsTr("Topic Shift"))
                        })
                        root.messages = msgs
                    } else if (msg.type === "start") {
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
                        root.requestState = "streaming"
                        root.isLoading = false
                        root.isStreaming = true
                        root._streamBuffer += msg.text
                        if (root.rawResultText.length === 0) {
                            root._flushStreamBuffer()
                        } else if (!streamBatchTimer.running) {
                            streamBatchTimer.restart()
                        }
                    } else if (msg.type === "done") {
                        streamBatchTimer.stop()
                        if (root._streamBuffer && root._streamBuffer.length > 0) {
                            root.rawResultText += root._streamBuffer
                            root._streamBuffer = ""
                        }
                        // Final markdown cleaning done once when finished
                        root.resultText = root.cleanMarkdown(root.rawResultText)
                        if (root.messages && root.messages.length > 0) {
                            const msgs = root.messages.slice()
                            const last = msgs[msgs.length - 1]
                            if (last && last.role === "assistant") {
                                msgs[msgs.length - 1] = Object.assign({}, last, {
                                    text: root.resultText,
                                    isStreaming: false
                                })
                                root.messages = msgs
                            }
                        }
                        root.isLoading = false
                        root.isStreaming = false
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
                        root.requestState = "completed"

                        // Save to persistent history
                        const request = root._activeRequest || ({ action: root.activeAction, sourceText: root.selectedText, prompt: root.activePrompt })
                        root.addToHistory(request.action, request.sourceText, root.resultText, request.prompt)

                        // Active multi-turn thread is only for custom conversational questions ("ask")
                        if (request.action === "ask" && request.mode === "standalone") {
                            root.clearThread(false)
                            root.topicAnchor = request.newAnchor || request.prompt || request.sourceText
                            root.currentThreadId = root.activeChatId
                        }
                        if (request.action === "ask" && root.resultText.length > 0) {
                            root.pushTurn(request.prompt || request.sourceText, root.resultText)
                        }

                        // Sync with persistent chat sessions
                        root.syncActiveChat()
                    } else if (msg.type === "error") {
                        streamBatchTimer.stop()
                        root._streamBuffer = ""
                        root.isLoading = false
                        root.isStreaming = false
                        root.requestState = "failed"
                        root.errorMessage = msg.message || "An error occurred."
                        root.errorType = msg.error_type || "generic"
                        if (msg.error_type === "auth") {
                            root.hasApiKey = false
                        }
                        if (root.messages && root.messages.length > 0) {
                            const msgs = root.messages.slice()
                            const last = msgs[msgs.length - 1]
                            if (last && last.role === "assistant" && (!last.text || last.text.length === 0)) {
                                msgs[msgs.length - 1] = Object.assign({}, last, {
                                    text: "⚠️ " + (msg.message || "An error occurred."),
                                    isStreaming: false
                                })
                                root.messages = msgs
                            }
                        }
                    }
                } catch (e) {
                    // Ignore malformed chunks
                }
            }
        }
        onExited: {
            // A stopped/superseded process can exit after a new request has begun.
            // The API's tagged terminal event owns normal completion; only handle
            // an exit as failure if the current request still has no terminal state.
            if (root.apiProc.running || (root.requestState !== "waiting" && root.requestState !== "streaming")) return
            streamBatchTimer.stop()
            if (root._streamBuffer && root._streamBuffer.length > 0) {
                root.rawResultText += root._streamBuffer
                root._streamBuffer = ""
                root.resultText = root.cleanMarkdown(root.rawResultText)
            }
            if (root.messages && root.messages.length > 0) {
                const msgs = root.messages.slice()
                const last = msgs[msgs.length - 1]
                if (last && last.role === "assistant" && last.isStreaming) {
                    msgs[msgs.length - 1] = Object.assign({}, last, {
                        text: root.resultText || last.text,
                        isStreaming: false
                    })
                    root.messages = msgs
                }
            }
            root.isLoading = false
            root.isStreaming = false
            root.requestState = "failed"
            root.errorType = "generic"
            root.errorMessage = qsTr("The assistant request ended unexpectedly.")
        }
    }

    function cancelCurrentRequest() {
        if (root.requestState === "waiting" || root.requestState === "streaming") {
            root.requestState = "cancelled"
        }
        if (apiProc.running) {
            apiProc.running = false
        }
        if (ttsProc.running) {
            ttsProc.running = false
        }
        root.isSpeaking = false
        root.isLoading = false
        root.isStreaming = false
    }

    function retryAction() {
        if (root._activeRequest && root._activeRequest.action) {
            const request = root._activeRequest
            root.runAction(request.action, request.prompt, request.sourceText)
        } else if (root.activeAction && root.activeAction.length > 0) {
            root.runAction(root.activeAction, root.activePrompt)
        } else if (root.selectedText && root.selectedText.length > 0) {
            root.runAction("explain", "")
        }
    }

    // ── Speech / TTS (Natural Neural Voice via assistant_tts.py) ──
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

        const scriptPath = Quickshell.env("HOME") + "/.config/quickshell/caelestia/scripts/assistant_tts.py"
        const pythonBin = Quickshell.env("HOME") + "/piper-venv/bin/python3"

        ttsProc.command = [pythonBin, scriptPath, txt]
        root.isSpeaking = true
        ttsProc.running = true
    }

    // ── Config write process (Safe argv execution) ────────────────
    Process {
        id: saveConfigProc
        stdinEnabled: true
        onStarted: write(JSON.stringify(root._pendingSettingsInput) + "\n")
        onExited: {
            configStorage.reload()
            if (!credentialStatusProc.running) credentialStatusProc.running = true
            if (root.activeAction) {
                root.runAction(root.activeAction, root.activePrompt)
            }
        }
    }

    function saveSettings(geminiKey, groqKey, provider, maxChars, clearGeminiKey = false, clearGroqKey = false) {
        const scriptPath = Quickshell.env("HOME") + "/.config/quickshell/caelestia/scripts/assistant_api.py"
        const gKey = clearGeminiKey ? "" : (geminiKey !== undefined && geminiKey !== "" ? geminiKey : root.geminiKey || "").trim()
        const qKey = clearGroqKey ? "" : (groqKey !== undefined && groqKey !== "" ? groqKey : root.groqKey || "").trim()
        const prov = (provider || root.preferredProvider || "gemini").toLowerCase()
        const mChars = String(maxChars || root.maxChars || 12000)

        root.geminiKey = gKey
        root.groqKey = qKey
        root.preferredProvider = prov
        root.maxChars = parseInt(mChars) || 12000
        if (clearGeminiKey) root.geminiConfigured = false
        else if (gKey) root.geminiConfigured = true
        if (clearGroqKey) root.groqConfigured = false
        else if (qKey) root.groqConfigured = true
        root.hasApiKey = root.geminiConfigured || root.groqConfigured

        saveConfigProc.command = [
            "python3", scriptPath, "save_config", "--stdin-json"
        ]
        root._pendingSettingsInput = {
            gemini_key: gKey, groq_key: qKey, provider: prov, max_chars: mChars,
            clear_gemini_key: clearGeminiKey, clear_groq_key: clearGroqKey
        }
        saveConfigProc.running = true
        root.errorMessage = ""
        root.errorType = ""
    }

    function saveKeys(geminiKey, groqKey) {
        root.saveSettings(geminiKey, groqKey, root.preferredProvider, root.maxChars)
    }

    // ── Trigger HUD & grab current selection ──────────────────────
    function trigger() {
        const st = ShellState.forActive() ?? ShellState.states[0]
        if (st) {
            st.assistant = true
        }
        root.isWatching = true
        root.errorMessage = ""
        root.errorType = ""
        if (root.listenClipboard) {
            root.checkClipboard(true)
        }
    }

    function toggle() {
        const st = ShellState.forActive() ?? ShellState.states[0]
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

    // ── Chat Session Persistence & Management ────────────────────
    function saveChats() {
        if (chatsStorage) {
            root._isSavingChats = true
            const jsonStr = JSON.stringify(root.chats, null, 2)
            root._lastSavedChatsJson = jsonStr
            chatsStorage.setText(jsonStr)
            Qt.callLater(() => { root._isSavingChats = false })
        }
    }

    function startNewChat() {
        root.cancelCurrentRequest()
        root._activeRequest = null
        root.activeChatId = "t_" + Date.now().toString(36)
        root.currentThreadId = root.activeChatId
        root.messages = []
        root.thread = []
        root.selectedText = ""
        root.rawResultText = ""
        root.resultText = ""
        root.activePrompt = ""
        root.errorMessage = ""
        root.errorType = ""
        root.activeAction = "ask"
    }

    function loadChat(chatId) {
        if (!chatId || !root.chats) return
        const chat = root.chats.find(c => c && String(c.id) === String(chatId))
        if (!chat) return

        root.activeChatId = String(chat.id)
        root.currentThreadId = String(chat.id)
        root.activeAction = "ask"
        root.selectedText = ""
        root.errorMessage = ""
        root.errorType = ""

        const msgs = (chat.messages || []).map(m => Object.assign({}, m))
        root.messages = msgs

        // Reconstruct conversation thread context for the LLM follow-ups
        const threadList = []
        for (let i = 0; i < msgs.length; i++) {
            const m = msgs[i]
            if (m.role === "user") {
                threadList.push({ role: "user", content: m.text || "" })
            } else if (m.role === "assistant") {
                threadList.push({ role: "assistant", content: root.distillEssentials(m.text || "") })
            }
        }
        root.thread = threadList

        const lastAssistant = msgs.slice().reverse().find(m => m.role === "assistant")
        root.resultText = lastAssistant ? lastAssistant.text : ""
        root.rawResultText = root.resultText

        // Switch directly to main chat view
        root.requestedView = "assistant"
    }

    function deleteChat(chatId) {
        if (!root.chats || !chatId) return
        root.chats = root.chats.filter(c => c && String(c.id) !== String(chatId))
        root.saveChats()
        if (root.activeChatId === String(chatId)) {
            root.startNewChat()
        }
    }

    function renameChat(chatId, newTitle) {
        if (!root.chats || !chatId || !newTitle) return
        const list = root.chats.slice()
        const target = list.find(c => c && String(c.id) === String(chatId))
        if (target) {
            target.title = newTitle.trim()
            root.chats = list
            root.saveChats()
        }
    }

    function togglePinChat(chatId) {
        if (!root.chats || !chatId) return
        const list = root.chats.slice()
        const target = list.find(c => c && String(c.id) === String(chatId))
        if (target) {
            target.pinned = !target.pinned
            target.starred = target.pinned
            root.chats = list
            root.saveChats()
        }
    }

    function syncActiveChat() {
        if (!root.messages || root.messages.length === 0) return

        if (!root.activeChatId) {
            root.activeChatId = "t_" + Date.now().toString(36)
            root.currentThreadId = root.activeChatId
        }

        const list = root.chats ? root.chats.slice() : []
        let chat = list.find(c => c && String(c.id) === String(root.activeChatId))
        const nowIso = new Date().toISOString()

        const cleanMsgs = root.messages.map(m => ({
            id: m.id || ("m_" + Math.random().toString(36).slice(2, 7)),
            role: m.role || "user",
            action: m.action || "ask",
            text: (m.text || "").trim(),
            sourceText: m.sourceText || "",
            prompt: m.prompt || "",
            timestamp: m.timestamp || new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
        })).filter(m => m.text.length > 0)

        if (cleanMsgs.length === 0) return

        if (!chat) {
            const firstUser = cleanMsgs.find(m => m.role === "user")
            let title = (firstUser ? firstUser.text : "New Chat").replace(/[\n\r`#*]+/g, " ").trim()
            if (title.length > 45) title = title.slice(0, 42) + "..."

            chat = {
                id: root.activeChatId,
                title: title,
                createdAt: nowIso,
                updatedAt: nowIso,
                pinned: false,
                starred: false,
                tags: root.getAutonomousTags("ask", firstUser ? firstUser.text : "", ""),
                messages: cleanMsgs
            }
            list.unshift(chat)

            // Trigger autonomous AI titling
            root.requestAiChatTitle(root.activeChatId, firstUser ? firstUser.text : "", cleanMsgs[1] ? cleanMsgs[1].text : "")
        } else {
            chat.messages = cleanMsgs
            chat.updatedAt = nowIso
            const idx = list.findIndex(c => String(c.id) === String(chat.id))
            if (idx > 0) {
                list.splice(idx, 1)
                list.unshift(chat)
            }
        }

        root.chats = list
        root.saveChats()
    }

    property string _pendingTitleChatId: ""

    Process {
        id: titleProc
        command: []
        stdout: StdioCollector {
            id: titleCollector
            onStreamFinished: {
                const output = titleCollector.text ? titleCollector.text.trim() : ""
                if (!output || !root._pendingTitleChatId) return
                try {
                    const parsed = JSON.parse(output)
                    if (parsed && parsed.title && root.chats) {
                        const list = root.chats.slice()
                        const target = list.find(c => c && String(c.id) === String(root._pendingTitleChatId))
                        if (target) {
                            target.title = parsed.title.trim()
                            if (parsed.tags && parsed.tags.length > 0) {
                                target.tags = parsed.tags
                            }
                            root.chats = list
                            root.saveChats()
                        }
                    }
                } catch (e) {}
            }
        }
    }

    function requestAiChatTitle(chatId, promptText, answerText) {
        if (!chatId || !promptText || titleProc.running) return
        root._pendingTitleChatId = chatId
        const scriptPath = Quickshell.env("HOME") + "/.config/quickshell/caelestia/scripts/assistant_api.py"
        titleProc.command = ["python3", scriptPath, "title_chat", promptText.slice(0, 500), answerText.slice(0, 500)]
        titleProc.running = true
    }

    // ── History Persistence & Management ────────────────────────
    function saveHistory() {
        if (historyStorage) {
            root._isSavingHistory = true
            const jsonStr = JSON.stringify(root.history, null, 2)
            root._lastSavedHistoryJson = jsonStr
            historyStorage.setText(jsonStr)
            Qt.callLater(() => { root._isSavingHistory = false })
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
            if (first.action === action && (first.text === cleanText || first.original === cleanText) && (first.prompt || "") === cleanPrompt) {
                first.answer = cleanAnswer
                first.timestamp = new Date().toISOString()
                root.history = list
                root.saveHistory()
                return
            }
        }

        let threadId = null
        if (action === "ask") {
            if (root.thread && root.thread.length > 0) {
                if (!root.currentThreadId) {
                    root.currentThreadId = "t_" + Date.now().toString(36)
                }
                threadId = root.currentThreadId
            } else {
                root.currentThreadId = "t_" + Date.now().toString(36)
                threadId = root.currentThreadId
            }
        }

        const now = new Date()
        const isoStr = now.toISOString()
        const isoSanitized = isoStr.replace(/[:.]/g, "-")
        const shortId = Math.random().toString(36).slice(2, 6)
        const entryId = "h_" + isoSanitized + "_" + shortId

        const newItem = {
            id: entryId,
            action: action,
            original: cleanText || cleanPrompt,
            text: cleanText,
            prompt: cleanPrompt,
            answer: cleanAnswer,
            timestamp: isoStr,
            starred: false,
            context_excluded: false,
            tags: root.getAutonomousTags(action, cleanText, cleanPrompt),
            thread_id: threadId
        }

        list.unshift(newItem)
        if (list.length > 300) {
            let dropIndex = -1
            for (let i = list.length - 1; i >= 0; i--) {
                if (!list[i].starred) {
                    dropIndex = i
                    break
                }
            }
            if (dropIndex !== -1) {
                list.splice(dropIndex, 1)
            } else {
                list.pop()
            }
        }
        root.history = list
        root.saveHistory()

        // Debounced autonomous memory extraction & SRS distillation (2s after turn completes)
        autoDistillTimer.restart()
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
                list[i] = Object.assign({}, list[i], { starred: !list[i].starred })
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
                list[i] = Object.assign({}, list[i], { context_excluded: !list[i].context_excluded })
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
        root.rawResultText = item.answer || ""
        root.resultText = root.cleanMarkdown(item.answer || "")
        root.activeAction = item.action || "ask"
        root.activePrompt = item.prompt || item.original || ""
        root.errorMessage = ""
        root.errorType = ""

        const msgs = []
        const threadList = []

        // If part of an existing thread, load all turns from that thread in chronological order
        if (item.thread_id && root.history && root.history.length > 0) {
            const threadHistory = root.history
                .filter(h => h && h.thread_id === item.thread_id)
                .sort((a, b) => new Date(a.timestamp || 0) - new Date(b.timestamp || 0))

            if (threadHistory.length > 0) {
                for (let i = 0; i < threadHistory.length; i++) {
                    const h = threadHistory[i]
                    const hPrompt = (h.prompt || h.original || h.text || "").trim()
                    const hDisplay = hPrompt || (h.action && h.action !== "ask" ? h.action.toUpperCase() : qsTr("Question"))
                    const hTime = h.timestamp ? new Date(h.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : ""
                    const hAnswer = root.cleanMarkdown(h.answer || "")

                    msgs.push({
                        id: "u_" + (h.id || i),
                        role: "user",
                        action: h.action || "ask",
                        text: hDisplay,
                        sourceText: h.text || "",
                        prompt: hPrompt,
                        timestamp: hTime
                    })
                    msgs.push({
                        id: "a_" + (h.id || i),
                        role: "assistant",
                        action: h.action || "ask",
                        sourceText: h.text || "",
                        prompt: hPrompt,
                        text: hAnswer,
                        isStreaming: false,
                        timestamp: hTime
                    })
                    threadList.push({ role: "user", content: hPrompt })
                    threadList.push({ role: "assistant", content: root.distillEssentials(h.answer || "") })
                }
            }
        }

        // Fallback for single item without thread_id or standalone item
        if (msgs.length === 0) {
            const userPrompt = (item.prompt || item.original || item.text || "").trim()
            const userDisplay = userPrompt || (item.action && item.action !== "ask" ? item.action.toUpperCase() : qsTr("Question"))
            const timeStr = item.timestamp ? new Date(item.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : ""

            msgs.push({
                id: "u_" + (item.id || Date.now()),
                role: "user",
                action: item.action || "ask",
                text: userDisplay,
                timestamp: timeStr
            })
            msgs.push({
                id: "a_" + (item.id || Date.now()),
                role: "assistant",
                action: item.action || "ask",
                text: root.resultText,
                isStreaming: false,
                timestamp: timeStr
            })
            threadList.push({ role: "user", content: userPrompt })
            threadList.push({ role: "assistant", content: root.distillEssentials(item.answer || "") })
        }

        while (threadList.length > 6) {
            threadList.shift()
        }

        root.messages = msgs
        root.thread = threadList
        root.currentThreadId = item.thread_id || ("t_" + Date.now().toString(36))
        const lastPrompt = (item.prompt || item.original || item.text || "").trim()
        root.topicAnchor = lastPrompt.slice(0, 350)
        root.inputMode = "followup"
    }

    // ── Autonomous Classification & Background Memory Distillation ──
    function getAutonomousTags(action, text, prompt) {
        const combined = ((action || "") + " " + (text || "") + " " + (prompt || "")).toLowerCase()
        const tags = []
        if (action === "translate" || /[\u0600-\u06FF]/.test(combined)) tags.push("arabic")
        if (action === "fix" || /(?:error|exception|traceback|failed|panic|syntaxerror)/.test(combined)) tags.push("debug")
        if (/(?:python|pip|pytest|django|flask|fastapi)/.test(combined)) tags.push("python")
        if (/(?:spring|java|maven|gradle|jvm)/.test(combined)) tags.push("java")
        if (/(?:linux|arch|hyprland|bash|zsh|systemd|pacman)/.test(combined)) tags.push("linux")
        if (/(?:git|rebase|merge|commit|branch)/.test(combined)) tags.push("git")
        if (/(?:qml|quickshell|qt)/.test(combined)) tags.push("qml")
        if (/(?:javascript|typescript|react|html|css|node)/.test(combined)) tags.push("web")
        if (/(?:docker|container|podman|k8s)/.test(combined)) tags.push("devops")
        if (/(?:sql|postgres|sqlite|database)/.test(combined)) tags.push("database")
        if (tags.length === 0) tags.push(action || "general")
        return tags.slice(0, 3)
    }

    Timer {
        id: autoDistillTimer
        interval: 1800
        repeat: false
        onTriggered: {
            if (!Memory.isDistilling && !root.isStreaming && !root.isLoading) {
                Memory.distill()
            }
        }
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

    function runAction(action, customPrompt, retrySourceText) {
        customPrompt = customPrompt || ""
        const sourceText = String(retrySourceText !== undefined ? retrySourceText : (root.selectedText || ""))
        root.activeAction = action
        root.activePrompt = customPrompt
        root._activeRequest = {action: action, prompt: customPrompt, sourceText: sourceText}

        const isAsk = (action === "ask" && customPrompt && customPrompt.trim().length > 0)
        const hasText = sourceText.trim().length > 0

        if (!hasText && !isAsk) {
            root.errorType = "no_selection"
            root.errorMessage = "No text selected or copied."
            root.isLoading = false
            return
        }

        let mode = "standalone"
        let newAnchor = root.topicAnchor
        let topicShift = false
        if (action === "ask") {
            topicShift = (root.inputMode === "auto" && root.thread.length > 0 && root.isTopicShift(customPrompt, root.thread, root.topicAnchor))
            mode = root.resolveMode(customPrompt)
            if (mode === "standalone") {
                if (!root.activeChatId) {
                    root.activeChatId = "t_" + Date.now().toString(36)
                }
                newAnchor = (customPrompt || sourceText).trim().replace(/\s+/g, " ").slice(0, 350)
                if (topicShift && retrySourceText === undefined) {
                    const msgs = (root.messages || []).slice()
                    msgs.push({
                        id: "shift_" + Date.now(),
                        type: "topic_divider",
                        text: qsTr("New Context")
                    })
                    root.messages = msgs
                }
            } else if (!root.topicAnchor || root.thread.length === 0) {
                if (sourceText.trim().length > 0) {
                    const raw = sourceText.trim().replace(/\s+/g, " ")
                    newAnchor = raw.slice(0, 350)
                } else if (customPrompt && customPrompt.trim().length > 0) {
                    newAnchor = customPrompt.trim().replace(/\s+/g, " ").slice(0, 350)
                }
            }
        }
        root._activeRequest = {
            action: action, prompt: customPrompt, sourceText: sourceText, mode: mode,
            newAnchor: newAnchor, topicShift: topicShift
        }

        const nowStr = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
        const promptSnippet = sourceText ? (sourceText.trim().slice(0, 140) + (sourceText.trim().length > 140 ? "…" : "")) : ""
        const userMsg = {
            id: "u_" + Date.now(),
            role: "user",
            action: action,
            text: customPrompt ? customPrompt : (action && action !== "ask" ? (action.toUpperCase() + ": " + promptSnippet) : promptSnippet),
            sourceText: sourceText,
            prompt: customPrompt,
            timestamp: nowStr
        }

        // Cancel previous request if still running
        root.cancelCurrentRequest()
        root._requestSerial += 1
        const requestId = "assistant_" + root._requestSerial
        root._activeRequest.id = requestId

        const assistantMsg = {
            id: "a_" + Date.now(),
            role: "assistant",
            action: action,
            sourceText: sourceText,
            prompt: customPrompt,
            text: "",
            isStreaming: true,
            timestamp: nowStr
        }
        const msgsList = (root.messages || []).slice()
        msgsList.push(userMsg)
        msgsList.push(assistantMsg)
        root.messages = msgsList

        root.isLoading = true
        root.errorMessage = ""
        root.errorType = ""
        root.requestState = "waiting"
        root.providerUsed = ""
        root.latencyMs = 0
        root.rawResultText = ""
        root.resultText = ""
        root.isTruncated = false
        root.recalledContext = null

        const scriptPath = Quickshell.env("HOME") + "/.config/quickshell/caelestia/scripts/assistant_api.py"
        const queryForContext = (action === "ask") ? (customPrompt || sourceText) : sourceText
        const memContext = Memory.getPromptInjection(queryForContext)
        apiProc.command = ["python3", "-u", scriptPath, action, "--stdin-json"]
        root._pendingApiInput = {
            request_id: requestId,
            text: sourceText,
            custom_prompt: customPrompt,
            mode: mode,
            thread: (action === "ask" && mode === "followup") ? (root.thread || []) : [],
            anchor: (action === "ask" && mode === "followup") ? (root.topicAnchor || newAnchor || "") : "",
            context: memContext || ""
        }
        apiProc.running = true
    }
}
