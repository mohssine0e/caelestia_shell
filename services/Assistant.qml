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
    property bool isLoading: false
    property string errorMessage: ""
    property bool hasApiKey: true

    readonly property string configPath: Quickshell.env("HOME") + "/.config/caelestia/assistant.json"

    // ── Clipboard polling & update ──────────────────────────────
    property bool isWatching: false

    Process {
        id: clipProc
        command: ["wl-paste", "-p"]
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
        command: ["wl-paste"]
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
        root.selectedText = txt
        // Reset previous result so user sees fresh text and can choose action
        root.resultText = ""
        root.errorMessage = ""
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

    // ── AI Worker process ─────────────────────────────────────────
    Process {
        id: apiProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.isLoading = false
                try {
                    const res = JSON.parse(text)
                    if (res.success) {
                        root.resultText = res.content
                        root.providerUsed = res.provider || ""
                        root.errorMessage = ""
                        root.hasApiKey = true
                    } else if (res.error === "NO_API_KEY" || res.error === "AUTH_ERROR") {
                        root.hasApiKey = false
                        root.errorMessage = res.message || "Invalid or missing API key."
                    } else {
                        root.errorMessage = res.message || "An error occurred."
                    }
                } catch (e) {
                    root.errorMessage = "Failed to parse API response."
                }
            }
        }
    }

    // ── Config write process (Safe argv execution, no shell string interpolation) ──
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
    }

    // ── Trigger HUD & grab current selection ──────────────────────
    function trigger() {
        const st = ShellState.forActive()
        if (st) {
            st.assistant = true
        }
        root.isWatching = true
        root.errorMessage = ""
        root.resultText = ""
        root.checkClipboard()
    }

    function toggle() {
        const st = ShellState.forActive()
        if (st) {
            if (st.assistant) {
                st.assistant = false
                root.isWatching = false
            } else {
                root.trigger()
            }
        }
    }

    function runAction(action, customPrompt) {
        customPrompt = customPrompt || ""
        root.activeAction = action
        if (!root.selectedText || root.selectedText.trim().length === 0) {
            root.errorMessage = "No text provided."
            root.isLoading = false
            return
        }

        root.isLoading = true
        root.errorMessage = ""
        root.resultText = ""

        const scriptPath = Quickshell.env("HOME") + "/.config/quickshell/caelestia/scripts/assistant_api.py"
        const args = ["python3", scriptPath, action, root.selectedText]
        if (customPrompt.length > 0) {
            args.push(customPrompt)
        }
        apiProc.command = args
        apiProc.running = true
    }
}
