# Nested Subtasks — Detailed Plan (UI + Logic) — Pre-Approval

> **Status:** DRAFT — do not implement until approved. This plan is **inspired by the existing flat UI code at `c33e0546` + scaling prep (`SCALING_PREP.md` with `ListView reuse`, memoized caches, `__none` sentinel)** and describes how to introduce depth-3 nesting cleanly.

**Why this doc:** User asked to pause before nested, get a detailed UI + logic plan that builds on the current “cool” `TaskCard`/`SubtaskCard` look, keeps it light/instant, and is step-by-step.

---

## 1. Current baseline (what we’re building on)

- **Data (flat):** `task.subtasks: [{id,title,done,minutes,streak,bestStreak}]` depth 1 only. `DataManager` does `addSubtask(taskIdx, title)`, `toggleSubtask(taskIdx, subIdx)`, `syncDone` (all subtasks done → task done). No `children`.
- **TaskList (flat):** `ListView reuseItems` (P-A1) over `filteredModel` (`todoId`), `taskMap` + `taskIndexMap` (now incremental + `searchLower` cache, P-A2/B), `progressData` memoized per `todoId` (P-A3), `ListView` virtualized. `selectedSubtaskIndex: int` (flat index), `visibleTaskCount` via `searchLower`.
- **TaskCard (flat cool):** `StyledRect rowBg` → `ColumnLayout rowCol` → `mainRow` (expander `expand_more`/`chevron_right`, checkbox/icon, `StyledText title` + strikethrough, `edit` field, spacer, minutes chip `taskDuration`, progress `dSub/nSub` bar, streak, actions `edit`/`delete`). `ColumnLayout subtasksCol` (`visible: expanded`, `leftMargin 11`, `spacing 0`) → `Repeater model: subOrder` → `SubtaskCard` delegates (`isFirst`/`isLast`/`hasChildren:false`/`depth:1`, no chevron, no `SubtaskChildren`). `Add subtask…` `RowLayout` at bottom (`visible: expanded`, always, not `addingUnderId`-gated).
- **SubtaskCard (flat cool):** `Item` `implicitHeight: subRow` + `treeContainer` (`scaledIndent=depth*28`, vertical 2px, horizontal elbow + dot 6→12) + `RowLayout subRow` (checkbox, title/edit, chip, actions `edit`/`delete` only). No `childrenCol`, no chevron, `hasChildren:false` hard-coded, `depth:1`.
- **Scaling prep already applied:** `ListView` reuse, `_progressCache` etc., `saveTimer 400ms` compact, `searchDebounce 80ms`, `habitResetTimer` single-shot, `delete`→`=undefined`. Nesting must not regress these (keep `O(visible)` + memoized per-task).

---

## 2. Goals for nested

- Up to `MAX_DEPTH = 3` recursive children: `subtasks: [{…, children:[{…, children:[{…}]}]}]`. Task direct children depth 1, grandchildren 2, great-grandchildren 3. Beyond 3, `+` hidden and `add` rejected.
- **Data:** leaves drive `done`/`minutes`/`progress` (parent `done` = all leaves done, `sumMinutes` = sum of leaf `minutes`).
- **UX:** hover-only `+` per row → temporary inline `Add subtask…` field (only one open at a time). Expansion transient (`expandedIds` map, not persisted). Search auto-expands ancestors of matches. Cascade toggle: parent → all descendants; leaf → recompute ancestors up to task.
- **Performance:** keep `ListView` virtualization for task rows; subtask tree inside `TaskCard` is per-task `ColumnLayout` (not virtualized) but limited to ~15-30 nodes per task (fanout 5×3). Memoize per `subId` if needed later.
- **Visual:** keep flat “cool” spacing/colors, just extend indent/lines correctly — no overlay, no jump.

---

## 3. Data model — current vs nested (logic)

### 3.1 Current

```js
task = { todoId, title, done, minutes, subtasks: [
  { id, title, done, minutes, streak, bestStreak }
]}
```

### 3.2 Nested (proposed)

```js
task = { todoId, title, done, minutes, subtasks: [
  { id, title, done, minutes, streak, bestStreak, children: [
    { id, title, done, minutes, streak, bestStreak, children: [
      { id, title, done, minutes, streak, bestStreak, children: [] }
    ]}
  ]}
]}
// depth 1 = direct, 2,3 = nested. Old data: children missing → treated as [] (migration lazy, only rewrite if `migrated`).
// TaskTree.js pure `.pragma library` helpers (stateless, like TitleParse.js) — see 3.3
```

