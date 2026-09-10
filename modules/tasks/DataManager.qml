// DataManager.qml
pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: dataManager

    property var tasks: []
    property var history: ({})

    // When true, maintains streak/bestStreak and applies the 2am habit reset.
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
    signal habitHistoryChanged()

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

    function dayCompleted(dates, date) {
        return Array.isArray(dates) && dates.indexOf(date) !== -1;
    }

    function latestCompletionDate(dates) {
        var latest = null;
        if (!Array.isArray(dates))
            return latest;
        for (var i = 0; i < dates.length; i++) {
            if (!latest || dates[i] > latest)
                latest = dates[i];
        }
        return latest;
    }

    function copyDates(src) {
        return Array.isArray(src) ? src.slice() : [];
    }

    function datesFor(task) {
        return task && task.todoId ? copyDates(history[task.todoId]) : [];
    }

    function setDates(task, dates) {
        if (!task || !task.todoId)
            return;
        var nextHistory = {};
        for (var key in history) {
            if (history.hasOwnProperty(key))
                nextHistory[key] = copyDates(history[key]);
        }
        nextHistory[task.todoId] = copyDates(dates);
        history = nextHistory;
        habitHistoryChanged();
    }

    function importLegacyCompletions(task) {
        if (!task || !task.completions || typeof task.completions !== "object")
            return false;

        var dates = datesFor(task);
        for (var date in task.completions) {
            var value = task.completions[date];
            var completed = value === true || value === 1
                || (typeof value === "number" && value > 0)
                || (typeof value === "string" && value.length > 0)
                || (value && value.length > 0);
            if (task.completions.hasOwnProperty(date) && completed && dates.indexOf(date) === -1)
                dates.push(date);
        }
        setDates(task, dates);
        delete task.completions;
        return true;
    }

    function computeStreak(task, today) {
        var completions = datesFor(task);
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
        task.lastCompletedDate = latestCompletionDate(datesFor(task));
    }

    function ensureSubtaskFields(subtask) {
        var mutated = false;
        if (typeof subtask.streak !== "number" || subtask.streak < 0) {
            subtask.streak = 0;
            mutated = true;
        }
        if (typeof subtask.bestStreak !== "number" || subtask.bestStreak < 0) {
            subtask.bestStreak = subtask.streak;
            mutated = true;
        }
        return mutated;
    }

    function updateSubtaskStreak(subtask, isDone) {
        ensureSubtaskFields(subtask);
    }

    function applyHabitCompletion(task, isDone) {
        var today = habitDate();
        var completions = datesFor(task);

        if (isDone) {
            if (completions.indexOf(today) === -1)
                completions.push(today);
        } else if (completions.indexOf(today) !== -1) {
            completions.splice(completions.indexOf(today), 1);
        }

        setDates(task, completions);
        updateStreaks(task);
    }

    function ensureHabitFields(t) {
        var mutated = false;
        if (typeof t.streak !== "number" || t.streak < 0) {
            t.streak = 0;
            mutated = true;
        }
        if (typeof t.bestStreak !== "number" || t.bestStreak < 0) {
            t.bestStreak = 0;
            mutated = true;
        }
        if (t.lastCompletedDate === undefined) {
            t.lastCompletedDate = t.lastCompleted === undefined ? null : t.lastCompleted;
            if (t.lastCompleted !== undefined)
                delete t.lastCompleted;
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
        var dayChanged = currentHabitDay !== today;
        var newTasks = [];
        var changed = false;

        for (var i = 0; i < tasks.length; i++) {
            var t = tasks[i];
            if (ensureHabitFields(t))
                changed = true;

            var completedToday = dayCompleted(datesFor(t), today);
            var newDone = t.done;
            var newSubtasks = t.subtasks;

            if (dayChanged && !completedToday) {
                newDone = false;
                newSubtasks = [];
                for (var j = 0; j < (t.subtasks || []).length; j++) {
                    var s = t.subtasks[j];
                    newSubtasks.push({
                        id: s.id,
                        title: s.title,
                        done: false,
                        minutes: s.minutes || 0,
                        streak: s.streak || 0,
                        bestStreak: s.bestStreak || 0
                    });
                }
                changed = true;
            }

            var newTask = copyTask(t, { done: newDone, subtasks: newSubtasks });
            var oldStreak = t.streak || 0;
            var oldBest = t.bestStreak || 0;
            updateStreaks(newTask);
            if (newTask.streak !== oldStreak || newTask.bestStreak !== oldBest || newTask.lastCompletedDate !== t.lastCompletedDate || newDone !== t.done || newSubtasks !== t.subtasks)
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
            newTask.streak = 0;
            newTask.bestStreak = 0;
            newTask.lastCompletedDate = null;
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
                minutes: s.minutes || 0,
                streak: s.streak || 0,
                bestStreak: s.bestStreak || 0
            };
            updateSubtaskStreak(newSubtasks[j], newDone);
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
            minutes: 0,
            streak: 0,
            bestStreak: 0
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
            minutes: sub.minutes || 0,
            streak: sub.streak || 0,
            bestStreak: sub.bestStreak || 0
        };
        updateSubtaskStreak(newSub, newSub.done);

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
            minutes: sub.minutes || 0,
            streak: sub.streak || 0,
            bestStreak: sub.bestStreak || 0
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