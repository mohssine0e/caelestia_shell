pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.containers
import qs.components.effects
import qs.services

FocusScope {
    id: root

    required property FloatingMini mini
    property var windowRef: null

    readonly property alias card: card

    implicitWidth: 264
    implicitHeight: card.implicitHeight

    readonly property int pillHeight: 34
    readonly property int ringSize: 26
    readonly property real ringStroke: 2.5

    // ── Keyboard ──────────────────────────────────────────────────────
    focus: true
    activeFocusOnTab: true

    readonly property bool bannerVisible: FocusTimer.linkedTaskTitle.length > 0
    readonly property bool inputActive: objectiveInput && objectiveInput.activeFocus

    readonly property var presetOrder: [
        { value: "work",       minutes: 35 },
        { value: "shortBreak", minutes: 5  },
        { value: "stopwatch",  minutes: 0  }
    ]

    function cyclePreset(step) {
        step = step || 1
        const n = root.presetOrder.length
        let i = root.presetOrder.findIndex(p => p.value === FocusTimer.mode || (p.value === "shortBreak" && FocusTimer.mode === "break"))
        if (i < 0) i = 0
        const next = (i + step + n) % n
        const p = root.presetOrder[next]
        FocusTimer.setPreset(p.value, p.minutes)
    }

    Keys.onPressed: event => {
        if (root.inputActive) return
        switch (event.key) {
        case Qt.Key_Space:
            FocusTimer.toggle()
            event.accepted = true
            break

        case Qt.Key_Q:
            root.cyclePreset(event.modifiers & Qt.ShiftModifier ? -1 : 1)
            event.accepted = true
            break

        case Qt.Key_Up:
            if (typeof FocusTimer.adjustMinutes === "function")
                FocusTimer.adjustMinutes(1)
            event.accepted = true
            break

        case Qt.Key_Down:
            if (typeof FocusTimer.adjustMinutes === "function")
                FocusTimer.adjustMinutes(-1)
            event.accepted = true
            break

        case Qt.Key_Escape:
            if (root.mini.expanded) {
                if (root.inputActive) objectiveInput.focus = false
                root.mini.expanded = false
            } else {
                root.mini.dismissRequested()
            }
            event.accepted = true
            break
        }
    }

    Connections {
        target: FocusTimer
        function onLinkedTaskTitleChanged() {
            if (FocusTimer.linkedTaskTitle.length > 0)
                root.mini.expanded = true
        }
    }

    HoverHandler {
        id: hover
        onHoveredChanged: {
            if (hovered) root.mini.expanded = true
            else if (!root.bannerVisible && !root.inputActive) root.mini.expanded = false
        }
    }

    Elevation {
        anchors.fill: card
        radius: card.radius
        level: 3
    }

    StyledRect {
        id: card
        width: parent.width
        implicitHeight: mainLayout.implicitHeight + 16
        height: implicitHeight

        radius: 12
        color: Colours.tPalette.m3surfaceContainer
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

        Behavior on border.color { CAnim {} }

        ColumnLayout {
            id: mainLayout
            width: parent.width - 16
            x: 8
            y: 8
            spacing: 6

            // ── Top Pill Row (Ring + Time + Play + Close) ────────────
            Item {
                id: pillContainer
                Layout.fillWidth: true
                implicitHeight: root.pillHeight
                Layout.preferredHeight: root.pillHeight

                MouseArea {
                    id: timerDragArea
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.ArrowCursor
                    onPressed: mouse => {
                        if (root.windowRef) {
                            root.windowRef.startSystemMove()
                        }
                    }
                }

                RowLayout {
                    id: pillRow
                    anchors.fill: parent
                    spacing: 8

                    // Progress Ring with mode icon
                    Item {
                        id: ringContainer
                        implicitWidth: root.ringSize
                        implicitHeight: root.ringSize
                        Layout.alignment: Qt.AlignVCenter

                        readonly property real ringRadius: (Math.min(width, height) - root.ringStroke) / 2
                        readonly property real progress: Math.max(0, Math.min(1, FocusTimer.progress))
                        readonly property color activeColour: (FocusTimer.mode === "break" || FocusTimer.mode === "shortBreak")
                            ? Colours.palette.m3tertiary
                            : (FocusTimer.mode === "stopwatch" ? Colours.palette.m3secondary : Colours.palette.m3primary)
                        readonly property color trackColour: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            asynchronous: true

                            ShapePath {
                                fillColor: "transparent"
                                strokeColor: ringContainer.trackColour
                                strokeWidth: root.ringStroke
                                capStyle: ShapePath.RoundCap

                                PathAngleArc {
                                    radiusX: ringContainer.ringRadius
                                    radiusY: ringContainer.ringRadius
                                    centerX: ringContainer.width / 2
                                    centerY: ringContainer.height / 2
                                    startAngle: -90
                                    sweepAngle: 360
                                }
                            }

                            ShapePath {
                                fillColor: "transparent"
                                strokeColor: ringContainer.activeColour
                                strokeWidth: root.ringStroke
                                capStyle: ShapePath.RoundCap

                                PathAngleArc {
                                    radiusX: ringContainer.ringRadius
                                    radiusY: ringContainer.ringRadius
                                    centerX: ringContainer.width / 2
                                    centerY: ringContainer.height / 2
                                    startAngle: -90
                                    sweepAngle: 360 * ringContainer.progress
                                }

                                Behavior on strokeColor { CAnim {} }
                            }
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: (FocusTimer.mode === "break" || FocusTimer.mode === "shortBreak")
                                ? "coffee"
                                : (FocusTimer.mode === "stopwatch" ? "timer" : "work")
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }

                    // Formatted Time (e.g. 03:24)
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: FocusTimer.formattedTime
                        renderType: Text.NativeRendering
                        font.pixelSize: 20
                        font.weight: Font.Bold
                        color: Colours.palette.m3onSurface
                    }

                    Item { Layout.fillWidth: true }

                    // Big Circular Play/Pause Button
                    Rectangle {
                        id: playBtn
                        implicitWidth: 34
                        implicitHeight: 34
                        radius: 17
                        Layout.alignment: Qt.AlignVCenter
                        color: playHover.hovered
                            ? Qt.lighter(Colours.palette.m3primary, 1.08)
                            : Colours.palette.m3primary

                        HoverHandler { id: playHover }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: FocusTimer.isRunning ? "pause" : "play_arrow"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3onPrimary
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: FocusTimer.toggle()
                        }
                    }

                    // Close Button
                    Rectangle {
                        id: closeBtn
                        implicitWidth: 24
                        implicitHeight: 24
                        radius: 12
                        Layout.alignment: Qt.AlignVCenter
                        color: closeHover.hovered ? Colours.tPalette.m3surfaceContainerHigh : "transparent"

                        HoverHandler { id: closeHover }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "close"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.mini.dismissRequested()
                        }
                    }
                }
            }

            // ── Expanded Panel ────────────────────────────────────────
            ColumnLayout {
                id: expandedBlock
                visible: root.mini.expanded
                Layout.fillWidth: true
                spacing: 6

                BtnSwitcher {
                    id: presetSwitcher
                    Layout.fillWidth: true
                    givenHeight: 36

                    model: [
                        { icon: "work",   text: qsTr("Work"),      value: "work",       minutes: 35 },
                        { icon: "coffee", text: qsTr("Short"),     value: "shortBreak", minutes: 5  },
                        { icon: "timer",  text: qsTr("Stopwatch"), value: "stopwatch",  minutes: 0  }
                    ]
                    currentValue: (FocusTimer.mode === "break" || FocusTimer.mode === "shortBreak") ? "shortBreak" : FocusTimer.mode
                    showOnlyActiveText: true

                    onActivated: value => {
                        const preset = model.find(p => p.value === value)
                        if (preset)
                            FocusTimer.setPreset(preset.value, preset.minutes)
                    }
                }

                // ── Linked Task Banner (if any) ────────────────────────
                StyledRect {
                    id: taskBanner
                    Layout.fillWidth: true
                    implicitHeight: 28
                    visible: root.bannerVisible
                    radius: 8
                    color: Colours.palette.m3primaryContainer

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 4
                        spacing: 4

                        MaterialIcon {
                            text: "task_alt"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3onPrimaryContainer
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: FocusTimer.linkedTaskTitle
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onPrimaryContainer
                            elide: Text.ElideRight
                        }

                        IconButton {
                            type: IconButton.Text
                            icon: "close"
                            font: Tokens.font.icon.small
                            implicitWidth: 20
                            implicitHeight: 20
                            onClicked: FocusTimer.clearLinkedTask()
                        }
                    }
                }

                // ── Objectives Box (Tasks list) ────────────────────────
                StyledRect {
                    id: objectivesBox
                    visible: FocusTimer.objectives.length > 0
                    Layout.fillWidth: true
                    implicitHeight: Math.min(objCol.implicitHeight + 4, 56)
                    radius: 8
                    color: Colours.tPalette.m3surfaceContainerLowest
                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.35)
                    clip: true

                    Flickable {
                        id: objFlick
                        anchors.fill: parent
                        anchors.margins: 2
                        contentHeight: objCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: objCol
                            width: objFlick.width
                            spacing: 0

                            Repeater {
                                model: FocusTimer.objectives

                                Item {
                                    id: objItem
                                    required property var modelData
                                    required property int index

                                    Layout.fillWidth: true
                                    implicitHeight: 25

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        // Square checkbox on left
                                        MaterialIcon {
                                            text: "check_box_outline_blank"
                                            fontStyle: Tokens.font.icon.small
                                            color: checkHover.hovered ? Colours.palette.m3primary : Colours.palette.m3outline
                                            Layout.alignment: Qt.AlignVCenter

                                            HoverHandler { id: checkHover }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: FocusTimer.removeObjective(objItem.modelData ? objItem.modelData.id : objItem.index)
                                            }
                                        }

                                        // Objective text
                                        StyledText {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            text: (objItem.modelData && objItem.modelData.text) ? objItem.modelData.text : ""
                                            font: Tokens.font.body.small
                                            color: Colours.palette.m3onSurface
                                            elide: Text.ElideRight
                                        }

                                        // Checkmark on right
                                        MaterialIcon {
                                            text: "check"
                                            fontStyle: Tokens.font.icon.small
                                            color: doneHover.hovered ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                            Layout.alignment: Qt.AlignVCenter

                                            HoverHandler { id: doneHover }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: FocusTimer.removeObjective(objItem.modelData ? objItem.modelData.id : objItem.index)
                                            }
                                        }
                                    }

                                    // Divider between items (visible except on last item)
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 6
                                        height: 1
                                        color: Qt.alpha(Colours.palette.m3outlineVariant, 0.25)
                                        visible: objItem.index < (FocusTimer.objectives.length - 1)
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Add Objective Row (+ Objective...) ────────────────
                StyledRect {
                    id: inputContainer
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: 8
                    color: Colours.tPalette.m3surfaceContainerLowest
                    border.width: 1
                    border.color: objectiveInput.activeFocus ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outlineVariant, 0.35)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 6
                        spacing: 6

                        TextInput {
                            id: objectiveInput
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurface
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            selectByMouse: true

                            StyledText {
                                anchors.fill: parent
                                visible: !objectiveInput.text && !objectiveInput.activeFocus
                                text: qsTr("Objective…")
                                font: objectiveInput.font
                                color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.6)
                                verticalAlignment: Text.AlignVCenter
                            }

                            onAccepted: {
                                if (text.trim().length > 0) {
                                    FocusTimer.addObjective(text.trim())
                                    text = ""
                                }
                            }

                            Keys.onEscapePressed: {
                                text = ""
                                focus = false
                            }
                        }

                        IconButton {
                            type: IconButton.Text
                            icon: "check"
                            visible: objectiveInput.text.trim().length > 0
                            font: Tokens.font.icon.small
                            implicitWidth: 20
                            implicitHeight: 20
                            Layout.alignment: Qt.AlignVCenter
                            onClicked: {
                                if (objectiveInput.text.trim().length > 0) {
                                    FocusTimer.addObjective(objectiveInput.text.trim())
                                    objectiveInput.text = ""
                                }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        acceptedButtons: Qt.LeftButton
                        onPressed: mouse => {
                            objectiveInput.forceActiveFocus()
                        }
                        visible: !objectiveInput.activeFocus
                    }
                }
            }
        }
    }
}
