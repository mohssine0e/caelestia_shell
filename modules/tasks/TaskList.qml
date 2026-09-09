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

        onTaskAdded: (taskId, task) => {
            filteredModel.insert(0, { todoId: taskId });
            // root.selectedIndex = 0;
            root.tasks = dataManager.tasks;
            root.updateMaps();
            Qt.callLater(() => { root.save(); });
        }

        onTaskDeleted: (taskId) => {
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
            Qt.callLater(() => { root.save(); });
        }

        onTaskToggled: (taskId, newState) => {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            Qt.callLater(() => { root.save(); });
        }

        onTaskRenamed: (taskId, oldTitle, newTitle) => {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            root.editingTaskId = "";
            Qt.callLater(() => { root.save(); });
        }


        onSubtaskAdded: (taskId, subtaskId) => {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            Qt.callLater(() => { root.save(); });
        }

        onSubtaskToggled: (taskId, subtaskId, newState) => {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            Qt.callLater(() => { root.save(); });
        }

        onSubtaskRenamed: (taskId, subtaskId, oldTitle, newTitle) => {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            root.editingSubId = "";
            Qt.callLater(() => { root.save(); });
        }

        onSubtaskDeleted: (taskId, subtaskId) => {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            Qt.callLater(() => { root.save(); });
        }

        onHabitDayRolledOver: () => {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            Qt.callLater(() => { root.save(); });
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
    property int selectedSubtaskIndex: -1
    focus: true

    function selectedCard() {
        return selectedIndex >= 0 ? taskRepeater.itemAt(selectedIndex) : null;
    }

    function selectTask(index) {
        selectedIndex = index;
        selectedSubtaskIndex = -1;
        keepSelectedVisible(selectedCard());
    }

    function toggleSelected() {
        var card = selectedCard();
        if (!card || card.nSub > 0 && root.selectedSubtaskIndex < 0)
            return;
        if (selectedSubtaskIndex >= 0)
            dataManager.toggleSubtask(card.taskIndex, selectedSubtaskIndex);
        else dataManager.toggleTask(card.taskIndex);
    }

    function keepSelectedVisible(card) {
        if (!card)
            return;
        if (card.y < scroller.contentY)
            scroller.contentY = card.y;
        else if (card.y + card.height > scroller.contentY + scroller.height)
            scroller.contentY = card.y + card.height - scroller.height;
    }

    Keys.onPressed: event => {
        if (root.editingTaskId !== "" || root.editingSubId !== "")
            return;

        var nextIndex = root.selectedIndex;
        if (event.key === Qt.Key_Down) {
            var downCard = root.selectedCard();
            if (downCard && downCard.expanded && downCard.nSub > 0 && root.selectedSubtaskIndex < downCard.nSub - 1) {
                root.selectedSubtaskIndex = Math.max(0, root.selectedSubtaskIndex + 1);
                root.keepSelectedVisible(downCard);
                event.accepted = true;
                return;
            }
            if (downCard && downCard.expanded && root.selectedSubtaskIndex < 0) {
                root.selectedSubtaskIndex = 0;
                event.accepted = true;
                return;
            }
            nextIndex = Math.min(filteredModel.count - 1, Math.max(0, nextIndex + 1));
            root.selectedSubtaskIndex = -1;
        } else if (event.key === Qt.Key_Up) {
            var upCard = root.selectedCard();
            if (upCard && root.selectedSubtaskIndex > 0) {
                root.selectedSubtaskIndex--;
                root.keepSelectedVisible(upCard);
                event.accepted = true;
                return;
            }
            if (upCard && root.selectedSubtaskIndex === 0) {
                root.selectedSubtaskIndex = -1;
                event.accepted = true;
                return;
            }
            nextIndex = nextIndex < 0 ? filteredModel.count - 1 : Math.max(0, nextIndex - 1);
            root.selectedSubtaskIndex = -1;
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            var card = root.selectedCard();
            if (!card)
                return;
            if (event.key === Qt.Key_Left && root.selectedSubtaskIndex >= 0) {
                root.selectedSubtaskIndex = -1;
            } else if (event.key === Qt.Key_Left) {
                card.expanded = false;
            } else if (card.nSub > 0 && root.selectedSubtaskIndex < 0) {
                card.expanded = true;
                root.selectedSubtaskIndex = 0;
            }
            event.accepted = true;
            return;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter ) {
            root.toggleSelected();
            event.accepted = true;
            return;
        } else {
            return;
        }

        if (filteredModel.count > 0) {
            root.selectTask(nextIndex);
            root.keepSelectedVisible(root.selectedCard());
        }
        event.accepted = true;
    }

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
                    for (var j = 0; j < t.subtasks.length; j++) {
                        if (dataManager.ensureSubtaskFields(t.subtasks[j]))
                            migrated = true;
                    }
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

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: scroller
        }

        ColumnLayout {
            id: col
            width: parent.width
            height: implicitHeight
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
                    selectedSubtaskIndex: root.selectedIndex === index ? root.selectedSubtaskIndex : -1
                    nSub: progressData.total
                    dSub: progressData.done
                    subOrder: {
                        var order = [];
                        var subs = (task && task.subtasks) ? task.subtasks : [];
                        for (var i = 0; i < subs.length; i++) {
                            order.push(subs[i].id);
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
                }
            }

            // Keep the last row clear of the viewport edge when scrolled to bottom.
            Item {
                Layout.fillWidth: true
                implicitHeight: Tokens.padding.medium
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
