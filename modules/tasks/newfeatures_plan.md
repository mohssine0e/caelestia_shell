# New features: link, copy title, categories, #category capture

Scope: tasks module. No files modified yet.

## Decisions (resolved with the user)

- **Link input = explicit `!link` prefix (mirroring `@minutes`), with bare-URL auto-detect as a fallback.** `TitleParse.parseCapturePrefix` strips `!value` from the title and stores it as `link`; if the value has no scheme, `https://` is prepended so a bare domain (`!github.com/foo`) opens in a browser. Only values that look like a link (scheme or a dot) are honoured, so "Fix the !bug" is left untouched. A bare `https?://` URL is also auto-detected and stripped, filling in only when no `!link` was given. Rename prefill re-includes `!link` so it round-trips.
- **URL-only capture is rejected**, like `@5` / `#work` alone — metadata-only input is not a task.
- **Task-level backfill** runs `ensureHabitFields(task)` for *every* task in `TaskList.finishLoad()` (not just habits). Precedent: `completionDates` is already backfilled for tasks at TaskList.vue:611.
- **Categories apply to both pages** (Tasks + Daily). The dropdown is bound onto both `TaskList`s; `#category` parses for both.
- **Copy button feedback**: silent copy + icon flips to `inventory` for 2s (same idiom as Notification.vue:508-518).

## 1. TitleParse.js

`parseCapturePrefix(text)` returns `{ title, minutes, category, link }`:

- `@minutes` — existing.
- `!link` — regex `!(\S+)`. The value is the link, stripped from the title. If it has no scheme, `https://` is prepended (so `!github.com/foo` opens). Only values that look like a link (scheme or a dot) are honoured, so `Fix the !bug` is untouched.
- `#category` — regex `#[A-Za-z][A-Za-z0-9_-]*`. First match is the category; **all** matches are stripped from the title. Stored lowercased. `#42` is *not* matched (must start with a letter), so `Fix issue #42` is untouched.
- bare `https?://` URL — auto-detected and stripped as a fallback only when no `!link` was given.
- URLs are stripped before `@minutes` so a URL's `@digits` can't be mistaken for an estimate (e.g. `https://x.com/@42`).
- Whitespace normalized after stripping.
- `hasTitle` unchanged (keyed off `title`).

## 2. DataManager.vue

- Model doc-comment: add `link` (string), `category` (string).
- `addTask`: `newTask.category = parsed.category`, `newTask.link = parsed.link` (both default `""`).
- `renameTask`: apply `changes.category` and `changes.link` from `parsed`.
- `ensureHabitFields(t)`: backfill `t.link` (string) and `t.category` (string).
- `ensureSubtaskFields(subtask)` and `ensureNestedFields(n)`: backfill `link` as a string.
- `addSubtask` / `addNestedSubtask`: add `link: parsed.link` to the new-node literal.
- **Carry `link` through** the reconstructed objects in `toggleSubtask`, `renameSubtask`, `toggleNestedSubtask`, `renameNestedSubtask` (otherwise it is silently dropped on toggle/rename).
- `getFilteredTasks(statusFilter, searchQuery, categoryFilter)`: optional 3rd param; filter by category when it isn't `"all"`.
- Add `getCategories()` → sorted distinct non-empty categories.

## 3. TaskList.vue

- Add `property string categoryFilter: "all"`.
- In `matchesFilter`, add category check after status/search.
- Add `onCategoryFilterChanged` mirroring `onStatusFilterChanged`.
- Expose `readonly property var categoryOptions` (`["all", ...getCategories()]`).

## 4. Tasks.vue

- Add `property string categoryFilter: "all"`; bind it onto both `taskList` and `dailyHabitsList` (categories apply to both pages).
- Add a Tonal `SplitButton` category dropdown in the filter bar, items built with `Variants { model: taskList.categoryOptions; ...MenuItem{} }` (same idiom as `StorageCard.vue`), visible on the tasks page; selection sets `root.categoryFilter`. (Daily mirrors it via `dailyHabitsList`.)

## 5. TaskCard.vue, SubtaskCard.vue, NestedSubtaskCard.vue

- Add `import Quickshell`.
- In each actions `RowLayout`, add before the existing buttons:
  - `IconButton { icon: "content_copy"; onClicked: Quickshell.clipboardText = <title> }`.
  - `IconButton { icon: "link"; visible: (<link> ?? "") !== ""; onClicked: Qt.openUrlExternally(<link>) }`.
- Update `editPrefill` so rename round-trips the new fields: TaskCard → `title @minutes #category !link`; SubtaskCard/NestedSubtaskCard → `title @minutes !link`.

## 6. Validation

- `qmllint` the touched files if available; otherwise re-read each edited file to confirm structure, and check the popout renders (tasks add `#cat`, a URL, copy button, category filter).

No files have been modified yet. Please **toggle to Act mode** and I'll implement all of the above.