### 3.3 New `TaskTree.js` (logic, no QML imports)

- `MAX_DEPTH = 3`, `INDENT_UNIT = 28`
- `newNode(title)` → `{id:newId(), title, done:false, minutes:0, streak:0, bestStreak:0, children:[]}`
- `kids(node)` → `node.children||[]`
- `walkFind(root,id)`, `walkFindParent(root,id)`, `depthOf(root,id)`, `pathTo(root,id)` (ancestors excluding root/target), `childOrder(node)` (for Repeater model)
- `insertNode(root,parentId,child)` — immutable clone ancestors, parent `""` = root task
- `removeNode(root,id)` — prune subtree
- `replaceNode(root,id,updater)` — immutable
- `setDone(root,id,done)` — cascade down to descendants, recompute ancestors up (parent `done = all children done`)
- `syncDone(root)` — recompute `done` from leaves up (used after add/rename/delete)
- `leafStats(node)` → `{total, done, ratio}` from leaves; `sumMinutes(node)` leaf sum; `isLeaf`
- `flattenVisible(root, expandedIds)` → `[{id,depth,parentId,hasChildren,isFirst,isLast,isExpanded}]` depth 1-based
- `getFrontier` / `ancestorsToExpand` helpers
- `ensureFields(node)` — migration: ensures `id`/`streak`/`bestStreak`/`children:[]`, drops legacy `completions`, returns `mutated`
- `matchesSearch(node,q)` — recursive title match `toLower`
- Task helpers: `taskSubtreeFlatten(task, expandedIds)`, `taskDepth(task, subId)`, `taskAncestorsToExpand(task, subId, expandedIds)`
- `test.js` standalone Node (67+ tests: insert/remove/setDone cascade, flatten order, migration, depth limit)

### 3.4 `DataManager.qml` — wire to TaskTree

- `import "TaskTree.js" as TaskTree`
- `nodeFromTask(task) → {id:todoId, children:subtasks.slice()}`, `taskFromNode(node)` → `subtasks`
- `addSubtask(taskIdx, parentSubId, title)` — `parentSubId==""` = root; check `depthOf(root,parentSubId)+1 <= MAX_DEPTH` else reject; `newNode` + `insertNode` + `subtaskAdded(taskId, newId, parentSubId)`; keep `updateMapsForTask` incremental
- `toggleSubtask(taskIdx, subId)` → `TaskTree.setDone`, keep `applySubtreeChange` helper (holds `syncDone` + habit logic)
- `renameSubtask(taskIdx, subId, title)` → `replaceNode` + `parseCapturePrefix`
- `deleteSubtask(taskIdx, subId)` → `removeNode`
- `syncDone(t)` → delegates to `TaskTree.syncDone` via `nodeFromTask`
- `ensureSubtaskFields` → delegates to `TaskTree.ensureFields` (recursive)
- `toggleTask` → `TaskTree.setDone(root, todoId, newDone)` (preserve children via `taskFromNode`)
- `applyHabitDayRollover` → `TaskTree.resetDone` per task + streaks
- Remove `getSubtaskMap` (now `getNodeMap` via `TaskTree.walk`), keep `getTaskMap`/`getTaskIndexMap` incremental.
- Signal `subtaskAdded(string taskId, string subtaskId, string parentSubtaskId)` now 3 args.
- Backwards compat: keep `addSubtaskByIndex`/`toggleByIndex` shim for old callers (delegate index→id).

### 3.5 `TaskList.qml` — state owns tree (not UI)

