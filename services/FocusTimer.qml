pragma Singleton

import QtQuick
import Quickshell
import Caelestia
import qs.services

Singleton {
    id: root

    // ── Timer State ──────────────────────────────────────────────
    property bool isRunning: false
    property int remainingSeconds: 25 * 60
    property int totalDurationSeconds: 25 * 60
    property string mode: "work" // "work" | "shortBreak" | "longBreak" | "custom"

    // ── Linked Task Context ──────────────────────────────────────
    property string linkedTaskId: ""
    property string linkedTaskTitle: ""

    // ── Session counter (resets at midnight) ────────────────────
    property int sessionsToday: 0
    property string sessionDate: ""

    // ── Computed Progress ────────────────────────────────────────
    readonly property real progress: totalDurationSeconds > 0
        ? Math.max(0, Math.min(1, 1 - (remainingSeconds / totalDurationSeconds)))
        : 0

    readonly property string formattedTime: {
    const total = Math.max(0, remainingSeconds);
    const hours = Math.floor(total / 3600);
    const mins  = Math.floor((total % 3600) / 60);
    const secs  = total % 60;

    const mm = (hours > 0 && mins < 10) ? "0" + mins : String(mins);
    const ss = secs < 10 ? "0" + secs : String(secs);

    if (hours > 0) return `${hours}:${mm}:${ss}`;
    return `${mm < 10 ? "0" + mm : mm}:${ss}`;
}

    // ── Internal 1s Ticker ───────────────────────────────────────
    Timer {
        id: ticker
        interval: 1000
        repeat: true
        running: root.isRunning
        onTriggered: {
            if (root.remainingSeconds > 1) {
                root.remainingSeconds -= 1;
            } else {
                root.remainingSeconds = 0;
                root.isRunning = false;
                root.onTimerFinished();
            }
        }
    }

    // ── Daily reset check ────────────────────────────────────────
    function checkDayRollover(): void {
        const today = new Date().toISOString().slice(0, 10);
        if (root.sessionDate !== today) {
            root.sessionDate = today;
            root.sessionsToday = 0;
        }
    }

    Component.onCompleted: checkDayRollover()

    function onTimerFinished(): void {
        // Count a completed work session
        if (root.mode === "work" || root.mode === "custom") {
            checkDayRollover();
            root.sessionsToday += 1;
        }

        const title = root.mode === "work" ? Tr.tr("Focus Session Complete!") : Tr.tr("Break Finished!");
        const msg = root.linkedTaskTitle.length > 0
            ? Tr.tr("Time is up for task: %1").arg(root.linkedTaskTitle)
            : (root.mode === "work" ? Tr.tr("Great job! Take a short break.") : Tr.tr("Ready to focus again?"));
        const icon = root.mode === "work" ? "check_circle" : "coffee";

        Toaster.toast(title, msg, icon);
    }

    // ── Public Controls ──────────────────────────────────────────
    function start(): void {
        if (remainingSeconds <= 0)
            reset();
        isRunning = true;
    }

    function pause(): void {
        isRunning = false;
    }

    function toggle(): void {
        if (isRunning) pause();
        else start();
    }

    function reset(): void {
        isRunning = false;
        if (mode === "work") {
            setPreset("work", 25);
        } else if (mode === "shortBreak") {
            setPreset("shortBreak", 5);
        } else if (mode === "longBreak") {
            setPreset("longBreak", 15);
        } else {
            remainingSeconds = totalDurationSeconds;
        }
    }

    function setPreset(newMode: string, minutes: int): void {
        mode = newMode;
        totalDurationSeconds = Math.max(1, minutes) * 60;
        remainingSeconds = totalDurationSeconds;
    }

    // ── Adjust the current duration by ±N minutes ────────────────
    // Called from keyboard (Up/Down) in the timer pill.
    // Extends/shrinks both totalDurationSeconds and remainingSeconds
    // so progress stays sensible. Clamps to [1 min, 240 min].
    function adjustMinutes(delta: int): void {
        if (!delta) return;

        const MIN_SECONDS = 60;
        const MAX_SECONDS = 240 * 60;

        // New total = old total + delta*60, clamped
        let newTotal = totalDurationSeconds + delta * 60;
        newTotal = Math.max(MIN_SECONDS, Math.min(MAX_SECONDS, newTotal));

        // New remaining = old remaining + delta*60, clamped to [0, newTotal]
        let newRemaining = remainingSeconds + delta * 60;
        newRemaining = Math.max(0, Math.min(newTotal, newRemaining));

        totalDurationSeconds = newTotal;
        remainingSeconds = newRemaining;

        // If paused and remaining == 0 (only possible if user pushed down past 0),
        // keep it at 0; user can press play to reset from preset.
    }

    function startForTask(taskId: string, title: string, minutes: int): void {
        linkedTaskId = taskId ?? "";
        linkedTaskTitle = title ?? "";
        const dur = (minutes && minutes > 0) ? minutes : 25;
        mode = "custom";
        totalDurationSeconds = dur * 60;
        remainingSeconds = totalDurationSeconds;
        isRunning = true;
    }

    function clearLinkedTask(): void {
        linkedTaskId = "";
        linkedTaskTitle = "";
    }
}