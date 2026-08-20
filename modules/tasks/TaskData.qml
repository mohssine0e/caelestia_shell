pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia

Item {
    id: root

    // ── Data ─────────────────────────────────────────────────────
    property var    tasks:  []
    property bool   loaded: false

    // ── Maps for O(1) Lookups ──────────────────────────────────
    property var taskMap: ({})
    property var taskIndexMap: ({})

    // ── Signal ──────────────────────────────────────────────────
    signal dataChanged()

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
        dataChanged();
    }

    function getTaskSubtaskMap(taskId) {
        const task = taskMap[taskId];
        if (!task) return {};
        const map = {};
        for (const sub of task.subtasks) {
            map[sub.id] = sub;
        }
        return map;
    }

    // ── Signal Handlers ─────────────────────────────────────────
    onTasksChanged: updateMaps()
    onLoadedChanged: { if (loaded) updateMaps(); }

    // ── File I/O ─────────────────────────────────────────────────
    FileView {
        id: storage
        path: `${Paths.state}/todos.json`
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                for (const t of parsed) {
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
    
    function mutate(fn) { 
        const c = JSON.parse(JSON.stringify(root.tasks));
        fn(c);
        root.tasks = c;
    }

    // ── CRUD ─────────────────────────────────────────────────────
    function addTask(title) {
        if (!title.trim()) return;
        mutate(ts => ts.unshift({
            todoId: `${Date.now()}-${Math.floor(Math.random() * 1e6)}`,
            task: title.trim(),
            done: false,
            minutes: 0,
            priority: null,
            dueDate: null,
            project: "",
            createdAt: Date.now(),
            subtasks: []
        }));
    }

    function syncDone(t) {
        if (t.subtasks.length > 0)
            t.done = t.subtasks.every(s => s.done);
    }

    function toggleTask(i) {
        mutate(ts => {
            const next = !ts[i].done;
            ts[i].done = next;
            for (const s of ts[i].subtasks) s.done = next;
        });
    }

    function toggleExpand(i) {
        const id = tasks[i]?.todoId;
        if (!id) return;
        // This is UI state, not data - stored in TaskList
    }

    function renameTask(i, t) {
        if (!t.trim()) return; 
        mutate(ts => { ts[i].task = t.trim(); });
    }

    function deleteTask(i) {
        mutate(ts => ts.splice(i, 1));
    }

    function clearDone() {
        mutate(ts => {
            for (let i = ts.length - 1; i >= 0; i--)
                if (ts[i].done) ts.splice(i, 1);
        });
    }

    function addSubtask(ti, title) {
        if (!title.trim()) return;
        mutate(ts => {
            ts[ti].subtasks.push({
                id: `${Date.now()}-${Math.floor(Math.random() * 1e6)}`,
                title: title.trim(), done: false, minutes: 0
            });
            root.syncDone(ts[ti]);
        });
    }

    function toggleSubtask(ti, si) {
        mutate(ts => {
            ts[ti].subtasks[si].done = !ts[ti].subtasks[si].done;
            root.syncDone(ts[ti]);
        });
    }

    function renameSubtask(ti, si, t) { 
        if (!t.trim()) return; 
        mutate(ts => { ts[ti].subtasks[si].title = t.trim(); });
    }

    function deleteSubtask(ti, si) {
        mutate(ts => {
            ts[ti].subtasks.splice(si, 1);
            root.syncDone(ts[ti]);
        });
    }

    // ── Counts ──────────────────────────────────────────────────
    readonly property int activeCount: {
        let count = 0;
        for (const t of tasks) {
            if (!t.done) count++;
        }
        return count;
    }

    readonly property int doneCount: tasks.length - activeCount

    readonly property int totalActiveMinutes: {
        let sum = 0;
        for (const t of tasks) {
            if (!t.done && t.minutes > 0) sum += t.minutes;
        }
        return sum;
    }
}