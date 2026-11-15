pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import M3Shapes
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.components.effects
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

    function onWheel(event: WheelEvent): void {
        if (event.angleDelta.y > 0)
            screenState.dashboardDate = new Date(nonAnimCurrYear, nonAnimCurrMonth - 1, 1);
        else if (event.angleDelta.y < 0)
            screenState.dashboardDate = new Date(nonAnimCurrYear, nonAnimCurrMonth + 1, 1);
    }

    property var gcalEvents: ({})
    property bool gcalConfigured: false
    property string selectedDateKey: ""
    property bool isAddingEvent: false
    onIsAddingEventChanged: root.screenState.dashboardNeedsFocus = root.isAddingEvent

    // Reactive date from Time service (auto-updates at midnight)
    readonly property date todayDate: Time.date
    readonly property string todayKey: dateToKey(Time.date)
    readonly property string effectiveDateKey: selectedDateKey !== "" ? selectedDateKey : todayKey

    function dateToKey(d: var): string {
        if (!d) return "";
        const yr = d.getFullYear();
        const mo = String(d.getMonth() + 1).padStart(2, "0");
        const dy = String(d.getDate()).padStart(2, "0");
        return `${yr}-${mo}-${dy}`;
    }

    function extractMeetingUrl(text: string): string {
        if (!text) return "";
        const meetMatch = text.match(/https?:\/\/(?:meet\.google\.com\/[a-z0-9\-]+|zoom\.us\/j\/[0-9]+[^\s]*|teams\.microsoft\.com\/[^\s]+|[a-z0-9\.\-]+\.zoom\.us\/[^\s]+)/i);
        if (meetMatch) return meetMatch[0];
        const urlMatch = text.match(/https?:\/\/[^\s]+/i);
        return urlMatch ? urlMatch[0] : "";
    }

    function formatDateStr(k: string): string {
        if (!k) return "";
        const parts = k.split("-");
        if (parts.length < 3) return k;
        const d = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));
        return d.toLocaleDateString(Qt.locale(), "ddd, MMM d");
    }

    readonly property var flatAgendaItems: {
        // Mode 1: A specific day is selected from MonthGrid
        if (root.selectedDateKey !== "") {
            const evs = root.gcalEvents[root.selectedDateKey] || [];
            const isToday = root.selectedDateKey === root.todayKey;
            const dateStr = root.formatDateStr(root.selectedDateKey);
            const headerTitle = isToday ? ("Today • " + dateStr) : dateStr;

            const items = [{
                isHeader: true,
                isEmptyNotice: false,
                id: "hdr_" + root.selectedDateKey,
                title: headerTitle,
                dateKey: root.selectedDateKey,
                time: "",
                all_day: false,
                location: "",
                is_local: false,
                meetUrl: ""
            }];

            if (evs.length === 0) {
                items.push({
                    isHeader: false,
                    isEmptyNotice: true,
                    id: "empty_" + root.selectedDateKey,
                    title: "No events scheduled for this day",
                    dateKey: root.selectedDateKey,
                    time: "",
                    all_day: false,
                    location: "",
                    is_local: false,
                    meetUrl: ""
                });
            } else {
                for (let i = 0; i < evs.length; i++) {
                    const ev = evs[i];
                    items.push({
                        isHeader: false,
                        isEmptyNotice: false,
                        id: ev.id || ("ev_" + i),
                        title: ev.title || "Untitled Event",
                        time: ev.time || "All day",
                        all_day: !!ev.all_day,
                        location: ev.location || "",
                        is_local: !!ev.is_local,
                        dateKey: root.selectedDateKey,
                        meetUrl: root.extractMeetingUrl((ev.location || "") + " " + (ev.description || ""))
                    });
                }
            }
            return items;
        }

        // Mode 2: Full upcoming agenda feed (Today + Next 14 active days)
        const result = [];
        const todayStr = root.todayKey;
        const sortedKeys = Object.keys(root.gcalEvents).filter(k => k >= todayStr).sort();

        const todayObj = new Date(Time.date.getFullYear(), Time.date.getMonth(), Time.date.getDate());
        const tomorrowObj = new Date(todayObj);
        tomorrowObj.setDate(todayObj.getDate() + 1);
        const tomorrowKey = root.dateToKey(tomorrowObj);

        // Always show Today section
        const todayEvs = root.gcalEvents[todayStr] || [];
        const todayDateStr = todayObj.toLocaleDateString(Qt.locale(), "ddd, MMM d");
        result.push({
            isHeader: true,
            isEmptyNotice: false,
            id: "hdr_today",
            title: "Today • " + todayDateStr,
            dateKey: todayStr,
            time: "",
            all_day: false,
            location: "",
            is_local: false,
            meetUrl: ""
        });

        if (todayEvs.length === 0) {
            result.push({
                isHeader: false,
                isEmptyNotice: true,
                id: "empty_today",
                title: "Nothing scheduled today",
                dateKey: todayStr,
                time: "",
                all_day: false,
                location: "",
                is_local: false,
                meetUrl: ""
            });
        } else {
            for (let i = 0; i < todayEvs.length; i++) {
                const ev = todayEvs[i];
                result.push({
                    isHeader: false,
                    isEmptyNotice: false,
                    id: ev.id || ("today_" + i),
                    title: ev.title || "Untitled Event",
                    time: ev.time || "All day",
                    all_day: !!ev.all_day,
                    location: ev.location || "",
                    is_local: !!ev.is_local,
                    dateKey: todayStr,
                    meetUrl: root.extractMeetingUrl((ev.location || "") + " " + (ev.description || ""))
                });
            }
        }

        // Future active days
        let addedDays = 0;
        for (let k of sortedKeys) {
            if (k === todayStr) continue;
            const evs = root.gcalEvents[k] || [];
            if (evs.length === 0) continue;

            const parts = k.split("-");
            if (parts.length < 3) continue;
            const d = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));

            let headerTitle = "";
            if (k === tomorrowKey) {
                headerTitle = "Tomorrow • " + d.toLocaleDateString(Qt.locale(), "ddd, MMM d");
            } else {
                headerTitle = d.toLocaleDateString(Qt.locale(), "dddd • MMM d");
            }

            result.push({
                isHeader: true,
                isEmptyNotice: false,
                id: "hdr_" + k,
                title: headerTitle,
                dateKey: k,
                time: "",
                all_day: false,
                location: "",
                is_local: false,
                meetUrl: ""
            });

            for (let i = 0; i < evs.length; i++) {
                const ev = evs[i];
                result.push({
                    isHeader: false,
                    isEmptyNotice: false,
                    id: ev.id || (k + "_" + i),
                    title: ev.title || "Untitled Event",
                    time: ev.time || "All day",
                    all_day: !!ev.all_day,
                    location: ev.location || "",
                    is_local: !!ev.is_local,
                    dateKey: k,
                    meetUrl: root.extractMeetingUrl((ev.location || "") + " " + (ev.description || ""))
                });
            }

            addedDays++;
            if (addedDays >= 14) break;
        }

        return result;
    }

    readonly property int totalVisibleEventsCount: {
        let count = 0;
        for (let item of flatAgendaItems) {
            if (!item.isHeader && !item.isEmptyNotice) count++;
        }
        return count;
    }

    function commitAddEvent(titleRaw: string, timeRaw: string): void {
        let title = (titleRaw || "").trim();
        let time = (timeRaw || "").trim();
        if (!title) return;

        if (!time) {
            const timeMatch = title.match(/\b((?:[01]?\d|2[0-3]):[0-5]\d|[1-9]\s*(?:am|pm)|1[0-2]\s*(?:am|pm))\b/i);
            if (timeMatch) {
                time = timeMatch[1].trim();
                title = title.replace(timeMatch[0], "").trim().replace(/\s+at\s*$/i, "").trim();
            } else {
                time = "All day";
            }
        }

        const isAllDay = time.toLowerCase() === "all day" || time.toLowerCase() === "allday";
        const targetKey = root.selectedDateKey || root.effectiveDateKey;
        const newId = "local_" + Date.now();

        // 1. Instant local reactive UI update
        const newEv = {
            id: newId,
            title: title,
            time: time,
            all_day: isAllDay,
            location: "",
            is_local: true
        };
        const currentList = root.gcalEvents[targetKey] || [];
        const updatedList = currentList.concat([newEv]);
        let copy = Object.assign({}, root.gcalEvents);
        copy[targetKey] = updatedList;
        root.gcalEvents = copy;

        // 2. Persist to storage via background Python syncer
        const payload = JSON.stringify({
            date: targetKey,
            title: title,
            time: time
        });
        Quickshell.execDetached(["python3", Paths.home + "/.config/caelestia/scripts/sync-gcal.py", "--add-local", payload]);

        // 3. Reset state & notify
        root.isAddingEvent = false;
        Toaster.toast("Event Added", `${title} • ${time}`, "event_available");
    }

    function deleteLocalEvent(dateKey: string, evId: string, evTitle: string): void {
        // 1. Instant local reactive UI update
        let copy = Object.assign({}, root.gcalEvents);
        if (copy[dateKey]) {
            copy[dateKey] = copy[dateKey].filter(e => (evId ? e.id !== evId : e.title !== evTitle));
            if (copy[dateKey].length === 0) {
                delete copy[dateKey];
            }
            root.gcalEvents = copy;
        }

        // 2. Persist to storage
        const payload = JSON.stringify({
            date: dateKey,
            id: evId,
            title: evTitle
        });
        Quickshell.execDetached(["python3", Paths.home + "/.config/caelestia/scripts/sync-gcal.py", "--delete-local", payload]);

        Toaster.toast("Event Deleted", evTitle, "delete");
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

    anchors.left: parent.left
    anchors.right: parent.right
    implicitHeight: 390

    acceptedButtons: Qt.MiddleButton
    onClicked: {
        root.screenState.dashboardDate = new Date();
        root.selectedDateKey = "";
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
        id: inner
        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.small

        // Top Header Bar
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            RowLayout {
                spacing: Tokens.spacing.extraSmall
                Layout.alignment: Qt.AlignVCenter

                StyledText {
                    text: "Calendar"
                    font: Tokens.font.title.small
                    color: Colours.palette.m3primary
                }

                StyledText {
                    text: !root.gcalConfigured ? "• Local Only" : ""
                    font: Tokens.font.label.small
                    color: Colours.palette.m3outline
                    visible: text !== ""
                }
            }

            Item { Layout.fillWidth: true }

            // Filter status / Reset button
            IconButton {
                icon: "event_upcoming"
                isRound: true
                type: IconButton.Tonal
                font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                padding: Tokens.padding.extraSmall
                visible: root.selectedDateKey !== ""
                onClicked: {
                    root.selectedDateKey = "";
                    root.isAddingEvent = false;
                }
            }

            IconButton {
                icon: "today"
                isRound: true
                type: IconButton.Text
                font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                padding: Tokens.padding.extraSmall
                onClicked: {
                    root.screenState.dashboardDate = new Date();
                    root.selectedDateKey = "";
                }
            }

            IconButton {
                icon: root.isAddingEvent ? "remove" : "add"
                isRound: true
                type: root.isAddingEvent ? IconButton.Tonal : IconButton.Text
                font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                padding: Tokens.padding.extraSmall
                onClicked: root.isAddingEvent = !root.isAddingEvent
            }

            IconButton {
                id: syncBtn
                icon: "sync"
                isRound: true
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
        }

        // Inline Quick Add Bar
        Rectangle {
            id: quickAddBox
            Layout.fillWidth: true
            visible: root.isAddingEvent
            radius: Tokens.rounding.small
            color: Colours.palette.m3surfaceContainer
            border.width: 1
            border.color: Colours.palette.m3outlineVariant
            implicitHeight: quickAddLayout.implicitHeight + Tokens.padding.small * 2

            onVisibleChanged: {
                if (visible) {
                    eventTitleInput.text = "";
                    eventTimeInput.text = "";
                    Qt.callLater(() => eventTitleInput.forceActiveFocus());
                }
            }

            RowLayout {
                id: quickAddLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                spacing: Tokens.spacing.small

                StyledTextField {
                    id: eventTitleInput
                    Layout.fillWidth: true
                    placeholderText: "Event title (e.g. Design review 14:00)..."
                    placeholderFloats: false
                    verticalPadding: Tokens.padding.extraSmall
                    font: Tokens.font.body.small
                    onAccepted: root.commitAddEvent(eventTitleInput.text, eventTimeInput.text)
                    Keys.onEscapePressed: root.isAddingEvent = false
                }

                StyledTextField {
                    id: eventTimeInput
                    Layout.preferredWidth: 80
                    placeholderText: "14:00"
                    placeholderFloats: false
                    verticalPadding: Tokens.padding.extraSmall
                    font: Tokens.font.body.small
                    onAccepted: root.commitAddEvent(eventTitleInput.text, eventTimeInput.text)
                    Keys.onEscapePressed: root.isAddingEvent = false
                }

                IconButton {
                    icon: "check"
                    isRound: true
                    type: IconButton.Filled
                    font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                    padding: Tokens.padding.extraSmall / 2
                    onClicked: root.commitAddEvent(eventTitleInput.text, eventTimeInput.text)
                }

                IconButton {
                    icon: "close"
                    isRound: true
                    type: IconButton.Text
                    font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                    padding: Tokens.padding.extraSmall / 2
                    onClicked: root.isAddingEvent = false
                }
            }
        }

        // Main Side-by-Side Split Body
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacing.medium

            // LEFT PANE: Mini Month Navigator
            ColumnLayout {
                Layout.preferredWidth: 235
                Layout.fillHeight: true
                spacing: 2

                // Month Switcher
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    IconButton {
                        isRound: true
                        icon: "chevron_left"
                        type: IconButton.Text
                        font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                        padding: Tokens.padding.extraSmall
                        onClicked: root.screenState.dashboardDate = new Date(root.nonAnimCurrYear, root.nonAnimCurrMonth - 1, 1)
                    }

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: monthYearDisplay.implicitHeight + Tokens.padding.extraSmall

                        StateLayer {
                            color: Colours.palette.m3primary
                            radius: Tokens.rounding.small
                            onClicked: {
                                root.screenState.dashboardDate = new Date();
                                root.selectedDateKey = "";
                            }
                        }

                        StyledText {
                            id: monthYearDisplay
                            anchors.centerIn: parent
                            text: grid.title
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.title.builders.small.capitalisation(Font.Capitalize).build()
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

                // Days of week header
                DayOfWeekRow {
                    id: daysRow
                    Layout.fillWidth: true
                    locale: grid.locale

                    delegate: StyledText {
                        required property var model
                        horizontalAlignment: Text.AlignHCenter
                        text: model.shortName
                        font: Tokens.font.label.small
                        color: (model.day === 0 || model.day === 6) ? Colours.palette.m3tertiary : Colours.palette.m3onSurfaceVariant
                    }
                }

                // Month Grid
                MonthGrid {
                    id: grid
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    month: root.currMonth
                    year: root.currYear
                    spacing: 1
                    locale: Tr.locale

                    delegate: Item {
                        id: dayItem
                        required property var model

                        implicitWidth: implicitHeight
                        implicitHeight: text.implicitHeight + 14

                        readonly property string dayKey: root.dateToKey(dayItem.model.date)
                        readonly property var events: root.gcalEvents[dayKey] || []
                        readonly property int eventsCount: events.length
                        readonly property bool isSelected: root.selectedDateKey === dayKey
                        readonly property bool isToday: dayItem.model.today

                        // Selection / Today Background Pill
                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height) - 2
                            height: width
                            radius: width / 2
                            color: dayItem.isToday ? Colours.palette.m3primary : Colours.palette.m3primaryContainer
                            visible: dayItem.isToday || dayItem.isSelected
                            opacity: dayItem.isSelected && !dayItem.isToday ? 0.75 : 1
                            Behavior on opacity { Anim { type: Anim.FastEffects } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.isAddingEvent = false;
                                if (root.selectedDateKey === dayItem.dayKey) {
                                    root.selectedDateKey = "";
                                } else {
                                    root.selectedDateKey = dayItem.dayKey;
                                }
                            }
                        }

                        StyledText {
                            id: text
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -3
                            horizontalAlignment: Text.AlignHCenter
                            text: grid.locale.toString(dayItem.model.day)
                            color: {
                                if (dayItem.isToday) return Colours.palette.m3onPrimary;
                                if (dayItem.isSelected) return Colours.palette.m3onPrimaryContainer;
                                const dow = dayItem.model.date.getDay();
                                if (dow === 0 || dow === 6) return Colours.palette.m3tertiary;
                                return Colours.palette.m3onSurface;
                            }
                            opacity: dayItem.isToday || dayItem.model.month === grid.month ? 1 : 0.35
                            font: Tokens.font.body.small
                        }

                        // Event Density Indicator Dots (1, 2, or 3 dots)
                        Row {
                            anchors.top: text.bottom
                            anchors.topMargin: 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 2
                            visible: dayItem.eventsCount > 0

                            Repeater {
                                model: Math.min(dayItem.eventsCount, 3)
                                Rectangle {
                                    width: 3
                                    height: 3
                                    radius: 1.5
                                    color: dayItem.isToday ? Colours.palette.m3onPrimary : Colours.palette.m3tertiary
                                }
                            }
                        }
                    }
                }
            }

            // VERTICAL DIVIDER
            Rectangle {
                width: 1
                Layout.fillHeight: true
                color: Colours.palette.m3outlineVariant
                opacity: 0.35
            }

            // RIGHT PANE: Multi-Day Scrollable Agenda
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacing.extraSmall

                // Agenda Section Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: root.selectedDateKey !== "" ? ("Day • " + root.formatDateStr(root.selectedDateKey)) : "Upcoming Agenda"
                        font: Tokens.font.title.small
                        color: Colours.palette.m3onSurface
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: `${root.totalVisibleEventsCount} event${root.totalVisibleEventsCount === 1 ? "" : "s"}`
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }

                // Scrollable Agenda List
                ListView {
                    id: agendaView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Tokens.spacing.extraSmall
                    boundsBehavior: Flickable.StopAtBounds

                    model: root.flatAgendaItems

                    StyledScrollBar.vertical: StyledScrollBar {
                        flickable: agendaView
                    }

                    delegate: Item {
                        id: delegateRoot
                        required property var modelData

                        width: agendaView.width - Tokens.padding.small
                        implicitHeight: modelData.isHeader ? headerCol.implicitHeight : (modelData.isEmptyNotice ? emptyText.implicitHeight + 8 : eventBox.implicitHeight)

                        // 1. SECTION HEADER DELEGATE
                        ColumnLayout {
                            id: headerCol
                            width: parent.width
                            visible: delegateRoot.modelData.isHeader
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small

                                StyledText {
                                    text: delegateRoot.modelData.title || ""
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3primary
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Colours.palette.m3outlineVariant
                                opacity: 0.25
                            }
                        }

                        // 2. EMPTY NOTICE DELEGATE
                        StyledText {
                            id: emptyText
                            width: parent.width
                            visible: delegateRoot.modelData.isEmptyNotice
                            text: delegateRoot.modelData.title || "Nothing scheduled"
                            font: Tokens.font.body.builders.small.italic(true).build()
                            color: Colours.palette.m3outline
                        }

                        // 3. EVENT ROW DELEGATE
                        CustomMouseArea {
                            id: eventBox
                            width: parent.width
                            visible: !delegateRoot.modelData.isHeader && !delegateRoot.modelData.isEmptyNotice
                            implicitHeight: rowContent.implicitHeight + 6

                            RowLayout {
                                id: rowContent
                                anchors.fill: parent
                                spacing: Tokens.spacing.small

                                // Accent color strip
                                Rectangle {
                                    width: 3
                                    Layout.preferredHeight: textColumn.implicitHeight
                                    radius: 1.5
                                    color: delegateRoot.modelData.is_local ? Colours.palette.m3secondary : Colours.palette.m3tertiary
                                }

                                ColumnLayout {
                                    id: textColumn
                                    Layout.fillWidth: true
                                    spacing: 1

                                    StyledText {
                                        text: delegateRoot.modelData.title || "Untitled"
                                        font: Tokens.font.body.small
                                        color: Colours.palette.m3onSurface
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Tokens.spacing.extraSmall

                                        StyledText {
                                            text: {
                                                let t = delegateRoot.modelData.time || "";
                                                if (delegateRoot.modelData.location) {
                                                    t = t ? (t + " • " + delegateRoot.modelData.location) : delegateRoot.modelData.location;
                                                }
                                                return t;
                                            }
                                            font: Tokens.font.label.small
                                            color: Colours.palette.m3onSurfaceVariant
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        // Meeting Link Chip [Join]
                                        Rectangle {
                                            visible: delegateRoot.modelData.meetUrl !== ""
                                            radius: Tokens.rounding.extraSmall
                                            color: Colours.palette.m3primaryContainer
                                            implicitWidth: meetChipText.implicitWidth + 12
                                            implicitHeight: meetChipText.implicitHeight + 4

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Qt.openUrlExternally(delegateRoot.modelData.meetUrl)
                                            }

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 2
                                                StyledText {
                                                    text: "Join"
                                                    font: Tokens.font.label.small
                                                    color: Colours.palette.m3onPrimaryContainer
                                                    id: meetChipText
                                                }
                                            }
                                        }
                                    }
                                }

                                // Delete Button for Local Events
                                IconButton {
                                    icon: "delete"
                                    isRound: true
                                    type: IconButton.Text
                                    font: Tokens.font.icon.builders.small.weight(Font.Normal).build()
                                    padding: Tokens.padding.extraSmall / 2
                                    visible: delegateRoot.modelData.is_local
                                    onClicked: root.deleteLocalEvent(delegateRoot.modelData.dateKey, delegateRoot.modelData.id, delegateRoot.modelData.title)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