- `selectedSubtaskIndex:int` → `selectedSubtaskId:string = ""` (by id, not index)
- New: `expandedSubtaskIds: var ({})`, `addingUnderId: string = "__none"` (already in scaling prep as `__none` sentinel), `subtaskRows: var ({})` (id→Item registry for `keepSubtaskVisible` + scroll), `expandedTaskIds: var ({})` (already for virtualization)
- Helpers `setExpanded(id,on)` (replace-on-write), `toggleExpanded`, `setTaskExpanded`, `beginAddChild(parentId)` (auto-expand parent, focus field), `cancelAdd`, `commitAdd`, `keepSubtaskVisible(card, subId)` via registry, `moveSubtaskSelection(dir)`? Actually handled via `Keys` + `visibleRowsCache`
- `restoreKeyboardFocus`, `selectTask(index)` resets `selectedSubtaskId`, `beginEditingSelected` uses `subId`, `toggleSelected` via `subId`
- `finishLoad`: `TaskTree.ensureFields(syntheticRoot)` per task (recursive), drop `completions`, only save if `migrated`
- Search: `isTaskVisible`/`visibleTaskCount` delegate to `TaskTree.matchesSearch` on synthetic root `{id:todoId, title, children:subtasks}`; `visibleTaskCount` loop uses `searchLower`; `expandSearchMatches()` walks via `TaskTree.walk` + `ancestorsToExpand` to auto-expand.
- `progressData` per delegate now `TaskTree.leafStats(syntheticRoot)` (leaves, not just direct)
- `visibleRowsCache` keyed on `(tasks, expandedTaskIds, expandedSubtaskIds, filteredModel)` via `taskSubtreeFlatten` — used for Down/Up/Right/Left navigation (tree-aware)
- Keys: `Down` → next in `flattenVisible`, `Up` → prev, `Right` → collapsed with children → expand else first child, `Left` → expanded→collapse else parent else task collapse, `Enter` cascade toggle, `F2` rename, `Insert`/`Shift+Enter` add child, `Esc` cancel add field first, guard `addingUnderId !== "__none"`

---

## 4. UI — current vs nested (what should appear)

### 4.1 TaskCard — from flat “cool” to tree-aware (inspired by current code)

**Keep** (do not regress):

- `StyledRect rowBg` `radius small`, `color: isSelected?surfaceContainerHigh:hovered?surfaceContainer:surfaceContainerLow`, border `1` primary `0.35` when selected, `implicitHeight: rowCol + padding*2` `FastSpatial`, `HoverHandler` + `TapHandler` selection.
- `ColumnLayout rowCol` `leftMargin medium`/`rightMargin medium`/`margins small`, `spacing small`.
- `mainRow` RowLayout: expander `expand_more`/`chevron_right` (`m3primary` when expanded else `m3onSurfaceVariant` 0.5), checkbox/icon (`check_box`/`indeterminate`/`check_box_outline_blank` or `check_circle`/`radio_button_unchecked` for habit icon), title `body.large` + strikethrough, edit field `body.large` inline, spacer, minutes chip (`20h` `small` `surfaceContainerHighest`), progress `100w` `120x4` bar + text `dSub/nSub`, streak `fire`/`trophy`, actions `edit`/`delete` (shake) with `opacity hovered||selected?1:0.3`.

**Change for nested:**

- Remove always-visible bottom `Add subtask…` `RowLayout` (`visible: expanded`) — replace with **hover-only `+`** in actions `RowLayout` (`IconButton add` `type:Text` `font:icon.small` `icon:"add"`). Click `+` → `list.beginAddChild("")` (TaskList auto-expands card). Keep original `RowLayout` but gate `visible: expanded && addingUnderId === ""` (only when field open, not always).
- Pass-through props to level-1 `SubtaskCard`: `parentSubId: ""`, `depth:1`, `hasChildren`, `isFirst`, `isLast`, `isExpanded: expandedSubtaskIds[id]`, `expandedSubtaskIds`, `addingUnderId`, `subtaskRows`, `selectedSubtaskId`, `editingSubId`, `nodeMap`. Replace `subIdx:int` → `subId:string` in all signals (`toggleSubtaskRequested(taskIdx, subId)` etc.).
- Add signals `expandRequested(subId,bool)` + `addChildRequested(parentSubId,title)`.
- `taskDuration: TaskTree.sumMinutes({id:todoId, children:subtasks})` (was loop sum direct only).
- Checkbox partial: `taskPartial: leafStats.done>0 && leafStats.done<leafStats.total` (was `0<dSub<nSub` with direct count — now leaves).
- Keep `nSub: leafStats.total`, `dSub: leafStats.done`.

### 4.2 SubtaskCard — from flat leaf to recursive node

**Keep** (flat cool):

- `Item` `implicitHeight: subRow + (isExpanded?childrenCol:0)` `FastSpatial`, `Layout.fillWidth`.
- `treeContainer` `width: scaledIndent + spacing.small` (28*depth +8), vertical 2px, horizontal elbow, dot 6→12 `full` when selected, `m3primary 0.8`.
- `subRow RowLayout` (`left: treeContainer.right`, `leftMargin: isSelected?9:0` `FastSpatial`) spacing small.
- Checkbox `check_box`, title `body.medium` `onSurfaceVariant` when done, strikethrough, edit field `body.medium` with `title @minutes`, chip `20h` `small`, actions `edit`/`delete` shake, `HoverHandler` fade.

**Add for nested:**

