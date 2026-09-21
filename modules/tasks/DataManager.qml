// DataManager.qml
pragma ComponentBehavior: Bound

import QtQuick
import "TitleParse.js" as TitleParse


/*
data model used: for both tasks and habits // to keep for reference
{
    todoId: string,
    title: string,
    done: bool,           // avoid type initialized to true 
    icon: string | null,         // optional
    "type": "avoid",            //string : "build" | "avoid"

    minutes: int,              // estimated time in minutes, 0 = unset
    priority: int,             1,2,3

    streak: int,
    bestStreak: int,
    lastCompletedDate: string | null,           // for normal habits
    lastRelapseDate: string | null,             // for avoid habits
    
    subtasks: [
        {
            id: string,
            title: string,
            done: bool,
            minutes: int
        },
        ...
    ]
}

*/ 
    // ── Data Layer ──
    QtObject {
        id: dataManager

        property var tasks: []

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

    signal nestedSubtaskAdded(string taskId, string subtaskId, string nestedId)
    signal nestedSubtaskToggled(string taskId, string subtaskId, string nestedId, bool newState)
    signal nestedSubtaskRenamed(string taskId, string subtaskId, string nestedId, string oldTitle, string newTitle)
    signal nestedSubtaskDeleted(string taskId, string subtaskId, string nestedId)

    signal habitDayRolledOver()

    // ── Task Cloning ──
    function copyTask(task, changes) {
        return Object.assign({}, task, changes);
    }

    // ── Task Updates ──
    function updateTask(index, newTask) {
        var newTasks = [];
        for (var i = 0; i < tasks.length; i++) {
            newTasks[i] = i === index ? newTask : tasks[i];
        }
        tasks = newTasks;
    }

    // ── Subtask Updates ──
    function updateSubtask(taskIndex, subtaskIndex, newSubtask) {
        var task = tasks[taskIndex];
        if (!task) return;

        if (newSubtask.children === undefined && task.subtasks[subtaskIndex])
            newSubtask.children = task.subtasks[subtaskIndex].children || [];

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

    // Delegates to the shared TitleParse helper so every component
    // (cards, capture fields) agrees on how "@minutes" is parsed.
    function parseCapturePrefix(text) {
        return TitleParse.parseCapturePrefix(text);
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

    function datesFor(task) {
        return task && task.completionDates ? task.completionDates.slice() : [];
    }

    function computeStreak(task, today) {
        var stored = datesFor(task);
        var isAvoid = task.type === "avoid";
        var cursor = today || habitDate();
        var firstDay = isAvoid && task.createdAt ? habitDate(task.createdAt) : null;

        // Without a creation date, an empty relapse archive can only prove
        // that the current habit day is safe.
        if (isAvoid && !firstDay && stored.length === 0)
            return 1;

        function countsFor(dateStr) {
            var inHistory = dayCompleted(stored, dateStr);
            return isAvoid ? !inHistory : inHistory;
        }

        if (isAvoid && firstDay && cursor < firstDay)
            return 0;

        if (!countsFor(cursor)) {
            if (isAvoid)
                return 0;
            cursor = addDays(cursor, -1);
            if ((firstDay && cursor < firstDay) || !countsFor(cursor))
                return 0;
        }

        var streak = 0;
        while (countsFor(cursor) && (!firstDay || cursor >= firstDay)) {
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
        if (!subtask) return false;
        var mutated = false;
        if (typeof subtask.streak !== "number" || subtask.streak < 0) {
            subtask.streak = 0;
            mutated = true;
        }
        if (typeof subtask.bestStreak !== "number" || subtask.bestStreak < 0) {
            subtask.bestStreak = subtask.streak;
            mutated = true;
        }
        if (!Array.isArray(subtask.children)) {
            subtask.children = [];
            mutated = true;
        } else {
            for (var k = 0; k < subtask.children.length; k++) {
                if (ensureNestedFields(subtask.children[k]))
                    mutated = true;
                if (subtask.children[k].completions !== undefined) {
                    subtask.children[k].completions = undefined;
                    mutated = true;
                }
            }
        }
        return mutated;
    }

    // One level only: a nested child is a leaf (no deeper UI), but keep a
    // children array so the shape stays forward-compatible and lookups stay
    // uniform.
    function ensureNestedFields(n) {
        if (!n || typeof n !== "object") return false;
        var mutated = false;
        if (typeof n.title !== "string") { n.title = ""; mutated = true; }
        if (typeof n.done !== "boolean") { n.done = false; mutated = true; }
        if (typeof n.minutes !== "number") { n.minutes = 0; mutated = true; }
        if (typeof n.streak !== "number" || n.streak < 0) { n.streak = 0; mutated = true; }
        if (typeof n.bestStreak !== "number" || n.bestStreak < 0) { n.bestStreak = n.streak; mutated = true; }
        if (!n.id) { n.id = Date.now() + "-" + Math.floor(Math.random() * 1e6); mutated = true; }
        if (!Array.isArray(n.children)) { n.children = []; mutated = true; }
        return mutated;
    }

    function updateSubtaskStreak(subtask, isDone) {
        ensureSubtaskFields(subtask);
    }
    function applyHabitCompletion(task, isDone) {
        var today = habitDate();
        var completions = task.completionDates ? task.completionDates.slice() : [];
        var idx = completions.indexOf(today);



        // For BUILD: isDone=true → add today, isDone=false → remove today
        // For AVOID: isDone=true → remove today (not relapsed), isDone=false → add today (relapsed)
        var shouldBeInHistory = (task.type === "avoid") ? !isDone : isDone;

        if (shouldBeInHistory && idx === -1)
            completions.push(today);
        else if (!shouldBeInHistory && idx !== -1)
            completions.splice(idx, 1);

        task.completionDates = completions;
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
        if (!Array.isArray(t.completionDates)) {
            t.completionDates = [];
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

    // ── Habit Day Rollover ──
    function applyHabitDayRollover() {
        if (!habitMode)
            return false;

        var today = habitDate();
        var yesterday = addDays(today, -1);
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

            // ── Handle day rollover ──────────────────────
            if (dayChanged) {
                // For AVOID: if yesterday was still "safe" (done), mark it as completed
                if (t.type === "avoid") {
                    // A recorded relapse must remain visible for the current day.
                    newDone = !completedToday;
                } else {
                    // BUILD: if yesterday not completed, reset done
                    if (!completedToday) {
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
                                bestStreak: s.bestStreak || 0,
                                children: (s.children || []).map(function(c) {
                                    return Object.assign({}, c, { done: false, children: [] });
                                })
                            });
                        }
                        changed = true;
                    }
                }
            }

            var newTask = copyTask(t, { done: newDone, subtasks: newSubtasks });
            var oldStreak = t.streak || 0;
            var oldBest = t.bestStreak || 0;
            updateStreaks(newTask);
            if (newTask.streak !== oldStreak ||
                newTask.bestStreak !== oldBest ||
                newTask.lastCompletedDate !== t.lastCompletedDate ||
                newDone !== t.done) {
                changed = true;
            }
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
    function addTask(title, icon, type) {
        if (!title || !title.trim()) return;
        var isAvoid = type === "avoid";
        var habitType = isAvoid ? "avoid" : "build";

        var newTask = {
            todoId: Date.now() + "-" + Math.floor(Math.random() * 1e6),
            title: "",
            done: isAvoid ? true : false,
            type: habitType,
            minutes: 0,
            icon: icon || null,
            priority: null,
            createdAt: Date.now(),
            subtasks: [],
            completionDates: []
        };

        var parsed = parseCapturePrefix(title);
        if (!parsed.title) return;   // "@15" alone is not a task title
        newTask.title = parsed.title;
        newTask.minutes = parsed.minutes;

        if (habitMode) {
            newTask.streak = isAvoid ? 1 : 0;
            newTask.bestStreak = isAvoid ? 1 : 0;
            newTask.lastCompletedDate = isAvoid ? habitDate() : null;
        }

        var newTasks = tasks.slice();
        newTasks.unshift(newTask);
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
                bestStreak: s.bestStreak || 0,
                children: (s.children || []).map(function(c) {
                    return Object.assign({}, c, { done: newDone, children: [] });
                })
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

        // The edit field shows "title @minutes" for tasks without subtasks;
        // parse the suffix back out on submit so the estimate round-trips.
        var parsed = parseCapturePrefix(newTitle);
        if (!parsed.title) return;

        var changes = {
            title: parsed.title,
            subtasks: task.subtasks ? task.subtasks.slice() : []
        };

        // Only round-trip minutes for subtask-less tasks: their edit field
        // displays "@minutes". Parents show the subtask sum instead, so a
        // rename must not overwrite their stored estimate.
        if (!task.subtasks || task.subtasks.length === 0)
            changes.minutes = parsed.minutes;

        var taskId = task.todoId;
        var oldTitle = task.title;
        var newTask = copyTask(task, changes);

        updateTask(i, newTask);
        taskRenamed(taskId, oldTitle, parsed.title);
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

        var parsed = parseCapturePrefix(title);
        if (!parsed.title) return;   // "@10" alone is not a subtask title
        var newSubtask = {
            id: Date.now() + "-" + Math.floor(Math.random() * 1e6),
            title: parsed.title,
            done: false,
            minutes: parsed.minutes,
            streak: 0,
            bestStreak: 0,
            children: []
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
            bestStreak: sub.bestStreak || 0,
            children: (sub.children || []).map(function(c) {
                return Object.assign({}, c, { done: !sub.done, children: [] });
            })
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

        var parsed = parseCapturePrefix(title);
        if (!parsed.title) return;

        var newSub = {
            id: sub.id,
            title: parsed.title,
            done: sub.done,
            minutes: parsed.minutes,
            streak: sub.streak || 0,
            bestStreak: sub.bestStreak || 0,
            children: sub.children || []
        };

        updateSubtask(taskIndex, subtaskIndex, newSub);
        subtaskRenamed(taskId, sub.id, oldTitle, parsed.title);
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

    // ── Nested (depth-2, one level) CRUD ──
    // Only one level: subtask.children[]. A nested child is always a leaf.
    function addNestedSubtask(taskIndex, subtaskIndex, title) {
        if (!title || !title.trim()) return;
        var task = tasks[taskIndex];
        if (!task) return;
        var sub = task.subtasks[subtaskIndex];
        if (!sub) return;

        var parsed = parseCapturePrefix(title);
        if (!parsed.title) return;
        var newNested = {
            id: Date.now() + "-" + Math.floor(Math.random() * 1e6),
            title: parsed.title,
            done: false,
            minutes: parsed.minutes,
            streak: 0,
            bestStreak: 0,
            children: []
        };

        var newChildren = (sub.children || []).slice();
        newChildren.push(newNested);
        var newSub = Object.assign({}, sub, { children: newChildren });
        updateSubtask(taskIndex, subtaskIndex, newSub);
        nestedSubtaskAdded(task.todoId, sub.id, newNested.id);
    }

    function toggleNestedSubtask(taskIndex, subtaskIndex, nestedIndex) {
        var task = tasks[taskIndex];
        if (!task) return;
        var sub = task.subtasks[subtaskIndex];
        if (!sub || !sub.children) return;
        var nested = sub.children[nestedIndex];
        if (!nested) return;

        var newNested = Object.assign({}, nested, {
            done: !nested.done,
            minutes: nested.minutes || 0,
            streak: nested.streak || 0,
            bestStreak: nested.bestStreak || 0,
            children: []
        });
        updateSubtaskStreak(newNested, newNested.done);

        var newChildren = sub.children.slice();
        newChildren[nestedIndex] = newNested;
        var newSub = Object.assign({}, sub, { children: newChildren });
        updateSubtask(taskIndex, subtaskIndex, newSub);
        nestedSubtaskToggled(task.todoId, sub.id, nested.id, newNested.done);
    }

    function renameNestedSubtask(taskIndex, subtaskIndex, nestedIndex, title) {
        if (!title || !title.trim()) return;
        var task = tasks[taskIndex];
        if (!task) return;
        var sub = task.subtasks[subtaskIndex];
        if (!sub || !sub.children) return;
        var nested = sub.children[nestedIndex];
        if (!nested) return;

        var parsed = parseCapturePrefix(title);
        if (!parsed.title) return;
        var oldTitle = nested.title;

        var newNested = Object.assign({}, nested, {
            title: parsed.title,
            minutes: parsed.minutes,
            children: []
        });
        var newChildren = sub.children.slice();
        newChildren[nestedIndex] = newNested;
        var newSub = Object.assign({}, sub, { children: newChildren });
        updateSubtask(taskIndex, subtaskIndex, newSub);
        nestedSubtaskRenamed(task.todoId, sub.id, nested.id, oldTitle, parsed.title);
    }

    function deleteNestedSubtask(taskIndex, subtaskIndex, nestedIndex) {
        var task = tasks[taskIndex];
        if (!task) return;
        var sub = task.subtasks[subtaskIndex];
        if (!sub || !sub.children) return;
        var nested = sub.children[nestedIndex];
        if (!nested) return;

        var newChildren = [];
        for (var i = 0; i < sub.children.length; i++) {
            if (i !== nestedIndex) newChildren.push(sub.children[i]);
        }
        var newSub = Object.assign({}, sub, { children: newChildren });
        updateSubtask(taskIndex, subtaskIndex, newSub);
        nestedSubtaskDeleted(task.todoId, sub.id, nested.id);
    }

function isDoneToday(task) {
    var today = habitDate();
    var inHistory = dayCompleted(datesFor(task), today);
    return task.type === "avoid" ? !inHistory : inHistory;
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
                        var kids = s.children || [];
                        for (var k = 0; k < kids.length; k++) {
                            if (kids[k].title && kids[k].title.toLowerCase().indexOf(q) !== -1) {
                                matchSubtask = true;
                                break;
                            }
                        }
                        if (matchSubtask) break;
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