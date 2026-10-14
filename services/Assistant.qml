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

    // In-memory query response cache
    property var responseCache: ({})

    readonly property string configPath: Quickshell.env("HOME") + "/.config/caelestia/assistant.json"

    // ── Clipboard polling & update ──────────────────────────────
    property bool isWatching: false

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
        if (!txt || txt === root.selectedText) return
        
        // Truncate text over 4000 characters
        if (txt.length > 4000) {
            root.selectedText = txt.slice(0, 4000)
            root.isTruncated = true
        } else {
            root.selectedText = txt
            root.isTruncated = false
        }

        // Cancel any pending in-flight streaming
        root.cancelCurrentRequest()

        // Reset previous result so user sees fresh text and can choose action
        root.resultText = ""
        root.errorMessage = ""
        root.errorType = ""
        root.isLoading = false
    }

    function checkClipboard() {
        if (!clipProc.running && !clipFallbackProc.running) {
            clipProc.running = true
        }
    }

    Timer {
        id: clipWatchTimer
        interval: 800
        repeat: true
        running: root.isWatching
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
                    } else if (msg.type === "chunk") {
                        root.isLoading = false
                        root.resultText += msg.text
                    } else if (msg.type === "done") {
                        root.isLoading = false
                        root.providerUsed = msg.provider || root.providerUsed
                        root.latencyMs = msg.latency_ms || 0
                        root.errorMessage = ""
                        root.errorType = ""
                        root.hasApiKey = true

                        // Cache completed response
                        const cacheKey = root.getCacheKey(root.activeAction, root.selectedText, "")
                        root.responseCache[cacheKey] = {
                            resultText: root.resultText,
                            provider: root.providerUsed,
                            latencyMs: root.latencyMs
                        }
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
        root.isLoading = false
    }

    // ── Config write process (Safe argv execution) ────────────────
    Process {
        id: saveConfigProc
        onExited: {
            if (root.activeAction) {
                root.runAction(root.activeAction)
            }
        }
    }

    function saveKeys(geminiKey, groqKey) {
        const scriptPath = Quickshell.env("HOME") + "/.config/quickshell/caelestia/scripts/assistant_api.py"
        saveConfigProc.command = [
            "python3", scriptPath, "save_config",
            (geminiKey || "").trim(),
            (groqKey || "").trim()
        ]
        saveConfigProc.running = true
        root.errorMessage = ""
        root.errorType = ""
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
        root.resultText = ""
        root.checkClipboard()
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

    function runAction(action, customPrompt) {
        customPrompt = customPrompt || ""
        root.activeAction = action

        if (!root.selectedText || root.selectedText.trim().length === 0) {
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

        const scriptPath = Quickshell.env("HOME") + "/.config/quickshell/caelestia/scripts/assistant_api.py"
        const args = ["python3", "-u", scriptPath, action, root.selectedText]
        if (customPrompt.length > 0) {
            args.push(customPrompt)
        }
        apiProc.command = args
        apiProc.running = true
    }
}