- Props: `parentSubId`, `isExpanded`, `expandedSubtaskIds`, `addingUnderId`, `subtaskRows`, `selectedSubtaskId`, `editingSubId`, `nodeMap` (full walk map), keep `depth/isFirst/isLast/hasChildren`.
- **Chevron** before checkbox: `Item 24x24` `visible: hasChildren` → `MaterialIcon` `expand_more`/`chevron_right` (`m3primary` when expanded else `m3onSurfaceVariant` 0.5). Click → `expandRequested` + `selectionRequested`. **Not in flat.**
- Checkbox becomes cascade toggle (still `toggleRequested` but now `DataManager` will cascade via `TaskTree.setDone`).
- **`+` in actions** (`IconButton add` `visible: depth < MAX_DEPTH` `depth:1→2→3`, `MAX_DEPTH=3` check). Click `+` → `addChildRequested(taskIdx, subtaskId, "")` (empty → `TaskList` shows inline field, not instant add). Flat had no `+`.
- **`childrenCol` ColumnLayout** `visible: parentExpanded && isExpanded`? Actually `SubtaskChildren` item handles `visible: parentExpanded`, but inside `SubtaskCard` we gate via `SubtaskChildren` `parentExpanded: isExpanded`. When `isExpanded` false, `childrenCol` collapsed → `Repeater` model returns `[]` (no instantiation, not just visibility `visible:false`), so no `SubtaskCard` objects created for hidden subtree (perf).
- Inside `childrenCol`: `Repeater` `model: childOrder(node)` or `node.children` slice → `delegate: Loader { source: "SubtaskCard.qml" }` (breaks QML mutual recursion `SubtaskCard ↔ SubtaskChildren` cycle — use dynamic `Loader` + `Binding` per `NESTED_UI_SPEC` already proven, or `SubtaskChildren` dedicated wrapper that itself does not `import qs.modules.tasks`). `depth: root.depth+1`, `isFirst/isLast` from `index`, `hasChildren: nodeMap[childId].children.length>0`.
- **Inline add row** when `addingUnderId === subtaskId`: `RowLayout` `Layout.leftMargin: (depth+1)*28` (child indent) `topMargin 4` + `MaterialIcon add_circle_outline` + `StyledTextField 28h` `pointSize 11` `Add subtask…` (`TitleParse.hasTitle` guard, `Enter`→`addChildRequested`, `Esc`→`cancelAddRequested`). Flat had no such row.
- **Registry:** `Component.onCompleted: subtaskRows[subtaskId]=root` / `onDestruction: delete` so `TaskList.keepSubtaskVisible` can scroll to deep row (via `taskRepeater.itemAt` → `TaskCard` → `subtaskRows` lookup).
- **Tree lines polish:** vertical `visible: (!isFirst||!isLast)||(hasChildren&&isExpanded)` + `bottomMargin: (isLast&&!(hasChildren&&isExpanded))?½h:0` so single parent with expanded children keeps spine into children (was cut at half → ugly gap).

### 4.3 Wrapper `SubtaskChildren.qml` (or `NestedSubtaskCard.qml`)

- Why needed: QML forbids `SubtaskCard` instantiating itself in same file — recursion must cross file boundary. Use `Loader` pattern (already proven in Phase 9 via `Loader { source: "SubtaskCard.qml" }` + `Binding` for all props + `onLoaded` signal `connect` to bubble up). `SubtaskChildren.qml` is that wrapper: it owns `ColumnLayout childrenCol` + `Repeater` + `Loader` delegates + inline add row. It **does not** `import qs.modules.tasks` (breaks cycle `SubtaskCard ↔ SubtaskChildren` via `qt.qml.typeresolution.cycle` — use `Loader` string source).
- Alternative considered: `NestedSubtaskCard.qml` empty subclass `SubtaskCard {}` — also needs `Loader` to break cycle, same. Pick one name and keep `Decisions` updated.

---

## 5. Interactions — inspired vs nested

