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

    property string dataType: "tasks"
    property string statusFilter: "all"
    property string searchQuery: ""

    readonly property string dataPath: `/home/mohssine/${root.dataType}.json`
    readonly property string emptyStateText: root.dataType === "habits" ? qsTr("No habits yet") : qsTr("No tasks yet")
    readonly property real listMinHeight: 440
    readonly property real listMaxHeight: 640
    readonly property bool isHabitList: root.dataType === "habits"

    implicitHeight: CUtils.clamp(scroller.contentHeight, listMinHeight, listMaxHeight)

    property var tasks: []
    property bool loaded: false
    property var taskMap: ({})
    property var taskIndexMap: ({})

    // ── DataManager ──
    DataManager {
        id: dataManager
        tasks: root.tasks
        habitMode: root.isHabitList

        onTaskAdded: function(taskId, task) {
            filteredModel.insert(0, { todoId: taskId });
            // root.selectedIndex = 0;
            root.tasks = dataManager.tasks;
            root.updateMaps();
            Qt.callLater(function() { root.save(); });
        }

        onTaskDeleted: function(taskId) {
            for (var i = 0; i < filteredModel.count; i++) {
                if (filteredModel.get(i).todoId === taskId) {
                    filteredModel.remove(i);
                    break;
                }
            }
            if (root.selectedIndex >= filteredModel.count) {
                root.selectedIndex = filteredModel.count - 1;
            }
            root.tasks = dataManager.tasks;
            root.updateMaps();
            Qt.callLater(function() { root.save(); });
        }

        onTaskToggled: function(taskId, newState) {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            Qt.callLater(function() { root.save(); });
        }

        onTaskRenamed: function(taskId, oldTitle, newTitle) {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            root.editingTaskId = "";
            Qt.callLater(function() { root.save(); });
        }


        onSubtaskAdded: function(taskId, subtaskId) {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            Qt.callLater(function() { root.save(); });
        }

        onSubtaskToggled: function(taskId, subtaskId, newState) {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            Qt.callLater(function() { root.save(); });
        }

        onSubtaskRenamed: function(taskId, subtaskId, oldTitle, newTitle) {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            root.editingSubId = "";
            Qt.callLater(function() { root.save(); });
        }

        onSubtaskDeleted: function(taskId, subtaskId) {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            Qt.callLater(function() { root.save(); });
        }

        onHabitDayRolledOver: function() {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            Qt.callLater(function() { root.save(); });
        }
    }

    // ── 2am habit-day rollover ──
    // Fires at the next reset (and at least every 60s so suspend/resume still catches it).
    Timer {
        id: habitResetTimer
        running: root.isHabitList && root.loaded
        repeat: false
        interval: 1000
        triggeredOnStart: true
        onTriggered: {
            dataManager.applyHabitDayRollover();
            var ms = dataManager.msUntilNextReset();
            interval = Math.max(1000, Math.min(ms + 250, 60000));
            restart();
        }
    }

    // ── Filtered Model (ONLY for status, NOT for search) ──
    ListModel {
        id: filteredModel
    }

    function updateMaps() {
        taskMap = dataManager.getTaskMap();
        taskIndexMap = dataManager.getTaskIndexMap();
    }

    function updateFilteredModel() {
        // Status filter only - search is handled by visible
        var filteredIds = dataManager.getFilteredTasks(statusFilter, "");
        
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

    // ── Signal Handlers ──
    onTasksChanged: {
        dataManager.tasks = root.tasks;
        updateMaps();
        updateFilteredModel();
    }

    onLoadedChanged: {
        if (loaded) {
            dataManager.tasks = root.tasks;
            updateMaps();
            updateFilteredModel();
        }
    }

    // ── Search is handled by visible, NOT by rebuilding model ──
    // onSearchQueryChanged: updateFilteredModel()  ← REMOVE THIS!

    readonly property int visibleTaskCount: {
        var count = 0;
        var q = root.searchQuery.trim().toLowerCase();
        for (var i = 0; i < filteredModel.count; i++) {
            var task = root.taskMap[filteredModel.get(i).todoId];
            if (!task) continue;
            
            // Status filter
            if (root.statusFilter === "active" && task.done) continue;
            if (root.statusFilter === "done" && !task.done) continue;
            
            // Search filter (same as TaskCard.visible)
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

    // ── File I/O ──
    FileView {
        id: storage
        path: root.dataPath
        onLoaded: {
            try {
                var raw = JSON.parse(text());
                var parsed = Array.isArray(raw) ? raw : (raw.habits || []);
                var migrated = false;
                for (var i = 0; i < parsed.length; i++) {
                    var t = parsed[i];
                    if (!t.subtasks) t.subtasks = [];
                    if (!t.todoId) t.todoId = String(t.id || Date.now() + "-" + i);
                    t.todoId = String(t.todoId);
                    if (root.isHabitList) {
                        if (dataManager.ensureHabitFields(t))
                            migrated = true;
                        // First install: a checked habit with no history counts as today
                        // so we don't wipe a completion they already did this session.
                        var today = dataManager.habitDate();
                        if (t.done && Object.keys(t.completions).length === 0) {
                            dataManager.applyHabitCompletion(t, true);
                            migrated = true;
                        }
                    }
                    dataManager.syncDone(t);
                }
                root.tasks = parsed;
                if (root.isHabitList)
                    dataManager.applyHabitDayRollover();
                if (!Array.isArray(raw) || migrated)
                    Qt.callLater(function() { root.save(); });
            } catch (e) {
                root.tasks = [];
            }
            root.loaded = true;
        }
        onLoadFailed: function(err) {
            root.tasks = [];
            root.loaded = true;
            if (err === FileViewError.FileNotFound)
                Qt.callLater(function() { storage.setText("[]"); });
        }
    }

    function save() {
        storage.setText(JSON.stringify(root.tasks, null, 2));
    }

    // ── Counts (read `tasks` so QML bindings actually re-evaluate) ──
    readonly property int activeCount: {
        var count = 0;
        for (var i = 0; i < root.tasks.length; i++) {
            if (!root.tasks[i].done) count++;
        }
        return count;
    }
    readonly property int doneCount: Math.max(0, root.tasks.length - activeCount)
    readonly property int totalActiveMinutes: {
        var sum = 0;
        for (var i = 0; i < root.tasks.length; i++) {
            var t = root.tasks[i];
            if (!t.done && t.minutes > 0) sum += t.minutes;
        }
        return sum;
    }
    readonly property string habitDay: dataManager.currentHabitDay

    // ── List ──
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

            // Empty state
            Item {
                Layout.fillWidth: true
                implicitHeight: emptyState.implicitHeight + Tokens.padding.extraLarge * 2
                visible: root.loaded && root.visibleTaskCount === 0
                ColumnLayout {
                    id: emptyState
                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.searchQuery.trim().length > 0 ? "search_off"
                            : root.statusFilter === "done" ? "sentiment_satisfied" : "check_circle"
                        fontStyle: Tokens.font.icon.builders.extraLarge.build()
                        color: Colours.palette.m3outlineVariant
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: {
                            if (root.searchQuery.trim().length > 0) {
                                return qsTr('No matches for "%1"').arg(root.searchQuery.trim());
                            }
                            if (root.statusFilter === "done") return qsTr("Nothing completed yet");
                            if (root.statusFilter === "active") return qsTr("All caught up!");
                            return root.emptyStateText;
                        }
                        color: Colours.palette.m3outlineVariant
                        elide: Text.ElideRight
                        Layout.maximumWidth: root.width - Tokens.padding.extraLarge * 2
                    }
                }
            }

            Repeater {
                id: taskRepeater
                model: filteredModel

                delegate: TaskCard {
                    required property string todoId
                    required property int index

                    property var taskMap: root.taskMap
                    property var taskIndexMap: root.taskIndexMap
                    
                    readonly property var task: (function() {
                        var t = taskMap[todoId];
                        if (t) return t;
                        return {
                            todoId: todoId,
                            icon: null,
                            title: "",
                            done: false,
                            priority: null,
                            minutes: null,
                            subtasks: [],
                            streak: 0,
                            bestStreak: 0
                        };
                    })()

                    readonly property int absIdx: (function() {
                        var idx = taskIndexMap[todoId];
                        return idx !== undefined ? idx : -1;
                    })()

                    // ── Status + Search Filter ──
                    visible: {
                        // Status filter
                        if (root.statusFilter === "active" && task.done) return false;
                        if (root.statusFilter === "done" && !task.done) return false;
                        
                        // Search filter (INSTANT - no model rebuild!)
                        var q = root.searchQuery.trim().toLowerCase();
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
                    isEditing: root.editingTaskId === task.todoId
                    isSelected: root.selectedIndex === index
                    nSub: progressData.total
                    dSub: progressData.done
                    subOrder: {
                        var order = [];
                        for (var i = 0; i < task.subtasks.length; i++) {
                            order.push(task.subtasks[i].id);
                        }
                        return order;
                    }
                    prog: progressData.ratio
                    icon: root.isHabitList ? (task.icon || "") : ""
                    showStreak: root.isHabitList

                    editingSubId: root.editingSubId

                    onToggleRequested: function(taskIdx) { dataManager.toggleTask(taskIdx); }
                    onRenameRequested: function(taskIdx, newTitle) { dataManager.renameTask(taskIdx, newTitle); }
                    onDeleteRequested: function(taskIdx) { dataManager.deleteTask(taskIdx); }
                    onAddSubtaskRequested: function(taskIdx, title) { dataManager.addSubtask(taskIdx, title); }
                    onToggleSubtaskRequested: function(taskIdx, subIdx) { dataManager.toggleSubtask(taskIdx, subIdx); }
                    onDeleteSubtaskRequested: function(taskIdx, subIdx) { dataManager.deleteSubtask(taskIdx, subIdx); }
                    onRenameSubtaskRequested: function(taskIdx, subIdx, newTitle) { dataManager.renameSubtask(taskIdx, subIdx, newTitle); }
                    onEditingStarted: function(taskId) { root.editingTaskId = taskId; }
                    onEditingCancelled: function() { root.editingTaskId = ""; }
                    onSubtaskEditingStarted: function(subtaskId) { root.editingSubId = subtaskId; }
                    onSubtaskEditingCancelled: function() { root.editingSubId = ""; }
                    onToggleExpandRequested: function() { expanded = !expanded; }
                }
            }
        }
    }

    // ── Public API ──
    function addTask(title, icon) {
        dataManager.addTask(title, root.isHabitList ? (icon || "") : null);
    }

    function addHabit(title, icon) {
        dataManager.addTask(title, icon);
    }
}