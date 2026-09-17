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
            list.refresh();
        }

        onTaskRenamed: (taskId, oldTitle, newTitle) => {
            list.tasks = dataManager.tasks;
            list.updateMaps();
            list.editingTaskId = "";
            list.renameJustCommitted = true;
            renameCommitGuard.restart();
            list.restoreKeyboardFocus();
            list.refresh();
        }

        onSubtaskAdded: (taskId, subtaskId) => {
            list.tasks = dataManager.tasks;
            list.updateMaps();
            list.refresh();
        }

        onSubtaskToggled: (taskId, subtaskId, newState) => {
            list.tasks = dataManager.tasks;
            list.updateMaps();
            list.refresh();
        }

        onSubtaskRenamed: (taskId, subtaskId, oldTitle, newTitle) => {
            list.tasks = dataManager.tasks;
            list.updateMaps();
            list.editingSubId = "";
            list.renameJustCommitted = true;
            renameCommitGuard.restart();
            list.restoreKeyboardFocus();
            list.refresh();
        }

        onSubtaskDeleted: (taskId, subtaskId) => {
            list.tasks = dataManager.tasks;
            list.updateMaps();
            list.refresh();
        }

        onHabitDayRolledOver: () => {
            list.tasks = dataManager.tasks;
            list.updateMaps();
            list.refresh();
        }
    }

    // ── 2am habit-day rollover ──
    Timer {
        id: habitResetTimer
        running: list.isHabitList && list.loaded
        repeat: true
        interval: 60000
        triggeredOnStart: true
        onTriggered: {
            dataManager.applyHabitDayRollover();
            var ms = dataManager.msUntilNextReset();
            interval = Math.max(1000, Math.min(ms + 250, 60000));
        }
    }

    Timer {
        id: saveTimer
        interval: 100
        onTriggered: list.save()
    }

    ListModel {
        id: filteredModel
    }

    // ── Controller (filtering, selection, navigation) ──
    function updateMaps() {
        taskMap = dataManager.getTaskMap();
        taskIndexMap = dataManager.getTaskIndexMap();
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

    // Mirrors the delegates' visible binding (status filter + search).
    function isTaskVisible(index) {
        var entry = filteredModel.get(index);
        var task = entry ? list.taskMap[entry.todoId] : null;
        if (!task) return false;

        if (list.statusFilter === "active" && task.done) return false;
        if (list.statusFilter === "done" && !task.done) return false;

        var q = list.searchQuery.trim().toLowerCase();
        if (q) {
            var matchTitle = task.title ? task.title.toLowerCase().indexOf(q) !== -1 : false;
            var matchSub = false;
            var subs = task.subtasks || [];
            for (var j = 0; j < subs.length; j++) {
                if (subs[j].title && subs[j].title.toLowerCase().indexOf(q) !== -1) {
                    matchSub = true;
                    break;
                }
            }
            if (!matchTitle && !matchSub) return false;
        }
        return true;
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

    onSearchQueryChanged: {
        list.selectedIndex = list.firstVisibleIndex();
        list.selectedSubtaskIndex = -1;
    }

    readonly property int visibleTaskCount: {
        var count = 0;
        var q = list.searchQuery.trim().toLowerCase();
        for (var i = 0; i < filteredModel.count; i++) {
            var task = list.taskMap[filteredModel.get(i).todoId];
            if (!task) continue;

            if (list.statusFilter === "active" && task.done) continue;
            if (list.statusFilter === "done" && !task.done) continue;

            if (q) {
                var matchTitle = task.title ? task.title.toLowerCase().indexOf(q) !== -1 : false;
                var matchSubtask = false;
                if (task.subtasks) {
                    for (var j = 0; j < task.subtasks.length; j++) {
                        if (task.subtasks[j].title && task.subtasks[j].title.toLowerCase().indexOf(q) !== -1) {
                            matchSubtask = true;
                            break;
                        }
                    }
                }
                if (!matchTitle && !matchSubtask) continue;
            }

            count++;
        }
        return count;
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
        return selectedIndex >= 0 ? taskRepeater.itemAt(selectedIndex) : null;
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
        if (!card)
            return;
        if (card.y < scroller.contentY)
            scroller.contentY = card.y;
        else if (card.y + card.height > scroller.contentY + scroller.height)
            scroller.contentY = card.y + card.height - scroller.height;
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
                if (task.subtasks[j].completions !== undefined) {
                    delete task.subtasks[j].completions;
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
        storage.setText(JSON.stringify(list.tasks, null, 2));
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

    StyledFlickable {
        id: scroller
        anchors.fill: parent
        clip: true
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        contentHeight: col.implicitHeight
        focus: false

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: scroller
        }

        ColumnLayout {
            id: col
            width: parent.width
            height: implicitHeight
            spacing: Tokens.spacing.small

            Item {
                Layout.fillWidth: true
                implicitHeight: emptyState.implicitHeight + Tokens.padding.extraLarge * 2
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
                                return qsTr('No matches for "%1"').arg(list.searchQuery.trim());
                            }
                            if (list.statusFilter === "done") return qsTr("Nothing completed yet");
                            if (list.statusFilter === "active") return qsTr("All caught up!");
                            return list.emptyStateText;
                        }
                        color: Colours.palette.m3outlineVariant
                        elide: Text.ElideRight
                        Layout.maximumWidth: list.width - Tokens.padding.extraLarge * 2
                    }
                }
            }

            Repeater {
                id: taskRepeater
                model: filteredModel

                delegate: TaskCard {
                    required property string todoId
                    required property int index

                    property var taskMap: list.taskMap
                    property var taskIndexMap: list.taskIndexMap

                    readonly property var task: (function() {
                        var t = taskMap[todoId];
                        if (t) return t;
                        return {
                            todoId: todoId,
                            icon: null,
                            title: "",
                            done: false,
                            priority: null,
                            subtasks: [],
                            streak: 0,
                            bestStreak: 0
                        };
                    })()

                    readonly property int absIdx: (function() {
                        var idx = taskIndexMap[todoId];
                        return idx !== undefined ? idx : -1;
                    })()

                    visible: {
                        if (list.statusFilter === "active" && task.done) return false;
                        if (list.statusFilter === "done" && !task.done) return false;

                        var q = list.searchQuery.trim().toLowerCase();
                        if (q) {
                            var matchTitle = task.title ? task.title.toLowerCase().indexOf(q) !== -1 : false;
                            var matchSubtask = false;
                            if (task.subtasks) {
                                for (var j = 0; j < task.subtasks.length; j++) {
                                    if (task.subtasks[j].title && task.subtasks[j].title.toLowerCase().indexOf(q) !== -1) {
                                        matchSubtask = true;
                                        break;
                                    }
                                }
                            }
                            if (!matchTitle && !matchSubtask) return false;
                        }

                        return true;
                    }

                    readonly property var progressData: {
                        var subtasks = task.subtasks || [];
                        var total = subtasks.length;

                        if (total === 0) {
                            return { total: 0, done: 0, ratio: task.done ? 1 : 0 };
                        }

                        var done = 0;
                        for (var i = 0; i < subtasks.length; i++) {
                            if (subtasks[i].done) done++;
                        }
                        return { total: total, done: done, ratio: done / total };
                    }

                    taskData: task
                    taskIndex: absIdx
                    isEditing: list.editingTaskId === task.todoId
                    isSelected: list.selectedIndex === index
                    selectedSubtaskIndex: list.selectedIndex === index ? list.selectedSubtaskIndex : -1
                    nSub: progressData.total
                    dSub: progressData.done
                    subOrder: {
                        var order = [];
                        var subs = (task && task.subtasks) ? task.subtasks : [];
                        for (var i = 0; i < subs.length; i++) {
                            order.push({ id: subs[i].id });
                        }
                        return order;
                    }
                    prog: progressData.ratio
                    icon: list.isHabitList ? (task.icon || "") : ""
                    showStreak: list.isHabitList

                    editingSubId: list.editingSubId

                    onSelectionRequested: function() {
                        list.forceActiveFocus();
                        list.selectTask(index);
                    }

                    onSubtaskSelectionRequested: function(subIdx) {
                        list.forceActiveFocus();
                        list.selectedIndex = index;
                        list.selectedSubtaskIndex = subIdx;
                        list.keepSelectedVisible(taskRepeater.itemAt(index));
                    }

                    onToggleRequested: function(taskIdx) { dataManager.toggleTask(taskIdx); }
                    onRenameRequested: function(taskIdx, newTitle) { dataManager.renameTask(taskIdx, newTitle); }
                    onDeleteRequested: function(taskIdx) { dataManager.deleteTask(taskIdx); }
                    onAddSubtaskRequested: function(taskIdx, title) { dataManager.addSubtask(taskIdx, title); }
                    onToggleSubtaskRequested: function(taskIdx, subIdx) { dataManager.toggleSubtask(taskIdx, subIdx); }
                    onDeleteSubtaskRequested: function(taskIdx, subIdx) { dataManager.deleteSubtask(taskIdx, subIdx); }
                    onRenameSubtaskRequested: function(taskIdx, subIdx, newTitle) { dataManager.renameSubtask(taskIdx, subIdx, newTitle); }
                    onEditingStarted: function(taskId) {
                        list.editingSubId = "";
                        list.editingTaskId = taskId;
                    }
                    onEditingCancelled: function() {
                        list.editingTaskId = "";
                        list.restoreKeyboardFocus();
                    }
                    onSubtaskEditingStarted: function(subtaskId) {
                        list.editingTaskId = "";
                        list.editingSubId = subtaskId;
                    }
                    onSubtaskEditingCancelled: function() {
                        list.editingSubId = "";
                        list.restoreKeyboardFocus();
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: Tokens.padding.medium
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