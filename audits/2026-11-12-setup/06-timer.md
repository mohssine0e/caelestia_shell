# Focus timer and floating timer

**Judgment:** the compact timer is useful, but its time model needs correction before adding statistics or stronger task automation.

## Current → proposed

| ID / priority | Current evidence | Needed change |
|---|---|---|
| F01 · P1 | **Confirmed:** the countdown ticker subtracts linked-task time during all countdown modes, including breaks. [FocusTimer:105](../../services/FocusTimer.qml#L105) | Count task effort only during work/custom work phases. Breaks never reduce remaining task effort. |
| F02 · P1 | **Confirmed source risk:** countdown subtracts one second per UI timer callback, so delayed callbacks/suspend can diverge from elapsed time. Stopwatch uses timestamps already. [FocusTimer:111](../../services/FocusTimer.qml#L111), [FocusTimer:129](../../services/FocusTimer.qml#L129) | Derive countdown from a deadline; track work effort separately. Define suspend and clock-change behavior explicitly. A reasonable initial policy is to reconcile on resume and ask whether to continue a paused work session. |
| F03 · P1 | **Confirmed:** active session, linked task and counters exist only as singleton properties. [FocusTimer:13](../../services/FocusTimer.qml#L13) | Persist a small versioned session record on meaningful transitions. Restore paused/running/finished state correctly after reload or crash. Avoid writing every animation tick. |
| F04 · P2 | **Confirmed:** reset/preset changes alter phases while task remaining effort stays separate; switching to another task replaces the link immediately. [FocusTimer:231](../../services/FocusTimer.qml#L231), [FocusTimer:253](../../services/FocusTimer.qml#L253), [FocusTimer:286](../../services/FocusTimer.qml#L286) | Define Reset phase, Change duration, Unlink, and Switch task separately. Preserve already-recorded effort; show the effect of replacing an active task. |
| F05 · P2 | **Confirmed:** a used-up estimate says “Task Completed!” without updating task completion; phase text hardcodes 25 minutes. [FocusTimer:163](../../services/FocusTimer.qml#L163) | Say “Planned time finished.” Offer Mark done / Continue / Add time. Use the actual phase duration in feedback. Time spent alone does not prove completion. |
| F06 · P2 | **Confirmed:** daily counters use a UTC date, whereas habits use a local 02:00 day boundary. [FocusTimer:142](../../services/FocusTimer.qml#L142) | Choose and explain one local-day policy for stats. Reconcile on resume and relevant date/timezone changes. Keep habit-specific reset configurable. |
| F07 · P2 | **Confirmed:** completion wakes the display, plays a hardcoded sound, emits a toast and critical desktop notification. Window title includes task details and updates with time. [FocusTimer:55](../../services/FocusTimer.qml#L55), [TimerFloating:38](../../modules/timer/TimerFloating.qml#L38) | Normal urgency by default; user controls for sound/wake/task-name privacy. Avoid duplicate notifications. Use a stable window title unless detailed titles are explicitly enabled. |
| F08 · P2 | **Confirmed:** stopwatch ticks at 33 ms even if no timer view is visible; hover automatically expands/contracts the mini window. [FocusTimer:129](../../services/FocusTimer.qml#L129), [TimerMini:93](../../modules/timer/TimerMini.qml#L93) | Use high-frequency display updates only when visible. Keep real elapsed time timestamp-based. Provide explicit expansion that also works from keyboard and does not collapse under the pointer. |

## Proposed presentation

| Compact view | Expanded view |
|---|---|
| Phase name, remaining/elapsed time, Start/Pause, Expand | Task label, work recorded, remaining estimate, duration/preset, Reset phase, Unlink |
| Clear paused/finished distinction beyond color | Explain the effect of changing mode or duration |
| Stable width and readable time | Scroll only when content truly exceeds available space |

Timer bar popout and floating view should be two presentations of the same state/actions. Preserve existing keyboard shortcuts, with labels/tooltips where discovery is difficult.

## Acceptance checks

- A 50-minute task after 25 minutes work and 5 minutes break still has **25 minutes** of planned work remaining.
- Pause/resume, repeated Start, reset, mode switch, ±duration, task switch, and unlink do not double-count or erase effort.
- Handle a 20-minute task, a partial final phase, a task renamed/deleted during a phase, and zero-boundary events.
- Reload, crash recovery, suspend/resume, local midnight and clock changes produce the documented result; completion fires once.
- Hidden stopwatch display updates are reduced while elapsed time remains correct.
- Test normal notification mode and task-name privacy without sending duplicate alerts.

**Files:** `services/FocusTimer.qml`, `modules/timer/{TimerFloating,TimerMini}.qml`, `modules/bar/popouts/TimerPopout.qml`, `modules/tasks/TaskTimerChip.qml`, and task-store event integration. Session persistence needs the same recovery guarantees as other stores.
