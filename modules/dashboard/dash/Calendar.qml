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

    property var gcalEvents: ({})
    property bool gcalConfigured: false
    property string selectedDateKey: ""
    property bool isAddingEvent: false
    onIsAddingEventChanged: root.screenState.dashboardNeedsFocus = root.isAddingEvent

    readonly property string todayKey: dateToKey(Time.date)
    readonly property string effectiveDateKey: selectedDateKey !== "" ? selectedDateKey : todayKey

    function formatAgendaDate(key: string): string {
        const parts = key.split("-").map(Number);
        if (parts.length !== 3) return key;
        return new Date(parts[0], parts[1] - 1, parts[2]).toLocaleDateString(Qt.locale(), "ddd, MMM d");
    }

    readonly property var agendaItems: {
        const today = root.todayKey;
        const parts = today.split("-").map(Number);
        const tomorrow = new Date(parts[0], parts[1] - 1, parts[2] + 1);
        const tomorrowKey = root.dateToKey(tomorrow);
        const end = new Date(parts[0], parts[1] - 1, parts[2] + 14);
        const endKey = root.dateToKey(end);
        const keys = root.selectedDateKey ? [root.selectedDateKey]
            : [today].concat(Object.keys(root.gcalEvents).filter(key => key > today && key < endKey).sort());
        const result = [];
        for (const key of keys) {
            const events = (root.gcalEvents[key] || []).slice().sort((a, b) =>
                (Number(!!a.all_day) - Number(!!b.all_day)) * -1 || String(a.time || "").localeCompare(String(b.time || "")));
            if (events.length === 0 && key !== today && key !== root.selectedDateKey)
                continue;
            const allDayCount = events.filter(event =>
                event.all_day || !String(event.time || "").trim() || /^all\s*day$/i.test(String(event.time).trim())).length;
            const dayTitle = key === today ? "TODAY" : key === tomorrowKey ? "TOMORROW" : root.formatAgendaDate(key);
            const countLabel = events.length === 0 ? "" :
                allDayCount === events.length ? ` · ${events.length} all-day ${events.length === 1 ? "event" : "events"}` :
                ` · ${events.length} ${events.length === 1 ? "event" : "events"}${allDayCount ? `, ${allDayCount} all day` : ""}`;
            result.push({ kind: "heading", title: dayTitle + countLabel });
            if (events.length === 0)
                result.push({ kind: "empty", title: key === today ? "No events today" : "No events scheduled" });
            for (const event of events) {
                const time = String(event.time || "").trim();
                const isAllDay = event.all_day || !time || /^all\s*day$/i.test(time);
                result.push({ kind: "event", title: event.title || "Untitled Event",
                    time: isAllDay ? "" : time, location: event.location || "" });
            }
        }
        return result;
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
    implicitHeight: 360

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
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacing.medium

            ColumnLayout {
                Layout.preferredWidth: 330
                Layout.maximumWidth: 330
                Layout.fillHeight: true
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
                    font: Tokens.font.title.builders.medium.capitalisation(Font.Capitalize).build()
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
                font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                color: (model.day === 0 || model.day === 6) ? Colours.palette.m3tertiary : Colours.palette.m3onSurface
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
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
                locale: Tr.locale

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
                        font: Tokens.font.body.medium
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


            }

            Rectangle {
                Layout.fillHeight: true
                implicitWidth: 1
                color: Qt.alpha(Colours.palette.m3outlineVariant, 0.45)
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacing.extraSmall

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        text: root.selectedDateKey ? root.formatAgendaDate(root.selectedDateKey) : "Upcoming · 14 days"
                        font: Tokens.font.title.small
                        color: Colours.palette.m3onSurface
                        elide: Text.ElideRight
                    }

                    IconButton {
                        visible: root.selectedDateKey !== ""
                        icon: "close"
                        isRound: true
                        type: IconButton.Text
                        padding: Tokens.padding.extraSmall
                        onClicked: {
                            root.selectedDateKey = "";
                            root.isAddingEvent = false;
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
                        icon: root.isAddingEvent ? "remove" : "add"
                        isRound: true
                        type: root.isAddingEvent ? IconButton.Tonal : IconButton.Text
                        padding: Tokens.padding.extraSmall
                        ToolTip.visible: hovered
                        ToolTip.text: root.isAddingEvent ? "Cancel new event" : "Add event"
                        onClicked: root.isAddingEvent = !root.isAddingEvent
                    }
                }

                Rectangle {
                    id: quickAddBox
                    Layout.fillWidth: true
                    visible: root.isAddingEvent
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3surfaceContainerHigh
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
                        spacing: Tokens.spacing.extraSmall

                        StyledTextField {
                            id: eventTitleInput
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            placeholderText: "Event title"
                            placeholderFloats: false
                            verticalPadding: Tokens.padding.extraSmall
                            font: Tokens.font.body.small
                            onAccepted: root.commitAddEvent(text, eventTimeInput.text)
                            Keys.onEscapePressed: root.isAddingEvent = false
                        }

                        StyledTextField {
                            id: eventTimeInput
                            Layout.preferredWidth: 66
                            placeholderText: "14:00"
                            placeholderFloats: false
                            verticalPadding: Tokens.padding.extraSmall
                            font: Tokens.font.body.small
                            onAccepted: root.commitAddEvent(eventTitleInput.text, text)
                            Keys.onEscapePressed: root.isAddingEvent = false
                        }

                        IconButton {
                            icon: "check"
                            isRound: true
                            type: IconButton.Filled
                            padding: 2
                            onClicked: root.commitAddEvent(eventTitleInput.text, eventTimeInput.text)
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: agendaView
                        anchors.fill: parent
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        spacing: Tokens.spacing.extraSmall
                        model: root.agendaItems

                        HoverHandler {
                            id: agendaHover
                        }

                        StyledScrollBar.vertical: StyledScrollBar {
                            flickable: agendaView
                            policy: agendaHover.hovered ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                        }

                        Connections {
                            target: root
                            function onSelectedDateKeyChanged() { agendaView.positionViewAtBeginning(); }
                        }

                        delegate: Item {
                            id: agendaItem
                            required property var modelData
                            width: agendaView.width - 10
                            implicitHeight: modelData.kind === "heading" ? heading.implicitHeight + 12
                                : modelData.kind === "empty" ? emptyText.implicitHeight + 12
                                : eventContent.implicitHeight + 10

                            StyledText {
                                id: heading
                                anchors.bottom: parent.bottom
                                visible: agendaItem.modelData.kind === "heading"
                                text: agendaItem.modelData.title || ""
                                font: Tokens.font.label.builders.small.weight(Font.Bold).build()
                                color: Colours.palette.m3primary
                            }

                            StyledText {
                                id: emptyText
                                anchors.verticalCenter: parent.verticalCenter
                                visible: agendaItem.modelData.kind === "empty"
                                width: parent.width
                                text: agendaItem.modelData.title || ""
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurfaceVariant
                                wrapMode: Text.WordWrap
                            }

                            RowLayout {
                                id: eventContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: agendaItem.modelData.kind === "event"
                                spacing: Tokens.spacing.small

                                Rectangle {
                                    implicitWidth: 3
                                    Layout.minimumWidth: 3
                                    Layout.preferredHeight: eventText.implicitHeight
                                    radius: 2
                                    color: Colours.palette.m3tertiary
                                }

                                ColumnLayout {
                                    id: eventText
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 1

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: agendaItem.modelData.title || "Untitled Event"
                                        font: Tokens.font.body.small
                                        color: Colours.palette.m3onSurface
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        visible: text !== ""
                                        text: {
                                            const item = agendaItem.modelData;
                                            return [item.time, item.location].filter(Boolean).join(" · ");
                                        }
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3onSurfaceVariant
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 18
                        visible: agendaView.contentHeight > agendaView.height && !agendaView.atYEnd
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.alpha(Colours.tPalette.m3surfaceContainer, 0) }
                            GradientStop { position: 1; color: Colours.tPalette.m3surfaceContainer }
                        }
                    }
                }
            }
        }
    }
}
