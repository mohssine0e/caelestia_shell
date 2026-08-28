// DataManager.qml
pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: dataManager

    property var tasks: []
    
    // ── Specific Signals ──
    signal taskAdded(string taskId, var task)
    signal taskDeleted(string taskId)
    signal taskToggled(string taskId, bool newState)
    signal taskRenamed(string taskId, string oldTitle, string newTitle)
    
    signal subtaskAdded(string taskId, string subtaskId)
    signal subtaskToggled(string taskId, string subtaskId, bool newState)
    signal subtaskRenamed(string taskId, string subtaskId, string oldTitle, string newTitle)
    signal subtaskDeleted(string taskId, string subtaskId)

    function copyTask(task, changes) {
        var newTask = {};
        for (var key in task) {
            if (task.hasOwnProperty(key)) {
                newTask[key] = task[key];
            }
        }
        for (var changeKey in changes) {
            if (changes.hasOwnProperty(changeKey)) {
                newTask[changeKey] = changes[changeKey];
            }
        }
        return newTask;
    }

    function updateTask(index, newTask) {
        var newTasks = [];
        for (var i = 0; i < tasks.length; i++) {
            newTasks[i] = i === index ? newTask : tasks[i];
        }
        tasks = newTasks;
    }

    function updateSubtask(taskIndex, subtaskIndex, newSubtask) {
        var task = tasks[taskIndex];
        if (!task) return;
        
        var newSubtasks = [];
        for (var i = 0; i < task.subtasks.length; i++) {
            newSubtasks[i] = i === subtaskIndex ? newSubtask : task.subtasks[i];
        }
        
        var newTask = copyTask(task, { subtasks: newSubtasks });
        syncDone(newTask);
        updateTask(taskIndex, newTask);
    }

    function syncDone(t) {
        if (t.subtasks && t.subtasks.length > 0) {
            var allDone = true;
            for (var i = 0; i < t.subtasks.length; i++) {
                if (!t.subtasks[i].done) {
                    allDone = false;
                    break;
                }
            }
            t.done = allDone;
        }
    }

    // ── Task CRUD ──
    function addTask(title, icon) {
        if (!title || !title.trim()) return;
        
        var newTask = {
            todoId: Date.now() + "-" + Math.floor(Math.random() * 1e6),
            title: title.trim(),
            done: false,
            minutes: 0,
            icon: icon || null,
            priority: null,
            createdAt: Date.now(),
            subtasks: []
        };
        
        var newTasks = [newTask];
        for (var i = 0; i < tasks.length; i++) {
            newTasks[i + 1] = tasks[i];
        }
        tasks = newTasks;
        taskAdded(newTask.todoId, newTask);
    }

    function toggleTask(i) {
        if (i < 0 || i >= tasks.length) return;
        
        var task = tasks[i];
        var newDone = !task.done;
        var taskId = task.todoId;
        
        var newSubtasks = [];
        for (var j = 0; j < task.subtasks.length; j++) {
            var s = task.subtasks[j];
            newSubtasks[j] = {
                id: s.id,
                title: s.title,
                done: newDone,
                minutes: s.minutes || 0
            };
        }
        
        var newTask = copyTask(task, { done: newDone, subtasks: newSubtasks });
        updateTask(i, newTask);
        taskToggled(taskId, newDone);
    }

    function renameTask(i, newTitle) {
        if (!newTitle || !newTitle.trim()) return;
        
        var task = tasks[i];
        if (!task) return;
        
        var taskId = task.todoId;
        var oldTitle = task.title;
        var newTask = copyTask(task, {
            title: newTitle.trim(),
            subtasks: task.subtasks ? task.subtasks.slice() : []
        });
        
        updateTask(i, newTask);
        taskRenamed(taskId, oldTitle, newTitle.trim());
    }

    function deleteTask(i) {
        if (i < 0 || i >= tasks.length) return;
        
        var taskId = tasks[i].todoId;
        var newTasks = [];
        for (var j = 0; j < tasks.length; j++) {
            if (j !== i) newTasks.push(tasks[j]);
        }
        tasks = newTasks;
        taskDeleted(taskId);
    }

    // ── Subtask CRUD ──
    function addSubtask(taskIndex, title) {
        if (!title || !title.trim()) return;
        
        var task = tasks[taskIndex];
        if (!task) return;
        var taskId = task.todoId;
        
        var newSubtask = {
            id: Date.now() + "-" + Math.floor(Math.random() * 1e6),
            title: title.trim(),
            done: false,
            minutes: 0
        };
        
        var newSubtasks = task.subtasks.slice();
        newSubtasks.push(newSubtask);
        
        var newTask = copyTask(task, { subtasks: newSubtasks });
        syncDone(newTask);
        updateTask(taskIndex, newTask);
        subtaskAdded(taskId, newSubtask.id);
    }

    function toggleSubtask(taskIndex, subtaskIndex) {
        if (taskIndex < 0 || taskIndex >= tasks.length) return;
        
        var task = tasks[taskIndex];
        if (subtaskIndex < 0 || subtaskIndex >= task.subtasks.length) return;
        var taskId = task.todoId;
        
        var sub = task.subtasks[subtaskIndex];
        var newSub = {
            id: sub.id,
            title: sub.title,
            done: !sub.done,
            minutes: sub.minutes || 0
        };
        
        updateSubtask(taskIndex, subtaskIndex, newSub);
        subtaskToggled(taskId, sub.id, !sub.done);
    }

    function renameSubtask(taskIndex, subtaskIndex, title) {
        if (!title || !title.trim()) return;
        
        var task = tasks[taskIndex];
        if (!task) return;
        var taskId = task.todoId;
        
        var sub = task.subtasks[subtaskIndex];
        if (!sub) return;
        var oldTitle = sub.title;
        
        var newSub = {
            id: sub.id,
            title: title.trim(),
            done: sub.done,
            minutes: sub.minutes || 0
        };
        
        updateSubtask(taskIndex, subtaskIndex, newSub);
        subtaskRenamed(taskId, sub.id, oldTitle, title.trim());
    }

    function deleteSubtask(taskIndex, subtaskIndex) {
        var task = tasks[taskIndex];
        if (!task) return;
        var taskId = task.todoId;
        var subId = task.subtasks[subtaskIndex].id;
        
        var newSubtasks = [];
        for (var i = 0; i < task.subtasks.length; i++) {
            if (i !== subtaskIndex) newSubtasks.push(task.subtasks[i]);
        }
        
        var newTask = copyTask(task, { subtasks: newSubtasks });
        syncDone(newTask);
        updateTask(taskIndex, newTask);
        subtaskDeleted(taskId, subId);
    }

    // ── Statistics ──
    function getActiveCount() {
        var count = 0;
        for (var i = 0; i < tasks.length; i++) {
            if (!tasks[i].done) count++;
        }
        return count;
    }

    function getDoneCount() {
        return tasks.length - getActiveCount();
    }

    function getTotalActiveMinutes() {
        var sum = 0;
        for (var i = 0; i < tasks.length; i++) {
            var t = tasks[i];
            if (!t.done && t.minutes > 0) sum += t.minutes;
        }
        return sum;
    }

    function getTaskMap() {
        var map = {};
        for (var i = 0; i < tasks.length; i++) {
            var t = tasks[i];
            if (t && t.todoId) {
                map[t.todoId] = t;
            }
        }
        return map;
    }

    function getTaskIndexMap() {
        var idxMap = {};
        for (var i = 0; i < tasks.length; i++) {
            var t = tasks[i];
            if (t && t.todoId) {
                idxMap[t.todoId] = i;
            }
        }
        return idxMap;
    }

    function getFilteredTasks(statusFilter, searchQuery) {
        var q = searchQuery.trim().toLowerCase();
        var result = [];
        
        for (var i = 0; i < tasks.length; i++) {
            var t = tasks[i];
            
            if (statusFilter === "active" && t.done) continue;
            if (statusFilter === "done" && !t.done) continue;
            
            if (q) {
                var matchTitle = t.title ? t.title.toLowerCase().indexOf(q) !== -1 : false;
                var matchSubtask = false;
                if (t.subtasks) {
                    for (var j = 0; j < t.subtasks.length; j++) {
                        var s = t.subtasks[j];
                        if (s.title && s.title.toLowerCase().indexOf(q) !== -1) {
                            matchSubtask = true;
                            break;
                        }
                    }
                }
                if (!matchTitle && !matchSubtask) continue;
            }
            result.push(t.todoId);
        }
        return result;
    }

    function getSubtaskMap(taskId) {
        var task = getTaskMap()[taskId];
        if (!task) return {};
        
        var map = {};
        for (var i = 0; i < task.subtasks.length; i++) {
            var sub = task.subtasks[i];
            map[sub.id] = sub;
        }
        return map;
    }
}