| Area | Flat (current) | Nested (proposed) |
|------|----------------|-------------------|
| **Selection** | `selectedSubtaskIndex: int` `-1` = task | `selectedSubtaskId: string = ""` (id, not index) — by id stable across insert/delete |
| **Expansion** | `expanded: bool` per `TaskCard` local | `expandedTaskIds: var ({})` per task + `expandedSubtaskIds: var ({})` per subtask (transient, `setExpanded` replace-on-write). Card + subtask `expanded` derived from map (`list.expandedTaskIds[taskId] ?? false`). `isTaskExpanded` used in `visibleRowsCache` to skip hidden subtask rows. |
| **Add** | `Add subtask…` field always visible when `expanded` | Hover-only `+` → `list.beginAddChild(parentId)` auto-expands parent + `addingUnderId=parentId` → inline field appears under that parent (`visible: addingUnderId===subtaskId` or `=== ""` for root). `Esc` cancels first, `Enter` commits via `TitleParse.hasTitle`. Only one field at a time. Depth check `depthOf+1>3` reject (DataManager). |
| **Keyboard** | `Down` next subtask 0→n else next task, `Up` prev, `Right` expand+select first, `Left` deselect→collapse, `Enter` toggle, `F2` rename, `Esc` cancel edit | Tree-aware: `Down` next in `flattenVisible`, wrap; `Up` prev; `Right` collapsed with children → expand, expanded → first child; `Left` expanded→collapse else parent else task collapse; `Enter` cascade toggle (parent down + leaf up), `F2` rename `todoId__subId`, `Insert`/`Shift+Enter` add child under selected, `Esc` cancel add first then close. Guard `addingUnderId !== "__none"`. `visibleRowsCache` keyed on `(tasks, expandedTaskIds, expandedSubtaskIds, filteredModel)`. |
| **Toggle** | `toggleSubtask(taskIdx, subIdx)` direct | `toggleSubtask(taskIdx, subId)` → `TaskTree.setDone` cascade down + recompute up; leaf toggle recomputes ancestors; `progressData` via `leafStats` leaves |
| **Search** | `title.indexOf(q)` per task + loop subtasks direct | `TaskTree.matchesSearch(syntheticRoot, q)` recursive; `expandSearchMatches()` via `TaskTree.walk` + `ancestorsToExpand` to auto-expand paths |
| **Delete/Rename** | By `subIdx` | By `subId` → `removeNode`/`replaceNode` prune subtree / keep `children` |

---

## 6. Performance (keep scaling prep gains)

- Keep `ListView reuseItems` for task rows (already P-A1) — subtask tree inside `TaskCard` is per-task `ColumnLayout` (not virtualized) but limited fanout 5×3=~30 nodes max per task → still `O(visible)` delegates, not `O(n*m)` all.
- Keep `getProgressData`/`getSubOrder`/`_titleLowerCache` memo per `todoId` (P-A3/B) — nested leaves increase `m` but cache per `task` object identity keeps cost `1×O(leaves)` per changed task.
- Keep `saveTimer 400ms` compact, `searchDebounce 80ms`, `habitResetTimer` single-shot (P-C).
- No new C++ (per your removal) — stay QML `TaskTree.js` `.pragma library`.

---

## 7. Implementation phases (do one turn at a time, no batch)

