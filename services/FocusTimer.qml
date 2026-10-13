pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.services

Singleton {
    id: root

    // ── Timer State ──────────────────────────────────────────────
    property bool isRunning: false
    property int remainingSeconds: 25 * 60
    property int totalDurationSeconds: 25 * 60
    property string mode: "work" // "work" | "break" | "stopwatch" | "custom"

    // ── Stopwatch elapsed counter ────────────────────────────────
    property int elapsedSeconds: 0

    // ── Linked Task Context ──────────────────────────────────────
    property string linkedTaskId: ""
    property string linkedTaskTitle: ""

    // ── Session counter (resets at midnight) ────────────────────
    property int sessionsToday: 0
    property string sessionDate: ""

    // ── Pomodoro Cycle Tracking ─────────────────────────────────
    property int pomodorosInCycle: 0

    // ── Sound chime process ─────────────────────────────────────
    Process {
        id: soundProc
    }

    function playChime(): void {
        const sounds = [
            "/usr/share/sounds/freedesktop/stereo/complete.oga",
            "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga",
            "/usr/share/sounds/freedesktop/stereo/bell.oga"
        ];
        // Use pw-play or canberra-gtk-play
        soundProc.exec(["pw-play", sounds[0]]);
    }

    // ── Computed Progress ────────────────────────────────────────
    readonly property real progress: {
        if (mode === "stopwatch") {
            // Smooth pulsating or continuous 60s cycle for stopwatch ring
            return (elapsedSeconds % 60) / 60.0;
        }
        return totalDurationSeconds > 0
            ? Math.max(0, Math.min(1, 1 - (remainingSeconds / totalDurationSeconds)))
            : 0;
    }

    readonly property string formattedTime: {
        const total = mode === "stopwatch" ? Math.max(0, elapsedSeconds) : Math.max(0, remainingSeconds);
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
            if (root.mode === "stopwatch") {
                root.elapsedSeconds += 1;
            } else if (root.remainingSeconds > 1) {
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
            root.pomodorosInCycle = 0;
        }
    }

    Component.onCompleted: checkDayRollover()

    function onTimerFinished(): void {
        checkDayRollover();

        // Play audio chime
        playChime();

        if (root.mode === "work" || root.mode === "custom") {
            root.sessionsToday += 1;
            root.pomodorosInCycle += 1;

            const title = Tr.tr("Focus Session Complete!");
            const msg = root.linkedTaskTitle.length > 0
                ? Tr.tr("Time is up for task: %1. Take a break!").arg(root.linkedTaskTitle)
                : Tr.tr("Great job! Take a 5m break.");

            Toaster.toast(title, msg, "check_circle");
            setPreset("break", 5);
        } else {
            // Break finished
            const title = Tr.tr("Break Finished!");
            const msg = Tr.tr("Ready to start your next focus session?");
            Toaster.toast(title, msg, "coffee");
            setPreset("work", 25);
        }
    }

    // ── Public Controls ──────────────────────────────────────────
    function start(): void {
        if (mode !== "stopwatch" && remainingSeconds <= 0)
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
        if (mode === "stopwatch") {
            elapsedSeconds = 0;
        } else if (mode === "work") {
            setPreset("work", 25);
        } else if (mode === "break" || mode === "shortBreak" || mode === "longBreak") {
            setPreset("break", 5);
        } else {
            remainingSeconds = totalDurationSeconds;
        }
    }

    function setPreset(newMode: string, minutes: int): void {
        mode = newMode;
        if (newMode === "stopwatch") {
            elapsedSeconds = 0;
            totalDurationSeconds = 0;
            remainingSeconds = 0;
        } else {
            totalDurationSeconds = Math.max(1, minutes) * 60;
            remainingSeconds = totalDurationSeconds;
        }
    }

    // ── Adjust current duration by ±N minutes ────────────────────
    function adjustMinutes(delta: int): void {
        if (!delta || mode === "stopwatch") return;

        const MIN_SECONDS = 60;
        const MAX_SECONDS = 240 * 60;

        let newTotal = totalDurationSeconds + delta * 60;
        newTotal = Math.max(MIN_SECONDS, Math.min(MAX_SECONDS, newTotal));

        let newRemaining = remainingSeconds + delta * 60;
        newRemaining = Math.max(0, Math.min(newTotal, newRemaining));

        totalDurationSeconds = newTotal;
        remainingSeconds = newRemaining;
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