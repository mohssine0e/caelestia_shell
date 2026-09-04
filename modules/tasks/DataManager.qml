// DataManager.qml
pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: dataManager

    property var tasks: []

    // When true, toggles write completions[], maintain streak/bestStreak,
    // and applyHabitDayRollover() unchecks leftover dones after the 2am cut.
    property bool habitMode: false
    property int resetHour: 2
    property string currentHabitDay: ""

    // ── Specific Signals ──
    signal taskAdded(string taskId, var task)
    signal taskDeleted(string taskId)
    signal taskToggled(string taskId, bool newState)
    signal taskRenamed(string taskId, string oldTitle, string newTitle)

    signal subtaskAdded(string taskId, string subtaskId)
    signal subtaskToggled(string taskId, string subtaskId, bool newState)
    signal subtaskRenamed(string taskId, string subtaskId, string oldTitle, string newTitle)
    signal subtaskDeleted(string taskId, string subtaskId)

    signal habitDayRolledOver()

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
        if (habitMode)
            applyHabitCompletion(newTask, newTask.done);
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

    // ── Habit day (rolls at resetHour, default 02:00 local) ──
    function pad2(n) {
        return n < 10 ? "0" + n : "" + n;
    }

    function formatDay(d) {
        return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
    }

    function parseDay(dateStr) {
        var p = String(dateStr).split("-");
        return new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10));
    }

    function addDays(dateStr, n) {
        var d = parseDay(dateStr);
        d.setDate(d.getDate() + n);
        return formatDay(d);
    }

    function habitDate(ts) {
        var d = ts === undefined ? new Date() : new Date(ts);
        if (d.getHours() < resetHour)
            d.setDate(d.getDate() - 1);
        return formatDay(d);
    }

    function msUntilNextReset() {
        var now = new Date();
        var next = new Date(now.getFullYear(), now.getMonth(), now.getDate(), resetHour, 0, 0, 0);
        if (now.getTime() >= next.getTime())
            next.setDate(next.getDate() + 1);
        return Math.max(0, next.getTime() - now.getTime());
    }

    function dayCompleted(completions, date) {
        if (!completions)
            return false;
        var v = completions[date];
        if (v === true || v === 1)
            return true;
        if (typeof v === "number")
            return v > 0;
        if (typeof v === "string")
            return v.length > 0;
        if (v && v.length > 0)
            return true;
        return false;
    }

    function latestCompletionDate(completions) {
        var latest = null;
        if (!completions)
            return latest;
        for (var k in completions) {
            if (!completions.hasOwnProperty(k))
                continue;
            if (!dayCompleted(completions, k))
                continue;
            if (!latest || k > latest)
                latest = k;
        }
        return latest;
    }

    function copyCompletions(src) {
        var out = {};
        if (!src)
            return out;
        for (var k in src) {
            if (src.hasOwnProperty(k))
                out[k] = src[k];
        }
        return out;
    }

    function computeStreak(task, today) {
        var completions = task && task.completions ? task.completions : {};
        var cursor = today || habitDate();
        if (!dayCompleted(completions, cursor)) {
            cursor = addDays(cursor, -1);
            if (!dayCompleted(completions, cursor))
                return 0;
        }
        var streak = 0;
        while (dayCompleted(completions, cursor)) {
            streak++;
            cursor = addDays(cursor, -1);
        }
        return streak;
    }

    function updateStreaks(task) {
        var s = computeStreak(task);
        task.streak = s;
        var best = task.bestStreak || 0;
        task.bestStreak = best > s ? best : s;
    }

    function applyHabitCompletion(task, isDone) {
        var today = habitDate();
        var completions = copyCompletions(task.completions);

        if (isDone) {
            var ids = [];
            if (task.subtasks && task.subtasks.length > 0) {
                for (var i = 0; i < task.subtasks.length; i++) {
                    if (task.subtasks[i].done)
                        ids.push(task.subtasks[i].id);
                }
            } else {
                ids = [task.todoId];
            }
            completions[today] = ids;
            task.lastCompleted = today;
        } else {
            if (completions.hasOwnProperty(today))
                delete completions[today];
            task.lastCompleted = latestCompletionDate(completions);
        }

        task.completions = completions;
        updateStreaks(task);
    }

    function ensureHabitFields(t) {
        var mutated = false;
        if (!t.completions || typeof t.completions !== "object" || Array.isArray(t.completions)) {
            t.completions = {};
            mutated = true;
        }
        if (typeof t.streak !== "number" || t.streak < 0) {
            t.streak = 0;
            mutated = true;
        }
        if (typeof t.bestStreak !== "number" || t.bestStreak < 0) {
            t.bestStreak = 0;
            mutated = true;
        }
        if (t.lastCompleted === undefined) {
            t.lastCompleted = null;
            mutated = true;
        }
        return mutated;
    }

    // Uncheck leftovers from a previous habit-day, recompute streaks.
    // Returns true if anything changed (caller should persist).
    function applyHabitDayRollover() {
        if (!habitMode)
            return false;

        var today = habitDate();
        var newTasks = [];
        var changed = false;

        for (var i = 0; i < tasks.length; i++) {
            var t = tasks[i];
            if (ensureHabitFields(t))
                changed = true;

            var completedToday = dayCompleted(t.completions, today);
            var newDone = t.done;
            var newSubtasks = t.subtasks;

            if (t.done && !completedToday) {
                newDone = false;
                newSubtasks = [];
                for (var j = 0; j < (t.subtasks || []).length; j++) {
                    var s = t.subtasks[j];
                    newSubtasks.push({
                        id: s.id,
                        title: s.title,
                        done: false,
                        minutes: s.minutes || 0
                    });
                }
                changed = true;
            }

            var newTask = copyTask(t, { done: newDone, subtasks: newSubtasks });
            var oldStreak = t.streak || 0;
            var oldBest = t.bestStreak || 0;
            var oldLast = t.lastCompleted;
            updateStreaks(newTask);
            if (newTask.streak !== oldStreak || newTask.bestStreak !== oldBest || newTask.lastCompleted !== oldLast)
                changed = true;
            newTasks.push(newTask);
        }

        currentHabitDay = today;
        if (changed) {
            tasks = newTasks;
            habitDayRolledOver();
        }
        return changed;
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

        if (habitMode) {
            newTask.completions = {};
            newTask.streak = 0;
            newTask.bestStreak = 0;
            newTask.lastCompleted = null;
        }

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
        if (habitMode)
            applyHabitCompletion(newTask, newDone);
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
        if (habitMode)
            applyHabitCompletion(newTask, newTask.done);
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
        if (habitMode)
            applyHabitCompletion(newTask, newTask.done);
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