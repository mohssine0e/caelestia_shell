pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils

CustomMouseArea {
    id: root

    required property ScreenState screenState

    property date currentDate: screenState.dashboardDate
    readonly property int currMonth: currentDate.getMonth()
    readonly property int currYear: currentDate.getFullYear()
    readonly property int nonAnimCurrMonth: screenState.dashboardDate.getMonth()
    readonly property int nonAnimCurrYear: screenState.dashboardDate.getFullYear()

    readonly property int animDirection: screenState.dashboardDate > currentDate ? -1 : 1
    property real animTranslate
    property real animOpacity: 1

    property var gcalEvents: ({})
    property bool gcalConfigured: false
    property string selectedDateKey: ""
    property bool isAddingEvent: false
    property bool formAllDay: true
    property string editingEventId: ""
    property string mutationAction: ""
    property string mutationOutput: ""
    property string mutationError: ""
    onIsAddingEventChanged: root.screenState.dashboardNeedsFocus = root.isAddingEvent

    readonly property string todayKey: dateToKey(Time.date)
    readonly property string effectiveDateKey: selectedDateKey !== "" ? selectedDateKey : todayKey

    readonly property var weekDayHeaders: {
        // Compute localized Monday..Sunday short names anchored to a known Monday (2026-11-02).
        const names = [];
        for (let i = 0; i < 7; i++) {
            const d = new Date(2026, 10, 2 + i);
            names.push({
                label: d.toLocaleDateString(Tr.locale, "ddd"),
                isSunday: i === 6
            });
        }
        return names;
    }

    readonly property var monthCells: {
        const yr = root.currYear;
        const mo = root.currMonth;
        const firstOfMonth = new Date(yr, mo, 1);
        const mondayOffset = (firstOfMonth.getDay() + 6) % 7;
        const todayStr = root.todayKey;
        const cells = [];

        for (let i = 0; i < 42; i++) {
            const d = new Date(yr, mo, 1 - mondayOffset + i);
            const key = root.dateToKey(d);
            const rawEvents = root.gcalEvents[key] || [];
            const sortedEvents = rawEvents.slice().sort(root.compareEventsByTime);

            cells.push({
                index: i,
                row: Math.floor(i / 7),
                col: i % 7,
                day: d.getDate(),
                dayKey: key,
                isCurrentMonth: d.getMonth() === mo && d.getFullYear() === yr,
                isToday: key === todayStr,
                isSunday: d.getDay() === 0,
                events: sortedEvents
            });
        }
        return cells;
    }

    function computeNormalizedTracks(weights: var): var {
        const sum = weights.reduce((acc, w) => acc + w, 0) || 1;
        const fractions = [];
        const offsets = [];
        let cursor = 0;
        for (let i = 0; i < weights.length; i++) {
            const frac = weights[i] / sum;
            offsets.push(cursor);
            fractions.push(frac);
            cursor += frac;
        }
        return {
            fractions: fractions,
            offsets: offsets
        };
    }

    readonly property var colTracks: {
        const weights = [];
        for (let c = 0; c < 7; c++) {
            let maxEvents = 0;
            let hasToday = false;
            for (let r = 0; r < 6; r++) {
                const cell = root.monthCells[r * 7 + c];
                if (cell.events.length > maxEvents)
                    maxEvents = cell.events.length;
                if (cell.isToday)
                    hasToday = true;
            }
            if (maxEvents === 0 && !hasToday)
                weights.push(0.60);
            else if (maxEvents === 0)
                weights.push(1.0);
            else if (maxEvents === 1)
                weights.push(1.18);
            else
                weights.push(1.32);
        }
        return root.computeNormalizedTracks(weights);
    }

    readonly property var rowTracks: {
        const weights = [];
        for (let r = 0; r < 6; r++) {
            let maxEvents = 0;
            let hasToday = false;
            for (let c = 0; c < 7; c++) {
                const cell = root.monthCells[r * 7 + c];
                if (cell.events.length > maxEvents)
                    maxEvents = cell.events.length;
                if (cell.isToday)
                    hasToday = true;
            }
            if (maxEvents === 0 && !hasToday)
                weights.push(0.55);
            else if (maxEvents === 0)
                weights.push(0.95);
            else if (maxEvents === 1)
                weights.push(1.05);
            else if (maxEvents === 2)
                weights.push(1.28);
            else
                weights.push(1.45);
        }
        return root.computeNormalizedTracks(weights);
    }

    readonly property var selectedDayEvents: {
        if (!root.selectedDateKey)
            return [];
        const list = (root.gcalEvents[root.selectedDateKey] || []).slice();
        return list.sort(root.compareEventsByTime);
    }

    function eventStartMinutes(ev: var): int {
        if (root.isAllDayEvent(ev))
            return 1440;
        const match = String(ev.time || "").match(/(\d{1,2}):(\d{2})\s*(am|pm)?/i);
        if (!match)
            return 1439;
        let hour = Number(match[1]);
        const minute = Number(match[2]);
        const period = String(match[3] || "").toLowerCase();
        if (period === "pm" && hour < 12)
            hour += 12;
        else if (period === "am" && hour === 12)
            hour = 0;
        return hour * 60 + minute;
    }

    function compareEventsByTime(a: var, b: var): int {
        return root.eventStartMinutes(a) - root.eventStartMinutes(b);
    }

    function isAllDayEvent(ev: var): bool {
        if (!ev)
            return true;
        const t = String(ev.time || "").trim();
        return !!ev.all_day || !t || /^all\s*day$/i.test(t);
    }

    function shortEventTime(ev: var): string {
        if (isAllDayEvent(ev))
            return "";
        const t = String(ev.time || "").trim();
        const start = t.split(/\s*[-–]\s*/)[0].trim();
        return start.replace(/^0(\d:)/, "$1");
    }

    function eventLink(ev: var): string {
        const source = String(ev?.url || ev?.location || "");
        const match = source.match(/https?:\/\/[^\s<>]+/i);
        return match ? match[0] : "";
    }

    function formatAgendaDate(key: string): string {
        const parts = key.split("-").map(Number);
        if (parts.length !== 3)
            return key;
        return new Date(parts[0], parts[1] - 1, parts[2]).toLocaleDateString(Tr.locale, "ddd, MMM d");
    }

    function dateToKey(d: var): string {
        if (!d)
            return "";
        const yr = d.getFullYear();
        const mo = String(d.getMonth() + 1).padStart(2, "0");
        const dy = String(d.getDate()).padStart(2, "0");
        return `${yr}-${mo}-${dy}`;
    }

    function closeEventForm(): void {
        root.isAddingEvent = false;
        root.editingEventId = "";
        root.mutationError = "";
    }

    function startEventMutation(action: string, payload: var): void {
        if (eventMutation.running)
            return;
        root.mutationError = "";
        root.mutationOutput = "";
        root.mutationAction = action;
        eventMutation.command = ["python3", Paths.home + "/.config/quickshell/caelestia/scripts/calendar_event.py", action, JSON.stringify(payload)];
        eventMutation.running = true;
    }

    function editLocalEvent(ev: var): void {
        root.editingEventId = String(ev.id || "");
        root.formAllDay = root.isAllDayEvent(ev);
        root.isAddingEvent = true;
        eventTitleInput.text = String(ev.title || "");
        eventTimeInput.text = root.formAllDay ? "" : root.shortEventTime(ev);
        Qt.callLater(() => eventTitleInput.forceActiveFocus());
    }

    function commitAddEvent(titleRaw: string, timeRaw: string): void {
        let title = (titleRaw || "").trim();
        let time = (timeRaw || "").trim();
        if (!title)
            return;

        if (root.formAllDay) {
            time = "All day";
        } else if (!time) {
            // Allow a time in the title for fast keyboard entry.
            const timeMatch = title.match(/\b((?:[01]?\d|2[0-3]):[0-5]\d)\b/);
            if (timeMatch) {
                time = timeMatch[1].trim();
                title = title.replace(timeMatch[0], "").trim().replace(/\s+at\s*$/i, "").trim();
            }
        }
        root.startEventMutation(root.editingEventId ? "update" : "add", {
            date: root.effectiveDateKey, id: root.editingEventId, title: title, time: time
        });
    }

    FileView {
        id: gcalStorage

        path: Paths.home + "/.cache/caelestia/gcal.json"
        preload: true
        watchChanges: true
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.gcalEvents = data.events || {};
                root.gcalConfigured = data.configured ?? false;
            } catch (e) {
                console.log("[Calendar] FileView parse error:", e);
                root.gcalEvents = {};
                root.gcalConfigured = false;
            }
        }
        onFileChanged: reload()
    }

    Component.onCompleted: {
        try {
            const txt = gcalStorage.text();
            if (txt) {
                const data = JSON.parse(txt);
                root.gcalEvents = data.events || {};
                root.gcalConfigured = data.configured ?? false;
            }
        } catch (e) {
            console.log("[Calendar] Component.onCompleted error:", e);
        }
    }

    Process {
        id: syncProc

        command: ["python3", Paths.home + "/.config/caelestia/scripts/sync-gcal.py", "--notify"]
        onExited: gcalStorage.reload()
    }

    Process {
        id: eventMutation
        stdout: SplitParser { onRead: data => root.mutationOutput += data }
        onExited: code => {
            let result = ({});
            try { result = JSON.parse(root.mutationOutput.trim()); } catch (e) {}
            if (code !== 0 || !result.success) {
                root.mutationError = result.error || Tr.tr("Could not save this event.");
                return;
            }
            gcalStorage.reload();
            if (root.mutationAction !== "delete")
                root.closeEventForm();
            Toaster.toast(root.mutationAction === "delete" ? Tr.tr("Event deleted")
                : root.mutationAction === "update" ? Tr.tr("Event updated") : Tr.tr("Event added"),
                result.event?.title || "", "event_available");
        }
    }

    anchors.left: parent.left
    anchors.right: parent.right
    implicitHeight: 492

    acceptedButtons: Qt.MiddleButton
    onClicked: {
        root.screenState.dashboardDate = new Date();
        root.selectedDateKey = "";
        root.closeEventForm();
    }

    Anim {
        id: trOutAnim

        running: false
        target: root
        property: "animTranslate"
        to: root.Tokens.padding.extraLarge * root.animDirection
        type: Anim.FastSpatial
    }

    Behavior on currentDate {
        SequentialAnimation {
            ParallelAnimation {
                ScriptAction {
                    script: Qt.callLater(() => trOutAnim.start())
                }
                Anim {
                    target: root
                    property: "animOpacity"
                    to: 0
                    type: Anim.FastEffects
                }
            }
            ScriptAction {
                script: {
                    trOutAnim.complete();
                    root.animTranslate = root.Tokens.padding.extraLarge * -root.animDirection;
                }
            }
            PropertyAction {}
            ParallelAnimation {
                Anim {
                    target: root
                    property: "animTranslate"
                    to: 0
                    type: Anim.DefaultSpatial
                }
                Anim {
                    target: root
                    property: "animOpacity"
                    to: 1
                    type: Anim.DefaultEffects
                }
            }
        }
    }

    ColumnLayout {
        id: mainLayout

        anchors.fill: parent
        anchors.topMargin: Tokens.padding.small
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.bottomMargin: Tokens.padding.medium
        spacing: Tokens.spacing.extraSmall

        // Top bar: centered < Month Year >, right-aligned sync and + buttons.
        Item {
            id: topHeader

            Layout.fillWidth: true
            implicitHeight: Math.max(navRow.implicitHeight, actionsRow.implicitHeight)

            RowLayout {
                id: navRow

                anchors.centerIn: parent
                spacing: Tokens.spacing.large

                IconButton {
                    isRound: true
                    icon: "chevron_left"
                    type: IconButton.Text
                    font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                    padding: Tokens.padding.extraSmall
                    onClicked: root.screenState.dashboardDate = new Date(root.nonAnimCurrYear, root.nonAnimCurrMonth - 1, 1)
                }

                Item {
                    implicitWidth: monthYearDisplay.implicitWidth + Tokens.padding.large
                    implicitHeight: monthYearDisplay.implicitHeight + Tokens.padding.extraSmall * 2

                    StateLayer {
                        color: Colours.palette.m3primary
                        radius: pressed ? Tokens.rounding.small : height / 2
                        disabled: {
                            const now = new Date();
                            return root.nonAnimCurrMonth === now.getMonth() && root.nonAnimCurrYear === now.getFullYear();
                        }
                        onClicked: root.screenState.dashboardDate = new Date()

                        Behavior on radius {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }
                    }

                    StyledText {
                        id: monthYearDisplay

                        opacity: root.animOpacity
                        transform: Translate {
                            x: root.animTranslate
                        }

                        anchors.centerIn: parent
                        text: root.currentDate.toLocaleDateString(Tr.locale, "MMMM yyyy")
                        color: Colours.palette.m3primary
                        font: Tokens.font.title.builders.medium.capitalisation(Font.Capitalize).build()
                    }
                }

                IconButton {
                    isRound: true
                    icon: "chevron_right"
                    type: IconButton.Text
                    font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                    padding: Tokens.padding.extraSmall
                    onClicked: root.screenState.dashboardDate = new Date(root.nonAnimCurrYear, root.nonAnimCurrMonth + 1, 1)
                }
            }

            RowLayout {
                id: actionsRow

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Tokens.spacing.extraSmall

                IconButton {
                    id: syncBtn

                    isRound: true
                    icon: "sync"
                    type: IconButton.Text
                    font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                    padding: Tokens.padding.extraSmall
                    enabled: !syncProc.running
                    onClicked: syncProc.running = true

                    NumberAnimation on rotation {
                        running: syncProc.running
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 1000
                    }
                }

                IconButton {
                    icon: root.isAddingEvent ? "remove" : "add"
                    isRound: true
                    type: root.isAddingEvent ? IconButton.Tonal : IconButton.Text
                    font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                    padding: Tokens.padding.extraSmall
                    onClicked: {
                        if (!root.isAddingEvent && root.selectedDateKey === "")
                            root.selectedDateKey = root.todayKey;
                        if (root.isAddingEvent)
                            root.closeEventForm();
                        else {
                            root.editingEventId = "";
                            root.formAllDay = true;
                            root.isAddingEvent = true;
                        }
                    }
                }
            }
        }

        // Weekday column titles (Mon..Sun)
        Item {
            id: weekdayHeader

            Layout.fillWidth: true
            implicitHeight: 22

            Repeater {
                model: root.weekDayHeaders

                Item {
                    required property int index
                    required property var modelData

                    x: weekdayHeader.width * root.colTracks.offsets[index]
                    width: weekdayHeader.width * root.colTracks.fractions[index]
                    height: weekdayHeader.height

                    StyledText {
                        anchors.centerIn: parent
                        text: modelData.label
                        font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }

        // 6x7 monthly calendar sheet with dynamic empty row/col compression and soft Today fill.
        Item {
            id: gridContainer

            Layout.fillWidth: true
            Layout.fillHeight: true

            readonly property color dividerColor: Qt.alpha(Colours.palette.m3outlineVariant, 0.35)

            opacity: root.animOpacity
            transform: Translate {
                x: root.animTranslate
            }

            // Top hairline under Mon..Sun header
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: gridContainer.dividerColor
                z: 1
            }

            // Borderless tonal fill behind Today's box
            Rectangle {
                id: todayHighlight

                readonly property var todayCell: root.monthCells.find(c => c.isToday) ?? null
                visible: todayCell !== null
                x: (todayCell ? gridContainer.width * root.colTracks.offsets[todayCell.col] : 0) + 1
                y: (todayCell ? gridContainer.height * root.rowTracks.offsets[todayCell.row] : 0) + 1
                width: Math.max(0, (todayCell ? gridContainer.width * root.colTracks.fractions[todayCell.col] : 0) - 2)
                height: Math.max(0, (todayCell ? gridContainer.height * root.rowTracks.fractions[todayCell.row] : 0) - 2)
                z: 3
                radius: Tokens.rounding.small
                border.width: 0
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: Qt.alpha(Colours.palette.m3primary, 0.24)
                    }
                    GradientStop {
                        position: 1.0
                        color: Qt.alpha(Colours.palette.m3primary, 0.11)
                    }
                }
            }

            Repeater {
                model: root.monthCells

                Item {
                    id: cellItem

                    required property var modelData

                    readonly property int row: modelData.row
                    readonly property int col: modelData.col
                    readonly property bool isToday: modelData.isToday
                    readonly property bool isSelected: root.selectedDateKey === modelData.dayKey && !isToday
                    readonly property var events: modelData.events
                    readonly property int eventCount: events.length
                    readonly property int maxSlots: Math.max(0, Math.floor((height - dayNumberText.implicitHeight - 8) / 20))
                    readonly property bool hasOverflow: maxSlots > 0 && eventCount > maxSlots
                    readonly property var visibleEvents: hasOverflow ? (maxSlots >= 2 ? events.slice(0, maxSlots - 1) : []) : events.slice(0, maxSlots)

                    x: gridContainer.width * root.colTracks.offsets[col]
                    y: gridContainer.height * root.rowTracks.offsets[row]
                    width: gridContainer.width * root.colTracks.fractions[col]
                    height: gridContainer.height * root.rowTracks.fractions[row]
                    z: isToday ? 6 : 2

                    // 1px vertical & horizontal grid lines on non-edge edges
                    Rectangle {
                        visible: cellItem.col < 6
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        width: 1
                        color: gridContainer.dividerColor
                    }

                    Rectangle {
                        visible: cellItem.row < 5
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: gridContainer.dividerColor
                    }

                    // Hover / selected tint
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: Tokens.rounding.extraSmall
                        color: cellItem.isSelected ? Qt.alpha(Colours.palette.m3secondaryContainer, 0.45) : cellMouse.containsMouse && !cellItem.isToday ? Qt.alpha(Colours.palette.m3onSurface, 0.05) : "transparent"
                        border.width: cellItem.isSelected ? 1 : 0
                        border.color: Qt.alpha(Colours.palette.m3secondary, 0.7)

                        Behavior on color {
                            CAnim {}
                        }
                    }

                    MouseArea {
                        id: cellMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.isAddingEvent = false;
                            root.selectedDateKey = cellItem.modelData.dayKey;
                        }
                    }

                    // Compact top-centered day number
                    StyledText {
                        id: dayNumberText

                        anchors.top: parent.top
                        anchors.topMargin: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Tr.locale.toString(cellItem.modelData.day)
                        font: cellItem.isToday ? Tokens.font.label.builders.medium.weight(Font.DemiBold).build() : Tokens.font.label.small
                        color: {
                            if (cellItem.isToday)
                                return Colours.palette.m3primary;
                            if (cellItem.modelData.isSunday)
                                return Colours.palette.m3error;
                            return Colours.palette.m3onSurface;
                        }
                        opacity: {
                            if (cellItem.isToday)
                                return 1;
                            if (cellItem.modelData.isSunday)
                                return cellItem.modelData.isCurrentMonth ? 0.88 : 0.36;
                            return cellItem.modelData.isCurrentMonth ? 0.92 : 0.32;
                        }
                    }

                    // Centered empty hint inside Today's box when no events exist
                    StyledText {
                        visible: cellItem.isToday && cellItem.eventCount === 0
                        anchors.top: dayNumberText.bottom
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 4
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.WordWrap
                        text: Tr.tr("No events today")
                        font: Tokens.font.label.small
                        color: Qt.alpha(Colours.palette.m3onSurface, 0.65)
                    }

                    // Event pills stack below the centered day number
                    Column {
                        anchors.top: dayNumberText.bottom
                        anchors.topMargin: 3
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        spacing: 3

                        Repeater {
                            model: cellItem.visibleEvents

                            Rectangle {
                                id: eventPill

                                required property var modelData
                                readonly property bool isAllDay: root.isAllDayEvent(modelData)

                                width: parent.width
                                height: 17
                                radius: Tokens.rounding.extraSmall
                                color: isAllDay ? Qt.alpha(Colours.palette.m3onSurface, 0.08) : Qt.alpha(Colours.palette.term4, 0.24)
                                border.width: 1
                                border.color: isAllDay ? Qt.alpha(Colours.palette.m3outlineVariant, 0.35) : Qt.alpha(Colours.palette.term4, 0.42)

                                StyledText {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    anchors.rightMargin: 4
                                    text: eventPill.modelData.title || Tr.tr("Untitled Event")
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3onSurface
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // Overflow indicator pill when remaining events exceed cell height
                        Rectangle {
                            visible: cellItem.hasOverflow
                            width: parent.width
                            height: 16
                            radius: Tokens.rounding.extraSmall
                            color: Qt.alpha(Colours.palette.m3onSurface, 0.06)
                            border.width: 1
                            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.3)

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                text: Tr.tr("+%1 more").arg(cellItem.eventCount - cellItem.visibleEvents.length)
                                font: Tokens.font.label.small
                                color: Colours.palette.m3onSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }

    // Floating Day Details / Quick-Add overlay (only visible when clicking a day or "+")
    Rectangle {
        id: dayOverlayScrim

        anchors.fill: parent
        radius: Tokens.rounding.extraLarge
        visible: root.selectedDateKey !== "" || root.isAddingEvent
        color: Qt.alpha(Colours.palette.m3scrim, 0.45)
        z: 20

        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.selectedDateKey = "";
                root.closeEventForm();
            }
        }

        StyledRect {
            id: dayModal

            anchors.centerIn: parent
            width: Math.min(parent.width - Tokens.padding.large * 2, 420)
            implicitHeight: Math.min(parent.height - Tokens.padding.large * 2, modalColumn.implicitHeight + Tokens.padding.medium * 2)
            radius: Tokens.rounding.large
            color: Colours.palette.m3surfaceContainerHigh
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.75)

            MouseArea {
                anchors.fill: parent
            }

            RectangularShadow {
                anchors.fill: parent
                radius: parent.radius
                color: Qt.alpha(Colours.palette.m3shadow, 0.5)
                blur: 20
                z: -1
            }

            ColumnLayout {
                id: modalColumn

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.extraSmall

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        Layout.fillWidth: true
                        text: root.effectiveDateKey === root.todayKey ? Tr.tr("Today · %1").arg(root.formatAgendaDate(root.effectiveDateKey)) : root.formatAgendaDate(root.effectiveDateKey)
                        font: Tokens.font.label.medium
                        color: Colours.palette.m3onSurface
                        elide: Text.ElideRight
                    }

                    TextButton {
                        text: root.isAddingEvent ? Tr.tr("Cancel") : Tr.tr("Add event")
                        type: TextButton.Text
                        font: Tokens.font.label.small
                        horizontalPadding: 5
                        verticalPadding: 2
                        enabled: !eventMutation.running
                        onClicked: {
                            if (root.isAddingEvent)
                                root.closeEventForm();
                            else {
                                root.editingEventId = "";
                                root.formAllDay = true;
                                root.isAddingEvent = true;
                            }
                        }
                    }

                    IconButton {
                        icon: "close"
                        isRound: true
                        type: IconButton.Text
                        font: Tokens.font.icon.small
                        padding: 2
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        onClicked: {
                            root.selectedDateKey = "";
                            root.closeEventForm();
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: !!root.mutationError
                    text: root.mutationError
                    font: Tokens.font.label.small
                    color: Colours.palette.m3error
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: !root.isAddingEvent && root.selectedDayEvents.length === 0
                    text: Tr.tr("No events scheduled for this day")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                ListView {
                    id: dayEventsList

                    Layout.fillWidth: true
                    // Give the view enough initial height to create its delegates, then use
                    // their measured height. cacheBuffer includes rows below the fold.
                    Layout.preferredHeight: Math.min(216, Math.max(root.selectedDayEvents.length * 48, contentHeight))
                    visible: root.selectedDayEvents.length > 0
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 500
                    spacing: 4
                    model: root.selectedDayEvents

                    StyledScrollBar.vertical: StyledScrollBar {
                        flickable: dayEventsList
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        id: modalEventRow

                        required property var modelData
                        readonly property bool isAllDay: root.isAllDayEvent(modelData)
                        readonly property bool canEdit: !!modelData.is_local && !!modelData.id
                        readonly property string link: root.eventLink(modelData)
                        property bool confirmDelete: false

                        width: dayEventsList.width
                        implicitHeight: modalEventContent.implicitHeight + 12
                        radius: Tokens.rounding.small
                        color: Colours.palette.m3surfaceContainerLow
                        border.width: 1
                        border.color: Qt.alpha(Colours.palette.m3outlineVariant, rowHover.hovered ? 0.65 : 0.42)

                        HoverHandler { id: rowHover }
                        Timer {
                            interval: 4000
                            running: modalEventRow.confirmDelete
                            onTriggered: modalEventRow.confirmDelete = false
                        }

                        RowLayout {
                            id: modalEventContent

                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            anchors.topMargin: 6
                            anchors.bottomMargin: 6
                            spacing: 4

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 2

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: modalEventRow.modelData.title || Tr.tr("Untitled Event")
                                    font: Tokens.font.body.small
                                    color: Colours.palette.m3onSurface
                                    wrapMode: Text.WordWrap
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: {
                                        const ev = modalEventRow.modelData;
                                        const timePart = modalEventRow.isAllDay ? Tr.tr("All day") : String(ev.time || "").trim();
                                        return [timePart, ev.location].filter(Boolean).join(" · ");
                                    }
                                    font: Tokens.font.label.small
                                    color: modalEventRow.isAllDay ? Colours.palette.m3onSurfaceVariant : Colours.palette.term12
                                    wrapMode: Text.WordWrap
                                }
                            }

                            IconButton {
                                visible: rowHover.hovered && !!modalEventRow.link
                                icon: "open_in_new"
                                type: IconButton.Text
                                font: Tokens.font.icon.small
                                padding: 2
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                onClicked: Qt.openUrlExternally(modalEventRow.link)
                            }

                            IconButton {
                                visible: (rowHover.hovered || modalEventRow.confirmDelete) && modalEventRow.canEdit
                                icon: "edit"
                                type: IconButton.Text
                                font: Tokens.font.icon.small
                                padding: 2
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                enabled: !eventMutation.running
                                onClicked: root.editLocalEvent(modalEventRow.modelData)
                            }

                            IconButton {
                                visible: (rowHover.hovered || modalEventRow.confirmDelete) && modalEventRow.canEdit
                                icon: modalEventRow.confirmDelete ? "delete_forever" : "delete"
                                type: modalEventRow.confirmDelete ? IconButton.Tonal : IconButton.Text
                                font: Tokens.font.icon.small
                                padding: 2
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                enabled: !eventMutation.running
                                onClicked: {
                                    if (!modalEventRow.confirmDelete) {
                                        modalEventRow.confirmDelete = true;
                                        return;
                                    }
                                    modalEventRow.confirmDelete = false;
                                    root.startEventMutation("delete", {
                                        date: root.effectiveDateKey, id: modalEventRow.modelData.id
                                    });
                                }
                            }
                        }
                    }
                }
                ColumnLayout {
                    id: quickAddForm

                    Layout.fillWidth: true
                    visible: root.isAddingEvent
                    spacing: 6

                    onVisibleChanged: {
                        if (visible) {
                            eventTitleInput.text = "";
                            eventTimeInput.text = "";
                            Qt.callLater(() => eventTitleInput.forceActiveFocus());
                        }
                    }

                    RowLayout {
                        id: quickAddOptions
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.extraSmall

                        BtnSwitcher {
                            Layout.alignment: Qt.AlignVCenter
                            givenHeight: 28
                            font: Tokens.font.label.small
                            borderColor: Qt.alpha(Colours.palette.m3outlineVariant, 0.45)
                            backgroundColor: Colours.palette.m3surfaceContainerLow
                            enabled: !eventMutation.running
                            model: [
                                { text: Tr.tr("Day"), value: "all-day" },
                                { icon: "schedule", alwaysShowIcon: true, value: "time" }
                            ]
                            currentValue: root.formAllDay ? "all-day" : "time"
                            onActivated: value => {
                                root.formAllDay = value === "all-day";
                                if (value === "time")
                                    Qt.callLater(() => eventTimeInput.forceActiveFocus());
                            }
                        }

                        StyledTextField {
                            id: eventTimeInput

                            Layout.preferredWidth: Math.ceil(timeMetrics.advanceWidth) + leftPadding + rightPadding + Tokens.padding.small
                            visible: !root.formAllDay
                            placeholderText: Tr.tr("14:00")
                            placeholderFloats: false
                            horizontalPadding: 8
                            verticalPadding: 5
                            borderWidth: 1
                            font: Tokens.font.body.small
                            enabled: !eventMutation.running
                            onAccepted: root.commitAddEvent(eventTitleInput.text, text)
                            Keys.onEscapePressed: root.closeEventForm()
                        }

                        Item { Layout.fillWidth: true }

                        TextMetrics {
                            id: timeMetrics

                            font: Tokens.font.body.small
                            text: "00:00"
                        }
                    }

                    RowLayout {
                        id: quickAddLayout

                        Layout.fillWidth: true
                        spacing: Tokens.spacing.extraSmall

                        StyledTextField {
                            id: eventTitleInput

                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            placeholderText: root.editingEventId ? Tr.tr("Edit event title") : Tr.tr("Event title")
                            placeholderFloats: false
                            horizontalPadding: 10
                            verticalPadding: 5
                            borderWidth: 1
                            radius: Tokens.rounding.small
                            font: Tokens.font.body.small
                            enabled: !eventMutation.running
                            onAccepted: root.commitAddEvent(text, eventTimeInput.text)
                            Keys.onEscapePressed: root.closeEventForm()
                        }

                        CircularIndicator {
                            visible: eventMutation.running
                            running: visible
                            implicitSize: 22
                        }

                        IconButton {
                            icon: "check"
                            isRound: true
                            type: IconButton.Tonal
                            font: Tokens.font.icon.small
                            padding: 3
                            Layout.preferredWidth: 26
                            Layout.preferredHeight: 26
                            enabled: !eventMutation.running && !!eventTitleInput.text.trim()
                            onClicked: root.commitAddEvent(eventTitleInput.text, eventTimeInput.text)
                        }
                    }
                }

            }
        }
    }
}
