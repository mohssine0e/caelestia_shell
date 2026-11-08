# Tasks Popout Audit

**Scope:** Source review of the restored `2ca4cf5` checkout. No application code was changed. No UI sizes or persistence behavior were runtime-tested.

## Summary

The tasks popout combines task lists, daily focus notes, and command views. Main risks are fixed sizing, weak recovery when JSON is malformed or writes are interrupted, misleading seeded daily-focus examples, and unclear coupling between task records and the in-memory focus timer.

## Findings

### High priority: fixed dimensions can make the popout unusable on some screens

The root view sets its width to 1040 and height to 720 ([modules/tasks/Tasks.qml:15](modules/tasks/Tasks.qml#L15)). This may exceed smaller screens or become cramped at high display scaling.

**Recommended action:** Size the popout against the active screen with sensible minimum and maximum bounds. Add a compact layout and make the list/editor scroll independently.

### High priority: task JSON needs corruption and interrupted-write recovery

Task data is loaded through JSON parsing and a missing file is initialized to an empty array ([modules/tasks/TaskList.qml:760](modules/tasks/TaskList.qml#L760)). The visible persistence code writes JSON directly ([modules/tasks/TaskList.qml:801](modules/tasks/TaskList.qml#L801)). An interrupted write can leave invalid data, and an empty fallback risks hiding recoverable content.

**Recommended action:** Validate the task schema, preserve malformed source files, write atomically, and show load/save errors. Ensure the app does not save until initial loading has completed successfully.

### High priority: daily focus seeds example content and may save it as user data

When daily-focus data is missing or cannot be parsed, default groups contain example notes such as “Deploy staging” and “Review auth PR” ([modules/tasks/DailyFocusBanner.qml:63](modules/tasks/DailyFocusBanner.qml#L63)). Missing-file handling calls `requestSave()` ([modules/tasks/DailyFocusBanner.qml:99](modules/tasks/DailyFocusBanner.qml#L99)), which can persist those examples as if they were actual notes.

**Recommended action:** Default to empty notes or mark sample content unmistakably. Do not persist examples as user data without an explicit action. Preserve malformed input for recovery.

### Medium priority: task and timer linkage needs a stable lifecycle

Task timing is held in the timer singleton rather than a durable task session. The timer state is lost on shell restart, and stale linked task titles may remain if task data changes while a session is active.

**Recommended action:** Store the linked task ID in a session record and resolve its current title from task data. If a task is deleted or unavailable, show that the session is unlinked while preserving elapsed effort.

### Medium priority: destructive actions and save state need consistent feedback

The tasks view contains multiple task and subtask operations and persistence triggers. The source review did not establish a consistent undo and save-status experience across all operations.

**Recommended action:** Add visible save status, undo for deletion and bulk changes, and confirmation for deleting populated task trees. Keep keyboard focus and filter state stable after edits.

### Medium priority: user data files need a clear privacy and backup policy

Task and daily-focus content is persisted locally in JSON. This review did not verify file permissions or backup behavior.

**Recommended action:** Verify restrictive permissions, use atomic writes, and provide export/backup and delete controls. Explain where task data is stored.

## Recommended order

1. Harden task and daily-focus loading and saving, preserving invalid files for recovery.
2. Remove or clearly label seeded example notes and avoid silently saving them.
3. Make the popout responsive to screen size and scaling.
4. Define stable task/timer linkage and recovery after restart or task deletion.
5. Add consistent undo, save status, keyboard focus, and destructive-action feedback.

## Verification still needed

- Test on the smallest supported display and at high UI scaling.
- Simulate malformed and interrupted JSON writes using copies of data, not the live files.
- Confirm deletion and bulk actions can be undone or recovered.
- Inspect file permissions after initial creation and subsequent saves.

