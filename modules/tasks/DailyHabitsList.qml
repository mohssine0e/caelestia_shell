pragma ComponentBehavior: Bound

import QtQuick
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

    // ── Configuration ──────────────────────────────────────────
    readonly property real listMinHeight: 440
    readonly property real listMaxHeight: 640

    implicitHeight: CUtils.clamp(scroller.contentHeight, listMinHeight, listMaxHeight)

    // ── Default Habits ──────────────────────────────────────────
    readonly property var defaultHabits: [
        { todoId: "water",     priority:null, minutes:null, icon: "water_drop",       title: qsTr("Drink 2L of water"), subtasks: [] },
        { todoId: "stretch",   priority:null, minutes:null, icon: "directions_run",   title: qsTr("Morning stretch"), subtasks: [] },
        { todoId: "read",      priority:null, minutes:null, icon: "menu_book",        title: qsTr("Read for 20 min"), subtasks: [] },
        { todoId: "sugar",     priority:null, minutes:null, icon: "block",            title: qsTr("No sugar"), subtasks: [] },
        { todoId: "meditate",  priority:null, minutes:null, icon: "self_improvement", title: qsTr("Meditate"), subtasks: [] },
        { todoId: "plan",      priority:null, minutes:null, icon: "checklist",        title: qsTr("Plan the day"), subtasks: [] }
    ]

    // ── Data ─────────────────────────────────────────────────────
    property var habits: []
    property var completions: ({}) // { "yyyy-MM-dd": [todoId, ...] }
    property bool loaded: false

    readonly property string today: Qt.formatDate(new Date(), "yyyy-MM-dd")
    readonly property var todayDone: completions[today] ?? []

    // ── Edit State ──────────────────────────────────────────────
    property string editingHabitId: ""
    property string editingSubId: ""
    property string expandedId: ""
    property int selectedIndex: -1

    // ── Keyboard ─────────────────────────────────────────────────
    readonly property int selectedAbsIdx: selectedIndex >= 0 && selectedIndex < filteredModel.count
        ? (function() {
            const id = filteredModel.get(selectedIndex).habitId;
            for (let i = 0; i < habits.length; i++) {
                if (habits[i].todoId === id) return i;
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
        const item = habitRepeater.itemAt(i);
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
        const abs = root.selectedAbsIdx;

        if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
            root.moveSelection(1);
        } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
            root.moveSelection(-1);
        } else if (abs < 0) {
            event.accepted = false;
            return;
        } else if (event.key === Qt.Key_Space) {
            root.toggleHabit(root.habits[abs].todoId);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.editingHabitId = root.habits[abs].todoId;
        } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_X) {
            root.deleteHabit(abs);
        } else if (event.key === Qt.Key_L || event.key === Qt.Key_Right) {
            root.expandedId = root.habits[abs].todoId;
        } else if (event.key === Qt.Key_H || event.key === Qt.Key_Left) {
            root.expandedId = "";
        } else {
            event.accepted = false;
            return;
        }
        event.accepted = true;
    }

    // ── Filtered Model ──────────────────────────────────────────
    ListModel {
        id: filteredModel
    }

    function updateFilteredModel() {
        filteredModel.clear();
        for (let i = 0; i < habits.length; i++) {
            filteredModel.append({ habitId: habits[i].todoId });
        }
    }

    onHabitsChanged: updateFilteredModel()
    onLoadedChanged: if (loaded) updateFilteredModel()

    // ── File I/O ─────────────────────────────────────────────────
    FileView {
        id: storage
        path: `${Paths.state}/habits.json`
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.habits = data.habits ?? root.defaultHabits;
                for (let i = 0; i < root.habits.length; i++) {
                    const h = root.habits[i];
                    if (!h.subtasks) h.subtasks = [];
                    if (!h.icon) h.icon = "task_alt";
                    if (!h.todoId) h.todoId = h.id || Date.now() + "-" + Math.floor(Math.random() * 1e6);
                    if (!h.createdAt) h.createdAt = Date.now();
                }
                root.completions = data.completions ?? {};
            } catch (e) {
                root.habits = root.defaultHabits;
                for (let i = 0; i < root.habits.length; i++) {
                    const h = root.habits[i];
                    if (!h.subtasks) h.subtasks = [];
                    if (!h.icon) h.icon = "task_alt";
                    if (!h.todoId) h.todoId = h.id || Date.now() + "-" + Math.floor(Math.random() * 1e6);
                    if (!h.createdAt) h.createdAt = Date.now();
                }
                root.completions = {};
            }
            root.loaded = true;
            root.syncDoneFromCompletions();
        }
        onLoadFailed: err => {
            root.habits = root.defaultHabits;
            for (let i = 0; i < root.habits.length; i++) {
                const h = root.habits[i];
                if (!h.subtasks) h.subtasks = [];
                if (!h.icon) h.icon = "task_alt";
                if (!h.todoId) h.todoId = h.id || Date.now() + "-" + Math.floor(Math.random() * 1e6);
                if (!h.createdAt) h.createdAt = Date.now();
            }
            root.completions = {};
            root.loaded = true;
            root.syncDoneFromCompletions();
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => root.save());
        }
    }

    function save() {
        storage.setText(JSON.stringify({ habits: root.habits, completions: root.completions }, null, 2));
    }

    // ── Completion Helpers ──────────────────────────────────────
    function syncDoneFromCompletions() {
        for (let i = 0; i < habits.length; i++) {
            const h = habits[i];
            if (h.subtasks && h.subtasks.length > 0) {
                let allDone = true;
                for (let j = 0; j < h.subtasks.length; j++) {
                    if (!root.todayDone.includes(h.subtasks[j].id)) {
                        allDone = false;
                        break;
                    }
                }
                h.done = allDone;
            } else {
                h.done = root.todayDone.includes(h.todoId);
            }
        }
    }

    function findHabitById(list, id) {
        for (let i = 0; i < list.length; i++) {
            const h = list[i];
            if (h.todoId === id) return h;
            if (h.subtasks) {
                for (let j = 0; j < h.subtasks.length; j++) {
                    if (h.subtasks[j].id === id) return h.subtasks[j];
                }
            }
        }
        return null;
    }

    function isDone(id) {
        const h = findHabitById(habits, id);
        if (h && h.subtasks && h.subtasks.length > 0) {
            let allDone = true;
            for (let i = 0; i < h.subtasks.length; i++) {
                if (!root.todayDone.includes(h.subtasks[i].id)) {
                    allDone = false;
                    break;
                }
            }
            return allDone;
        }
        return root.todayDone.includes(id);
    }

    function getLeafIds(item) {
        if (item.subtasks && item.subtasks.length > 0) {
            let ids = [];
            for (let i = 0; i < item.subtasks.length; i++) {
                ids = ids.concat(getLeafIds(item.subtasks[i]));
            }
            return ids;
        }
        return [item.todoId];
    }

    // ── CRUD ─────────────────────────────────────────────────────
    function addHabit(title, icon) {
        if (!title.trim()) return;
        const newHabit = {
            todoId: Date.now() + "-" + Math.floor(Math.random() * 1e6),
            title: title.trim(),
            done: false,
            icon: icon || "task_alt",
            minutes: 0,
            createdAt: Date.now(),
            subtasks: []
        };
        const newHabits = [newHabit];
        for (let i = 0; i < habits.length; i++) {
            newHabits[i + 1] = habits[i];
        }
        habits = newHabits;
        save();
    }

    function toggleHabit(id) {
        const h = findHabitById(habits, id);
        if (!h) return;

        const done = Object.assign({}, root.completions);
        const list = done[root.today] ? done[root.today].slice() : [];
        const prevDone = root.isDone(id);
        const leafIds = getLeafIds(h);

        if (h.subtasks && h.subtasks.length > 0) {
            if (prevDone) {
                for (let i = 0; i < leafIds.length; i++) {
                    const idx = list.indexOf(leafIds[i]);
                    if (idx >= 0) list.splice(idx, 1);
                }
            } else {
                for (let i = 0; i < leafIds.length; i++) {
                    if (!list.includes(leafIds[i])) list.push(leafIds[i]);
                }
            }
        } else {
            const idx = list.indexOf(id);
            if (idx >= 0) list.splice(idx, 1);
            else list.push(id);
        }

        if (list.length > 0) {
            done[root.today] = list;
        } else {
            delete done[root.today];
        }
        root.completions = done;
        root.syncDoneFromCompletions();
        save();
    }

    function deleteHabit(i) {
        const habit = habits[i];
        if (!habit) return;

        // Remove from completions
        const newCompletions = {};
        const keys = Object.keys(root.completions);
        for (let k = 0; k < keys.length; k++) {
            const date = keys[k];
            const list = root.completions[date];
            if (list) {
                const newList = [];
                for (let l = 0; l < list.length; l++) {
                    if (list[l] !== habit.todoId) {
                        let isSubtask = false;
                        if (habit.subtasks) {
                            for (let m = 0; m < habit.subtasks.length; m++) {
                                if (list[l] === habit.subtasks[m].id) {
                                    isSubtask = true;
                                    break;
                                }
                            }
                        }
                        if (!isSubtask) newList.push(list[l]);
                    }
                }
                if (newList.length > 0) {
                    newCompletions[date] = newList;
                }
            }
        }
        root.completions = newCompletions;

        // Delete habit
        const newHabits = [];
        for (let j = 0; j < habits.length; j++) {
            if (j !== i) newHabits.push(habits[j]);
        }
        habits = newHabits;
        save();
    }

    function renameHabit(id, title) {
        if (!title.trim()) return;
        const h = findHabitById(habits, id);
        if (!h) return;
        h.title = title.trim();
        save();
        editingHabitId = "";
    }

    // ── Subtask CRUD ─────────────────────────────────────────────
    function addSubtask(ti, title) {
        if (!title.trim()) return;
        const h = habits[ti];
        if (!h) return;
        if (!h.subtasks) h.subtasks = [];
        h.subtasks.push({
            id: Date.now() + "-" + Math.floor(Math.random() * 1e6),
            title: title.trim(),
            done: false,
            minutes: 0
        });
        root.syncDoneFromCompletions();
        save();
    }

    function toggleSubtask(ti, si) {
        const h = habits[ti];
        if (!h || !h.subtasks || si >= h.subtasks.length) return;

        const sub = h.subtasks[si];
        const done = Object.assign({}, root.completions);
        const list = done[root.today] ? done[root.today].slice() : [];
        const idx = list.indexOf(sub.id);

        if (idx >= 0) list.splice(idx, 1);
        else list.push(sub.id);

        if (list.length > 0) {
            done[root.today] = list;
        } else {
            delete done[root.today];
        }
        root.completions = done;
        root.syncDoneFromCompletions();
        save();
    }

    function renameSubtask(ti, si, title) {
        if (!title.trim()) return;
        const h = habits[ti];
        if (!h || !h.subtasks || si >= h.subtasks.length) return;
        h.subtasks[si].title = title.trim();
        save();
        editingSubId = "";
    }

    function deleteSubtask(ti, si) {
        const h = habits[ti];
        if (!h || !h.subtasks || si >= h.subtasks.length) return;

        const subId = h.subtasks[si].id;

        // Remove from completions
        const newCompletions = {};
        const keys = Object.keys(root.completions);
        for (let k = 0; k < keys.length; k++) {
            const date = keys[k];
            const list = root.completions[date];
            if (list) {
                const newList = [];
                for (let l = 0; l < list.length; l++) {
                    if (list[l] !== subId) newList.push(list[l]);
                }
                if (newList.length > 0) {
                    newCompletions[date] = newList;
                }
            }
        }
        root.completions = newCompletions;

        h.subtasks.splice(si, 1);
        root.syncDoneFromCompletions();
        save();
    }

    // ── Counts ──────────────────────────────────────────────────
    readonly property int doneCount: {
        let c = 0;
        for (let i = 0; i < habits.length; i++) {
            if (habits[i].done) c++;
        }
        return c;
    }

    readonly property real doneFraction: habits.length > 0 ? doneCount / habits.length : 0

    readonly property int streakCount: {
        let streak = 0;
        function allDoneOn(dateStr) {
            const list = completions[dateStr];
            if (!list || list.length === 0) return false;
            if (habits.length === 0) return false;
            for (let i = 0; i < habits.length; i++) {
                const h = habits[i];
                if (h.subtasks && h.subtasks.length > 0) {
                    for (let j = 0; j < h.subtasks.length; j++) {
                        if (!list.includes(h.subtasks[j].id)) return false;
                    }
                } else {
                    if (!list.includes(h.todoId)) return false;
                }
            }
            return true;
        }

        let todayStr = Qt.formatDate(new Date(), "yyyy-MM-dd");
        if (allDoneOn(todayStr)) {
            streak = 1;
            let d = new Date();
            while (true) {
                d.setDate(d.getDate() - 1);
                let dStr = Qt.formatDate(d, "yyyy-MM-dd");
                if (allDoneOn(dStr)) {
                    streak++;
                } else {
                    break;
                }
            }
        } else {
            let d = new Date();
            d.setDate(d.getDate() - 1);
            let yesterdayStr = Qt.formatDate(d, "yyyy-MM-dd");
            if (allDoneOn(yesterdayStr)) {
                streak = 1;
                while (true) {
                    d.setDate(d.getDate() - 1);
                    let dStr = Qt.formatDate(d, "yyyy-MM-dd");
                    if (allDoneOn(dStr)) {
                        streak++;
                    } else {
                        break;
                    }
                }
            } else {
                streak = 0;
            }
        }
        return streak;
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
            spacing: Tokens.spacing.medium

            // ── Header ──────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "wb_sunny"
                    fontStyle: Tokens.font.icon.large
                    color: Colours.palette.m3primary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: qsTr("Daily Habits")
                        font: Tokens.font.title.medium
                        color: Colours.palette.m3onSurface
                    }
                    StyledText {
                        text: qsTr("Small actions. Big results.")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }

                // Streak
                RowLayout {
                    spacing: Tokens.spacing.small
                    visible: root.streakCount > 0
                    MaterialIcon {
                        text: "local_fire_department"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3tertiary
                    }
                    StyledText {
                        text: qsTr("%1 day streak").arg(root.streakCount)
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3tertiary
                    }
                }

                StyledText {
                    text: qsTr("%1 / %2 done").arg(root.doneCount).arg(root.habits.length)
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledRect {
                    Layout.preferredWidth: 128
                    implicitHeight: 6
                    radius: Tokens.rounding.full
                    color: Colours.tPalette.m3surfaceContainerHighest

                    StyledRect {
                        width: parent.width * root.doneFraction
                        height: parent.height
                        radius: parent.radius
                        color: Colours.palette.m3tertiary
                        Behavior on width { Anim {} }
                    }
                }
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Colours.palette.m3outlineVariant
                opacity: 0.4
            }

            // ── Habit List ──────────────────────────────────────
            Repeater {
                id: habitRepeater
                model: filteredModel

                delegate: TaskCard {
                    required property string modelData
                    required property int index

                    // Build maps for O(1) lookup
                    readonly property var habitMap: {
                        const map = {};
                        for (let i = 0; i < habits.length; i++) {
                            map[habits[i].todoId] = habits[i];
                        }
                        return map;
                    }
                    readonly property var habitIndexMap: {
                        const map = {};
                        for (let i = 0; i < habits.length; i++) {
                            map[habits[i].todoId] = i;
                        }
                        return map;
                    }

                    // TaskCard expects: taskData, taskIndex, isEditing, expanded, isSelected, nSub, dSub, subOrder, prog
                    readonly property var task: habitMap[modelData] ?? {
                        todoId: modelData,
                        title: "",
                        done: false,
                        icon: null,
                        priority: null,
                        minutes: null,
                        subtasks: []
                    }
                    readonly property int absIdx: habitIndexMap[modelData] ?? -1

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

                    // ── TaskCard Properties ─────────────────────
                    taskData: task
                    taskIndex: absIdx
                    isEditing: root.editingHabitId === task.todoId
                    // expanded: root.expandedId === modelData
                    isSelected: root.selectedIndex === index
                    nSub: progressData.total
                    dSub: progressData.done
                    subOrder: {
                        const order = [];
                        if (task.subtasks) {
                            for (let i = 0; i < task.subtasks.length; i++) {
                                order.push(task.subtasks[i].id);
                            }
                        }
                        return order;
                    }
                    prog: progressData.ratio

                    // Habit specific: show icon
                    icon: task.icon || ""

                    // Pass editingSubId for subtask editing
                    editingSubId: root.editingSubId

                    // ── Signal Handlers ─────────────────────────
                    onToggleRequested: (taskIdx) => {
                        root.toggleHabit(task.todoId)
                    }
                    // onToggleExpandRequested: (taskIdx) => {
                    //     root.expandedId = root.expandedId === modelData ? "" : modelData
                    // }
                    onRenameRequested: (taskIdx, newTitle) => {
                        root.renameHabit(task.todoId, newTitle)
                    }
                    onDeleteRequested: (taskIdx) => {
                        root.deleteHabit(absIdx)
                    }
                    onAddSubtaskRequested: (taskIdx, title) => {
                        root.addSubtask(absIdx, title)
                    }
                    onToggleSubtaskRequested: (taskIdx, subIdx) => {
                        root.toggleSubtask(absIdx, subIdx)
                    }
                    onDeleteSubtaskRequested: (taskIdx, subIdx) => {
                        root.deleteSubtask(absIdx, subIdx)
                    }
                    onRenameSubtaskRequested: (taskIdx, subIdx, newTitle) => {
                        root.renameSubtask(absIdx, subIdx, newTitle)
                    }
                    onEditingStarted: (taskId) => {
                        root.editingHabitId = taskId
                    }
                    onEditingCancelled: () => {
                        root.editingHabitId = ""
                    }
                    onSubtaskEditingStarted: (subtaskId) => {
                        root.editingSubId = subtaskId
                    }
                    onSubtaskEditingCancelled: () => {
                        root.editingSubId = ""
                    }
                }
            }

            // Empty state
            Item {
                Layout.fillWidth: true
                implicitHeight: emptyState.implicitHeight + Tokens.padding.extraLarge * 2
                visible: root.loaded && filteredModel.count === 0
                ColumnLayout {
                    id: emptyState
                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "wb_sunny"
                        fontStyle: Tokens.font.icon.builders.extraLarge.build()
                        color: Colours.palette.m3outlineVariant
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("No habits yet. Add one above!")
                        color: Colours.palette.m3outlineVariant
                        elide: Text.ElideRight
                        Layout.maximumWidth: root.width - Tokens.padding.extraLarge * 2
                    }
                }
            }
        }
    }
}