- **Phase 0** Setup: backup `~/tasks.json` + `modules/tasks/*.qml` → `modules/tasks/.backup/`, confirm `quickshell -p` 0 errors baseline (already had at `c33e0546`).
- **Phase 1** `TaskTree.js` + `test.js`: create pure helpers + 67 tests, run `node test.js`.
- **Phase 2** `DataManager.qml`: wire to `TaskTree` (add `import TaskTree.js`, `nodeFromTask`/`taskFromNode`, `addSubtask(parentSubId)`, depth check, `toggle/rename/delete` via `setDone`/`replaceNode`/`removeNode`, `syncDone`→`TaskTree.syncDone`, `ensureFields`→`TaskTree.ensureFields`, `toggleTask` clone, `applyHabitDayRollover`→`resetDone`, remove `getSubtaskMap`, signal `subtaskAdded` 3 args, grep no `{ id:` rebuild).
- **Phase 3** `TaskList.qml` state: `selectedSubtaskId`, `expandedSubtaskIds`+`expandedTaskIds` (virtualization), `addingUnderId="__none"`, `subtaskRows`, `setExpanded`/`toggleExpanded`/`setTaskExpanded`/`beginAddChild`/`cancelAdd`/`commitAdd`/`keepSubtaskVisible`/`moveSubtaskSelection`, `restoreKeyboardFocus`/`selectTask`/`beginEditingSelected`/`toggleSelected` cascade.
- **Phase 4** `TaskList.qml` migration/search: `finishLoad`→`ensureFields` recursive, `getFilteredTasks`→`matchesSearch` synthetic root, `visibleTaskCount`/`isTaskVisible` via `searchLower` cache, `progressData`→`leafStats`, `expandSearchMatches` via `walk`+`ancestorsToExpand`.
- **Phase 5** `TaskList.qml` keyboard nav: tree-aware `Down`/`Up`/`Right`/`Left`/`Enter`/`F2`/`Insert`/`Esc` via `visibleRowsCache` keyed on `(tasks, expandedTaskIds, expandedSubtaskIds)`, guard `addingUnderId`.
- **Phase 6** `TaskCard.qml`: remove always-visible add field, add hover `+`, pass-through props to `SubtaskCard` (`parentSubId:"", depth:1, hasChildren→nodeMap, isFirst/isLast, isExpanded→expandedSubtaskIds, addingUnderId, subtaskRows`), `subIdx`→`subId`, `expandRequested`/`addChildRequested`, `taskDuration→sumMinutes`, `taskPartial` via `leafStats`.
- **Phase 7** `SubtaskCard.qml` recursive: props `parentSubId/isExpanded/expandedSubtaskIds/addingUnderId/subtaskRows/selectedSubtaskId/editingSubId/nodeMap`, keep `depth/isFirst/isLast/hasChildren`, chevron, cascade checkbox, `+` `depth<3`, `childrenCol` gated on `isExpanded` via `Loader` (`Repeater` `NestedSubtaskCard` `depth+1`, `isFirst/isLast` from index), inline add row `addingUnderId===subtaskId`, registry `Component.onCompleted`, string-id signals, tree line polish (`visible/bottomMargin` with `hasChildren&&isExpanded`). Create `SubtaskChildren.qml` (or `NestedSubtaskCard.qml`) wrapper with `Loader` + `Binding` to break `qt.qml.typeresolution.cycle`.
- **Phase 8** Docs: `behaviors.txt` signal table ids, keyboard Right/Left/Insert, expansion ownership, hover `+`, `MAX_DEPTH`, registry; update header snippets in `TaskCard`/`DataManager` to recursive `children:[]`; update `SCALING_PREP` checklists.
- **Phase 9** Verify: `qmllint` no new violations, `quickshell -p` 0 `ERROR`/`cycle`, manual depth 1/2/3 add, hover `+` Esc/Enter, cascade, leaf recompute, delete subtree, rename, collapse/expand, Right/Left/Down/Up/Enter/F2/Insert, search auto-expand, All/Active/Done filters, habit rollover, round-trip, stress 5×3×5 smooth (per `NESTED_UI_SPEC` §6).

---

## 8. Risks & mitigations

- **QML cycle `SubtaskCard ↔ SubtaskChildren`** → must use `Loader { source: "SubtaskCard.qml" }` + `Binding` (proven Phase 9). Do not `import qs.modules.tasks` in wrapper.
- **`ListView reuse` leaks `expanded` local** → store in `expandedTaskIds` map, derive `TaskCard.expanded: list.expandedTaskIds[taskId]??false`, mutate via `list.setTaskExpanded` (not `card.expanded=`). Already prepared in scaling prep.
- **`addingUnderId` sentinel** → use `"__none"` for no field, `""` for root field — avoids always-visible root field (Phase 10 fix). Keep `Esc` → `cancelAdd` first.
- **Migration** lazy `ensureFields` only sets `children:[]` if missing, drops legacy `completions` via `=undefined` (not `delete` de-opt), only saves if `migrated`.
- **`visibleRowsCache` must include `expandedTaskIds`** → else Up/Down enters collapsed tasks (Q10-2 bug). Key on `(tasks, expandedTaskIds, expandedSubtaskIds, filteredModel)`.
- **String alloc in search** → keep `searchLower` + `getTitleLower` cache (P-B) so recursive `matchesSearch` not per-delegate `toLower`.

---

## 9. Approval checklist (check before “go”)

- [ ] Data model with `children:[]` depth 3 and `MAX_DEPTH` ok?
- [ ] `TaskTree.js` `.pragma library` pure helpers + `test.js` 67 tests ok?
- [ ] `DataManager` by `subId` not `subIdx` and depth reject ok?
- [ ] UI keeps “cool” TaskCard look — hover `+` not always-visible field, tree lines indent `28*depth`, dot 6→12, chevron before checkbox?
- [ ] `SubtaskChildren` `Loader` + `Binding` to break cycle understood?
- [ ] `ListView reuse` + memoized per-task caches kept (no regress)?
- [ ] Want me to start Phase 0 → Phase 9 step-by-step, one turn per phase, with `qmllint` + `quickshell -p` + `node test.js` after each?

*Reply “approved” or comment edits — I’ll wait.*

