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

    readonly property real listMinHeight: 440
    readonly property real listMaxHeight: 640

    implicitHeight: CUtils.clamp(scroller.contentHeight, listMinHeight, listMaxHeight)
    
    // ── Data ─────────────────────────────────────────────────────
    readonly property var defaultHabits: [
        { id: "water",    icon: "water_drop",       label: qsTr("Drink 2L of water"), subtasks: [] },
        { id: "stretch",  icon: "directions_run",   label: qsTr("Morning stretch"), subtasks: [] },
        { id: "read",     icon: "menu_book",        label: qsTr("Read for 20 min"), subtasks: [] },
        { id: "sugar",    icon: "block",            label: qsTr("No sugar"), subtasks: [] },
        { id: "meditate", icon: "self_improvement", label: qsTr("Meditate"), subtasks: [] },
        { id: "plan",     icon: "checklist",        label: qsTr("Plan the day"), subtasks: [] }
    ]

    property var habits: []
    property var completions: ({}) // { "yyyy-MM-dd": [id, ...] }
    property bool loaded: false

    readonly property string today: Qt.formatDate(new Date(), "yyyy-MM-dd")
    readonly property var todayDone: completions[today] ?? []

    // Edit state (kept on root so it survives delegate re-renders)
    property string editingHabitId: ""
    property string editingSubId: ""

    // Which group is expanded — runtime-only (accordion, so at most one)
    property string expandedId: ""

    // Click-to-select highlight — index into root.filtered (i.e. visible order)
    property int selectedIndex: -1

    // Done-sinks-to-bottom snapshot
    property var sortSnapshot: ({})

    function refreshSort() {
        const m = {};
        for (const h of root.habits) {
            m[h.id] = isDone(h.id);
            if (h.subtasks) {
                for (const s of h.subtasks) {
                    m[s.id] = isDone(s.id);
                }
            }
        }
        root.sortSnapshot = m;
    }

    function sortDone(id, liveDone) {
        const s = root.sortSnapshot;
        return (id in s) ? s[id] : liveDone;
    }

    HoverHandler {
        id: listHover
        onHoveredChanged: if (!hovered) root.refreshSort()
    }

    // Undo state - unified snapshot mechanism
    property var lastAction: null // { type: "...", prevHabits, prevCompletions }
    property bool showUndo: false
    Timer {
        id: undoTimer
        interval: 6000
        onTriggered: { root.showUndo = false; root.lastAction = null; }
    }

    readonly property int selectedAbsIdx: selectedIndex >= 0 && selectedIndex < filtered.length
        ? habits.findIndex(h => h.id === filtered[selectedIndex]) : -1

    function moveSelection(delta) {
        if (root.filtered.length === 0)
            return;
        const next = root.selectedIndex < 0
            ? (delta > 0 ? 0 : root.filtered.length - 1)
            : root.selectedIndex + delta;
        root.selectedIndex = Math.max(0, Math.min(next, root.filtered.length - 1));
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
        const ctrl = event.modifiers & Qt.ControlModifier;
        const abs = root.selectedAbsIdx;

        if (event.key === Qt.Key_Z && ctrl && root.lastAction) {
            root.undoLast();
        } else if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
            root.moveSelection(1);
        } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
            root.moveSelection(-1);
        } else if (abs < 0) {
            event.accepted = false;
            return;
        } else if (event.key === Qt.Key_Space) {
            root.toggleHabit(root.habits[abs].id);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.editingHabitId = root.habits[abs].id;
        } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_X) {
            root.deleteHabit(root.habits[abs].id);
        } else if (event.key === Qt.Key_L || event.key === Qt.Key_Right) {
            root.expandedId = root.habits[abs].id;
        } else if (event.key === Qt.Key_H || event.key === Qt.Key_Left) {
            root.expandedId = "";
        } else {
            event.accepted = false;
            return;
        }
        event.accepted = true;
    }

    function pushUndo(action) {
        root.lastAction = action;
        root.showUndo = true;
        undoTimer.restart();
    }

    FileView {
        id: storage
        path: `${Paths.state}/habits.json`
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.habits = data.habits ?? [];
                for (const h of root.habits) {
                    if (!h.subtasks) h.subtasks = [];
                }
                root.completions = data.completions ?? {};
            } catch (e) {
                root.habits = root.defaultHabits;
                for (const h of root.habits) {
                    if (!h.subtasks) h.subtasks = [];
                }
                root.completions = {};
            }
            root.loaded = true;
            root.refreshSort();
        }
        onLoadFailed: err => {
            root.habits = root.defaultHabits;
            for (const h of root.habits) {
                if (!h.subtasks) h.subtasks = [];
            }
            root.completions = {};
            root.loaded = true;
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => root.save());
        }
    }

    function save() { storage.setText(JSON.stringify({ habits: root.habits, completions: root.completions }, null, 2)); }

    function mutate(fn, type) {
        const prevHabits = JSON.parse(JSON.stringify(root.habits));
        const prevCompletions = JSON.parse(JSON.stringify(root.completions));
        const c = JSON.parse(JSON.stringify(root.habits));
        fn(c);
        root.habits = c;
        save();
        pushUndo({ type, prevHabits, prevCompletions });
    }

    function findHabitById(list, id) {
        for (const h of list) {
            if (h.id === id) return h;
            if (h.subtasks) {
                for (const s of h.subtasks) {
                    if (s.id === id) return s;
                }
            }
        }
        return null;
    }

    function isDone(id) {
        const h = findHabitById(root.habits, id);
        if (h && h.subtasks && h.subtasks.length > 0) {
            return h.subtasks.every(s => todayDone.includes(s.id));
        }
        return todayDone.includes(id);
    }

    function toggleHabit(id) {
        const prevHabits = JSON.parse(JSON.stringify(root.habits));
        const prevCompletions = JSON.parse(JSON.stringify(root.completions));

        const h = findHabitById(root.habits, id);
        if (!h) return;

        const done = Object.assign({}, root.completions);
        const list = done[root.today] ? [...done[root.today]] : [];

        function getLeafIds(item) {
            if (item.subtasks && item.subtasks.length > 0) {
                let ids = [];
                for (const sub of item.subtasks) {
                    ids = ids.concat(getLeafIds(sub));
                }
                return ids;
            }
            return [item.id];
        }

        const prevDone = isDone(id);
        const leafIds = getLeafIds(h);

        if (h.subtasks && h.subtasks.length > 0) {
            if (prevDone) {
                for (const lid of leafIds) {
                    const idx = list.indexOf(lid);
                    if (idx >= 0) list.splice(idx, 1);
                }
            } else {
                for (const lid of leafIds) {
                    if (!list.includes(lid)) list.push(lid);
                }
            }
        } else {
            const idx = list.indexOf(id);
            if (idx >= 0) list.splice(idx, 1); else list.push(id);
        }

        done[root.today] = list;
        root.completions = done;
        save();

        pushUndo({ type: "toggle", prevHabits, prevCompletions });
    }

    function addHabit(label, icon) {
        if (!label.trim()) return;
        mutate(hs => {
            hs.push({
                id: `${Date.now()}-${Math.floor(Math.random() * 1e6)}`,
                icon: icon || "task_alt",
                label: label.trim(),
                subtasks: []
            });
        }, "add-habit");
    }

    function deleteHabit(id) {
        const idx = root.habits.findIndex(h => h.id === id);
        if (idx < 0) return;
        mutate(hs => {
            hs.splice(idx, 1);
        }, "delete-habit");
    }

    function undoLast() {
        if (!lastAction) return;
        if (lastAction.prevHabits) root.habits = lastAction.prevHabits;
        if (lastAction.prevCompletions) root.completions = lastAction.prevCompletions;
        save();
        showUndo = false;
        lastAction = null;
        undoTimer.stop();
    }

    function renameHabit(id, label) {
        if (!label.trim()) return;
        mutate(hs => {
            const h = findHabitById(hs, id);
            if (h) h.label = label.trim();
        }, "rename-habit");
        editingHabitId = "";
    }

    function addSubtask(ti, label) {
        if (!label.trim()) return;
        mutate(hs => {
            if (!hs[ti].subtasks) hs[ti].subtasks = [];
            hs[ti].subtasks.push({
                id: `${Date.now()}-${Math.floor(Math.random() * 1e6)}`,
                label: label.trim()
            });
        }, "add-subhabit");
    }

    function toggleSubtask(ti, si) {
        const prevHabits = JSON.parse(JSON.stringify(root.habits));
        const prevCompletions = JSON.parse(JSON.stringify(root.completions));

        const sub = root.habits[ti].subtasks[si];
        const done = Object.assign({}, root.completions);
        const list = done[root.today] ? [...done[root.today]] : [];
        const idx = list.indexOf(sub.id);
        if (idx >= 0) list.splice(idx, 1); else list.push(sub.id);

        done[root.today] = list;
        root.completions = done;
        save();

        pushUndo({ type: "toggle-subhabit", prevHabits, prevCompletions });
    }

    function renameSubtask(ti, si, label) {
        if (!label.trim()) return;
        mutate(hs => {
            hs[ti].subtasks[si].label = label.trim();
        }, "rename-subhabit");
        editingSubId = "";
    }

    function deleteSubtask(ti, si) {
        mutate(hs => {
            hs[ti].subtasks.splice(si, 1);
        }, "delete-subhabit");
    }

    function moveTask(fromDisplayIdx, toDisplayIdx) {
        if (fromDisplayIdx === toDisplayIdx) return;
        const ids = root.filtered;
        mutate(hs => {
            const absFrom = hs.findIndex(h => h.id === ids[fromDisplayIdx]);
            if (absFrom < 0) return;
            let absTo;
            if (toDisplayIdx <= 0) {
                absTo = 0;
            } else if (toDisplayIdx >= ids.length) {
                absTo = hs.length;
            } else {
                absTo = hs.findIndex(h => h.id === ids[toDisplayIdx]);
                if (absTo < 0) return;
                if (absTo > absFrom) absTo -= 1;
            }
            const [item] = hs.splice(absFrom, 1);
            hs.splice(absTo, 0, item);
        }, "move-habit");
    }

    function moveSubtask(ti, ids, fromDisplayIdx, toDisplayIdx) {
        if (fromDisplayIdx === toDisplayIdx) return;
        mutate(hs => {
            const subs = hs[ti].subtasks || [];
            const absFrom = subs.findIndex(s => s.id === ids[fromDisplayIdx]);
            if (absFrom < 0) return;
            let absTo;
            if (toDisplayIdx <= 0) {
                absTo = 0;
            } else if (toDisplayIdx >= ids.length) {
                absTo = subs.length;
            } else {
                absTo = subs.findIndex(s => s.id === ids[toDisplayIdx]);
                if (absTo < 0) return;
                if (absTo > absFrom) absTo -= 1;
            }
            const [item] = subs.splice(absFrom, 1);
            subs.splice(absTo, 0, item);
        }, "move-subhabit");
    }

    readonly property var filtered: {
        const snap = root.sortSnapshot;
        const open = [], done = [];
        for (const h of habits) {
            const hDone = isDone(h.id);
            ((h.id in snap ? snap[h.id] : hDone) ? done : open).push(h.id);
        }
        return open.concat(done);
    }

    readonly property int doneCount: {
        let c = 0;
        for (const h of root.habits) {
            if (isDone(h.id)) c++;
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
            for (const h of habits) {
                if (h.subtasks && h.subtasks.length > 0) {
                    if (!h.subtasks.every(s => list.includes(s.id))) {
                        return false;
                    }
                } else {
                    if (!list.includes(h.id)) {
                        return false;
                    }
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

    property int dragOverIndex: -1

    onFilteredChanged: {
        if (root.selectedIndex >= root.filtered.length)
            root.selectedIndex = -1;
    }

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

            // ── Title + progress ───────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon { text: "wb_sunny"; fontStyle: Tokens.font.icon.large; color: Colours.palette.m3primary }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText { text: qsTr("Daily Habits"); font: Tokens.font.title.medium; color: Colours.palette.m3onSurface }
                    StyledText { text: qsTr("Small actions. Big results."); font: Tokens.font.body.small; color: Colours.palette.m3onSurfaceVariant }
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

            StyledRect { Layout.fillWidth: true; implicitHeight: 1; color: Colours.palette.m3outlineVariant; opacity: 0.4 }

            // ── Habit rows ─────────────────────────────────────
            Repeater {
                id: habitRepeater
                model: ScriptModel { values: root.filtered }
                delegate: Item {
                    id: cw
                    required property string modelData // habit id
                    required property int index

                    readonly property int absIdx: root.habits.findIndex(h => h.id === modelData)
                    readonly property var habit: root.habits[absIdx]
                        ?? ({ id: modelData, icon: "task_alt", label: "", subtasks: [] })
                    readonly property bool done: root.isDone(modelData)
                    readonly property bool isEditing: root.editingHabitId === modelData
                    readonly property bool expanded: root.expandedId === modelData
                    readonly property bool isSelected: root.selectedIndex === index
                    readonly property int nSub: habit.subtasks ? habit.subtasks.length : 0
                    readonly property int dSub: {
                        let d = 0;
                        if (habit.subtasks) {
                            for (const s of habit.subtasks) {
                                if (root.isDone(s.id)) d++;
                            }
                        }
                        return d;
                    }

                    readonly property var subOrder: {
                        const snap = root.sortSnapshot;
                        const open = [], done = [];
                        if (habit.subtasks) {
                            for (const s of habit.subtasks) {
                                const sDone = root.isDone(s.id);
                                ((s.id in snap ? snap[s.id] : sDone) ? done : open).push(s.id);
                            }
                        }
                        return open.concat(done);
                    }

                    readonly property real prog: nSub > 0 ? dSub / nSub : (cw.done ? 1 : 0)

                    property real dragY: 0

                    Layout.fillWidth: true
                    implicitHeight: rowBg.implicitHeight
                    z: dragHandler.active ? 100 : 1
                    transform: Translate { y: cw.dragY }

                    StyledRect {
                        id: rowBg
                        width: parent.width
                        radius: Tokens.rounding.large
                        color: cw.isSelected ? Colours.tPalette.m3surfaceContainerHigh
                             : rowHover.hovered ? Colours.tPalette.m3surfaceContainer
                             : Colours.tPalette.m3surfaceContainerLow
                        border.width: cw.isSelected ? 2 : 0
                        border.color: Colours.palette.m3primary

                        opacity: cw.done ? 0.65 : 1
                        Behavior on opacity { Anim { type: Anim.DefaultEffects } }

                        implicitHeight: rowCol.implicitHeight + Tokens.padding.small * 2
                        Behavior on implicitHeight { Anim { type: Anim.FastSpatial } }
                        Behavior on color { CAnim {} }

                        HoverHandler { id: rowHover }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.selectedIndex = cw.index;
                                root.forceActiveFocus();
                            }
                            onDoubleClicked: if (cw.absIdx >= 0) root.expandedId = root.expandedId === cw.modelData ? "" : cw.modelData
                        }

                        ColumnLayout {
                            id: rowCol
                            anchors { left: parent.left; right: parent.right; top: parent.top
                                      margins: Tokens.padding.small; leftMargin: Tokens.padding.medium; rightMargin: Tokens.padding.medium }
                            spacing: Tokens.spacing.small

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    text: "drag_indicator"
                                    fontStyle: Tokens.font.icon.small
                                    color: Colours.palette.m3outlineVariant
                                    opacity: (dragHandler.active || rowHover.hovered || cw.isSelected) ? 0.6 : 0
                                    Behavior on opacity { Anim { type: Anim.DefaultEffects } }

                                    DragHandler {
                                        id: dragHandler
                                        target: null
                                        onActiveChanged: {
                                            if (!active) {
                                                if (root.dragOverIndex >= 0)
                                                    root.moveTask(cw.index, root.dragOverIndex);
                                                cw.dragY = 0;
                                                root.dragOverIndex = -1;
                                            }
                                        }
                                        onTranslationChanged: {
                                            if (!active) return;
                                            cw.dragY = translation.y;
                                            let target = 0;
                                            for (let i = 0; i < habitRepeater.count; i++) {
                                                if (i === cw.index) continue;
                                                const sib = habitRepeater.itemAt(i);
                                                if (!sib) continue;
                                                if (sib.y + sib.height / 2 < cw.y + cw.dragY + cw.height / 2)
                                                    target++;
                                            }
                                            root.dragOverIndex = target;
                                        }
                                    }
                                }

                                MaterialIcon {
                                    text: cw.expanded ? "keyboard_arrow_down" : "keyboard_arrow_right"
                                    fontStyle: Tokens.font.icon.small
                                    color: Colours.palette.m3onSurfaceVariant
                                    opacity: cw.nSub > 0 ? 1
                                           : (rowHover.hovered || cw.isSelected) ? 0.5 : 0
                                    Behavior on opacity { Anim { type: Anim.DefaultEffects } }

                                    MouseArea {
                                        anchors.fill: parent; anchors.margins: -4
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (cw.absIdx >= 0) root.expandedId = root.expandedId === cw.modelData ? "" : cw.modelData
                                    }
                                }

                                StyledRect {
                                    implicitWidth: 36; implicitHeight: 36
                                    radius: Tokens.rounding.medium
                                    color: cw.done ? Colours.tPalette.m3primaryContainer : Colours.tPalette.m3surfaceContainerHigh
                                    Behavior on color { CAnim {} }
                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        text: cw.habit.icon
                                        fontStyle: Tokens.font.icon.medium
                                        color: cw.done ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                                        Behavior on color { CAnim {} }
                                    }
                                }

                                StyledText {
                                    visible: !cw.isEditing
                                    Layout.fillWidth: true
                                    text: cw.habit.label
                                    font: Tokens.font.body.large
                                    color: cw.done ? Colours.palette.m3outline : Colours.palette.m3onSurface
                                    elide: Text.ElideRight
                                    Behavior on color { CAnim {} }

                                    StyledRect {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: cw.done ? Math.min(parent.contentWidth, parent.width) : 0
                                        height: 2
                                        radius: Tokens.rounding.full
                                        color: Colours.palette.m3outline
                                        Behavior on width { Anim { type: Anim.FastSpatial } }
                                    }
                                }

                                StyledTextField {
                                    visible: cw.isEditing
                                    Layout.fillWidth: true
                                    text: cw.habit.label
                                    font: Tokens.font.body.large
                                    onVisibleChanged: if (visible) { forceActiveFocus(); selectAll(); }
                                    onAccepted: root.renameHabit(cw.modelData, text)
                                    Keys.onEscapePressed: { root.editingHabitId = ""; text = cw.habit.label; }
                                }

                                RowLayout {
                                    visible: cw.nSub > 0 && !cw.isEditing
                                    spacing: Tokens.spacing.small
                                    StyledText {
                                        text: `${cw.dSub} / ${cw.nSub}`
                                        font: Tokens.font.body.small
                                        color: Colours.palette.m3onSurfaceVariant
                                    }
                                    StyledRect {
                                        implicitWidth: 128; implicitHeight: 6
                                        radius: Tokens.rounding.full
                                        color: Colours.tPalette.m3surfaceContainerHighest

                                        StyledRect {
                                            width: parent.width * cw.prog
                                            height: parent.height
                                            radius: parent.radius
                                            color: Colours.palette.m3tertiary
                                            Behavior on width { Anim {} }
                                        }
                                    }
                                }

                                RowLayout {
                                    visible: !cw.isEditing
                                    spacing: 0
                                    opacity: (rowHover.hovered || cw.isSelected) ? 1 : 0
                                    Behavior on opacity { Anim { type: Anim.DefaultEffects } }

                                    IconButton {
                                        type: IconButton.Text
                                        font: Tokens.font.icon.small
                                        icon: "edit"
                                        onClicked: root.editingHabitId = cw.modelData
                                    }
                                    IconButton {
                                        type: IconButton.Text
                                        font: Tokens.font.icon.small
                                        icon: "delete_outline"
                                        onClicked: if (cw.absIdx >= 0) root.deleteHabit(cw.modelData)
                                    }
                                }

                                MaterialIcon {
                                    text: cw.done ? "check_circle" : (cw.nSub > 0 && cw.dSub > 0 ? "indeterminate_check_box" : "radio_button_unchecked")
                                    fill: cw.done ? 1 : 0
                                    fontStyle: Tokens.font.icon.medium
                                    color: cw.done ? Colours.palette.m3tertiary : Colours.palette.m3outline
                                    Behavior on color { CAnim {} }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleHabit(cw.modelData)
                                    }
                                }
                            }

                            // Sub-habits list
                            ColumnLayout {
                                visible: cw.expanded
                                Layout.fillWidth: true
                                Layout.leftMargin: Tokens.padding.extraLarge
                                spacing: Tokens.spacing.extraSmall

                                Repeater {
                                    id: subRepeater
                                    model: ScriptModel { values: cw.subOrder }
                                    delegate: Item {
                                        id: sw
                                        required property string modelData // subhabit id
                                        required property int index

                                        readonly property int subIdx: cw.habit.subtasks ? cw.habit.subtasks.findIndex(s => s.id === modelData) : -1
                                        readonly property var sub: (cw.habit.subtasks && subIdx >= 0) ? cw.habit.subtasks[subIdx]
                                            : ({ id: modelData, label: "" })
                                        readonly property string sid: `${cw.modelData}__${modelData}`
                                        readonly property bool isEditingSub: root.editingSubId === sid
                                        readonly property bool subDone: root.isDone(modelData)

                                        property real dragY: 0

                                        Layout.fillWidth: true
                                        implicitHeight: subRow.implicitHeight
                                        z: subDrag.active ? 100 : 1
                                        transform: Translate { y: sw.dragY }

                                        HoverHandler { id: subRowHover }

                                        RowLayout {
                                            id: subRow
                                            width: parent.width
                                            spacing: Tokens.spacing.small

                                            MaterialIcon {
                                                text: "drag_indicator"
                                                fontStyle: Tokens.font.icon.small
                                                color: Colours.palette.m3outlineVariant
                                                opacity: (subDrag.active || subRowHover.hovered) ? 0.5 : 0
                                                Behavior on opacity { Anim { type: Anim.DefaultEffects } }

                                                DragHandler {
                                                    id: subDrag
                                                    target: null
                                                    onActiveChanged: {
                                                        if (!active) {
                                                            let target = 0;
                                                            for (let i = 0; i < subRepeater.count; i++) {
                                                                if (i === sw.index) continue;
                                                                const sib = subRepeater.itemAt(i);
                                                                if (!sib) continue;
                                                                if (sib.y + sib.height / 2 < sw.y + sw.dragY + sw.height / 2)
                                                                    target++;
                                                            }
                                                            root.moveSubtask(cw.absIdx, cw.subOrder, sw.index, target);
                                                            sw.dragY = 0;
                                                        }
                                                    }
                                                    onTranslationChanged: if (active) sw.dragY = translation.y;
                                                }
                                            }

                                            MaterialIcon {
                                                text: sw.subDone ? "check_box" : "check_box_outline_blank"
                                                fill: sw.subDone ? 1 : 0
                                                fontStyle: Tokens.font.icon.small
                                                color: sw.subDone ? Colours.palette.m3tertiary : Colours.palette.m3outline
                                                Behavior on color { CAnim {} }
                                                MouseArea {
                                                    anchors.fill: parent; anchors.margins: -4
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: if (cw.absIdx >= 0 && sw.subIdx >= 0) root.toggleSubtask(cw.absIdx, sw.subIdx)
                                                }
                                            }

                                            StyledText {
                                                visible: !sw.isEditingSub
                                                Layout.fillWidth: true; text: sw.sub.label
                                                font: Tokens.font.body.medium
                                                color: sw.subDone ? Colours.palette.m3outline : Colours.palette.m3onSurfaceVariant
                                                elide: Text.ElideRight
                                                Behavior on color { CAnim {} }

                                                StyledRect {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: sw.subDone ? Math.min(parent.contentWidth, parent.width) : 0
                                                    height: 2
                                                    radius: Tokens.rounding.full
                                                    color: Colours.palette.m3outline
                                                    Behavior on width { Anim { type: Anim.FastSpatial } }
                                                }
                                            }

                                            StyledTextField {
                                                visible: sw.isEditingSub; Layout.fillWidth: true
                                                text: sw.sub.label; font: Tokens.font.body.medium
                                                onVisibleChanged: if (visible) { forceActiveFocus(); selectAll(); }
                                                onAccepted: if (cw.absIdx >= 0 && sw.subIdx >= 0) root.renameSubtask(cw.absIdx, sw.subIdx, text)
                                                Keys.onEscapePressed: { root.editingSubId = ""; text = sw.sub.label; }
                                            }

                                            RowLayout {
                                                visible: !sw.isEditingSub
                                                spacing: 0
                                                opacity: subRowHover.hovered ? 1 : 0
                                                Behavior on opacity { Anim { type: Anim.DefaultEffects } }

                                                IconButton {
                                                    type: IconButton.Text
                                                    font: Tokens.font.icon.small
                                                    icon: "edit"
                                                    onClicked: root.editingSubId = sw.sid
                                                }
                                                IconButton {
                                                    type: IconButton.Text
                                                    font: Tokens.font.icon.small
                                                    icon: "delete_outline"
                                                    onClicked: if (cw.absIdx >= 0 && sw.subIdx >= 0) root.deleteSubtask(cw.absIdx, sw.subIdx)
                                                }
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true; spacing: Tokens.spacing.small
                                    Layout.topMargin: Tokens.spacing.extraSmall
                                    MaterialIcon { text: "add"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3primary }
                                    StyledTextField {
                                        Layout.fillWidth: true; font: Tokens.font.body.medium
                                        placeholderText: qsTr("Add subtask…")
                                        onAccepted: { if (cw.absIdx >= 0) root.addSubtask(cw.absIdx, text); clear(); }
                                        Keys.onEscapePressed: { clear(); focus = false; }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Breathing room so the pinned undo banner never covers the last row
            Item {
                Layout.fillWidth: true
                implicitHeight: root.showUndo ? 56 : 0
                Behavior on implicitHeight { Anim { type: Anim.FastSpatial } }
            }
        }

        // Drop-position indicator
        StyledRect {
            visible: root.dragOverIndex >= 0
            z: 200
            x: 0
            width: col.width
            height: 3
            radius: Tokens.rounding.full
            color: Colours.palette.m3primary
            y: {
                if (root.dragOverIndex < 0)
                    return 0;
                if (root.dragOverIndex >= habitRepeater.count) {
                    const last = habitRepeater.itemAt(habitRepeater.count - 1);
                    return last ? last.y + last.height : 0;
                }
                const item = habitRepeater.itemAt(root.dragOverIndex);
                return item ? item.y : 0;
            }
        }
    }

    // ── Undo banner ──────────────────────────────────────────────
    Item {
        id: undoBanner

        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        implicitHeight: undoRow.implicitHeight + Tokens.padding.small * 2 + 4
        height: implicitHeight
        z: 300

        opacity: root.showUndo ? 1 : 0
        visible: opacity > 0
        transform: Translate { y: root.showUndo ? 0 : undoBanner.height
            Behavior on y { Anim { type: Anim.FastSpatial } } }
        Behavior on opacity { Anim { type: Anim.DefaultEffects } }

        property real timeLeft: 1
        NumberAnimation {
            id: undoCountdown
            target: undoBanner
            property: "timeLeft"
            from: 1; to: 0
            duration: undoTimer.interval
        }
        Connections {
            target: root
            function onLastActionChanged() {
                if (root.lastAction) undoCountdown.restart();
            }
        }

        StyledRect {
            anchors.fill: parent
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainerHighest
            border.width: 1
            border.color: Colours.palette.m3outlineVariant

            StyledRect {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: Tokens.padding.small
                anchors.bottomMargin: 3
                width: (parent.width - Tokens.padding.small * 2) * undoBanner.timeLeft
                height: 3
                radius: Tokens.rounding.full
                color: Colours.palette.m3primary
            }

            RowLayout {
                id: undoRow
                anchors { left: parent.left; right: parent.right
                          verticalCenter: parent.verticalCenter
                          margins: Tokens.padding.small }
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: root.lastAction?.type === "toggle" || root.lastAction?.type === "toggle-subhabit" ? "undo" : "delete_outline"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
                }
                StyledText {
                    Layout.fillWidth: true
                    text: {
                        const a = root.lastAction;
                        if (!a) return "";
                        if (a.type === "delete-habit") return qsTr("Habit deleted");
                        if (a.type === "delete-subhabit") return qsTr("Sub-habit deleted");
                        if (a.type === "toggle" || a.type === "toggle-subhabit") return qsTr("Status change undone");
                        return qsTr("Action undone");
                    }
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                    elide: Text.ElideRight
                }
                StyledText {
                    text: qsTr("Ctrl+Z")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3outline
                }
                TextButton { text: qsTr("Undo"); onClicked: root.undoLast() }
            }
        }
    }
}
