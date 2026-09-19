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
    id: list

    property string dataType: "tasks"
    readonly property bool isHabitList: list.dataType === "habits"

    property string statusFilter: "all"
    property string searchQuery: ""

    readonly property string dataPath: Paths.home + "/" + list.dataType + ".json"
    
    readonly property string emptyStateText: list.dataType === "habits" ? qsTr("No habits yet") : qsTr("No tasks yet")
    
    readonly property real listMinHeight: 440
    readonly property real listMaxHeight: 640

    implicitHeight: CUtils.clamp(scroller.contentHeight, listMinHeight, listMaxHeight)

    property var tasks: []
    property bool loaded: false
    property bool tasksLoaded: false
    property var taskMap: ({})
    property var taskIndexMap: ({})
    // P-A3 memoized derived per-task (progress, duration, subtask maps) — single cache per todoId,
    // invalidated only when that task object identity changes (DataManager keeps refs for unchanged tasks)
    property var _progressCache: ({})
    property var _subtaskMapCache: ({})
    property var _taskDurationCache: ({})
    property var _subOrderCache: ({})

    function getProgressData(todoId) {
        var task = taskMap[todoId]
        if (!task) return { total: 0, done: 0, ratio: 0 }
        var cached = _progressCache[todoId]
        if (cached && cached.task === task) return cached.value
        var subs = task.subtasks || []
        var total = subs.length
        var res
        if (total === 0) {
            res = { total: 0, done: 0, ratio: task.done ? 1 : 0 }
        } else {
            var done = 0
            for (var i = 0; i < subs.length; i++) if (subs[i].done) done++
            res = { total: total, done: done, ratio: done / total }
        }
        // replace-on-write to keep binding cheap (only this key changes)
        var next = Object.assign({}, _progressCache)
        next[todoId] = { task: task, value: res }
        _progressCache = next
        return res
    }
    function getSubtaskMapCached(todoId) {
        var task = taskMap[todoId]
        if (!task) return {}
        var cached = _subtaskMapCache[todoId]
        if (cached && cached.task === task) return cached.value
        var map = {}
        var subs = task.subtasks || []
        for (var i = 0; i < subs.length; i++) map[subs[i].id] = subs[i]
        var next = Object.assign({}, _subtaskMapCache)
        next[todoId] = { task: task, value: map }
        _subtaskMapCache = next
        return map
    }
    function getTaskDuration(todoId) {
        var task = taskMap[todoId]
        if (!task) return 0
        var cached = _taskDurationCache[todoId]
        if (cached && cached.task === task) return cached.value
        var subs = task.subtasks || []
        var val = 0
        if (subs.length > 0) {
            for (var i = 0; i < subs.length; i++) val += (subs[i].minutes || 0)
        } else {
            val = task.minutes || 0
        }
        var next = Object.assign({}, _taskDurationCache)
        next[todoId] = { task: task, value: val }
        _taskDurationCache = next
        return val
    }
    function getSubOrder(todoId) {
        var task = taskMap[todoId]
        if (!task) return []
        var cached = _subOrderCache[todoId]
        if (cached && cached.task === task) return cached.value
        var order = []
        var subs = task.subtasks || []
        for (var i = 0; i < subs.length; i++) order.push({ id: subs[i].id })
        var next = Object.assign({}, _subOrderCache)
        next[todoId] = { task: task, value: order }
        _subOrderCache = next
        return order
    }

    // ── Data Layer (DataManager bridge) ──
    DataManager {
        id: dataManager
        tasks: list.tasks
        habitMode: list.isHabitList

        onTaskAdded: (taskId, task) => {
            filteredModel.insert(0, { todoId: taskId });
            list.tasks = dataManager.tasks;
            list.updateMaps();
            list.refresh();
        }

        onTaskDeleted: (taskId) => {
            for (var i = 0; i < filteredModel.count; i++) {
                if (filteredModel.get(i).todoId === taskId) {
                    filteredModel.remove(i);
                    break;
                }
            }
            if (list.selectedIndex >= filteredModel.count) {
                list.selectedIndex = filteredModel.count - 1;
            }
            list.tasks = dataManager.tasks;
            list.updateMaps();
            list.refresh();
        }

        onTaskToggled: (taskId, newState) => {
            list.tasks = dataManager.tasks
            list.updateMapsForTask(taskId)
            list.requestSave()
        }

        onTaskRenamed: (taskId, oldTitle, newTitle) => {
            list.tasks = dataManager.tasks
            list.updateMapsForTask(taskId)
            list.editingTaskId = ""
            list.renameJustCommitted = true
            renameCommitGuard.restart()
            list.restoreKeyboardFocus()
            list.requestSave()
        }

        onSubtaskAdded: (taskId, subtaskId) => {
            list.tasks = dataManager.tasks
            list.updateMapsForTask(taskId)
            list.requestSave()
        }

        onSubtaskToggled: (taskId, subtaskId, newState) => {
            list.tasks = dataManager.tasks
            list.updateMapsForTask(taskId)
            list.requestSave()
        }

        onSubtaskRenamed: (taskId, subtaskId, oldTitle, newTitle) => {
            list.tasks = dataManager.tasks
            list.updateMapsForTask(taskId)
            list.editingSubId = ""
            list.renameJustCommitted = true
            renameCommitGuard.restart()
            list.restoreKeyboardFocus()
            list.requestSave()
        }

        onSubtaskDeleted: (taskId, subtaskId) => {
            list.tasks = dataManager.tasks
            list.updateMapsForTask(taskId)
            list.requestSave()
        }

        onHabitDayRolledOver: () => {
            list.tasks = dataManager.tasks;
            list.updateMaps();
            list.refresh();
        }
    }

    // ── 2am habit-day rollover ── (P-C1: single-shot to next reset, lighter idle CPU)
    Timer {
        id: habitResetTimer
        running: list.isHabitList && list.loaded
        repeat: true
        interval: 60000
        triggeredOnStart: true
        onTriggered: {
            var changed = dataManager.applyHabitDayRollover()
            var ms = dataManager.msUntilNextReset()
            // Sleep until next 2am (not every 60s) — only wake once per day when idle
            interval = Math.max(1000, ms + 250)
            // If nothing changed and not habits, we could stop, but keep running for day change
            if (!changed && !list.isHabitList) interval = 60000
        }
    }

    Timer {
        id: saveTimer
        interval: 400 // coalesced: rapid toggles (5 subs) → 1 stringify, lighter CPU (P-A4)
        onTriggered: list.save()
    }

    // Debounce search so typing "lab" doesn't do 3× O(n*m) scans in quick succession (P-A5)
    Timer {
        id: searchDebounce
        interval: 80
        onTriggered: {
            list.selectedIndex = list.firstVisibleIndex()
            list.selectedSubtaskIndex = -1
        }
    }

    ListModel {
        id: filteredModel
    }

    // ── Controller (filtering, selection, navigation) ──
    function updateMaps() {
        taskMap = dataManager.getTaskMap();
        taskIndexMap = dataManager.getTaskIndexMap();
    }
    // P-A2 incremental: update only one taskId (lighter than full O(n) rebuild) — keeps taskIndexMap as is when index unchanged
    function updateMapsForTask(taskId) {
        var fresh = dataManager.getTaskMap()[taskId]
        if (fresh) {
            var nextMap = Object.assign({}, taskMap)
            nextMap[taskId] = fresh
            taskMap = nextMap
            // invalidate per-task caches for this id only
            if (_progressCache[taskId]) { var n = Object.assign({}, _progressCache); delete n[taskId]; _progressCache = n }
            if (_subtaskMapCache[taskId]) { var n2 = Object.assign({}, _subtaskMapCache); delete n2[taskId]; _subtaskMapCache = n2 }
            if (_taskDurationCache[taskId]) { var n3 = Object.assign({}, _taskDurationCache); delete n3[taskId]; _taskDurationCache = n3 }
            if (_subOrderCache[taskId]) { var n4 = Object.assign({}, _subOrderCache); delete n4[taskId]; _subOrderCache = n4 }
            if (_titleLowerCache[taskId]) { var n5 = Object.assign({}, _titleLowerCache); delete n5[taskId]; _titleLowerCache = n5 }
        } else {
            // deleted — remove from maps (index map will be rebuilt lazily via full updateMaps when needed)
            if (taskMap[taskId] !== undefined) {
                var nm = Object.assign({}, taskMap); delete nm[taskId]; taskMap = nm
            }
            if (_progressCache[taskId]) { var nc = Object.assign({}, _progressCache); delete nc[taskId]; _progressCache = nc }
            if (_titleLowerCache[taskId]) { var nt = Object.assign({}, _titleLowerCache); delete nt[taskId]; _titleLowerCache = nt }
        }
    }
    // P-B cached lower search (avoid per-task toLower per frame)
    readonly property string searchLower: searchQuery.trim().toLowerCase()
    property var _titleLowerCache: ({})
    function getTitleLower(todoId) {
        var task = taskMap[todoId]
        if (!task) return ""
        var cached = _titleLowerCache[todoId]
        if (cached && cached.task === task) return cached.value
        var v = task.title ? task.title.toLowerCase() : ""
        var next = Object.assign({}, _titleLowerCache)
        next[todoId] = { task: task, value: v }
        _titleLowerCache = next
        return v
    }

    function updateFilteredModel() {
        // Keep BOTH search and status filtering in each delegate's visible
        // binding so switching filters (like typing) never rebuilds the
        // model — the model only changes when the set of task ids does.
        var filteredIds = dataManager.getFilteredTasks("", "");

        if (filteredModel.count === filteredIds.length) {
            var same = true;
            for (var i = 0; i < filteredIds.length; i++) {
                if (filteredModel.get(i).todoId !== filteredIds[i]) {
                    same = false;
                    break;
                }
            }
            if (same) return;
        }

        filteredModel.clear();
        for (var i = 0; i < filteredIds.length; i++) {
            filteredModel.append({ todoId: filteredIds[i] });
        }
    }

    // Mirrors the delegates' visible binding (status filter + search). P-B: uses cached searchLower + titleLower
    function isTaskVisible(index) {
        var entry = filteredModel.get(index);
        var task = entry ? list.taskMap[entry.todoId] : null;
        if (!task) return false;

        if (list.statusFilter === "active" && task.done) return false;
        if (list.statusFilter === "done" && !task.done) return false;

        var q = list.searchLower
        if (q) {
            var matchTitle = getTitleLower(entry.todoId).indexOf(q) !== -1
            var matchSub = false
            var subs = task.subtasks || []
            for (var j = 0; j < subs.length; j++) {
                if (subs[j].title && subs[j].title.toLowerCase().indexOf(q) !== -1) {
                    matchSub = true
                    break
                }
            }
            if (!matchTitle && !matchSub) return false
        }
        return true
    }

    // Nearest visible index searching from `from` in `dir` (+1 / -1) with
    // wrap-around; -1 when nothing is visible.
    function nextVisibleIndex(from, dir) {
        var count = filteredModel.count;
        for (var step = 1; step <= count; step++) {
            var idx = ((from + dir * step) % count + count) % count;
            if (list.isTaskVisible(idx)) return idx;
        }
        return -1;
    }

    function firstVisibleIndex() {
        for (var i = 0; i < filteredModel.count; i++)
            if (list.isTaskVisible(i)) return i;
        return -1;
    }

    function lastVisibleIndex() {
        for (var i = filteredModel.count - 1; i >= 0; i--)
            if (list.isTaskVisible(i)) return i;
        return -1;
    }

    // Keep the selection on a visible task after data changes (e.g. a task
    // toggled away under the "active" filter).
    function ensureSelectionVisible() {
        if (filteredModel.count === 0) {
            list.selectedIndex = -1;
            return;
        }
        if (list.selectedIndex >= filteredModel.count)
            list.selectedIndex = filteredModel.count - 1;
        if (list.selectedIndex >= 0 && !list.isTaskVisible(list.selectedIndex))
            list.selectedIndex = list.nextVisibleIndex(list.selectedIndex, 1);
    }

    function refresh() {
        list.tasks = dataManager.tasks;
        list.updateMaps();
        list.updateFilteredModel();
        list.ensureSelectionVisible();
        list.requestSave();
    }

    onTasksChanged: {
        if (dataManager.tasks !== list.tasks)
            dataManager.tasks = list.tasks;
        list.updateMaps();
        list.updateFilteredModel();
    }

    onLoadedChanged: {
        if (loaded) {
            dataManager.tasks = list.tasks;
            list.updateMaps();
            list.updateFilteredModel();
        }
    }

    onStatusFilterChanged: {
        // Instant: the delegates hide/show via their visible bindings,
        // no model rebuild — just move the selection to a visible task.
        list.selectedSubtaskIndex = -1;
        list.selectedIndex = list.firstVisibleIndex();
    }

    onSearchQueryChanged: searchDebounce.restart()

    readonly property int visibleTaskCount: {
        var count = 0
        var q = list.searchLower
        for (var i = 0; i < filteredModel.count; i++) {
            var todoId = filteredModel.get(i).todoId
            var task = list.taskMap[todoId]
            if (!task) continue

            if (list.statusFilter === "active" && task.done) continue
            if (list.statusFilter === "done" && !task.done) continue

            if (q) {
                var matchTitle = getTitleLower(todoId).indexOf(q) !== -1
                var matchSubtask = false
                if (task.subtasks) {
                    for (var j = 0; j < task.subtasks.length; j++) {
                        if (task.subtasks[j].title && task.subtasks[j].title.toLowerCase().indexOf(q) !== -1) {
                            matchSubtask = true
                            break
                        }
                    }
                }
                if (!matchTitle && !matchSubtask) continue
            }

            count++
        }
        return count
    }

    property string editingTaskId: ""
    property string editingSubId: ""
    property int selectedIndex: -1
    property int selectedSubtaskIndex: -1
    // Set when a rename commit returns focus to the list: the Enter key
    // that triggered the commit must not then toggle the task.
    property bool renameJustCommitted: false

    Timer {
        id: renameCommitGuard
        interval: 0
        onTriggered: list.renameJustCommitted = false
    }
    focus: true

    onSelectedIndexChanged: list.selectedSubtaskIndex = -1

    function selectedCard() {
        return selectedIndex >= 0 ? scroller.itemAtIndex(selectedIndex) : null;
    }

    function restoreKeyboardFocus() {
        Qt.callLater(function() {
            if (!list.visible)
                return;
            // Release focus from any lingering item first
            if (Window.activeFocusItem)
                Window.activeFocusItem.focus = false;
            list.focus = true;
            list.forceActiveFocus(Qt.TabFocusReason);
        });
    }

    function selectTask(index) {
        selectedIndex = index;
        selectedSubtaskIndex = -1;
        keepSelectedVisible(selectedCard());
    }

    function toggleSelected() {
        var card = selectedCard();
        if (!card)
            return;
        if (list.selectedSubtaskIndex >= 0)
            dataManager.toggleSubtask(card.taskIndex, list.selectedSubtaskIndex);
        else if (card.nSub === 0)
            dataManager.toggleTask(card.taskIndex);
    }

    function beginEditingSelected() {
        var card = selectedCard();
        if (!card)
            return;

        if (list.selectedSubtaskIndex >= 0 && list.selectedSubtaskIndex < card.nSub) {
            var subtask = card.taskData.subtasks[list.selectedSubtaskIndex];
            list.editingTaskId = "";
            list.editingSubId = `${card.taskId}__${subtask.id}`;
        } else {
            list.editingSubId = "";
            list.editingTaskId = card.taskId;
        }
    }

    function keepSelectedVisible(card) {
        if (card) {
            if (card.y < scroller.contentY)
                scroller.contentY = card.y;
            else if (card.y + card.height > scroller.contentY + scroller.height)
                scroller.contentY = card.y + card.height - scroller.height;
            return;
        }
        // Virtualized case: delegate not instantiated (offscreen) — ask ListView to bring it into view
        if (selectedIndex >= 0 && scroller.positionViewAtIndex) {
            scroller.positionViewAtIndex(selectedIndex, ListView.Contain);
        }
    }

    function finishLoad() {
        if (!list.tasksLoaded)
            return;

        var migrated = false;
        for (var i = 0; i < list.tasks.length; i++) {
            var task = list.tasks[i];
            if (list.isHabitList) {
                if (dataManager.ensureHabitFields(task))
                    migrated = true;
                dataManager.updateStreaks(task);
            }
            for (var j = 0; j < (task.subtasks || []).length; j++) {
                if (dataManager.ensureSubtaskFields(task.subtasks[j]))
                    migrated = true;
                // P-C2: avoid `delete` (de-optimizes QML/JS object shapes) — set to undefined instead
                if (task.subtasks[j].completions !== undefined) {
                    task.subtasks[j].completions = undefined;
                    migrated = true;
                }
            }
            if (!task.completionDates) {
                task.completionDates = [];
                migrated = true;
            }
            dataManager.syncDone(task);
        }

        if (list.isHabitList)
            dataManager.applyHabitDayRollover();
        list.loaded = true;
        if (migrated)
            list.requestSave();
    }

    Keys.onPressed: event => {
        if (list.editingTaskId !== "" || list.editingSubId !== "") {
            event.accepted = false;
            return;
        }

        var nextIndex = list.selectedIndex;
        if (event.key === Qt.Key_F2) {
            list.beginEditingSelected();
            event.accepted = true;
            return;
        } else if (event.key === Qt.Key_Down) {
            var downCard = list.selectedCard();
            if (downCard && downCard.expanded && downCard.nSub > 0) {
                list.selectedSubtaskIndex = list.selectedSubtaskIndex < 0
                    ? 0
                    : (list.selectedSubtaskIndex + 1) % downCard.nSub;
                list.keepSelectedVisible(downCard);
                event.accepted = true;
                return;
            }
            var count = filteredModel.count;
            if (count > 0) {
                nextIndex = list.nextVisibleIndex(list.selectedIndex, 1);
            }
            list.selectedSubtaskIndex = -1;
        } else if (event.key === Qt.Key_Up) {
            var upCard = list.selectedCard();
            if (upCard && upCard.expanded && upCard.nSub > 0) {
                list.selectedSubtaskIndex = list.selectedSubtaskIndex < 0
                    ? upCard.nSub - 1
                    : (list.selectedSubtaskIndex - 1 + upCard.nSub) % upCard.nSub;
                list.keepSelectedVisible(upCard);
                event.accepted = true;
                return;
            }
            var count = filteredModel.count;
            if (count > 0) {
                var cur = list.selectedIndex;
                nextIndex = (cur < 0) ? list.lastVisibleIndex() : list.nextVisibleIndex(cur, -1);
            }
            list.selectedSubtaskIndex = -1;
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            var card = list.selectedCard();
            if (!card) {
                event.accepted = false;
                return;
            } else if (event.key === Qt.Key_Left) {
                list.selectedSubtaskIndex = -1;
                restoreKeyboardFocus()
                card.expanded = false;
            } else if (list.selectedSubtaskIndex < 0) {
                card.expanded = true;
                if (card.nSub > 0) list.selectedSubtaskIndex = 0;
            }
            event.accepted = true;
            return;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            // Swallow the Enter that triggered a rename commit so it
            // doesn't also toggle the just-edited item.
            if (list.renameJustCommitted) {
                list.renameJustCommitted = false
                event.accepted = true
                return
            }
            list.toggleSelected();
            event.accepted = true;
            return;
        } else {
            event.accepted = false;
            return;
        }

        if (filteredModel.count > 0) {
            list.selectTask(nextIndex);
            list.keepSelectedVisible(list.selectedCard());
        }
        event.accepted = true;
    }

    // ── Persistence (load/save) ──
    FileView {
        id: storage
        path: list.dataPath
        onLoaded: {
            try {
                var raw = JSON.parse(text());
                var parsed = Array.isArray(raw) ? raw : (raw.habits || []);
                for (var i = 0; i < parsed.length; i++) {
                    var t = parsed[i];
                    if (!t.subtasks) t.subtasks = [];
                    for (var j = 0; j < t.subtasks.length; j++) {
                        if (!t.subtasks[j].id)
                            t.subtasks[j].id = String(Date.now() + "-" + j);
                    }
                    if (!t.todoId) t.todoId = String(t.id || Date.now() + "-" + i);
                    t.todoId = String(t.todoId);
                }
                list.tasks = parsed;
                list.tasksLoaded = true;
                list.finishLoad();
            } catch (e) {
                list.tasks = [];
                list.tasksLoaded = true;
                list.finishLoad();
            }
        }
        onLoadFailed: function(err) {
            list.tasks = [];
            list.tasksLoaded = true;
            if (err === FileViewError.FileNotFound)
                Qt.callLater(function() { storage.setText("[]"); });
            list.finishLoad();
        }
    }

    function save() {
        // Compact JSON (no pretty) → ~30% smaller & faster, less main-thread block (P-A4)
        storage.setText(JSON.stringify(list.tasks));
    }

    function requestSave() {
        saveTimer.restart();
    }

    // ── View (repeater, delegates, empty state) ──
    readonly property int activeCount: {
        var count = 0;
        for (var i = 0; i < list.tasks.length; i++) {
            if (!list.tasks[i].done) count++;
        }
        return count;
    }
    readonly property int doneCount: Math.max(0, list.tasks.length - activeCount)
    readonly property string habitDay: dataManager.currentHabitDay

    // ── Optimized View: virtualized ListView (P-A1) — only visible delegates instantiated
    // Replaces StyledFlickable+ColumnLayout+Repeater (which created all delegates) with
    // ListView reuseItems. Keeps emptyState as overlay, not as delegate, so hidden filtered
    // tasks don't reserve space. CacheBuffer 500 keeps scroll smooth.
    ListView {
        id: scroller
        anchors.fill: parent
        clip: true
        model: filteredModel
        spacing: Tokens.spacing.small
        cacheBuffer: 500
        reuseItems: true
        interactive: contentHeight > height
        flickableDirection: Flickable.VerticalFlick
        focus: false

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: scroller
        }

        delegate: TaskCard {
            required property string todoId
            required property int index

            width: ListView.view ? ListView.view.width : parent ? parent.width : 0
            // Collapse hidden filtered items to 0 height so they don't reserve space in ListView
            height: visible ? implicitHeight : 0
            visible: {
                var t = task
                if (!t) return false
                if (list.statusFilter === "active" && t.done) return false
                if (list.statusFilter === "done" && !t.done) return false
                var q = list.searchLower
                if (q) {
                    var matchTitle = list.getTitleLower(todoId).indexOf(q) !== -1
                    var matchSubtask = false
                    if (t.subtasks) {
                        for (var j = 0; j < t.subtasks.length; j++) {
                            if (t.subtasks[j].title && t.subtasks[j].title.toLowerCase().indexOf(q) !== -1) {
                                matchSubtask = true
                                break
                            }
                        }
                    }
                    if (!matchTitle && !matchSubtask) return false
                }
                return true
            }

            property var taskMap: list.taskMap
            property var taskIndexMap: list.taskIndexMap

            readonly property var task: (function() {
                var t = taskMap[todoId]
                if (t) return t
                return {
                    todoId: todoId,
                    icon: null,
                    title: "",
                    done: false,
                    priority: null,
                    subtasks: [],
                    streak: 0,
                    bestStreak: 0
                }
            })()

            readonly property int absIdx: (function() {
                var idx = taskIndexMap[todoId]
                return idx !== undefined ? idx : -1
            })()

            // P-A3 memoized: single cache per todoId, not per-delegate loop
            readonly property var progressData: list.getProgressData(todoId)

            taskData: task
            taskIndex: absIdx
            isEditing: list.editingTaskId === task.todoId
            isSelected: list.selectedIndex === index
            selectedSubtaskIndex: list.selectedIndex === index ? list.selectedSubtaskIndex : -1
            nSub: progressData.total
            dSub: progressData.done
            subOrder: list.getSubOrder(todoId)
            prog: progressData.ratio
            icon: list.isHabitList ? (task.icon || "") : ""
            showStreak: list.isHabitList

            editingSubId: list.editingSubId

            onSelectionRequested: function() {
                list.forceActiveFocus()
                list.selectTask(index)
            }

            onSubtaskSelectionRequested: function(subIdx) {
                list.forceActiveFocus()
                list.selectedIndex = index
                list.selectedSubtaskIndex = subIdx
                list.keepSelectedVisible(scroller.itemAtIndex(index))
            }

            onToggleRequested: function(taskIdx) { dataManager.toggleTask(taskIdx) }
            onRenameRequested: function(taskIdx, newTitle) { dataManager.renameTask(taskIdx, newTitle) }
            onDeleteRequested: function(taskIdx) { dataManager.deleteTask(taskIdx) }
            onAddSubtaskRequested: function(taskIdx, title) { dataManager.addSubtask(taskIdx, title) }
            onToggleSubtaskRequested: function(taskIdx, subIdx) { dataManager.toggleSubtask(taskIdx, subIdx) }
            onDeleteSubtaskRequested: function(taskIdx, subIdx) { dataManager.deleteSubtask(taskIdx, subIdx) }
            onRenameSubtaskRequested: function(taskIdx, subIdx, newTitle) { dataManager.renameSubtask(taskIdx, subIdx, newTitle) }
            onEditingStarted: function(taskId) {
                list.editingSubId = ""
                list.editingTaskId = taskId
            }
            onEditingCancelled: function() {
                list.editingTaskId = ""
                list.restoreKeyboardFocus()
            }
            onSubtaskEditingStarted: function(subtaskId) {
                list.editingTaskId = ""
                list.editingSubId = subtaskId
            }
            onSubtaskEditingCancelled: function() {
                list.editingSubId = ""
                list.restoreKeyboardFocus()
            }
        }

        footer: Item {
            width: 1
            height: Tokens.padding.medium
        }
    }

    // Empty state overlay (visible when no tasks match filter/search, not part of ListView model)
    Item {
        anchors.fill: parent
        visible: list.loaded && list.visibleTaskCount === 0
        ColumnLayout {
            id: emptyState
            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: list.searchQuery.trim().length > 0 ? "search_off"
                    : list.statusFilter === "done" ? "sentiment_satisfied" : "check_circle"
                fontStyle: Tokens.font.icon.builders.extraLarge.build()
                color: Colours.palette.m3outlineVariant
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: {
                    if (list.searchQuery.trim().length > 0) {
                        return qsTr('No matches for "%1"').arg(list.searchQuery.trim())
                    }
                    if (list.statusFilter === "done") return qsTr("Nothing completed yet")
                    if (list.statusFilter === "active") return qsTr("All caught up!")
                    return list.emptyStateText
                }
                color: Colours.palette.m3outlineVariant
                elide: Text.ElideRight
                Layout.maximumWidth: list.width - Tokens.padding.extraLarge * 2
            }
        }
    }

    function addTask(title, icon, type) {
        dataManager.addTask(title, list.isHabitList ? (icon || "") : "", type);
    }

    function addHabit(title, icon, type) {
        dataManager.addTask(title, icon, type);
    }
}