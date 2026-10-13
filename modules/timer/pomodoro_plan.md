# Pomodoro Timer "Little Window" & Task Integration Plan

## 1. Overview & Goals
Build a lightweight, clean Pomodoro / Focus Timer window with mode presets (Work, Short Break, Long Break, or custom durations) and dropdown selection.
The timer will run continuously in the background (surviving window close / popout hide) and can be triggered either independently or directly by clicking the time/minutes chip on any task card.

---

## 2. Architecture & Components

```
┌────────────────────────────────────────────────────────┐
│             FocusTimer Service (Singleton)             │
│  - State: remainingSeconds, totalSeconds, isRunning    │
│  - Mode: "work" (25m) | "shortBreak" (5m) | "longBreak"│
│  - Active Context: taskId, taskTitle, originalEstimate │
│  - Actions: start(), pause(), reset(), setMode()       │
│  - Notifications: Toaster on completion                │
└──────────────────────────┬─────────────────────────────┘
                           │
             ┌─────────────┴─────────────┐
             ▼                           ▼
┌───────────────────────────┐ ┌──────────────────────────┐
│   Timer Window / Popup    │ │   Tasks Module Cards     │
│   (Pomodoro Popout / Win) │ │   - TaskCard             │
│ - Compact elegant card    │ │   - SubtaskCard          │
│ - Circular progress & text│ │   - NestedSubtaskCard    │
│ - Mode dropdown / selector│ │                          │
│ - Play / Pause / Skip     │ │ When user clicks the     │
│ - Linked task banner/chip │ │ minutes chip → starts    │
└───────────────────────────┘ │ timer with task context  │
                              └──────────────────────────┘
```

---

## 3. Detailed Component Plan

### A. FocusTimer Service (`services/FocusTimer.qml`)
- **Singleton state engine**: Keeps ticking even when UI windows close or drawers toggle.
- **Properties**:
  - `isRunning`: `bool`
  - `remainingSeconds`: `int`
  - `totalDurationSeconds`: `int`
  - `mode`: `"work"` | `"shortBreak"` | `"longBreak"` | `"custom"`
  - `linkedTaskId`: `string` (empty if standalone)
  - `linkedTaskTitle`: `string`
- **Presets & Dropdown Options**:
  - `Work (25m)`
  - `Short Break (5m)`
  - `Long Break (15m)`
  - `Custom / Task estimate`
- **Methods**:
  - `start()`, `pause()`, `toggle()`
  - `reset()`
  - `setPreset(mode, minutes)`
  - `startForTask(taskId, taskTitle, minutes)`
- **Alert / Notification**:
  - On finish (`remainingSeconds === 0`), invoke `Toaster.toast(...)` ("Focus session complete!" / "Break over!").

### B. Little Timer Window / Dropdown (`modules/tasks/PomodoroWindow.qml` or Bar Popout)
- **Compact & Minimal Surface**:
  - Matching Caelestia design language (`Tokens`, `Colours.palette`, Material 3).
  - Floating or anchored window / popout overlay.
- **Visuals & Controls**:
  1. **Mode Dropdown / Selector**:
     - Using `SplitButton` (same as Category/Status dropdowns) to pick `Work (25m)`, `Short Break (5m)`, `Long Break (15m)`.
  2. **Linked Task Pill**:
     - Shows current task title if launched from a task card (with an unlink/close icon).
  3. **Timer Display**:
     - `CircularProgress` with animated stroke or sleek digital `MM:SS` display in `Tokens.font.display.medium`.
  4. **Action Controls**:
     - `IconButton` play/pause (`play_arrow` / `pause`).
     - Reset / Stop button (`replay` / `stop`).
     - Skip session button (`skip_next`).

### C. Task Card Integration (Phase 2 Linkage)
- Enhance the minutes chip (`RowLayout` with `minutesLabel` in `TaskCard.qml`, `SubtaskCard.qml`, and `NestedSubtaskCard.qml`):
  - Add hover state / pointer cursor.
  - Add an inline play/timer icon or click handler.
  - On click: calls `FocusTimer.startForTask(id, title, duration)` and opens/shows the timer window.
  - If a timer is currently active for this task, show a pulsing or highlight color on the minutes chip!

---

## 4. Phased Implementation Roadmap

### Phase 1: General Timer Window & Core Engine (Current Focus)
1. **Create `services/FocusTimer.qml`**:
   - Background 1s timer, mode switching, play/pause/reset functions.
2. **Create the Timer UI Component / Little Window**:
   - Dropdown for interval selection.
   - Timer countdown display + Play/Pause/Reset buttons.
   - Test standalone behavior and notifications.

### Phase 2: Link to Tasks Popout & Minutes Chip
1. Connect minutes chip in `TaskCard`, `SubtaskCard`, and `NestedSubtaskCard` to trigger `FocusTimer.startForTask`.
2. Display the linked task info inside the timer window.
3. Add active session indicators on the task cards.
