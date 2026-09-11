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
    readonly property string historyPath: "/home/mohssine/habits_history.json"
    readonly property string emptyStateText: root.dataType === "habits" ? qsTr("No habits yet") : qsTr("No tasks yet")
    readonly property real listMinHeight: 440
    readonly property real listMaxHeight: 640
    readonly property bool isHabitList: root.dataType === "habits"

    implicitHeight: CUtils.clamp(scroller.contentHeight, listMinHeight, listMaxHeight)

    property var tasks: []
    property bool loaded: false
    property bool tasksLoaded: false
    property bool historyLoaded: !root.isHabitList
    property var taskMap: ({})
    property var taskIndexMap: ({})

    // ── DataManager ──
    DataManager {
        id: dataManager
        tasks: root.tasks
        habitMode: root.isHabitList

        onTaskAdded: (taskId, task) => {
            filteredModel.insert(0, { todoId: taskId });
            root.tasks = dataManager.tasks;
            root.updateMaps();
            root.requestSave();
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
            root.requestSave();
        }

        onTaskToggled: (taskId, newState) => {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            root.requestSave();
        }

        onTaskRenamed: (taskId, oldTitle, newTitle) => {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            root.editingTaskId = "";
            root.restoreKeyboardFocus();
            root.requestSave();
        }

        onSubtaskAdded: (taskId, subtaskId) => {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            root.requestSave();
        }

        onSubtaskToggled: (taskId, subtaskId, newState) => {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            root.requestSave();
        }

        onSubtaskRenamed: (taskId, subtaskId, oldTitle, newTitle) => {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            root.editingSubId = "";
            root.restoreKeyboardFocus();
            root.requestSave();
        }

        onSubtaskDeleted: (taskId, subtaskId) => {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            root.requestSave();
        }

        onHabitDayRolledOver: () => {
            root.tasks = dataManager.tasks;
            root.updateMaps();
            root.requestSave();
        }

        onHabitHistoryChanged: {
            if (root.loaded)
                root.requestSave();
        }
    }

    // ── 2am habit-day rollover ──
    Timer {
        id: habitResetTimer
        running: root.isHabitList && root.loaded
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
        onTriggered: root.save()
    }

    ListModel {
        id: filteredModel
    }

    function updateMaps() {
        taskMap = dataManager.getTaskMap();
        taskIndexMap = dataManager.getTaskIndexMap();
    }

    function updateFilteredModel() {
        var filteredIds = dataManager.getFilteredTasks(statusFilter, searchQuery);

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

    onTasksChanged: {
        if (dataManager.tasks !== root.tasks)
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

    onStatusFilterChanged: {
        root.selectedIndex = filteredModel.count > 0 ? 0 : -1;
        root.selectedSubtaskIndex = -1;
    }

    onSearchQueryChanged: {
        updateFilteredModel();
        root.selectedIndex = filteredModel.count > 0 ? 0 : -1;
        root.selectedSubtaskIndex = -1;
    }

    readonly property int visibleTaskCount: {
        var count = 0;
        var q = root.searchQuery.trim().toLowerCase();
        for (var i = 0; i < filteredModel.count; i++) {
            var task = root.taskMap[filteredModel.get(i).todoId];
            if (!task) continue;

            if (root.statusFilter === "active" && task.done) continue;
            if (root.statusFilter === "done" && !task.done) continue;

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

    onSelectedIndexChanged: root.selectedSubtaskIndex = -1

    function selectedCard() {
        return selectedIndex >= 0 ? taskRepeater.itemAt(selectedIndex) : null;
    }

    function restoreKeyboardFocus() {
        Qt.callLater(function() {
            if (!root.visible)
                return;
            // Release focus from any lingering item first
            if (Window.activeFocusItem)
                Window.activeFocusItem.focus = false;
            root.focus = true;
            root.forceActiveFocus(Qt.TabFocusReason);
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
        if (root.selectedSubtaskIndex >= 0)
            dataManager.toggleSubtask(card.taskIndex, root.selectedSubtaskIndex);
        else if (card.nSub === 0)
            dataManager.toggleTask(card.taskIndex);
    }

    function beginEditingSelected() {
        var card = selectedCard();
        if (!card)
            return;

        if (root.selectedSubtaskIndex >= 0 && root.selectedSubtaskIndex < card.nSub) {
            var subtask = card.taskData.subtasks[root.selectedSubtaskIndex];
            root.editingTaskId = "";
            root.editingSubId = `${card.taskId}__${subtask.id}`;
        } else {
            root.editingSubId = "";
            root.editingTaskId = card.taskId;
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
        if (!root.tasksLoaded || !root.historyLoaded)
            return;

        var migrated = false;
        for (var i = 0; i < root.tasks.length; i++) {
            var task = root.tasks[i];
            if (root.isHabitList) {
                if (dataManager.importLegacyCompletions(task))
                    migrated = true;
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
            dataManager.syncDone(task);
        }

        if (root.isHabitList)
            dataManager.applyHabitDayRollover();
        root.loaded = true;
        if (migrated)
            root.requestSave();
    }

    Keys.onPressed: event => {
        if (root.editingTaskId !== "" || root.editingSubId !== "") {
            event.accepted = false;
            return;
        }

        var nextIndex = root.selectedIndex;
        if (event.key === Qt.Key_F2) {
            root.beginEditingSelected();
            event.accepted = true;
            return;
        } else if (event.key === Qt.Key_Down) {
            var downCard = root.selectedCard();
            if (downCard && downCard.expanded && downCard.nSub > 0) {
                root.selectedSubtaskIndex = root.selectedSubtaskIndex < 0
                    ? 0
                    : (root.selectedSubtaskIndex + 1) % downCard.nSub;
                root.keepSelectedVisible(downCard);
                event.accepted = true;
                return;
            }
            var count = filteredModel.count;
            if (count > 0) {
                var cur = root.selectedIndex;
                nextIndex = (cur < 0) ? 0 : (cur + 1) % count;
            }
            root.selectedSubtaskIndex = -1;
        } else if (event.key === Qt.Key_Up) {
            var upCard = root.selectedCard();
            if (upCard && upCard.expanded && upCard.nSub > 0) {
                root.selectedSubtaskIndex = root.selectedSubtaskIndex < 0
                    ? upCard.nSub - 1
                    : (root.selectedSubtaskIndex - 1 + upCard.nSub) % upCard.nSub;
                root.keepSelectedVisible(upCard);
                event.accepted = true;
                return;
            }
            var count = filteredModel.count;
            if (count > 0) {
                var cur = root.selectedIndex;
                nextIndex = (cur <= 0) ? count - 1 : (cur - 1);
            }
            root.selectedSubtaskIndex = -1;
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            var card = root.selectedCard();
            if (!card) {
                event.accepted = false;
                return;
            } else if (event.key === Qt.Key_Left) {
                root.selectedSubtaskIndex = -1;
                card.expanded = false;
            } else if (root.selectedSubtaskIndex < 0) {
                card.expanded = true;
                if (card.nSub > 0) root.selectedSubtaskIndex = 0;
            }
            event.accepted = true;
            return;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.toggleSelected();
            event.accepted = true;
            return;
        } else {
            event.accepted = false;
            return;
        }

        if (filteredModel.count > 0) {
            root.selectTask(nextIndex);
            root.keepSelectedVisible(root.selectedCard());
        }
        event.accepted = true;
    }

    FileView {
        id: storage
        path: root.dataPath
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
                root.tasks = parsed;
                root.tasksLoaded = true;
                root.finishLoad();
            } catch (e) {
                root.tasks = [];
                root.tasksLoaded = true;
                root.finishLoad();
            }
        }
        onLoadFailed: function(err) {
            root.tasks = [];
            root.tasksLoaded = true;
            if (err === FileViewError.FileNotFound)
                Qt.callLater(function() { storage.setText("[]"); });
            root.finishLoad();
        }
    }

    FileView {
        id: historyStorage
        path: root.historyPath
        onLoaded: {
            try {
                var raw = JSON.parse(text());
                dataManager.history = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
            } catch (e) {
                dataManager.history = {};
            }
            root.historyLoaded = true;
            root.finishLoad();
        }
        onLoadFailed: function(err) {
            dataManager.history = {};
            root.historyLoaded = true;
            if (err === FileViewError.FileNotFound)
                Qt.callLater(function() { historyStorage.setText("{}"); });
            root.finishLoad();
        }
    }

    function save() {
        storage.setText(JSON.stringify(root.tasks, null, 2));
        if (root.isHabitList)
            historyStorage.setText(JSON.stringify(dataManager.history, null, 2));
    }

    function requestSave() {
        saveTimer.restart();
    }

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

                    visible: {
                        if (root.statusFilter === "active" && task.done) return false;
                        if (root.statusFilter === "done" && !task.done) return false;

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

                    onSelectionRequested: function() {
                        root.forceActiveFocus();
                        root.selectTask(index);
                    }

                    onSubtaskSelectionRequested: function(subIdx) {
                        root.forceActiveFocus();
                        root.selectedIndex = index;
                        root.selectedSubtaskIndex = subIdx;
                        root.keepSelectedVisible(taskRepeater.itemAt(index));
                    }

                    onToggleRequested: function(taskIdx) { dataManager.toggleTask(taskIdx); }
                    onRenameRequested: function(taskIdx, newTitle) { dataManager.renameTask(taskIdx, newTitle); }
                    onDeleteRequested: function(taskIdx) { dataManager.deleteTask(taskIdx); }
                    onAddSubtaskRequested: function(taskIdx, title) { dataManager.addSubtask(taskIdx, title); }
                    onToggleSubtaskRequested: function(taskIdx, subIdx) { dataManager.toggleSubtask(taskIdx, subIdx); }
                    onDeleteSubtaskRequested: function(taskIdx, subIdx) { dataManager.deleteSubtask(taskIdx, subIdx); }
                    onRenameSubtaskRequested: function(taskIdx, subIdx, newTitle) { dataManager.renameSubtask(taskIdx, subIdx, newTitle); }
                    onEditingStarted: function(taskId) {
                        root.editingSubId = "";
                        root.editingTaskId = taskId;
                    }
                    onEditingCancelled: function() {
                        root.editingTaskId = "";
                        root.restoreKeyboardFocus();
                    }
                    onSubtaskEditingStarted: function(subtaskId) {
                        root.editingTaskId = "";
                        root.editingSubId = subtaskId;
                    }
                    onSubtaskEditingCancelled: function() {
                        root.editingSubId = "";
                        root.restoreKeyboardFocus();
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
        dataManager.addTask(title, root.isHabitList ? (icon || "") : "", type);
    }

    function addHabit(title, icon, type) {
        dataManager.addTask(title, icon, type);
    }
}