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

    // ── Maps for O(1) Lookups ──────────────────────────────────
    property var taskMap: ({})
    property var taskIndexMap: ({})

    // ── Filtered Model (ONLY for search) ───────────────────────
    ListModel {
        id: filteredModel
    }

    // ── Helper Functions ────────────────────────────────────────
    function updateMaps() {
        const map = {};
        const idxMap = {};
        for (let i = 0; i < tasks.length; i++) {
            const t = tasks[i];
            if (t && t.todoId) {
                map[t.todoId] = t;
                idxMap[t.todoId] = i;
            }
        }
        taskMap = map;
        taskIndexMap = idxMap;
    }

    function updateFilteredModel() {
        const q = searchQuery.trim().toLowerCase();
        
        if (!q) {
            if (filteredModel.count === tasks.length) {
                let same = true;
                for (let i = 0; i < tasks.length; i++) {
                    if (filteredModel.get(i).todoId !== tasks[i].todoId) {
                        same = false;
                        break;
                    }
                }
                if (same) return;
            }
            
            filteredModel.clear();
            for (let i = 0; i < tasks.length; i++) {
                filteredModel.append({ todoId: tasks[i].todoId });
            }
            return;
        }
        
        const result = [];
        for (let i = 0; i < tasks.length; i++) {
            const t = tasks[i];
            const matchTitle = t.task ? t.task.toLowerCase().includes(q) : false;
            
            let matchSubtask = false;
            if (t.subtasks) {
                for (let j = 0; j < t.subtasks.length; j++) {
                    const s = t.subtasks[j];
                    if (s.title && s.title.toLowerCase().includes(q)) {
                        matchSubtask = true;
                        break;
                    }
                }
            }
            
            if (matchTitle || matchSubtask) {
                result.push(t.todoId);
            }
        }
        
        if (filteredModel.count === result.length) {
            let same = true;
            for (let i = 0; i < result.length; i++) {
                if (filteredModel.get(i).todoId !== result[i]) {
                    same = false;
                    break;
                }
            }
            if (same) return;
        }
        
        filteredModel.clear();
        for (let i = 0; i < result.length; i++) {
            filteredModel.append({ todoId: result[i] });
        }
    }

    function getTaskSubtaskMap(taskId) {
        const task = taskMap[taskId];
        if (!task) return {};
        
        const map = {};
        for (let i = 0; i < task.subtasks.length; i++) {
            const sub = task.subtasks[i];
            map[sub.id] = sub;
        }
        return map;
    }

    // ── Signal Handlers ─────────────────────────────────────────
    onTasksChanged: {
        updateMaps();
        updateFilteredModel();
    }

    onLoadedChanged: {
        if (loaded) {
            updateMaps();
            updateFilteredModel();
        }
    }

    onSearchQueryChanged: updateFilteredModel()

    property string editingTaskId: ""
    property string editingSubId: ""
    property string expandedId: ""
    property int  selectedIndex: -1

    // ── Keyboard ─────────────────────────────────────────────────
    readonly property int selectedAbsIdx: selectedIndex >= 0 && selectedIndex < filteredModel.count
        ? (function() {
            const id = filteredModel.get(selectedIndex).todoId;
            for (let i = 0; i < tasks.length; i++) {
                if (tasks[i].todoId === id) return i;
            }
            return -1;
        })() : -1

    function moveSelection(delta) {
        if (filteredModel.count === 0)
            return;
        const next = root.selectedIndex < 0
            ? (delta > 0 ? 0 : filteredModel.count - 1)
            : root.selectedIndex + delta;
        root.selectedIndex = Math.max(0, Math.min(next, filteredModel.count - 1));
        root.ensureVisible(root.selectedIndex);
    }

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

        if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
            root.moveSelection(1);
        } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
            root.moveSelection(-1);
        } else if (abs < 0) {
            event.accepted = false;
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

    // ── File I/O ─────────────────────────────────────────────────
    FileView {
        id: storage
        path: `${Paths.state}/todos.json`
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                for (let i = 0; i < parsed.length; i++) {
                    const t = parsed[i];
                    if (!t.subtasks) t.subtasks = [];
                    root.syncDone(t);
                }
                root.tasks = parsed;
            } catch (e) {
                root.tasks = [];
            }
            root.loaded = true;
        }
        onLoadFailed: err => {
            root.tasks = []; 
            root.loaded = true;
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => storage.setText("[]"));
        }
    }

    function save() { 
        storage.setText(JSON.stringify(root.tasks, null, 2)); 
    }
    
    // ── OPTIMIZED MUTATION ──────────────────────────────────────
    // Instead of deep cloning everything, only clone what's needed
    function updateTask(index, newTask) {
        const newTasks = [];
        for (let i = 0; i < tasks.length; i++) {
            newTasks[i] = i === index ? newTask : tasks[i];
        }
        tasks = newTasks;
        save();
    }

    function updateSubtask(taskIndex, subtaskIndex, newSubtask) {
        const task = tasks[taskIndex];
        if (!task) return;
        
        // Create new subtasks array
        const newSubtasks = [];
        for (let i = 0; i < task.subtasks.length; i++) {
            newSubtasks[i] = i === subtaskIndex ? newSubtask : task.subtasks[i];
        }
        
        // Create new task with updated subtasks
        const newTask = {
            todoId: task.todoId,
            task: task.task,
            done: task.done,
            minutes: task.minutes || 0,
            priority: task.priority || null,
            dueDate: task.dueDate || null,
            project: task.project || "",
            createdAt: task.createdAt || Date.now(),
            subtasks: newSubtasks
        };
        
        // Sync done status
        newTask.done = newTask.subtasks.every(function(s) { return s.done; });
        
        // Update
        updateTask(taskIndex, newTask);
    }

    // ── CRUD ─────────────────────────────────────────────────────
    function addTask(title) {
        if (!title.trim()) return;
        const newTask = {
            todoId: Date.now() + "-" + Math.floor(Math.random() * 1e6),
            task: title.trim(),
            done: false,
            minutes: 0,
            createdAt: Date.now(),
            subtasks: []
        };
        const newTasks = [newTask];
        for (let i = 0; i < tasks.length; i++) {
            newTasks[i + 1] = tasks[i];
        }
        tasks = newTasks;
        save();
    }

    function syncDone(t) {
        if (t.subtasks && t.subtasks.length > 0) {
            let allDone = true;
            for (let i = 0; i < t.subtasks.length; i++) {
                if (!t.subtasks[i].done) {
                    allDone = false;
                    break;
                }
            }
            t.done = allDone;
        }
    }

    function toggleTask(i) {
        if (i < 0 || i >= tasks.length) return;
        const task = tasks[i];
        const newDone = !task.done;
        
        // Create new subtasks with toggled done
        const newSubtasks = [];
        for (let j = 0; j < task.subtasks.length; j++) {
            const s = task.subtasks[j];
            newSubtasks[j] = {
                id: s.id,
                title: s.title,
                done: newDone,
                minutes: s.minutes || 0
            };
        }
        
        const newTask = {
            todoId: task.todoId,
            task: task.task,
            done: newDone,
            minutes: task.minutes || 0,
            priority: task.priority || null,
            dueDate: task.dueDate || null,
            project: task.project || "",
            createdAt: task.createdAt || Date.now(),
            subtasks: newSubtasks
        };
        
        updateTask(i, newTask);
    }

    function toggleExpand(i) {
        const id = tasks[i]?.todoId;
        if (!id) return;
        root.expandedId = root.expandedId === id ? "" : id;
    }

    function renameTask(i, t) {
        if (!t.trim()) return;
        const task = tasks[i];
        if (!task) return;
        
        const newTask = {
            todoId: task.todoId,
            task: t.trim(),
            done: task.done,
            minutes: task.minutes || 0,
            priority: task.priority || null,
            dueDate: task.dueDate || null,
            project: task.project || "",
            createdAt: task.createdAt || Date.now(),
            subtasks: task.subtasks ? task.subtasks.slice() : []
        };
        
        updateTask(i, newTask);
        editingTaskId = "";
    }

    function setTaskEstimate(i, mins) {
        const task = tasks[i];
        if (!task) return;
        
        const newTask = {
            todoId: task.todoId,
            task: task.task,
            done: task.done,
            minutes: mins,
            priority: task.priority || null,
            dueDate: task.dueDate || null,
            project: task.project || "",
            createdAt: task.createdAt || Date.now(),
            subtasks: task.subtasks ? task.subtasks.slice() : []
        };
        
        updateTask(i, newTask);
    }

    function deleteTask(i) {
        const newTasks = [];
        for (let j = 0; j < tasks.length; j++) {
            if (j !== i) newTasks.push(tasks[j]);
        }
        tasks = newTasks;
        save();
    }

    function clearDone() {
        const newTasks = [];
        for (let i = 0; i < tasks.length; i++) {
            if (!tasks[i].done) newTasks.push(tasks[i]);
        }
        tasks = newTasks;
        save();
    }

    function addSubtask(ti, title) {
        if (!title.trim()) return;
        const task = tasks[ti];
        if (!task) return;
        
        const newSubtask = {
            id: Date.now() + "-" + Math.floor(Math.random() * 1e6),
            title: title.trim(),
            done: false,
            minutes: 0
        };
        
        const newSubtasks = task.subtasks.slice();
        newSubtasks.push(newSubtask);
        
        const newTask = {
            todoId: task.todoId,
            task: task.task,
            done: task.done,
            minutes: task.minutes || 0,
            priority: task.priority || null,
            dueDate: task.dueDate || null,
            project: task.project || "",
            createdAt: task.createdAt || Date.now(),
            subtasks: newSubtasks
        };
        
        syncDone(newTask);
        updateTask(ti, newTask);
    }

    function toggleSubtask(ti, si) {
        if (ti < 0 || ti >= tasks.length) return;
        const task = tasks[ti];
        if (si < 0 || si >= task.subtasks.length) return;
        
        const sub = task.subtasks[si];
        const newSub = {
            id: sub.id,
            title: sub.title,
            done: !sub.done,
            minutes: sub.minutes || 0
        };
        
        updateSubtask(ti, si, newSub);
    }

    function renameSubtask(ti, si, t) {
        if (!t.trim()) return;
        const task = tasks[ti];
        if (!task) return;
        
        const sub = task.subtasks[si];
        const newSub = {
            id: sub.id,
            title: t.trim(),
            done: sub.done,
            minutes: sub.minutes || 0
        };
        
        updateSubtask(ti, si, newSub);
        editingSubId = "";
    }

    function deleteSubtask(ti, si) {
        const task = tasks[ti];
        if (!task) return;
        
        const newSubtasks = [];
        for (let i = 0; i < task.subtasks.length; i++) {
            if (i !== si) newSubtasks.push(task.subtasks[i]);
        }
        
        const newTask = {
            todoId: task.todoId,
            task: task.task,
            done: task.done,
            minutes: task.minutes || 0,
            priority: task.priority || null,
            dueDate: task.dueDate || null,
            project: task.project || "",
            createdAt: task.createdAt || Date.now(),
            subtasks: newSubtasks
        };
        
        syncDone(newTask);
        updateTask(ti, newTask);
    }

    // ── Counts ──────────────────────────────────────────────────
    readonly property int activeCount: {
        let count = 0;
        for (let i = 0; i < tasks.length; i++) {
            if (!tasks[i].done) count++;
        }
        return count;
    }

    readonly property int doneCount: tasks.length - activeCount

    readonly property int totalActiveMinutes: {
        let sum = 0;
        for (let i = 0; i < tasks.length; i++) {
            const t = tasks[i];
            if (!t.done && t.minutes > 0) sum += t.minutes;
        }
        return sum;
    }

    // ── List ─────────────────────────────────────────────────────
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
                visible: root.loaded && filteredModel.count === 0
                ColumnLayout {
                    id: emptyState
                    anchors.centerIn: parent; 
                    spacing: Tokens.spacing.small
                    readonly property bool searching: root.searchQuery.trim().length > 0
                    readonly property bool hasVisibleTasks: {
                        for (let i = 0; i < filteredModel.count; i++) {
                            const id = filteredModel.get(i).todoId;
                            const task = root.taskMap[id];
                            if (task) {
                                if (root.statusFilter === "active" && task.done) continue;
                                if (root.statusFilter === "done" && !task.done) continue;
                                return true;
                            }
                        }
                        return false;
                    }

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: emptyState.searching ? "search_off"
                            : root.statusFilter === "done" ? "sentiment_satisfied" : "check_circle"
                        fontStyle: Tokens.font.icon.builders.extraLarge.build()
                        color: Colours.palette.m3outlineVariant
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: {
                            if (emptyState.searching) {
                                return qsTr('No matches for "%1"').arg(root.searchQuery.trim());
                            }
                            if (root.statusFilter === "done") {
                                return qsTr("Nothing completed yet");
                            }
                            if (root.statusFilter === "active") {
                                return qsTr("All caught up!");
                            }
                            return qsTr("No tasks yet");
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
                    required property string modelData
                    required property int index

                    property var taskMap: root.taskMap
                    property var taskIndexMap: root.taskIndexMap
                    
                    readonly property var task: (function() {
                        const t = taskMap[modelData];
                        if (t) return t;
                        return {
                            todoId: modelData,
                            task: "",
                            done: false,
                            priority: null,
                            dueDate: null,
                            subtasks: []
                        };
                    })()

                    readonly property int absIdx: (function() {
                        const idx = taskIndexMap[modelData];
                        return idx !== undefined ? idx : -1;
                    })()

                    visible: {
                        if (root.statusFilter === "active" && task.done) return false;
                        if (root.statusFilter === "done" && !task.done) return false;
                        return true;
                    }

                    readonly property var progressData: {
                        const subtasks = task.subtasks || [];
                        const total = subtasks.length;
                        
                        if (total === 0) {
                            return { total: 0, done: 0, ratio: task.done ? 1 : 0 };
                        }
                        
                        let done = 0;
                        for (let i = 0; i < subtasks.length; i++) {
                            if (subtasks[i].done) done++;
                        }
                        return { total: total, done: done, ratio: done / total };
                    }
                    
                    taskData: task
                    taskIndex: absIdx
                    isEditing: root.editingTaskId === task.todoId
                    expanded: root.expandedId === modelData
                    isSelected: root.selectedIndex === index
                    nSub: progressData.total
                    dSub: progressData.done
                    subOrder: {
                        const order = [];
                        for (let i = 0; i < task.subtasks.length; i++) {
                            order.push(task.subtasks[i].id);
                        }
                        return order;
                    }
                    prog: progressData.ratio

                    onToggleRequested: (taskIdx) => root.toggleTask(taskIdx)
                    onToggleExpandRequested: (taskIdx) => root.toggleExpand(taskIdx)
                    onRenameRequested: (taskIdx, newTitle) => root.renameTask(taskIdx, newTitle)
                    onDeleteRequested: (taskIdx) => root.deleteTask(taskIdx)
                    onAddSubtaskRequested: (taskIdx, title) => root.addSubtask(taskIdx, title)
                    onToggleSubtaskRequested: (taskIdx, subIdx) => root.toggleSubtask(taskIdx, subIdx)
                    onDeleteSubtaskRequested: (taskIdx, subIdx) => root.deleteSubtask(taskIdx, subIdx)
                    onRenameSubtaskRequested: (taskIdx, subIdx, newTitle) => root.renameSubtask(taskIdx, subIdx, newTitle)
                    onEditingStarted: (taskId) => root.editingTaskId = taskId
                    onEditingCancelled: () => root.editingTaskId = ""
                    onSubtaskEditingStarted: (subtaskId) => root.editingSubId = subtaskId
                    onSubtaskEditingCancelled: () => root.editingSubId = ""
                }
            }
        }
    }
}