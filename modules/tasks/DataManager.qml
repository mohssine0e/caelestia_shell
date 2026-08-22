// DataManager.qml
pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: dataManager

    // Reference to the tasks list (will be passed from parent)
    property var tasks: []
    
    // Signal to notify when data changes
    signal dataChanged()
    signal taskRenamed(string oldTitle, string newTitle)
    signal taskDeleted(string taskId)
    signal taskAdded(string taskId)
    signal taskToggled(string taskId, bool newState)

    function copyTask(task, changes) {
        return Object.assign({}, task, changes);
    }

    // ── Helper Functions ────────────────────────────────────────
    function updateTask(index, newTask) {
        const newTasks = [];
        for (let i = 0; i < tasks.length; i++) {
            newTasks[i] = i === index ? newTask : tasks[i];
        }
        tasks = newTasks;
        dataChanged();
    }

    function updateSubtask(taskIndex, subtaskIndex, newSubtask) {
        const task = tasks[taskIndex];
        if (!task) return;
        
        const newSubtasks = [];
        for (let i = 0; i < task.subtasks.length; i++) {
            newSubtasks[i] = i === subtaskIndex ? newSubtask : task.subtasks[i];
        }
        
        const newTask = copyTask(task, { subtasks: newSubtasks });
        
        syncDone(newTask);
        updateTask(taskIndex, newTask);
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


    // ── Task CRUD Operations ─────────────────────────────────────
    
    // Add a new task (works for both tasks and habits with optional icon)
    function addTask(title, icon = null) {
        if (!title || !title.trim()) return;
        
        const newTask = {
            todoId: Date.now() + "-" + Math.floor(Math.random() * 1e6),
            title: title.trim(),
            done: false,
            minutes: 0,
            icon: icon,
            priority: null,
            createdAt: Date.now(),
            subtasks: []
        };
        
        const newTasks = [newTask];
        for (let i = 0; i < tasks.length; i++) {
            newTasks[i + 1] = tasks[i];
        }
        tasks = newTasks;
        dataChanged();
        taskAdded(newTask.todoId);
    }

    // Toggle task done status
    function toggleTask(i) {
        if (i < 0 || i >= tasks.length) return;
        
        const task = tasks[i];
        const newDone = !task.done;
        
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
        
        const newTask = copyTask(task, { done: newDone, subtasks: newSubtasks });
        
        updateTask(i, newTask);
        taskToggled(task.todoId, newDone);
    }

    // Rename a task
    function renameTask(i, newTitle) {
        if (!newTitle || !newTitle.trim()) return;
        
        const task = tasks[i];
        if (!task) return;
        
        const oldTitle = task.title;
        const newTask = copyTask(task, {
            title: newTitle.trim(),
            subtasks: task.subtasks ? task.subtasks.slice() : []
        });
        
        updateTask(i, newTask);
        taskRenamed(oldTitle, newTitle.trim());
    }

    // Set task estimate in minutes
    function setTaskEstimate(i, mins) {
        const task = tasks[i];
        if (!task) return;
        
        const newTask = copyTask(task, {
            minutes: mins,
            subtasks: task.subtasks ? task.subtasks.slice() : []
        });
        
        updateTask(i, newTask);
    }

    // Delete a task
    function deleteTask(i) {
        if (i < 0 || i >= tasks.length) return;
        
        const taskId = tasks[i].todoId;
        const newTasks = [];
        for (let j = 0; j < tasks.length; j++) {
            if (j !== i) newTasks.push(tasks[j]);
        }
        tasks = newTasks;
        dataChanged();
        taskDeleted(taskId);
    }

    // Clear all done tasks
    function clearDone() {
        const newTasks = [];
        const deletedIds = [];
        for (let i = 0; i < tasks.length; i++) {
            if (!tasks[i].done) {
                newTasks.push(tasks[i]);
            } else {
                deletedIds.push(tasks[i].todoId);
            }
        }
        tasks = newTasks;
        dataChanged();
        for (let i = 0; i < deletedIds.length; i++) {
            taskDeleted(deletedIds[i]);
        }
    }

    // ── Subtask CRUD Operations ──────────────────────────────────

    // Add a subtask
    function addSubtask(taskIndex, title) {
        if (!title || !title.trim()) return;
        
        const task = tasks[taskIndex];
        if (!task) return;
        
        const newSubtask = {
            id: Date.now() + "-" + Math.floor(Math.random() * 1e6),
            title: title.trim(),
            done: false,
            minutes: 0
        };
        
        const newSubtasks = task.subtasks.slice();
        newSubtasks.push(newSubtask);
        
        const newTask = copyTask(task, { subtasks: newSubtasks });
        
        syncDone(newTask);
        updateTask(taskIndex, newTask);
    }

    // Toggle a subtask
    function toggleSubtask(taskIndex, subtaskIndex) {
        if (taskIndex < 0 || taskIndex >= tasks.length) return;
        
        const task = tasks[taskIndex];
        if (subtaskIndex < 0 || subtaskIndex >= task.subtasks.length) return;
        
        const sub = task.subtasks[subtaskIndex];
        const newSub = {
            id: sub.id,
            title: sub.title,
            done: !sub.done,
            minutes: sub.minutes || 0
        };
        
        updateSubtask(taskIndex, subtaskIndex, newSub);
    }

    // Rename a subtask
    function renameSubtask(taskIndex, subtaskIndex, title) {
        if (!title || !title.trim()) return;
        
        const task = tasks[taskIndex];
        if (!task) return;
        
        const sub = task.subtasks[subtaskIndex];
        if (!sub) return;
        
        const newSub = {
            id: sub.id,
            title: title.trim(),
            done: sub.done,
            minutes: sub.minutes || 0
        };
        
        updateSubtask(taskIndex, subtaskIndex, newSub);
    }

    // Delete a subtask
    function deleteSubtask(taskIndex, subtaskIndex) {
        const task = tasks[taskIndex];
        if (!task) return;
        
        const newSubtasks = [];
        for (let i = 0; i < task.subtasks.length; i++) {
            if (i !== subtaskIndex) newSubtasks.push(task.subtasks[i]);
        }
        
        const newTask = copyTask(task, { subtasks: newSubtasks });
        
        syncDone(newTask);
        updateTask(taskIndex, newTask);
    }

    // ── Batch Operations ─────────────────────────────────────────

    // Reorder tasks (if needed in the future)
    function reorderTasks(newOrder) {
        const newTasks = [];
        for (let i = 0; i < newOrder.length; i++) {
            const taskId = newOrder[i];
            for (let j = 0; j < tasks.length; j++) {
                if (tasks[j].todoId === taskId) {
                    newTasks.push(tasks[j]);
                    break;
                }
            }
        }
        tasks = newTasks;
        dataChanged();
    }

    // Import tasks (merge with existing)
    function importTasks(importedTasks) {
        if (!importedTasks || !Array.isArray(importedTasks)) return;
        
        const newTasks = tasks.slice();
        for (let i = 0; i < importedTasks.length; i++) {
            const t = importedTasks[i];
            if (!t.subtasks) t.subtasks = [];
            syncDone(t);
            newTasks.push(t);
        }
        tasks = newTasks;
        dataChanged();
    }

    // ── Statistics ───────────────────────────────────────────────
    
    function getActiveCount() {
        let count = 0;
        for (let i = 0; i < tasks.length; i++) {
            if (!tasks[i].done) count++;
        }
        return count;
    }

    function getDoneCount() {
        return tasks.length - getActiveCount();
    }

    function getTotalActiveMinutes() {
        let sum = 0;
        for (let i = 0; i < tasks.length; i++) {
            const t = tasks[i];
            if (!t.done && t.minutes > 0) sum += t.minutes;
        }
        return sum;
    }

    function getTaskMap() {
        const map = {};
        for (let i = 0; i < tasks.length; i++) {
            const t = tasks[i];
            if (t && t.todoId) {
                map[t.todoId] = t;
            }
        }
        return map;
    }

    function getTaskIndexMap() {
        const idxMap = {};
        for (let i = 0; i < tasks.length; i++) {
            const t = tasks[i];
            if (t && t.todoId) {
                idxMap[t.todoId] = i;
            }
        }
        return idxMap;
    }

    // Get filtered tasks based on status and search query
    function getFilteredTasks(statusFilter, searchQuery) {
        const q = searchQuery.trim().toLowerCase();
        const result = [];
        
        for (let i = 0; i < tasks.length; i++) {
            const t = tasks[i];
            
            // Status filter
            if (statusFilter === "active" && t.done) continue;
            if (statusFilter === "done" && !t.done) continue;
            
            // Search filter
            if (q) {
                const matchTitle = t.title ? t.title.toLowerCase().includes(q) : false;
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
                if (!matchTitle && !matchSubtask) continue;
            }
            
            result.push(t.todoId);
        }
        
        return result;
    }

    // Get subtask map for a specific task
    function getSubtaskMap(taskId) {
        const task = getTaskMap()[taskId];
        if (!task) return {};
        
        const map = {};
        for (let i = 0; i < task.subtasks.length; i++) {
            const sub = task.subtasks[i];
            map[sub.id] = sub;
        }
        return map;
    }

    // Calculate progress for a task
    function getTaskProgress(task) {
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
}
