pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import M3Shapes
import Caelestia.Config
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

    readonly property string effectiveDateKey: selectedDateKey !== "" ? selectedDateKey : dateToKey(new Date())
    readonly property var currentDayEvents: gcalEvents[effectiveDateKey] || []

    readonly property var nextUpcomingEvent: {
        const todayStr = root.dateToKey(new Date());
        const keys = Object.keys(root.gcalEvents).filter(k => k >= todayStr).sort();
        if (keys.length > 0) {
            const nextDate = keys[0];
            const evs = root.gcalEvents[nextDate];
            if (evs && evs.length > 0) {
                return { dateKey: nextDate, event: evs[0] };
            }
        }
        return null;
    }

    function dateToKey(d: var): string {
        if (!d) return "";
        const yr = d.getFullYear();
        const mo = String(d.getMonth() + 1).padStart(2, "0");
        const dy = String(d.getDate()).padStart(2, "0");
        return `${yr}-${mo}-${dy}`;
    }

    function getEventsFor(d: var): var {
        const k = dateToKey(d);
        return root.gcalEvents[k] || [];
    }

    function commitAddEvent(titleRaw: string, timeRaw: string): void {
        let title = (titleRaw || "").trim();
        let time = (timeRaw || "").trim();
        if (!title) return;

        // Smart extract time from title if time field is empty
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

        // 1. Instant local reactive UI update
        const newEv = {
            title: title,
            time: time,
            all_day: isAllDay,
            location: ""
        };
        const currentList = root.gcalEvents[targetKey] || [];
        const updatedList = currentList.concat([newEv]);
        let copy = Object.assign({}, root.gcalEvents);
        copy[targetKey] = updatedList;
        root.gcalEvents = copy;

        // 2. Persist to ~/.config/caelestia/local_events.json & ~/.cache/caelestia/gcal.json
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
                console.log("[Calendar] FileView loaded " + Object.keys(root.gcalEvents).length + " dates");
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
                console.log("[Calendar] Component.onCompleted loaded " + Object.keys(root.gcalEvents).length + " dates");
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
    implicitHeight: inner.implicitHeight + inner.anchors.margins * 2

    acceptedButtons: Qt.MiddleButton
    onClicked: root.screenState.dashboardDate = new Date()

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
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.extraSmall

        RowLayout {
            id: monthNavigationRow

            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            IconButton {
                isRound: true
                icon: "chevron_left"
                type: IconButton.Text
                font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                padding: Tokens.padding.small
                onClicked: root.screenState.dashboardDate = new Date(root.nonAnimCurrYear, root.nonAnimCurrMonth - 1, 1)
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                implicitWidth: monthYearDisplay.implicitWidth + Tokens.padding.large * 2
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
                    text: grid.title
                    color: Colours.palette.m3primary
                    font: Tokens.font.title.builders.small.capitalisation(Font.Capitalize).build()
                }
            }

            IconButton {
                id: syncBtn
                isRound: true
                icon: "sync"
                type: IconButton.Text
                font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                padding: Tokens.padding.small
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
                isRound: true
                icon: "chevron_right"
                type: IconButton.Text
                font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                padding: Tokens.padding.small
                onClicked: root.screenState.dashboardDate = new Date(root.nonAnimCurrYear, root.nonAnimCurrMonth + 1, 1)
            }
        }

        DayOfWeekRow {
            id: daysRow

            Layout.fillWidth: true
            locale: grid.locale

            delegate: StyledText {
                required property var model

                horizontalAlignment: Text.AlignHCenter
                text: model.shortName
                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                color: (model.day === 0 || model.day === 6) ? Colours.palette.m3tertiary : Colours.palette.m3onSurface
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: grid.implicitHeight

            opacity: root.animOpacity
            transform: Translate {
                x: root.animTranslate
            }

            MonthGrid {
                id: grid

                month: root.currMonth
                year: root.currYear

                anchors.fill: parent

                spacing: 3
                locale: Qt.locale()

                delegate: Item {
                    id: dayItem

                    required property var model

                    implicitWidth: implicitHeight
                    implicitHeight: text.implicitHeight + Tokens.padding.small + 4

                    readonly property string dayKey: root.dateToKey(dayItem.model.date)
                    readonly property var events: root.gcalEvents[dayKey] || []
                    readonly property bool hasEvents: events.length > 0
                    readonly property bool isSelected: root.selectedDateKey === dayKey

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) - 4
                        height: width
                        radius: width / 2
                        color: Colours.palette.m3primaryContainer
                        opacity: dayItem.isSelected && !dayItem.model.today ? 0.7 : 0
                        Behavior on opacity {
                            Anim { type: Anim.FastEffects }
                        }
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
                        anchors.verticalCenterOffset: -2

                        horizontalAlignment: Text.AlignHCenter
                        text: grid.locale.toString(dayItem.model.day)
                        color: {
                            if (dayItem.isSelected && !dayItem.model.today)
                                return Colours.palette.m3onPrimaryContainer;
                            const dayOfWeek = dayItem.model.date.getDay();
                            if (dayOfWeek === 0 || dayOfWeek === 6)
                                return Colours.palette.m3tertiary;

                            return Colours.palette.m3onSurfaceVariant;
                        }
                        opacity: dayItem.model.today || dayItem.model.month === grid.month ? 1 : 0.4
                        font: Tokens.font.body.small
                    }

                    Rectangle {
                        id: dot
                        anchors.top: text.bottom
                        anchors.topMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 4
                        height: 4
                        radius: 2
                        color: dayItem.model.today ? Colours.palette.m3onPrimary : Colours.palette.m3tertiary
                        visible: dayItem.hasEvents
                    }
                }
            }

            MaterialShape {
                id: todayIndicator

                readonly property Item todayItem: grid.contentItem.children.find(c => c.model.today) ?? null
                property Item today

                onTodayItemChanged: {
                    if (todayItem)
                        today = todayItem;
                }

                x: today ? today.x + (today.width - implicitWidth) / 2 : 0
                y: today ? today.y - Tokens.padding.extraSmall - 1 : 0

                implicitSize: today ? Math.max(today.implicitWidth, today.implicitHeight) + Tokens.padding.extraSmall * 2 : 0
                shape: MaterialShape.Sunny

                clip: true
                color: Colours.palette.m3primary

                opacity: todayItem ? 1 : 0

                Colouriser {
                    x: -todayIndicator.x
                    y: -todayIndicator.y

                    implicitWidth: grid.width
                    implicitHeight: grid.height

                    source: grid
                    sourceColor: Colours.palette.m3onSurface
                    colorizationColor: Colours.palette.m3onPrimary
                }
            }
        }

        // Event List / Agenda for selected day, today, or upcoming
        ColumnLayout {
            id: agendaSection

            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall
            visible: root.selectedDateKey !== "" || root.currentDayEvents.length > 0 || (root.gcalConfigured && root.nextUpcomingEvent !== null)

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Colours.palette.m3outlineVariant
                opacity: 0.35
                Layout.topMargin: Tokens.spacing.extraSmall
                Layout.bottomMargin: Tokens.spacing.extraSmall / 2
            }

            // Day Agenda Header (when a date is selected or today has events)
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small
                visible: root.selectedDateKey !== "" || root.currentDayEvents.length > 0

                StyledText {
                    text: {
                        const targetKey = root.effectiveDateKey;
                        const parts = targetKey.split("-");
                        if (parts.length < 3) return "";
                        const d = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));
                        const today = new Date();
                        const isToday = d.getDate() === today.getDate() &&
                                        d.getMonth() === today.getMonth() &&
                                        d.getFullYear() === today.getFullYear();
                        const dateStr = d.toLocaleDateString(Qt.locale(), "ddd, MMM d");
                        return isToday ? ("Today • " + dateStr) : dateStr;
                    }
                    font: Tokens.font.title.small
                    color: Colours.palette.m3onSurface
                    Layout.fillWidth: true
                }

                IconButton {
                    icon: root.isAddingEvent ? "remove" : "add"
                    isRound: true
                    type: root.isAddingEvent ? IconButton.Tonal : IconButton.Text
                    font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                    padding: Tokens.padding.extraSmall
                    visible: root.selectedDateKey !== "" || root.currentDayEvents.length === 0
                    onClicked: {
                        root.isAddingEvent = !root.isAddingEvent;
                    }
                }

                IconButton {
                    icon: "close"
                    isRound: true
                    type: IconButton.Text
                    font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                    padding: Tokens.padding.extraSmall
                    visible: root.selectedDateKey !== ""
                    onClicked: {
                        root.selectedDateKey = "";
                        root.isAddingEvent = false;
                    }
                }
            }

            // Inline Quick-Add Mini-Input
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
                        placeholderText: "Event title..."
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

            // Events for the selected day or today
            Repeater {
                model: (root.selectedDateKey !== "" || root.currentDayEvents.length > 0) ? root.currentDayEvents : []

                delegate: RowLayout {
                    id: eventItem
                    required property var modelData

                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Rectangle {
                        width: 3
                        Layout.preferredHeight: contentCol.implicitHeight
                        radius: 1.5
                        color: Colours.palette.m3tertiary
                    }

                    ColumnLayout {
                        id: contentCol
                        Layout.fillWidth: true
                        spacing: 1

                        StyledText {
                            text: eventItem.modelData.title || "Untitled Event"
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurface
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        StyledText {
                            text: {
                                let t = eventItem.modelData.time || "";
                                if (eventItem.modelData.location) {
                                    t = t ? (t + " • " + eventItem.modelData.location) : eventItem.modelData.location;
                                }
                                return t;
                            }
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                            elide: Text.ElideRight
                            visible: text !== ""
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            // Empty state for explicitly selected day with 0 events
            StyledText {
                visible: root.currentDayEvents.length === 0 && root.selectedDateKey !== "" && !root.isAddingEvent
                text: !root.gcalConfigured ? "Google Calendar not linked yet\nPaste your private iCal link into ~/.config/caelestia/calendar_url.txt" : "No events scheduled"
                horizontalAlignment: Text.AlignHCenter
                font: Tokens.font.body.small
                color: Colours.palette.m3outline
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.padding.extraSmall
                Layout.bottomMargin: Tokens.padding.extraSmall
            }

            // Next Upcoming Event block (when today has no events & no date selected)
            ColumnLayout {
                id: upcomingBlock
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall
                visible: root.selectedDateKey === "" && root.currentDayEvents.length === 0 && root.nextUpcomingEvent !== null

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: "Upcoming"
                        font: Tokens.font.title.small
                        color: Colours.palette.m3onSurface
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: {
                            if (!root.nextUpcomingEvent) return "";
                            const parts = root.nextUpcomingEvent.dateKey.split("-");
                            const d = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));
                            return d.toLocaleDateString(Qt.locale(), "MMM d, yyyy");
                        }
                        font: Tokens.font.label.small
                        color: Colours.palette.m3primary
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Rectangle {
                        width: 3
                        Layout.preferredHeight: upcomingContentCol.implicitHeight
                        radius: 1.5
                        color: Colours.palette.m3tertiary
                    }

                    ColumnLayout {
                        id: upcomingContentCol
                        Layout.fillWidth: true
                        spacing: 1

                        StyledText {
                            text: root.nextUpcomingEvent ? (root.nextUpcomingEvent.event.title || "Untitled Event") : ""
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurface
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        StyledText {
                            text: {
                                if (!root.nextUpcomingEvent) return "";
                                let t = root.nextUpcomingEvent.event.time || "";
                                if (root.nextUpcomingEvent.event.location) {
                                    t = t ? (t + " • " + root.nextUpcomingEvent.event.location) : root.nextUpcomingEvent.event.location;
                                }
                                return t;
                            }
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                            elide: Text.ElideRight
                            visible: text !== ""
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
    }
}
