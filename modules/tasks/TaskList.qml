pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.utils

FocusScope {
    id: root

    required property string statusFilter
    property string searchQuery: ""

    readonly property real listMinHeight: 440
    readonly property real listMaxHeight: 640

    implicitHeight: CUtils.clamp(scroller.contentHeight, listMinHeight, listMaxHeight)

    // ── Data ─────────────────────────────────────────────────────
    property var    tasks:  []
    property bool   loaded: false

    // Edit state (kept on root so it survives delegate re-renders)
    property string editingTaskId: ""
    property string editingSubId:  ""

    // Which group is expanded — runtime-only (accordion, so at most one).
    // Deliberately not persisted: expanding is a view action, and routing it
    // through mutate() rewrote the whole todos.json on every chevron click.
    property string expandedId: ""

    // Click-to-select highlight — index into root.filtered (i.e. visible order)
    property int  selectedIndex: -1

    // ── Done-sinks-to-bottom ─────────────────────────────────────
    // Completed items sort below open ones, at both levels. The sort key is
    // read from a *frozen snapshot* (id -> done) rather than live state: if
    // rows re-sorted the instant you ticked one, everything below would jump
    // up a row and your next click would land on the wrong task. The snapshot
    // refreshes when the pointer leaves the list, so the reflow happens while
    // you're not aiming at anything. Membership (which rows exist) is always
    // live — only the ordering is deferred.
    property var sortSnapshot: ({})

    function refreshSort() {
        const m = {};
        for (const t of root.tasks) {
            m[t.todoId] = t.done;
            for (const s of t.subtasks)
                m[s.id] = s.done;
        }
        root.sortSnapshot = m;
    }

    // Sort key for one id: frozen value if we have one, else its live state
    // (so freshly-added items still land in the right section immediately).
    function sortDone(id, liveDone) {
        const s = root.sortSnapshot;
        return (id in s) ? s[id] : liveDone;
    }

    HoverHandler {
        id: listHover
        onHoveredChanged: if (!hovered) root.refreshSort()
    }

    // Undo state — covers deletes and accidental done-toggles alike
    property var   lastAction: null // { type: "delete-task"|"delete-sub"|"toggle-task", ... }
    property bool  showUndo:   false
    Timer {
        id: undoTimer
        interval: 6000
        onTriggered: { root.showUndo = false; root.lastAction = null; }
    }

    // ── Keyboard ─────────────────────────────────────────────────
    // selectedIndex + the selection border already existed but nothing could
    // move them except the mouse, so the whole list was pointer-only.
    // Text fields consume these first, so typing is unaffected.
    readonly property int selectedAbsIdx: selectedIndex >= 0 && selectedIndex < filtered.length
        ? tasks.findIndex(t => t.todoId === filtered[selectedIndex]) : -1

    function moveSelection(delta) {
        if (root.filtered.length === 0)
            return;
        const next = root.selectedIndex < 0
            ? (delta > 0 ? 0 : root.filtered.length - 1)
            : root.selectedIndex + delta;
        root.selectedIndex = Math.max(0, Math.min(next, root.filtered.length - 1));
        root.ensureVisible(root.selectedIndex);
    }

    // Keep the selected row inside the viewport without yanking the whole list
    function ensureVisible(i) {
        const item = taskRepeater.itemAt(i);
        if (!item)
            return;
        const pad = Tokens.spacing.small;
        if (item.y < scroller.contentY)
            scroller.contentY = Math.max(0, item.y - pad);
        else if (item.y + item.height > scroller.contentY + scroller.height)
            scroller.contentY = Math.min(Math.max(0, scroller.contentHeight - scroller.height),
                                         item.y + item.height - scroller.height + pad);
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const abs = root.selectedAbsIdx;

        if (event.key === Qt.Key_Z && ctrl && root.lastAction) {
            root.undoLast();
        } else if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
            root.moveSelection(1);
        } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
            root.moveSelection(-1);
        } else if (abs < 0) {
            event.accepted = false; // nothing selected: rest of the keymap is a no-op
            return;
        } else if (event.key === Qt.Key_Space) {
            root.toggleTask(abs);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.editingTaskId = root.tasks[abs].todoId;
        } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_X) {
            root.deleteTask(abs);
        } else if (event.key === Qt.Key_L || event.key === Qt.Key_Right) {
            root.expandedId = root.tasks[abs].todoId;
        } else if (event.key === Qt.Key_H || event.key === Qt.Key_Left) {
            root.expandedId = "";
        } else {
            event.accepted = false;
            return;
        }
        event.accepted = true;
    }
    function pushUndo(action) {
        root.lastAction = action;
        root.showUndo = true;
        undoTimer.restart();
    }

    // ── File I/O ─────────────────────────────────────────────────
    FileView {
        id: storage
        path: `${Paths.state}/todos.json`
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                // Reconcile groups written before done-ness was derived, so a
                // fully-ticked group isn't stuck in Active until it's touched.
                for (const t of parsed) {
                    if (!t.subtasks) t.subtasks = [];
                    root.syncDone(t);
                }
                root.tasks = parsed;
            } catch (e) {
                root.tasks = [];
            }
            root.loaded = true;
            root.refreshSort();
        }
        onLoadFailed: err => {
            root.tasks = []; root.loaded = true;
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => storage.setText("[]"));
        }
    }

    function save()     { storage.setText(JSON.stringify(root.tasks, null, 2)); }
    function mutate(fn) { const c = JSON.parse(JSON.stringify(root.tasks)); fn(c); root.tasks = c; save(); }

    // ── CRUD ─────────────────────────────────────────────────────
    function addTask(title) {
        if (!title.trim()) return;
        mutate(ts => ts.unshift({
            todoId: `${Date.now()}-${Math.floor(Math.random() * 1e6)}`,
            task: title.trim(), done: false, minutes: 0, project: "",
            createdAt: Date.now(), subtasks: []
        }));
    }

    // A group's done-ness is *derived*: it is done exactly when every subtask
    // is. Call after any mutation of t.subtasks so the two can't drift apart.
    // Plain tasks (no subtasks) keep whatever the checkbox set.
    function syncDone(t) {
        if (t.subtasks.length > 0)
            t.done = t.subtasks.every(s => s.done);
    }

    // Ticking a group cascades to its subtasks — the only reading of "done"
    // that stays consistent with syncDone above.
    function toggleTask(i) {
        const taskId = tasks[i].todoId;
        const prevDone = tasks[i].done;
        const prevSubs = JSON.parse(JSON.stringify(tasks[i].subtasks));
        mutate(ts => {
            const next = !ts[i].done;
            ts[i].done = next;
            for (const s of ts[i].subtasks) s.done = next;
        });
        pushUndo({ type: "toggle-task", taskId, prevDone, prevSubs });
    }
    // Accordion: expanding one task collapses every other
    function toggleExpand(i) {
        const id = tasks[i]?.todoId;
        if (!id) return;
        root.expandedId = root.expandedId === id ? "" : id;
    }
    function renameTask(i, t)       { if (!t.trim()) return; mutate(ts => { ts[i].task = t.trim(); }); editingTaskId = ""; }
    function setTaskEstimate(i, mins) {
        mutate(ts => {
            ts[i].minutes = mins;
        });
    }

    function deleteTask(i) {
        pushUndo({ type: "delete-task", idx: i, item: JSON.parse(JSON.stringify(tasks[i])) });
        mutate(ts => ts.splice(i, 1));
    }

    function clearDone() {
        const removed = [];
        tasks.forEach((t, i) => { if (t.done) removed.push({ idx: i, item: JSON.parse(JSON.stringify(t)) }); });
        if (!removed.length) return;
        pushUndo({ type: "clear-done", items: removed });
        mutate(ts => {
            for (let i = ts.length - 1; i >= 0; i--)
                if (ts[i].done) ts.splice(i, 1);
        });
    }

    function addSubtask(ti, title) {
        if (!title.trim()) return;
        mutate(ts => {
            ts[ti].subtasks.push({
                id: `${Date.now()}-${Math.floor(Math.random() * 1e6)}`,
                title: title.trim(), done: false, minutes: 0
            });
            root.syncDone(ts[ti]);
        });
    }

    function toggleSubtask(ti, si) {
        mutate(ts => {
            ts[ti].subtasks[si].done = !ts[ti].subtasks[si].done;
            root.syncDone(ts[ti]);
        });
    }
    function renameSubtask(ti, si, t) { if (!t.trim()) return; mutate(ts => { ts[ti].subtasks[si].title = t.trim(); }); editingSubId = ""; }

    function deleteSubtask(ti, si) {
        pushUndo({ type: "delete-sub", subIdx: si, prevDone: tasks[ti].done,
            taskId: tasks[ti].todoId, item: JSON.parse(JSON.stringify(tasks[ti].subtasks[si])) });
        mutate(ts => {
            ts[ti].subtasks.splice(si, 1);
            root.syncDone(ts[ti]);
        });
    }

    function undoLast() {
        if (!lastAction) return;
        const a = lastAction;
        if (a.type === "delete-task") {
            mutate(ts => { const at = Math.min(a.idx, ts.length); ts.splice(at, 0, a.item); });
        } else if (a.type === "delete-sub") {
            mutate(ts => {
                const ti = ts.findIndex(t => t.todoId === a.taskId);
                if (ti >= 0) {
                    const at = Math.min(a.subIdx, ts[ti].subtasks.length);
                    ts[ti].subtasks.splice(at, 0, a.item);
                    ts[ti].done = a.prevDone;
                }
            });
        } else if (a.type === "toggle-task") {
            mutate(ts => {
                const ti = ts.findIndex(t => t.todoId === a.taskId);
                if (ti >= 0) {
                    ts[ti].done = a.prevDone;
                    // Restore the pre-cascade subtask states, not just the parent
                    if (a.prevSubs) ts[ti].subtasks = a.prevSubs;
                }
            });
        } else if (a.type === "clear-done") {
            mutate(ts => {
                // items were recorded in ascending index order, so inserting
                // in that same order restores every original position
                for (const r of a.items)
                    ts.splice(Math.min(r.idx, ts.length), 0, r.item);
            });
        }
        showUndo = false; lastAction = null; undoTimer.stop();
    }

    // Drag-to-reorder: commits once on release (no live mid-drag splicing),
    // computed from the final position among currently visible siblings.
    function moveTask(fromDisplayIdx, toDisplayIdx) {
        if (fromDisplayIdx === toDisplayIdx) return;
        const ids = root.filtered;
        mutate(ts => {
            const absFrom = ts.findIndex(t => t.todoId === ids[fromDisplayIdx]);
            if (absFrom < 0) return;
            let absTo;
            if (toDisplayIdx <= 0) {
                absTo = 0;
            } else if (toDisplayIdx >= ids.length) {
                absTo = ts.length;
            } else {
                absTo = ts.findIndex(t => t.todoId === ids[toDisplayIdx]);
                if (absTo < 0) return;
                if (absTo > absFrom) absTo -= 1;
            }
            const [item] = ts.splice(absFrom, 1);
            ts.splice(absTo, 0, item);
        });
    }

    // Same display-order → absolute-index mapping as moveTask: once done
    // subtasks sink, the visible order no longer matches the stored array, so
    // splicing on raw delegate indices would reorder the wrong rows.
    function moveSubtask(ti, ids, fromDisplayIdx, toDisplayIdx) {
        if (fromDisplayIdx === toDisplayIdx) return;
        mutate(ts => {
            const subs = ts[ti].subtasks;
            const absFrom = subs.findIndex(s => s.id === ids[fromDisplayIdx]);
            if (absFrom < 0) return;
            let absTo;
            if (toDisplayIdx <= 0) {
                absTo = 0;
            } else if (toDisplayIdx >= ids.length) {
                absTo = subs.length;
            } else {
                absTo = subs.findIndex(s => s.id === ids[toDisplayIdx]);
                if (absTo < 0) return;
                if (absTo > absFrom) absTo -= 1;
            }
            const [item] = subs.splice(absFrom, 1);
            subs.splice(absTo, 0, item);
        });
    }

    // ── Filter ───────────────────────────────────────────────────
    // Holds todoIds, not indices: id identity is stable across a delete,
    // so the Repeater only tears down the one removed row instead of
    // rebuilding every row after it (index-based models shift on splice,
    // which is what made deletes visibly lag).
    readonly property var filtered: {
        const snap = root.sortSnapshot; // read directly so this rebinds on refresh
        const open = [], done = [];
        const q = searchQuery.trim().toLowerCase();
        for (const t of tasks) {
            if (statusFilter === "active" && t.done)  continue;
            if (statusFilter === "done"   && !t.done) continue;
            // Match subtask titles too — a group's own title often says nothing
            // about what's actually inside it.
            if (q && !t.task.toLowerCase().includes(q)
                  && !t.subtasks.some(s => s.title.toLowerCase().includes(q)))
                continue;
            ((t.todoId in snap ? snap[t.todoId] : t.done) ? done : open).push(t.todoId);
        }
        // Partition rather than sort(): stable by construction, so manual drag
        // order survives untouched inside each section.
        return open.concat(done);
    }

    readonly property int activeCount: tasks.filter(t => !t.done).length
    readonly property int doneCount: tasks.length - activeCount

    readonly property int totalActiveMinutes: {
        let sum = 0;
        for (const t of tasks) {
            if (!t.done && t.minutes > 0) sum += t.minutes;
        }
        return sum;
    }

    // Live drag-target index (for the drop-position indicator) — kept
    // separate from the commit-on-release logic in moveTask/moveSubtask.
    property int dragOverIndex: -1

    onFilteredChanged: {
        if (root.selectedIndex >= root.filtered.length)
            root.selectedIndex = -1;
    }

    // ── List ─────────────────────────────────────────────────────
    // Plain flickable (no edge-fade mask), and only scrollable at all
    // when the content actually overflows.
    StyledFlickable {
        id: scroller
        anchors.fill: parent
        clip: true
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        contentHeight: col.implicitHeight

        ColumnLayout {
            id: col
            width: parent.width
            spacing: Tokens.spacing.small
            // No move transition: ColumnLayout is a Layout, not a Positioner, so
            // it has none. Reorders land as a cut — acceptable only because the
            // done-sink is deferred until the pointer has left the list.

            // Empty state
            Item {
                Layout.fillWidth: true
                implicitHeight: emptyState.implicitHeight + Tokens.padding.extraLarge * 2
                visible: root.loaded && root.filtered.length === 0
                ColumnLayout {
                    id: emptyState
                    anchors.centerIn: parent; spacing: Tokens.spacing.small
                    // An empty result while searching means "no matches", not
                    // "all caught up" — branch on the query before the filter.
                    readonly property bool searching: root.searchQuery.trim().length > 0

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: emptyState.searching ? "search_off"
                            : root.statusFilter === "done" ? "sentiment_satisfied" : "check_circle"
                        fontStyle: Tokens.font.icon.builders.extraLarge.build()
                        color: Colours.palette.m3outlineVariant
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: emptyState.searching ? qsTr('No matches for "%1"').arg(root.searchQuery.trim())
                            : root.statusFilter === "done" ? qsTr("Nothing completed yet")
                            : root.statusFilter === "active" ? qsTr("All caught up!")
                            : qsTr("No tasks yet")
                        color: Colours.palette.m3outlineVariant
                        elide: Text.ElideRight
                        Layout.maximumWidth: root.width - Tokens.padding.extraLarge * 2
                    }
                }
            }

            Repeater {
                id: taskRepeater
                model: ScriptModel { values: root.filtered }

                delegate: Item {
                    id: cw
                    required property string modelData // todoId (stable across list mutations)
                    required property int index        // position within the visible/filtered list

                    readonly property int absIdx: root.tasks.findIndex(t => t.todoId === modelData)
                    // Fallback covers the one frame between a delete mutating
                    // root.tasks and the Repeater destroying this delegate.
                    readonly property var  task: root.tasks[absIdx]
                        ?? ({ todoId: modelData, task: "", done: false, subtasks: [] })
                    readonly property bool isEditing: root.editingTaskId === task.todoId
                    readonly property bool expanded: root.expandedId === modelData
                    readonly property bool isSelected: root.selectedIndex === index
                    readonly property int  nSub: task.subtasks.length
                    readonly property int  dSub: { let d = 0; for (const s of task.subtasks) if (s.done) d++; return d; }
                    // Subtask ids in display order — open first, done sunk to
                    // the bottom, using the same frozen key as the task list.
                    readonly property var subOrder: {
                        const snap = root.sortSnapshot;
                        const open = [], done = [];
                        for (const s of task.subtasks)
                            ((s.id in snap ? snap[s.id] : s.done) ? done : open).push(s.id);
                        return open.concat(done);
                    }
                    readonly property real prog: nSub > 0 ? dSub / nSub : (task.done ? 1 : 0)

                    property real dragY: 0

                    Layout.fillWidth: true
                    implicitHeight: rowBg.implicitHeight
                    z: dragHandler.active ? 100 : 1
                    transform: Translate { y: cw.dragY }

                    StyledRect {
                        id: rowBg
                        width: parent.width
                        radius: Tokens.rounding.large
                        // Permanent card background (not just on hover/select) so
                        // rows read as distinct blocks instead of running text.
                        color: cw.isSelected ? Colours.tPalette.m3surfaceContainerHigh
                             : rowHover.hovered ? Colours.tPalette.m3surfaceContainer
                             : Colours.tPalette.m3surfaceContainerLow
                        border.width: cw.isSelected ? 2 : 0
                        border.color: Colours.palette.m3primary

                        // Completed rows visually recede
                        opacity: cw.task.done ? 0.65 : 1
                        Behavior on opacity { Anim { type: Anim.DefaultEffects } }

                        implicitHeight: rowCol.implicitHeight + Tokens.padding.small * 2
                        Behavior on implicitHeight { Anim { type: Anim.FastSpatial } }
                        Behavior on color { CAnim {} }

                        HoverHandler { id: rowHover }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.selectedIndex = cw.index;
                                root.forceActiveFocus(); // so Ctrl+Z reaches the list
                            }
                            onDoubleClicked: root.toggleExpand(cw.absIdx)
                        }

                        ColumnLayout {
                            id: rowCol
                            anchors { left: parent.left; right: parent.right; top: parent.top
                                      margins: Tokens.padding.small; leftMargin: Tokens.padding.medium; rightMargin: Tokens.padding.medium }
                            spacing: Tokens.spacing.small

                            // ── Main row ───────────────────────
                            RowLayout {
                                Layout.fillWidth: true; spacing: Tokens.spacing.small

                                // Drag handle — full opacity while relevant (dragging/
                                // hovered/selected), otherwise nearly invisible so a
                                // resting list isn't cluttered with chrome.
                                MaterialIcon {
                                    text: "drag_indicator"
                                    fontStyle: Tokens.font.icon.small
                                    color: Colours.palette.m3outlineVariant
                                    opacity: (dragHandler.active || rowHover.hovered || cw.isSelected) ? 0.6 : 0
                                    Behavior on opacity { Anim { type: Anim.DefaultEffects } }

                                    DragHandler {
                                        id: dragHandler
                                        target: null
                                        onActiveChanged: {
                                            if (!active) {
                                                if (root.dragOverIndex >= 0)
                                                    root.moveTask(cw.index, root.dragOverIndex);
                                                cw.dragY = 0;
                                                root.dragOverIndex = -1;
                                            }
                                        }
                                        onTranslationChanged: {
                                            if (!active) return;
                                            cw.dragY = translation.y;
                                            let target = 0;
                                            for (let i = 0; i < taskRepeater.count; i++) {
                                                if (i === cw.index) continue;
                                                const sib = taskRepeater.itemAt(i);
                                                if (!sib) continue;
                                                if (sib.y + sib.height / 2 < cw.y + cw.dragY + cw.height / 2)
                                                    target++;
                                            }
                                            root.dragOverIndex = target;
                                        }
                                    }
                                }

                                // Expander. Always occupies its slot so titles don't
                                // shift on hover; a task with no subtasks yet fades
                                // one in on hover — otherwise "add a subtask" is
                                // reachable only by guessing at double-click.
                                MaterialIcon {
                                    text: cw.expanded ? "keyboard_arrow_down" : "keyboard_arrow_right"
                                    fontStyle: Tokens.font.icon.small
                                    color: Colours.palette.m3onSurfaceVariant
                                    opacity: cw.nSub > 0 ? 1
                                           : (rowHover.hovered || cw.isSelected) ? 0.5 : 0
                                    Behavior on opacity { Anim { type: Anim.DefaultEffects } }

                                    MouseArea {
                                        anchors.fill: parent; anchors.margins: -4
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleExpand(cw.absIdx)
                                    }
                                }

                                // Checkbox — now shown for groups too. For a group it
                                // reflects the derived state and cascades on click, so
                                // a finished group can actually leave the Active list.
                                MaterialIcon {
                                    text: cw.task.done ? "check_box"
                                        : (cw.nSub > 0 && cw.dSub > 0) ? "indeterminate_check_box"
                                        : "check_box_outline_blank"
                                    fill: cw.task.done ? 1 : 0
                                    fontStyle: Tokens.font.icon.medium
                                    color: cw.task.done ? Colours.palette.m3tertiary : Colours.palette.m3primary
                                    Behavior on color { CAnim {} }
                                    MouseArea {
                                        anchors.fill: parent; anchors.margins: -4
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleTask(cw.absIdx)
                                    }
                                }

                                // Title — display or edit
                                StyledText {
                                    visible: !cw.isEditing
                                    Layout.fillWidth: true
                                    text: cw.task.task
                                    font: Tokens.font.body.large
                                    color: cw.task.done ? Colours.palette.m3outline : Colours.palette.m3onSurface
                                    elide: Text.ElideRight
                                    Behavior on color { CAnim {} }

                                    // Strikethrough drawn as an overlay (font.strikeout can't be
                                    // combined with a whole-font binding) — animates in on check.
                                    StyledRect {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: cw.task.done ? Math.min(parent.contentWidth, parent.width) : 0
                                        height: 2
                                        radius: Tokens.rounding.full
                                        color: Colours.palette.m3outline
                                        Behavior on width { Anim { type: Anim.FastSpatial } }
                                    }
                                }
                                StyledTextField {
                                    visible: cw.isEditing
                                    Layout.fillWidth: true
                                    text: cw.task.task
                                    font: Tokens.font.body.large
                                    onVisibleChanged: if (visible) { forceActiveFocus(); selectAll(); }
                                    onAccepted: root.renameTask(cw.absIdx, text)
                                    Keys.onEscapePressed: { root.editingTaskId = ""; text = cw.task.task; }
                                }

                                // Group progress (only when it has subtasks)
                                RowLayout {
                                    visible: cw.nSub > 0 && !cw.isEditing
                                    spacing: Tokens.spacing.small
                                    StyledText {
                                        text: `${cw.dSub} / ${cw.nSub}`
                                        font: Tokens.font.body.small
                                        color: Colours.palette.m3onSurfaceVariant
                                    }
                                    // One continuous bar: track + proportional fill
                                    StyledRect {
                                        implicitWidth: 128; implicitHeight: 6
                                        radius: Tokens.rounding.full
                                        color: Colours.tPalette.m3surfaceContainerHighest

                                        StyledRect {
                                            width: parent.width * cw.prog
                                            height: parent.height
                                            radius: parent.radius
                                            color: Colours.palette.m3tertiary
                                            Behavior on width { Anim {} }
                                        }
                                    }
                                }

                                // Inline actions — same hover-reveal treatment as the drag handle
                                RowLayout {
                                    visible: !cw.isEditing
                                    spacing: 0
                                    opacity: (rowHover.hovered || cw.isSelected || (cw.task.minutes && cw.task.minutes > 0)) ? 1 : 0
                                    Behavior on opacity { Anim { type: Anim.DefaultEffects } }

                                    IconTextButton {
                                        type: ButtonBase.Text
                                        font: Tokens.font.label.small
                                        icon: "schedule"
                                        text: (cw.task.minutes && cw.task.minutes > 0) ? (cw.task.minutes >= 60 ? `${Math.floor(cw.task.minutes / 60)}h${cw.task.minutes % 60 ? ` ${cw.task.minutes % 60}m` : ""}` : `${cw.task.minutes}m`) : ""
                                        onClicked: estimateMenu.popup()

                                        QC.Menu {
                                            id: estimateMenu
                                            QC.MenuItem { text: qsTr("None"); onTriggered: root.setTaskEstimate(cw.absIdx, 0) }
                                            QC.MenuItem { text: qsTr("5m"); onTriggered: root.setTaskEstimate(cw.absIdx, 5) }
                                            QC.MenuItem { text: qsTr("15m"); onTriggered: root.setTaskEstimate(cw.absIdx, 15) }
                                            QC.MenuItem { text: qsTr("30m"); onTriggered: root.setTaskEstimate(cw.absIdx, 30) }
                                            QC.MenuItem { text: qsTr("1h"); onTriggered: root.setTaskEstimate(cw.absIdx, 60) }
                                            QC.MenuItem { text: qsTr("2h"); onTriggered: root.setTaskEstimate(cw.absIdx, 120) }
                                        }
                                    }

                                    IconButton {
                                        type: IconButton.Text
                                        font: Tokens.font.icon.small
                                        icon: "edit"
                                        onClicked: root.editingTaskId = cw.task.todoId
                                    }
                                    IconButton {
                                        type: IconButton.Text
                                        font: Tokens.font.icon.small
                                        icon: "delete_outline"
                                        onClicked: root.deleteTask(cw.absIdx)
                                    }
                                }
                            }

                            // ── Subtasks (indented, own drag-reorder) ─
                            ColumnLayout {
                                visible: cw.expanded
                                Layout.fillWidth: true
                                Layout.leftMargin: Tokens.padding.extraLarge
                                spacing: Tokens.spacing.extraSmall

                                Repeater {
                                    id: subRepeater
                                    model: ScriptModel { values: cw.subOrder }
                                    delegate: Item {
                                        id: sw
                                        required property string modelData // subtask id
                                        required property int index        // position in display order

                                        // Display order != array order once done items sink,
                                        // so every data op goes through subIdx, never index.
                                        readonly property int subIdx: cw.task.subtasks.findIndex(s => s.id === modelData)
                                        readonly property var sub: cw.task.subtasks[subIdx]
                                            ?? ({ id: modelData, title: "", done: false })
                                        readonly property string sid: `${cw.task.todoId}__${modelData}`
                                        readonly property bool isEditingSub: root.editingSubId === sid

                                        property real dragY: 0

                                        Layout.fillWidth: true
                                        implicitHeight: subRow.implicitHeight
                                        z: subDrag.active ? 100 : 1
                                        transform: Translate { y: sw.dragY }

                                        HoverHandler { id: subRowHover }

                                        RowLayout {
                                            id: subRow
                                            width: parent.width
                                            spacing: Tokens.spacing.small

                                            MaterialIcon {
                                                text: "drag_indicator"
                                                fontStyle: Tokens.font.icon.small
                                                color: Colours.palette.m3outlineVariant
                                                opacity: (subDrag.active || subRowHover.hovered) ? 0.5 : 0
                                                Behavior on opacity { Anim { type: Anim.DefaultEffects } }

                                                DragHandler {
                                                    id: subDrag
                                                    target: null
                                                    onActiveChanged: {
                                                        if (!active) {
                                                            let target = 0;
                                                            for (let i = 0; i < subRepeater.count; i++) {
                                                                if (i === sw.index) continue;
                                                                const sib = subRepeater.itemAt(i);
                                                                if (!sib) continue;
                                                                if (sib.y + sib.height / 2 < sw.y + sw.dragY + sw.height / 2)
                                                                    target++;
                                                            }
                                                            root.moveSubtask(cw.absIdx, cw.subOrder, sw.index, target);
                                                            sw.dragY = 0;
                                                        }
                                                    }
                                                    onTranslationChanged: if (active) sw.dragY = translation.y;
                                                }
                                            }

                                            MaterialIcon {
                                                text: sw.sub.done ? "check_box" : "check_box_outline_blank"
                                                fill: sw.sub.done ? 1 : 0
                                                fontStyle: Tokens.font.icon.small
                                                color: sw.sub.done ? Colours.palette.m3tertiary : Colours.palette.m3outline
                                                Behavior on color { CAnim {} }
                                                MouseArea {
                                                    anchors.fill: parent; anchors.margins: -4
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.toggleSubtask(cw.absIdx, sw.subIdx)
                                                }
                                            }
                                            StyledText {
                                                visible: !sw.isEditingSub
                                                Layout.fillWidth: true; text: sw.sub.title
                                                font: Tokens.font.body.medium
                                                color: sw.sub.done ? Colours.palette.m3outline : Colours.palette.m3onSurfaceVariant
                                                elide: Text.ElideRight
                                                Behavior on color { CAnim {} }

                                                StyledRect {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: sw.sub.done ? Math.min(parent.contentWidth, parent.width) : 0
                                                    height: 2
                                                    radius: Tokens.rounding.full
                                                    color: Colours.palette.m3outline
                                                    Behavior on width { Anim { type: Anim.FastSpatial } }
                                                }
                                            }
                                            StyledTextField {
                                                visible: sw.isEditingSub; Layout.fillWidth: true
                                                text: sw.sub.title; font: Tokens.font.body.medium
                                                onVisibleChanged: if (visible) { forceActiveFocus(); selectAll(); }
                                                onAccepted: root.renameSubtask(cw.absIdx, sw.subIdx, text)
                                                Keys.onEscapePressed: { root.editingSubId = ""; text = sw.sub.title; }
                                            }
                                            RowLayout {
                                                visible: !sw.isEditingSub
                                                spacing: 0
                                                opacity: subRowHover.hovered ? 1 : 0
                                                Behavior on opacity { Anim { type: Anim.DefaultEffects } }

                                                IconButton {
                                                    type: IconButton.Text
                                                    font: Tokens.font.icon.small
                                                    icon: "edit"
                                                    onClicked: root.editingSubId = sw.sid
                                                }
                                                IconButton {
                                                    type: IconButton.Text
                                                    font: Tokens.font.icon.small
                                                    icon: "delete_outline"
                                                    onClicked: root.deleteSubtask(cw.absIdx, sw.subIdx)
                                                }
                                            }
                                        }
                                    }
                                }

                                // Add-subtask
                                RowLayout {
                                    Layout.fillWidth: true; spacing: Tokens.spacing.small
                                    Layout.topMargin: Tokens.spacing.extraSmall
                                    MaterialIcon { text: "add"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3primary }
                                    StyledTextField {
                                        Layout.fillWidth: true; font: Tokens.font.body.medium
                                        placeholderText: qsTr("Add subtask…")
                                        onAccepted: { root.addSubtask(cw.absIdx, text); clear(); }
                                        Keys.onEscapePressed: { clear(); focus = false; }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Breathing room so the pinned undo banner never covers the last row
            Item {
                Layout.fillWidth: true
                implicitHeight: root.showUndo ? 56 : 0
                Behavior on implicitHeight { Anim { type: Anim.FastSpatial } }
            }
        }

        // Drop-position indicator — shows where the dragged row will land,
        // instead of leaving reordering as a blind guess.
        StyledRect {
            visible: root.dragOverIndex >= 0
            z: 200
            x: 0
            width: col.width
            height: 3
            radius: Tokens.rounding.full
            color: Colours.palette.m3primary
            y: {
                if (root.dragOverIndex < 0)
                    return 0;
                if (root.dragOverIndex >= taskRepeater.count) {
                    const last = taskRepeater.itemAt(taskRepeater.count - 1);
                    return last ? last.y + last.height : 0;
                }
                const item = taskRepeater.itemAt(root.dragOverIndex);
                return item ? item.y : 0;
            }
        }
    }

    // ── Undo banner ──────────────────────────────────────────────
    // Pinned over the bottom of the list rather than living inside the
    // flickable: as scrolled content it animated in below the fold on a long
    // list, so the whole undo window could expire without ever being seen.
    Item {
        id: undoBanner

        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        implicitHeight: undoRow.implicitHeight + Tokens.padding.small * 2 + 4
        height: implicitHeight
        z: 300

        opacity: root.showUndo ? 1 : 0
        visible: opacity > 0
        // Slide up from the edge instead of just fading in place
        transform: Translate { y: root.showUndo ? 0 : undoBanner.height
            Behavior on y { Anim { type: Anim.FastSpatial } } }
        Behavior on opacity { Anim { type: Anim.DefaultEffects } }

        // Fraction of the undo window still remaining (1 → 0)
        property real timeLeft: 1
        NumberAnimation {
            id: undoCountdown
            target: undoBanner
            property: "timeLeft"
            from: 1; to: 0
            duration: undoTimer.interval
        }
        Connections {
            target: root
            function onLastActionChanged() {
                if (root.lastAction) undoCountdown.restart();
            }
        }

        StyledRect {
            anchors.fill: parent
            radius: Tokens.rounding.large
            // Sits on top of rows now, so it needs to read as a raised surface
            color: Colours.tPalette.m3surfaceContainerHighest
            border.width: 1
            border.color: Colours.palette.m3outlineVariant

            // Countdown line — press Undo before it runs out
            StyledRect {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: Tokens.padding.small
                anchors.bottomMargin: 3
                width: (parent.width - Tokens.padding.small * 2) * undoBanner.timeLeft
                height: 3
                radius: Tokens.rounding.full
                color: Colours.palette.m3primary
            }

            RowLayout {
                id: undoRow
                anchors { left: parent.left; right: parent.right
                          verticalCenter: parent.verticalCenter
                          margins: Tokens.padding.small }
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: root.lastAction?.type === "toggle-task" ? "undo" : "delete_outline"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
                }
                StyledText {
                    Layout.fillWidth: true
                    text: {
                        const a = root.lastAction;
                        if (!a) return "";
                        if (a.type === "delete-task") return qsTr('"%1" deleted').arg(a.item.task);
                        if (a.type === "delete-sub") return qsTr('Subtask deleted');
                        if (a.type === "clear-done") return qsTr('%1 done task(s) cleared').arg(a.items.length);
                        if (a.type === "toggle-task") return a.prevDone ? qsTr('Task marked not done') : qsTr('Task marked done');
                        return "";
                    }
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                    elide: Text.ElideRight
                }
                StyledText {
                    text: qsTr("Ctrl+Z")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3outline
                }
                TextButton { text: qsTr("Undo"); onClicked: root.undoLast() }
            }
        }
    }
}
