# Static Nested Subtask — One-Level UI Plan (pre-approval)

> **Status:** DRAFT — static UI only, one level deep, shows on **every** `SubtaskCard` even if it has no children. No logic / no `TaskTree` / no depth-3 yet. New file only. Inspired by current flat `SubtaskCard.qml` (tree lines `28*depth`, `subRow` row, `HoverHandler`, actions) and `TaskCard.qml` `subtasksCol`.

**Goal:** Add a **static placeholder nested row** under each subtask so the *look* of nesting is visible before any data/logic. One file, one level, always visible (even when `children.length === 0`) — so you can see/approve indent, lines, spacing, chip, actions before we make it dynamic.

---

## 1. What “static” means

- **One level only:** TaskCard → SubtaskCard (depth 1) → **NestedRow (depth 2)**. No recursion, no `Loader` cycle, no `expandedSubtaskIds` yet.
- **Always shows:** Even if `subtaskData.children` is missing/empty, we render a nested row placeholder. Later (dynamic) it will be gated on `hasChildren || addingUnderId === subtaskId`; now it’s always `visible: true` for approval.
- **No data mutation:** No `DataManager.addSubtask(parentId)`, no `depthOf` check. The nested row is read-only UI with dummy data or `subtaskData`’s first child if exists, else placeholder “Nested subtask …”.

---

## 2. New file — `SubtaskNestedRow.qml` (or `NestedSubtaskCard.qml`)

**Location:** `modules/tasks/SubtaskNestedRow.qml` (new, single file — keep `SubtaskCard.qml` untouched except for one import + one instantiation).

**Why new file:** Keeps `SubtaskCard.qml` “cool” flat code untouched; recursion later will replace this static row with `Loader`/`Repeater` but the visual contract (indent, lines, row) stays same — easy to diff.

**Props (static):**

```qml
Item {
    id: root
    required property var parentSubtaskData  // the depth-1 subtask we are nested under
    required property string parentSubtaskId
    property bool isHabitList: false
    property bool isSelected: false        // for nested selection demo (optional)
    // For static, no isExpanded/hasChildren needed — always show one row
}
```

**Visual contract (mirrors `SubtaskCard` but depth 2):**

- **Indent:** `depth = 2` → `scaledIndent = 2 * 28 = 56` (`INDENT_UNIT` from future `TaskTree.js`, but hard-coded 28 for static). `treeContainer.width = 56 + Tokens.spacing.small`.
- **Tree lines:** reuse same `StyledRect` vertical/horizontal/dot as `SubtaskCard`:
  - Vertical: `visible: true` (since we show even when parent has no children, keep spine visible for single nested row — later will be `!isFirst||!isLast`).
  - `anchors.bottomMargin: 0` (no half-cut, since we’re not handling `isLast` yet).
  - Horizontal length same `extraLarge - spacing.small`, dot `6` → `12` when `isSelected`.
- **Row (`subRow` clone):** `RowLayout` `anchors.left: treeContainer.right`:
  1. **No chevron** (static, no expand) — keep 24x24 placeholder `Item` hidden to keep alignment, or show disabled chevron.
  2. **Checkbox** `check_box_outline_blank` static (not bound to `subtaskData.done` yet — placeholder).
  3. **Title** `StyledText` `body.medium` text: `parentSubtaskData.title ? parentSubtaskData.title + " → nested" : "Nested subtask"` or `"Add nested subtask..."` placeholder. `Layout.fillWidth: true`.
  4. **Minutes chip** `20h` `small` if `parentSubtaskData.minutes>0` (demo).
  5. **Actions** `RowLayout` `opacity: hovered||selected ?1:0` — `edit`/`delete` icons static (no signal yet).
- **Spacing/heights:** `implicitHeight: 32` (same as `SubtaskCard` `subRow`), `Layout.fillWidth: true`, `spacing: Tokens.spacing.small`. No `childrenCol` yet — single row only.
- **Hover:** `HoverHandler` same fade as parent.

**Code sketch (static, no logic):**

