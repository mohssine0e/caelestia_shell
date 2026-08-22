# Next productivity features

The current model is already suitable for extending both tasks and habits:

```js
{
    todoId: String,
    title: String,
    done: Boolean,
    icon: String | null,
    minutes: Number,
    priority: Number | null,
    createdAt: Number,
    subtasks: [{ id, title, done, minutes }]
}
```

Keep new features as fields on this object so tasks and habits continue to use
the same `TaskList`, `DataManager`, and `TaskCard` pipeline.

## Habit streak counter

Add a `completionDates` array to habits:

```js
completionDates: ["2026-08-20", "2026-08-21"]
```

When a habit is toggled on, append today's ISO date if it is not present. When
it is toggled off, remove today's date. Calculate the current streak by walking
backward from today until the first missing date. Keep this calculation in a
small `HabitStats.js` helper or in `DataManager`, not inside every delegate.

Show a compact `3 day streak` label beside the habit progress, and use a
different label for the best streak. Do not infer streaks from `done` alone;
`done` only describes today's state.

## Estimated time

The task already has `minutes`, and each subtask has its own `minutes` field.
Add a small stepper or numeric field in the edit/action area:

```qml
SpinBox {
    from: 0
    to: 1440
    stepSize: 5
    value: taskData.minutes || 0
    onValueModified: dataManager.setTaskEstimate(taskIndex, value)
}
```

For a task with subtasks, display both the explicit estimate and the sum of
subtask estimates. Make the sum a read-only hint; do not silently overwrite a
parent estimate chosen by the user.

## Priority

Use a small integer field, for example `0` none, `1` low, `2` medium, `3`
high. Add a compact icon or color marker to `TaskCard`, and add priority as a
secondary sort/filter in `DataManager.getFilteredTasks()`.

Keep the filter optional and preserve insertion order when priorities are equal.
That makes prioritization useful without making the list jump unexpectedly.

## Focused work mode

Add a `focusTaskId` property to `TaskList`. A focus button on the card can:

1. mark one task as the active work item;
2. show only that task and its subtasks in a focused view;
3. restore the normal list without changing task data.

This is more useful than another global filter because it reduces visual noise
while working on one item.

## Subtask progress improvements

Keep the existing `nSub`, `dSub`, and `prog` values, but add a clear rule:

- a task with no subtasks uses its own `done` value;
- a task with subtasks derives completion from all leaf subtasks;
- toggling a parent toggles all leaf subtasks.

Put this rule in one `syncDone()` function and call it after every mutation.
Avoid separate completion logic in `TaskCard` and `TaskList`.

## Better capture workflow

Support lightweight prefixes in the capture field without adding a modal:

```text
!high Read chapter
@15 Review notes
```

Parse the prefix before creating the task, assigning priority or minutes. Keep
the original title clean. This makes capture fast from the keyboard.

## Useful keyboard actions

Add shortcuts only for actions used repeatedly:

- `j` / `k`: move selection;
- `space`: toggle selected item;
- `e`: edit title;
- `x`: delete selected item;
- `o`: open or close subtasks;
- `p`: cycle priority;
- `+`: focus the capture field.

Keep these in the list's `Keys` handler and ensure text fields accept normal
typing before handling a shortcut.

## Daily review indicators

Add small summary values above the list:

- active task count;
- completed task count;
- total estimated active minutes;
- habit streak total.

These should be computed once on the list root and exposed as read-only
properties. Do not recalculate them independently inside every card.

## Data integrity and performance

- Normalize every loaded ID to a string.
- Replace arrays instead of mutating nested objects in place.
- Preserve unknown fields with `Object.assign` when updating a task.
- Debounce search text by roughly 100ms for large lists.
- Save after a completed mutation, not during every visual binding update.
- Keep one resident `TaskList` per page while the popout is open; avoid
  repeatedly constructing file-backed component trees during animation.

The highest-value next steps are streaks, estimates, and priority. Together
they turn the list from a checklist into a planning surface without adding
reminders, due dates, or notification complexity.
