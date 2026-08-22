# Tasks module: rendering diagnosis and next-level fix

## What is stopping the cards from rendering

The primary failure is in the `Repeater` delegates in `TaskList.qml` and
`DailyHabitsList.qml`.

Both repeaters use a `ListModel` whose rows are appended as `{ todoId: id }`,
but the delegate declares:

```qml
required property string modelData
```

`modelData` is not the role supplied by a `ListModel` row. The role is
`todoId`. With `pragma ComponentBehavior: Bound`, a required property that is
not supplied prevents the delegate from being constructed, so the repeater is
empty even when the JSON contains data. The same mistake appears in the
subtask repeater: its model rows contain an `id` role, not `modelData`.

### Minimal delegate fix

In both `TaskList.qml` and `DailyHabitsList.qml`, replace the delegate
header and all uses of `modelData` with the actual role:

```qml
delegate: TaskCard {
    required property string todoId
    required property int index

    readonly property var task: taskMap[todoId] ?? {
        todoId: todoId,
        title: "",
        done: false,
        icon: null,
        priority: null,
        minutes: 0,
        subtasks: []
    }
    readonly property int absIdx: taskIndexMap[todoId] ?? -1
    // Use todoId everywhere else in this delegate.
}
```

For the subtask repeater in `TaskCard.qml`, use the `id` role:

```qml
delegate: SubtaskCard {
    required property string id
    required property int index

    readonly property var sub: root.subtaskMap[id] ?? {
        id: id, title: "", done: false
    }
    subtaskId: id
    isEditing: root.editingSubId === id
    // Keep the other existing property and signal assignments.
}
```

An alternative is to make the filtered model an array of strings and keep
`modelData`, but do not mix the two contracts. A `ListModel` should use named
roles consistently.

## Second fatal issue: habits are not being displayed

`Tasks.qml` creates a `TaskList` for both pages:

```qml
TaskList { dataType: "tasks" }
TaskList { dataType: "habits" }
```

However, `TaskList` expects the file to be a JSON array. The existing habits
file format used by `DailyHabitsList.qml` is an object:

```json
{ "habits": [], "completions": { "yyyy-MM-dd": [] } }
```

Therefore the daily page must use the habits implementation until both data
models are deliberately unified:

```qml
TaskList {
    id: taskList
    dataType: "tasks"
    // Keep the current task bindings.
}

DailyHabitsList {
    id: dailyHabitsList
    Layout.fillWidth: true
    Layout.fillHeight: true
    visible: root.activePage === "daily"
    focus: root.activePage === "daily"
}
```

Do not pass `dataType: "habits"` to `TaskList` as a substitute; it changes
only the path, not the parser or completion semantics.

Also fix capture routing in `Tasks.qml`. It currently always adds to
`taskList`. Use:

```qml
onCaptureAccepted: text => {
    if (root.activePage === "daily")
        dailyHabitsList.addHabit(text, root.habitIcon)
    else
        taskList.addTask(text)
}
```

## TaskCard contract errors

`TaskCard.qml` previously required `expanded`, then changed to local
`isExpanded`. The parents still contain commented-out `expanded:` assignments.
Use one contract. A consistent parent-owned version is:

```qml
// TaskCard.qml
required property bool expanded
signal toggleExpandRequested(int taskIdx)
```

Use `root.expanded` in the card, and in each parent delegate:

```qml
expanded: root.expandedId === todoId
onToggleExpandRequested: root.expandedId =
    root.expandedId === todoId ? "" : todoId
```

Keeping local `isExpanded` can also work, but then remove the dead parent
`expandedId` state and use `isExpanded` consistently. At present the parent
signal is commented out while the card still contains expansion UI.

## Other bugs exposed after delegates start loading

1. Keep one title field everywhere: `taskData.title`, not `taskData.task`.
2. Do not create a `ListModel` inside a property binding with
   `Qt.createQmlObject`. It can be recreated when dependencies change and leak
   objects. Bind the repeater directly to `root.subtasks`, or keep one explicit
   `ListModel` and update it.
3. `DataManager.qml` owns mutation while `TaskList.qml` owns persistence.
   Keep `dataChanged -> copy manager tasks to root -> save -> rebuild maps ->
   rebuild filtered model` as one update path.
4. The current manager assigns `dataManager.tasks`, but `root.tasks` is not
   explicitly updated in `onDataChanged`. A binding may be broken by later
   assignments. Make the ownership explicit:

```qml
onDataChanged: {
    root.tasks = dataManager.tasks
    root.save()
    root.updateMaps()
    root.updateFilteredModel()
}
```

5. Preserve optional fields such as `icon`, `project`, or future metadata
   when cloning a task. Several `DataManager` operations reconstruct objects
   field by field and currently drop `icon`, which will make habit icons
   disappear. Prefer:

```js
const newTask = Object.assign({}, task, {
    title: newTitle.trim(),
    subtasks: task.subtasks.slice()
})
```

6. Guard nested arrays at the load boundary before calling `.slice()`,
   `.length`, or iterating.
7. Filter by status once in `getFilteredTasks()`. The delegate's extra
   `visible` filter is redundant and can confuse layout and selection indices.
8. Do not rebuild the habit ID maps inside every delegate. Build them once on
   the list root, as `TaskList.qml` already does.
9. Log JSON parse errors instead of silently replacing data with `[]`; this
   distinguishes malformed storage from delegate construction errors.

## Recommended verification order

1. Change `modelData` to `todoId` and `id` in all three repeaters.
2. Restore `DailyHabitsList` in `Tasks.qml` and route capture by page.
3. Make the `expanded`/`isExpanded` API consistent.
4. Make `DataManager` ownership explicit and preserve all task fields.
5. Restart Quickshell and watch its terminal output while opening Tasks.
6. Test an empty file, one task, one task with subtasks, one habit, search,
   active/done filters, toggle, rename, delete, and restart persistence.

`qmllint` currently emits no syntax diagnostics for these files, which is
expected: the main failures are runtime model-role and persistence-contract
errors, not basic QML syntax errors.
