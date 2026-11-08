# Focus Timer Audit

**Scope:** Source review of the restored `2ca4cf5` checkout. No application code was changed. Suspend/resume timing and desktop notification behavior were not runtime-tested.

## Summary

The timer supports countdown, stopwatch, linked-task phases, notifications, and a floating view. The most concrete logic defect is that linked-task time is decremented during breaks. Timer state is also in memory only, daily rollover uses UTC, and notifications/window titles can expose task names.

## Findings

### High priority: linked-task estimate decreases during breaks

The one-second ticker decrements `taskRemainingSeconds` whenever the timer runs, without checking whether the mode is work or break ([services/FocusTimer.qml:105](services/FocusTimer.qml#L105)). As a result, taking a break consumes the linked task's remaining estimate.

**Recommended action:** Decrement task effort only during work phases. Track break duration independently and test transitions at phase completion, pause, reset, and preset changes.

### High priority: task estimate semantics are not protected across timer controls

Starting a linked task initializes its remaining estimate in memory ([services/FocusTimer.qml:285](services/FocusTimer.qml#L285)). Preset changes and reset alter timer phase state, but the code does not define a durable or user-visible policy for whether the task estimate represents planned effort or remaining effort ([services/FocusTimer.qml:227](services/FocusTimer.qml#L227)).

**Recommended action:** Define task estimate semantics explicitly. Keep task effort separate from phase duration and ensure changing presets or resetting a phase cannot silently rewrite task progress.

### Medium priority: timer state is lost on shell restart

Timer mode, remaining time, linked task, and session counters are properties in the singleton and no persistence is visible in `FocusTimer.qml` ([services/FocusTimer.qml:13](services/FocusTimer.qml#L13)). Restarting the shell therefore loses the active session and linked-task context.

**Recommended action:** Persist a small session record, including an absolute deadline for countdown mode. On restart, offer resume or discard and handle deleted/unavailable linked tasks safely.

### Medium priority: countdown timing can drift

Countdown time is decremented by a repeating one-second UI timer ([services/FocusTimer.qml:105](services/FocusTimer.qml#L105)). Delayed event processing or system suspend may make the displayed time diverge from elapsed wall time.

**Recommended action:** Store a deadline timestamp and derive remaining time from it. Decide whether suspend counts as elapsed time and communicate that behavior in the UI.

### Medium priority: daily session reset uses UTC

The daily date key comes from `new Date().toISOString()` ([services/FocusTimer.qml:141](services/FocusTimer.qml#L141)). This can reset the session counter at an unexpected local time.

**Recommended action:** Use the local calendar date and check rollover during the service lifetime. Persist counters if they are intended to survive restarts.

### Medium priority: notifications reveal linked task names

Completion notifications include the linked task title and use critical urgency ([services/FocusTimer.qml:163](services/FocusTimer.qml#L163)). Desktop notifications can appear on screen or remain in notification history.

**Recommended action:** Add a privacy setting to hide task names, lower urgency by default, and make sound and display-wake behavior configurable.

### Medium priority: floating window title contains task details

The floating window title includes the linked task title, phase, and countdown ([modules/timer/TimerFloating.qml:38](modules/timer/TimerFloating.qml#L38)). Window titles may be visible to window switchers, screen recordings, or other desktop integrations.

**Recommended action:** Remove task text from the window title by default or make it optional. Show the task name inside the timer UI where the user can control its visibility.

### UI improvement: timer state and controls need clearer feedback

The mini view has a compact fixed width and expands on hover or when linked to a task ([modules/timer/TimerMini.qml:15](modules/timer/TimerMini.qml#L15)). It should clearly distinguish work, break, and stopwatch state and explain when linked task effort is being counted.

**Recommended action:** Add explicit labels and task-time feedback, make keyboard focus visible, and ensure the panel remains usable at high display scaling and on small screens.

## Recommended order

1. Fix task-time subtraction during breaks.
2. Define task estimate behavior across reset, preset change, and phase transitions.
3. Use deadline-based countdown timing and decide suspend behavior.
4. Add session recovery after restart and use local-date rollover.
5. Add privacy controls for notification contents and floating window titles.

## Verification still needed

- Test pause/resume and work/break transitions, including exactly-at-zero boundaries.
- Test timing over suspend and delayed UI processing.
- Confirm notification urgency, visibility, and history behavior on the target desktop.