```qml
pragma ComponentBehavior: Bound
import QtQuick; import QtQuick.Layouts
import Caelestia; import Caelestia.Config; import qs.components; import qs.components.controls; import qs.services
Item {
    id: root
    required property var parentSubtaskData
    required property string parentSubtaskId
    property bool isHabitList: false
    property bool isSelected: false
    readonly property int depth: 2
    readonly property int scaledIndent: depth * 28
    Layout.fillWidth: true
    implicitHeight: subRow.implicitHeight
    HoverHandler { id: hover }
    Item { id: treeContainer; anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: scaledIndent + Tokens.spacing.small
        StyledRect { id: vLine; anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 2; color: Colours.palette.m3primary }
        StyledRect { id: hLine; anchors.left: vLine.right; anchors.verticalCenter: parent.verticalCenter; width: Tokens.padding.extraLarge - Tokens.spacing.small; height: 2; color: Colours.palette.m3primary }
        StyledRect { id: dot; anchors.left: hLine.right; anchors.verticalCenter: parent.verticalCenter; width: isSelected?12:6; height: isSelected?12:6; radius: isSelected? Tokens.rounding.full : Tokens.rounding.small; color: Colours.palette.m3primary }
    }
    RowLayout { id: subRow; anchors.left: treeContainer.right; anchors.right: parent.right; anchors.top: parent.top; spacing: Tokens.spacing.small
        MaterialIcon { text: "check_box_outline_blank"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3primary }
        StyledText { Layout.fillWidth: true; text: "Nested subtask"; font: Tokens.font.body.medium; color: Colours.palette.m3primary }
        RowLayout { visible: !isHabitList; StyledRect { implicitHeight:20; implicitWidth: label.implicitWidth+8; radius: Tokens.rounding.full; color: Colours.palette.m3surfaceContainerHighest; StyledText { id: label; anchors.centerIn: parent; text: "5m"; font: Tokens.font.body.small } } }
        RowLayout { opacity: (hover.hovered||isSelected)?1:0; IconButton { icon: "edit" } IconButton { icon: "delete_outline" } }
    }
}
```

---

## 3. How it plugs into existing `SubtaskCard.qml` (static)

- **Import once:** `import "SubtaskNestedRow.qml"` (no `qs.modules.tasks` cycle because `SubtaskNestedRow` does **not** import `SubtaskCard` — one-way only, no recursion yet).
- **Instantiate always:** Inside `SubtaskCard`, after `subRow` (where `childrenCol` would later be), add:

```qml
// ── Static nested placeholder (one level, always visible for UI approval) ──
SubtaskNestedRow {
    id: nestedRow
    anchors.top: subRow.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: 0
    parentSubtaskData: root.subtaskData
    parentSubtaskId: root.subtaskId
    isHabitList: root.isHabitList
    isSelected: root.selectedSubtaskId === root.subtaskId + "_nested" // demo
}
```

- **Height:** `SubtaskCard.implicitHeight` becomes `subRow.implicitHeight + nestedRow.implicitHeight` (always, not gated on `isExpanded`), so every subtask grows to show nested row with correct `depth 2` indent — you’ll see the ugly vs cool immediately and can approve.

---

## 4. What you will see (numbers & lines)

- TaskCard `Repeater` depth 1 rows (indent 28) each now has a **depth 2 nested row** (indent 56) directly below, with its own vertical/horizontal/dot at `56` offset. So `TaskCard` `ColumnLayout` will show: `Task header` → `Subtask 1 (28)` → `Nested of 1 (56)` → `Subtask 2 (28)` → `Nested of 2 (56)` …
- `TaskCard` `nSub`/`dSub`/`taskDuration` numbers **unchanged** (still flat depth-1 count) — nested is static placeholder, not counted. Progress bar still `leafStats` flat.
- No `+` yet on nested row (static) — add later when dynamic.

---

## 5. Plan steps (wait for approval, then one turn per step)

- **Step 1** Create `SubtaskNestedRow.qml` static file (indent 56, row, lines, chip, actions, hover) — no logic.
- **Step 2** `SubtaskCard.qml` add `import` + `SubtaskNestedRow` anchored below `subRow` + update `implicitHeight` to include it (always).
- **Step 3** `qmllint` + `timeout 8 quickshell -p shell.qml` 0 errors + visual check in popout (every subtask shows nested row).
- **Step 4** (after approval) make it dynamic: gate `visible: hasChildren && isExpanded`, replace static `SubtaskNestedRow` with `Repeater` + real `children` data via `TaskTree`, add hover `+`/`depth<2` logic — but not now.

---

## 6. Approval checklist

- [ ] New file name `SubtaskNestedRow.qml` ok (vs `NestedSubtaskCard.qml`)?
- [ ] Static always-visible (even when no children) ok for UI approval?
- [ ] One level only ok (depth 2 indent `56`, not 3)?
- [ ] Keep `SubtaskCard` untouched except anchored `SubtaskNestedRow` + `implicitHeight`?
- [ ] Placeholder text “Nested subtask” ok vs blank?

*Reply “approved” or edits — I’ll wait and then create the file in one turn.*

