pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.I18n
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
    property int elapsedMillis: 0
    property double _stopwatchStart: 0
    property double _stopwatchAccumulated: 0

    // ── Linked Task Context ──────────────────────────────────────
    property string linkedTaskId: ""
    property string linkedTaskTitle: ""
    property int taskTotalMinutes: 0
    property int taskRemainingSeconds: 0
    property int phaseMinutes: 25

    function formatDuration(totalMins: int): string {
        if (totalMins <= 0) return "0m";
        const h = Math.floor(totalMins / 60);
        const m = totalMins % 60;
        if (h > 0 && m > 0) return `${h}h${m}mn`;
        if (h > 0) return `${h}h`;
        return `${m}mn`;
    }

    readonly property string taskPhaseString: {
        if (!linkedTaskId || taskTotalMinutes <= 0) return "";
        const currentPhaseMins = Math.min(phaseMinutes, Math.ceil(totalDurationSeconds / 60));
        const totalStr = formatDuration(taskTotalMinutes);
        return `${currentPhaseMins}m/${totalStr}`;
    }

    // ── Session counter (resets at midnight) ────────────────────
    property int sessionsToday: 0
    property string sessionDate: ""

    // ── Pomodoro Cycle Tracking ─────────────────────────────────
    property int pomodorosInCycle: 0

    function playChime(): void {
        // Wake display if blanked/DPMS off
        Hypr.dispatch(Hypr.usingLua ? "hl.dsp.dpms({ action = 'enable' })" : "dpms on");

        const sound = "/usr/share/sounds/gnome/default/alarms/glass-bell.oga";
        Quickshell.execDetached(["pw-play", sound]);
    }

    // ── Computed Progress ────────────────────────────────────────
    readonly property real progress: {
        if (mode === "stopwatch") {
            // Smooth continuous 60s sweep for stopwatch ring
            return ((elapsedMillis % 60000) / 60000.0);
        }
        return totalDurationSeconds > 0
            ? Math.max(0, Math.min(1, 1 - (remainingSeconds / totalDurationSeconds)))
            : 0;
    }

    readonly property string formattedSeconds: {
        const total = mode === "stopwatch" ? Math.max(0, elapsedSeconds) : Math.max(0, remainingSeconds);
        const hours = Math.floor(total / 3600);
        const mins  = Math.floor((total % 3600) / 60);
        const secs  = total % 60;

        const mm = (hours > 0 && mins < 10) ? "0" + mins : String(mins);
        const ss = secs < 10 ? "0" + secs : String(secs);

        if (hours > 0) return `${hours}:${mm}:${ss}`;
        return `${mm < 10 ? "0" + mm : mm}:${ss}`;
    }

    readonly property string formattedTime: {
        if (mode === "stopwatch") {
            const ms = Math.max(0, elapsedMillis);
            const hours = Math.floor(ms / 3600000);
            const mins  = Math.floor((ms % 3600000) / 60000);
            const secs  = Math.floor((ms % 60000) / 1000);
            const cs    = Math.floor((ms % 1000) / 10);

            const mm = (hours > 0 && mins < 10) ? "0" + mins : String(mins);
            const ss = secs < 10 ? "0" + secs : String(secs);
            const csStr = cs < 10 ? "0" + cs : String(cs);

            if (hours > 0) return `${hours}:${mm}:${ss}.${csStr}`;
            return `${mm < 10 ? "0" + mm : mm}:${ss}.${csStr}`;
        }
        return formattedSeconds;
    }

    // ── Internal 1s Ticker (Work/Break) ──────────────────────────
    Timer {
        id: ticker
        interval: 1000
        repeat: true
        running: root.isRunning && root.mode !== "stopwatch"
        onTriggered: {
            if (root.remainingSeconds > 1) {
                root.remainingSeconds -= 1;
                if (root.taskRemainingSeconds > 1) {
                    root.taskRemainingSeconds -= 1;
                }
            } else {
                root.remainingSeconds = 0;
                if (root.taskRemainingSeconds > 0) {
                    root.taskRemainingSeconds = Math.max(0, root.taskRemainingSeconds - 1);
                }
                root.isRunning = false;
                root.onTimerFinished();
            }
        }
    }

    // ── High-frequency Ticker (Stopwatch, ~30 FPS) ───────────────
    Timer {
        id: stopwatchTicker
        interval: 33
        repeat: true
        running: root.isRunning && root.mode === "stopwatch"
        onTriggered: {
            const now = Date.now();
            root.elapsedMillis = Math.floor(root._stopwatchAccumulated + (now - root._stopwatchStart));
            root.elapsedSeconds = Math.floor(root.elapsedMillis / 1000);
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

        // Play audio chime and wake display
        playChime();

        if (root.mode === "work" || root.mode === "custom") {
            root.sessionsToday += 1;
            root.pomodorosInCycle += 1;

            if (root.linkedTaskId.length > 0 && root.taskRemainingSeconds > 0) {
                const remMins = Math.ceil(root.taskRemainingSeconds / 60);
                const title = Tr.tr("Phase Complete!");
                const msg = Tr.tr("25m phase done for %1 (%2 left). Take a 5m break!").arg(root.linkedTaskTitle).arg(root.formatDuration(remMins));
                Toaster.toast(title, msg, "check_circle");
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Focus Timer", "-i", "alarm", title, msg]);
                setPreset("break", 5);
            } else if (root.linkedTaskId.length > 0) {
                const title = Tr.tr("Task Completed!");
                const msg = Tr.tr("All phases finished for: %1!").arg(root.linkedTaskTitle);
                Toaster.toast(title, msg, "check_circle");
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Focus Timer", "-i", "alarm", title, msg]);
                root.clearLinkedTask();
                setPreset("work", 25);
            } else {
                const title = Tr.tr("Focus Session Complete!");
                const msg = Tr.tr("Great job! Take a 5m break.");
                Toaster.toast(title, msg, "check_circle");
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Focus Timer", "-i", "alarm", title, msg]);
                setPreset("break", 5);
            }
        } else {
            // Break finished
            if (root.linkedTaskId.length > 0 && root.taskRemainingSeconds > 0) {
                const nextPhaseMins = Math.min(root.phaseMinutes, Math.ceil(root.taskRemainingSeconds / 60));
                root.mode = "work";
                root.totalDurationSeconds = nextPhaseMins * 60;
                root.remainingSeconds = root.totalDurationSeconds;
                root.isRunning = false;

                const title = Tr.tr("Break Finished!");
                const msg = Tr.tr("Ready for the next %1m phase on %2?").arg(nextPhaseMins).arg(root.linkedTaskTitle);
                Toaster.toast(title, msg, "coffee");
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Focus Timer", "-i", "alarm", title, msg]);
            } else {
                const title = Tr.tr("Break Finished!");
                const msg = Tr.tr("Ready to start your next focus session?");
                Toaster.toast(title, msg, "coffee");
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Focus Timer", "-i", "alarm", title, msg]);
                setPreset("work", 25);
            }
        }
    }

    // ── Public Controls ──────────────────────────────────────────
    function start(): void {
        if (mode === "stopwatch") {
            _stopwatchStart = Date.now();
        } else if (remainingSeconds <= 0) {
            reset();
        }
        isRunning = true;
    }

    function pause(): void {
        if (mode === "stopwatch" && isRunning) {
            _stopwatchAccumulated += (Date.now() - _stopwatchStart);
            elapsedMillis = Math.floor(_stopwatchAccumulated);
            elapsedSeconds = Math.floor(elapsedMillis / 1000);
        }
        isRunning = false;
    }

    function toggle(): void {
        if (isRunning) pause();
        else start();
    }

    function reset(): void {
        isRunning = false;
        if (mode === "stopwatch") {
            _stopwatchStart = 0;
            _stopwatchAccumulated = 0;
            elapsedMillis = 0;
            elapsedSeconds = 0;
        } else if (mode === "work" || mode === "custom") {
            if (linkedTaskId.length > 0 && taskRemainingSeconds > 0) {
                const phaseMins = Math.min(phaseMinutes, Math.ceil(taskRemainingSeconds / 60));
                totalDurationSeconds = phaseMins * 60;
                remainingSeconds = totalDurationSeconds;
            } else {
                setPreset("work", 25);
            }
        } else if (mode === "break" || mode === "shortBreak" || mode === "longBreak") {
            setPreset("break", 5);
        } else {
            remainingSeconds = totalDurationSeconds;
        }
    }

    function setPreset(newMode: string, minutes: int): void {
        isRunning = false;
        mode = newMode;
        if (newMode === "stopwatch") {
            _stopwatchStart = 0;
            _stopwatchAccumulated = 0;
            elapsedMillis = 0;
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
        taskTotalMinutes = dur;
        taskRemainingSeconds = dur * 60;

        // Split into 25m work phases
        const phaseMins = Math.min(phaseMinutes, dur);
        mode = "work";
        totalDurationSeconds = phaseMins * 60;
        remainingSeconds = totalDurationSeconds;
        isRunning = true;
    }

    function clearLinkedTask(): void {
        linkedTaskId = "";
        linkedTaskTitle = "";
        taskTotalMinutes = 0;
        taskRemainingSeconds = 0;
    }
}