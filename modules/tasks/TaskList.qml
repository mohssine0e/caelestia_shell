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

/*
    modeldata: for both tasks and daily habits, the model data is an array of objects with the following structure:
    [
        {
            todoId: string,
            title: string,
            done: bool,
            minutes: int,
            icon: string | null,
            priority: int | null,
            createdAt: int (timestamp),
            subtasks: [
                {
                    id: string,
                    title: string,
                    done: bool,
                    minutes: int
                },
                ...
            ]
        },
        ...
]
*/ 
FocusScope {
    id: root

    property string dataType: "tasks" // "tasks" | "habits"

    readonly property string dataPath: `${Paths.state}/${root.dataType}.json`

    readonly property string emptyStateText: root.dataType === "habits" 
    ? qsTr("No habits yet") 
    : qsTr("No tasks yet")

    property string statusFilter: "all" // "all" | "active" | "done"
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

    DataManager {
        id: dataManager
        tasks: root.tasks
        
        onDataChanged: {
            root.tasks = dataManager.tasks;
            root.save();
            root.updateMaps();
            root.updateFilteredModel();
        }
    }


    // ── Filtered Model (ONLY for search) ───────────────────────
    ListModel {
        id: filteredModel
    }

    // ── Helper Functions ────────────────────────────────────────
    function updateMaps() {
        const map = dataManager.getTaskMap();
        const idxMap = dataManager.getTaskIndexMap();
        taskMap = map;
        taskIndexMap = idxMap;
    }

    function updateFilteredModel() {
        const q = searchQuery.trim().toLowerCase();
        
        // Use DataManager to get filtered tasks
        const filteredIds = dataManager.getFilteredTasks(statusFilter, searchQuery);
        
        // Check if we need to update
        if (filteredModel.count === filteredIds.length) {
            let same = true;
            for (let i = 0; i < filteredIds.length; i++) {
                if (filteredModel.get(i).todoId !== filteredIds[i]) {
                    same = false;
                    break;
                }
            }
            if (same) return;
        }
        
        filteredModel.clear();
        for (let i = 0; i < filteredIds.length; i++) {
            filteredModel.append({ todoId: filteredIds[i] });
        }

    }

    function getTaskSubtaskMap(taskId) {
        return dataManager.getSubtaskMap(taskId);
    }

    // ── Signal Handlers ─────────────────────────────────────────
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

    onSearchQueryChanged: updateFilteredModel()

    property string editingTaskId: ""
    property string editingSubId: ""
    property string expandedId: ""
    property int  selectedIndex: -1



    // ── File I/O ─────────────────────────────────────────────────
    FileView {
        id: storage
        path: root.dataPath
        onLoaded: {
            try {
                const raw = JSON.parse(text());
                const parsed = Array.isArray(raw) ? raw : (raw.habits || []);
                for (let i = 0; i < parsed.length; i++) {
                    const t = parsed[i];
                    if (!t.subtasks) t.subtasks = [];
                    if (!t.todoId) t.todoId = String(t.id || Date.now() + "-" + i);
                    t.todoId = String(t.todoId);
                    if (root.dataType === "habits" && !t.icon) t.icon = "task_alt";
                    dataManager.syncDone(t);
                }
                root.tasks = parsed;
                if (!Array.isArray(raw))
                    Qt.callLater(() => root.save());
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

    // ── Counts (using DataManager) ─────────────────────────────
    readonly property int activeCount: dataManager.getActiveCount()
    readonly property int doneCount: dataManager.getDoneCount()
    readonly property int totalActiveMinutes: dataManager.getTotalActiveMinutes()

    // ── List ─────────────────────────────────────────────────────
    StyledFlickable { // this is the scrollable area
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
                            return root.emptyStateText
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
                        const t = taskMap[todoId];
                        if (t) return t;
                        return {
                            todoId: todoId,
                            icon: null,
                            title: "",
                            done: false,
                            priority: null,
                            minutes: null,
                            subtasks: []
                        };
                    })()

                    readonly property int absIdx: (function() {
                        const idx = taskIndexMap[todoId];
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
                    expanded: root.expandedId === todoId
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
                    icon: root.dataType === "habits" ? (task.icon || "task_alt") : ""

                    editingSubId: root.editingSubId

                    // ── Signal Handlers (using DataManager) ──
                    onToggleRequested: (taskIdx) => dataManager.toggleTask(taskIdx)
                    onRenameRequested: (taskIdx, newTitle) => dataManager.renameTask(taskIdx, newTitle)
                    onDeleteRequested: (taskIdx) => dataManager.deleteTask(taskIdx)
                    onAddSubtaskRequested: (taskIdx, title) => dataManager.addSubtask(taskIdx, title)
                    onToggleSubtaskRequested: (taskIdx, subIdx) => dataManager.toggleSubtask(taskIdx, subIdx)
                    onDeleteSubtaskRequested: (taskIdx, subIdx) => dataManager.deleteSubtask(taskIdx, subIdx)
                    onRenameSubtaskRequested: (taskIdx, subIdx, newTitle) => dataManager.renameSubtask(taskIdx, subIdx, newTitle)
                    onEditingStarted: (taskId) => root.editingTaskId = taskId
                    onEditingCancelled: () => root.editingTaskId = ""
                    onSubtaskEditingStarted: (subtaskId) => root.editingSubId = subtaskId
                    onSubtaskEditingCancelled: () => root.editingSubId = ""
                    onToggleExpandRequested: () => {
                        root.expandedId = root.expandedId === todoId ? "" : todoId;
                    }
                }
            }
        }
    }


    // ── Required Public API for adding tasks ─────────────────────────────
    function addTask(title, icon = null) {
        dataManager.addTask(title, root.dataType === "habits" ? (icon || "task_alt") : null);
    }

    // Add this for habits
    function addHabit(title, icon) {
        dataManager.addTask(title, icon);
    }

    function clearDone() {
        dataManager.clearDone();
    }
}
