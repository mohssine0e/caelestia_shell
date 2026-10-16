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

    implicitWidth: FocusTimer.taskPhaseString.length > 0 ? 296 : 270
    implicitHeight: card.implicitHeight

    readonly property int pillHeight: 32
    readonly property int iconSize: 32
    readonly property int ringSize: 26
    readonly property int ringStroke: 3

    // ── Keyboard ──────────────────────────────────────────────────────
    focus: true
    activeFocusOnTab: true

    readonly property bool bannerVisible: FocusTimer.linkedTaskTitle.length > 0

    readonly property var presetOrder: [
        { value: "work",       minutes: 25 },
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
            if (root.mini.expanded) root.mini.expanded = false
            else root.mini.dismissRequested()
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
            else if (!root.bannerVisible) root.mini.expanded = false
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
        implicitHeight: mainLayout.implicitHeight + Tokens.padding.small * 2
        height: implicitHeight

        radius: 2
        color: Colours.tPalette.m3surfaceContainer
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

        Behavior on border.color { CAnim {} }

        ColumnLayout {
            id: mainLayout
            width: parent.width - Tokens.padding.small * 2
            x: Tokens.padding.small
            y: Tokens.padding.small
            spacing: Tokens.spacing.extraSmall

            // ── Pill Row ──────────────────────────────────────────────
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
                    spacing: Tokens.spacing.small

                    Item {
                        id: ringContainer
                        implicitWidth: root.ringSize
                        implicitHeight: root.ringSize
                        Layout.alignment: Qt.AlignVCenter

                        readonly property real ringRadius: (Math.min(width, height) - root.ringStroke) / 2
                        readonly property real progress: Math.max(0, Math.min(1, FocusTimer.progress))
                        readonly property color activeColour: FocusTimer.mode === "work" || FocusTimer.mode === "custom"
                            ? Colours.palette.m3primary
                            : (FocusTimer.mode === "stopwatch" ? Colours.palette.m3secondary : Colours.palette.m3tertiary)
                        readonly property color trackColour: Colours.palette.m3surfaceContainerHighest

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
                            text: FocusTimer.isRunning
                                ? (FocusTimer.mode === "work" ? "bolt" : (FocusTimer.mode === "stopwatch" ? "timer" : "coffee"))
                                : "timer"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: FocusTimer.formattedTime
                        font: Tokens.font.title.small
                        color: Colours.palette.m3onSurface
                    }

                    StyledRect {
                        visible: FocusTimer.taskPhaseString.length > 0
                        Layout.alignment: Qt.AlignVCenter
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3surfaceContainerHighest
                        implicitHeight: 20
                        implicitWidth: phaseText.implicitWidth + Tokens.padding.small * 2

                        StyledText {
                            id: phaseText
                            anchors.centerIn: parent
                            text: FocusTimer.taskPhaseString
                            font: Tokens.font.label.small
                            color: Colours.palette.m3primary
                        }
                    }

                Item { Layout.fillWidth: true }

                IconButton {
                    type: IconButton.Filled
                    icon: FocusTimer.isRunning ? "pause" : "play_arrow"
                    font: Tokens.font.icon.small
                    implicitWidth: root.iconSize
                    implicitHeight: root.iconSize
                    onClicked: FocusTimer.toggle()
                }

                IconButton {
                    type: IconButton.Text
                    icon: "close"
                    font: Tokens.font.icon.small
                    implicitWidth: root.iconSize
                    implicitHeight: root.iconSize
                    onClicked: root.mini.dismissRequested()
                }
            }
        }

            // ── Expanded Panel ────────────────────────────────────────
            ColumnLayout {
                id: expandedBlock
                visible: root.mini.expanded
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.small
                spacing: Tokens.spacing.small

                BtnSwitcher {
                    id: presetSwitcher
                    Layout.fillWidth: true
                    givenHeight: 36

                    model: [
                        { icon: "work",   text: qsTr("Work"),      value: "work",       minutes: 25 },
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

                StyledRect {
                    id: taskBanner
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    visible: root.bannerVisible
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3primaryContainer

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.small
                        anchors.rightMargin: Tokens.padding.extraSmall
                        spacing: Tokens.spacing.extraSmall

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
                            implicitWidth: 24
                            implicitHeight: 24
                            onClicked: FocusTimer.clearLinkedTask()
                        }
                    }
                }
            }
        }
    }
}