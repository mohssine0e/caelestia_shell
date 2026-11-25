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
            // Show fixed-time events first so scheduled slots stay visible above all-day tasks.
            const sortedEvents = rawEvents.slice().sort((a, b) => {
                const aAllDay = root.isAllDayEvent(a);
                const bAllDay = root.isAllDayEvent(b);
                if (aAllDay !== bAllDay)
                    return aAllDay ? 1 : -1;
                return String(a.time || "").localeCompare(String(b.time || ""));
            });

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

    readonly property var selectedDayEvents: {
        if (!root.selectedDateKey)
            return [];
        const list = (root.gcalEvents[root.selectedDateKey] || []).slice();
        return list.sort((a, b) => {
            const aAllDay = root.isAllDayEvent(a);
            const bAllDay = root.isAllDayEvent(b);
            if (aAllDay !== bAllDay)
                return aAllDay ? 1 : -1;
            return String(a.time || "").localeCompare(String(b.time || ""));
        });
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

    function commitAddEvent(titleRaw: string, timeRaw: string): void {
        let title = (titleRaw || "").trim();
        let time = (timeRaw || "").trim();
        if (!title)
            return;

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
        const copy = Object.assign({}, root.gcalEvents);
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

    anchors.left: parent.left
    anchors.right: parent.right
    implicitHeight: 492

    acceptedButtons: Qt.MiddleButton
    onClicked: {
        root.screenState.dashboardDate = new Date();
        root.selectedDateKey = "";
        root.isAddingEvent = false;
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
                        root.isAddingEvent = !root.isAddingEvent;
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

                    x: index * (weekdayHeader.width / 7)
                    width: weekdayHeader.width / 7
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

        // 6x7 monthly calendar sheet with crisp 1px grid dividers and glowing Today box.
        Item {
            id: gridContainer

            Layout.fillWidth: true
            Layout.fillHeight: true

            readonly property real cellW: width / 7
            readonly property real cellH: height / 6
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

            // Soft outer glow behind Today's box
            Item {
                id: todayGlowLayer

                readonly property var todayCell: root.monthCells.find(c => c.isToday) ?? null
                visible: todayCell !== null
                x: todayCell ? todayCell.col * gridContainer.cellW : 0
                y: todayCell ? todayCell.row * gridContainer.cellH : 0
                width: gridContainer.cellW
                height: gridContainer.cellH
                z: 4

                RectangularShadow {
                    anchors.fill: todayBox
                    radius: todayBox.radius
                    color: Qt.alpha(Colours.palette.m3primary, 0.48)
                    blur: 16
                    spread: 1
                }

                Rectangle {
                    id: todayBox

                    anchors.fill: parent
                    radius: Tokens.rounding.small
                    border.width: 2
                    border.color: Colours.palette.m3primary
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: Qt.alpha(Colours.palette.m3primary, 0.26)
                        }
                        GradientStop {
                            position: 1.0
                            color: Qt.alpha(Colours.palette.m3primary, 0.11)
                        }
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
                    readonly property bool hasOverflow: eventCount > 2
                    readonly property var visibleEvents: hasOverflow ? events.slice(0, 1) : events.slice(0, 2)

                    x: col * gridContainer.cellW
                    y: row * gridContainer.cellH
                    width: gridContainer.cellW
                    height: gridContainer.cellH
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

                    // Centered day number at top of cell
                    StyledText {
                        id: dayNumberText

                        anchors.top: parent.top
                        anchors.topMargin: 5
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Tr.locale.toString(cellItem.modelData.day)
                        font: cellItem.isToday ? Tokens.font.body.builders.medium.weight(Font.DemiBold).build() : Tokens.font.body.small
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

                    // "Today" micro-label at top-right of Today cell
                    StyledText {
                        visible: cellItem.isToday
                        anchors.top: parent.top
                        anchors.topMargin: 6
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        text: Tr.tr("Today")
                        font: Tokens.font.label.small
                        color: Qt.alpha(Colours.palette.m3primary, 0.92)
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
                        anchors.topMargin: 4
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
                                readonly property string timeStr: root.shortEventTime(modelData)

                                width: parent.width
                                height: 18
                                radius: Tokens.rounding.extraSmall
                                color: isAllDay ? Qt.alpha(Colours.palette.m3onSurface, 0.08) : Qt.alpha(Colours.palette.term4, 0.24)
                                border.width: 1
                                border.color: isAllDay ? Qt.alpha(Colours.palette.m3outlineVariant, 0.35) : Qt.alpha(Colours.palette.term4, 0.42)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    anchors.rightMargin: 4
                                    spacing: 3

                                    StyledText {
                                        visible: !eventPill.isAllDay && eventPill.timeStr !== ""
                                        text: eventPill.timeStr
                                        font: Tokens.font.label.builders.small.weight(Font.DemiBold).build()
                                        color: Colours.palette.term12
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: eventPill.modelData.title || Tr.tr("Untitled Event")
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3onSurface
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        // Overflow indicator pill when a day has 3+ events
                        Rectangle {
                            visible: cellItem.hasOverflow
                            width: parent.width
                            height: 17
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
                                text: Tr.tr("+%1 more").arg(cellItem.eventCount - 1)
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
                root.isAddingEvent = false;
            }
        }

        StyledRect {
            id: dayModal

            anchors.centerIn: parent
            width: Math.min(parent.width - Tokens.padding.large * 2, 420)
            implicitHeight: Math.min(parent.height - Tokens.padding.large * 2, modalColumn.implicitHeight + Tokens.padding.large * 2)
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
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        text: root.effectiveDateKey === root.todayKey ? Tr.tr("Today · %1").arg(root.formatAgendaDate(root.effectiveDateKey)) : root.formatAgendaDate(root.effectiveDateKey)
                        font: Tokens.font.title.small
                        color: Colours.palette.m3primary
                        elide: Text.ElideRight
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
                        icon: "close"
                        isRound: true
                        type: IconButton.Text
                        font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                        padding: Tokens.padding.extraSmall
                        onClicked: {
                            root.selectedDateKey = "";
                            root.isAddingEvent = false;
                        }
                    }
                }

                Rectangle {
                    id: quickAddBox

                    Layout.fillWidth: true
                    visible: root.isAddingEvent
                    radius: Tokens.rounding.medium
                    color: Colours.palette.m3surfaceContainer
                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.7)
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
                            placeholderText: Tr.tr("Event title")
                            placeholderFloats: false
                            verticalPadding: Tokens.padding.extraSmall
                            font: Tokens.font.body.small
                            onAccepted: root.commitAddEvent(text, eventTimeInput.text)
                            Keys.onEscapePressed: root.isAddingEvent = false
                        }

                        StyledTextField {
                            id: eventTimeInput

                            Layout.preferredWidth: Math.ceil(timeMetrics.advanceWidth) + leftPadding + rightPadding + Tokens.padding.small
                            placeholderText: "14:00"
                            placeholderFloats: false
                            verticalPadding: Tokens.padding.extraSmall
                            font: Tokens.font.body.small
                            onAccepted: root.commitAddEvent(eventTitleInput.text, text)
                            Keys.onEscapePressed: root.isAddingEvent = false
                        }

                        TextMetrics {
                            id: timeMetrics

                            font: Tokens.font.body.small
                            text: "00:00"
                        }

                        IconButton {
                            icon: "check"
                            isRound: true
                            type: IconButton.Filled
                            padding: Tokens.padding.extraSmall
                            onClicked: root.commitAddEvent(eventTitleInput.text, eventTimeInput.text)
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.selectedDayEvents.length === 0
                    text: Tr.tr("No events scheduled for this day")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                ListView {
                    id: dayEventsList

                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 240)
                    visible: root.selectedDayEvents.length > 0
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    spacing: Tokens.spacing.extraSmall
                    model: root.selectedDayEvents

                    StyledScrollBar.vertical: StyledScrollBar {
                        flickable: dayEventsList
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        id: modalEventRow

                        required property var modelData
                        readonly property bool isAllDay: root.isAllDayEvent(modelData)

                        width: dayEventsList.width
                        implicitHeight: modalEventContent.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.small
                        color: Colours.palette.m3surfaceContainer
                        border.width: 1
                        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.35)

                        RowLayout {
                            id: modalEventContent

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.small
                            spacing: Tokens.spacing.small

                            Rectangle {
                                implicitWidth: 4
                                Layout.minimumWidth: 4
                                Layout.fillHeight: true
                                radius: Tokens.rounding.full
                                color: modalEventRow.isAllDay ? Colours.palette.m3tertiary : Colours.palette.term4
                            }

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
                        }
                    }
                }
            }
        }
    }
}
