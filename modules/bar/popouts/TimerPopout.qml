pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    required property PopoutState popouts

    implicitWidth: 280
    implicitHeight: layout.implicitHeight + Tokens.padding.medium * 2

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacing.medium

        // ── Header: Title & Time ─────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: FocusTimer.isRunning
                    ? (FocusTimer.mode === "work" ? "bolt" : "coffee")
                    : "timer"
                color: FocusTimer.mode === "work" || FocusTimer.mode === "custom"
                    ? Colours.palette.m3primary
                    : Colours.palette.m3tertiary
                fontStyle: Tokens.font.icon.medium
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: FocusTimer.mode === "work" ? qsTr("Focus Timer")
                        : (FocusTimer.mode === "break" || FocusTimer.mode === "shortBreak" || FocusTimer.mode === "longBreak") ? qsTr("Break")
                        : FocusTimer.mode === "stopwatch" ? qsTr("Stopwatch")
                        : qsTr("Task Timer")
                    font: Tokens.font.title.small
                    color: Colours.palette.m3onSurface
                }

                RowLayout {
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        text: FocusTimer.formattedTime
                        font: Tokens.font.headline.small
                        color: FocusTimer.isRunning ? Colours.palette.m3primary : Colours.palette.m3outline
                    }

                    Item { Layout.fillWidth: true }

                    // Daily completed pomodoros chip
                    StyledRect {
                        visible: FocusTimer.sessionsToday > 0
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primaryContainer
                        implicitHeight: 18
                        implicitWidth: sessText.implicitWidth + 10

                        StyledText {
                            id: sessText
                            anchors.centerIn: parent
                            text: qsTr("%1 done").arg(FocusTimer.sessionsToday)
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onPrimaryContainer
                        }
                    }
                }
            }

            IconButton {
                type: IconButton.Filled
                icon: FocusTimer.isRunning ? "pause" : "play_arrow"
                font: Tokens.font.icon.small
                onClicked: FocusTimer.toggle()
            }

            IconButton {
                type: IconButton.Tonal
                icon: "replay"
                font: Tokens.font.icon.small
                onClicked: FocusTimer.reset()
            }
        }

        // ── Mode Switcher (Work, Break, Stopwatch) ───────────────────
        BtnSwitcher {
            id: switcher
            Layout.fillWidth: true
            givenHeight: 36

            model: [
                { icon: "work",      text: qsTr("Work"),      value: "work",      minutes: 25 },
                { icon: "coffee",    text: qsTr("Break"),     value: "break",     minutes: 5  },
                { icon: "timer",     text: qsTr("Stopwatch"), value: "stopwatch", minutes: 0  }
            ]
            currentValue: (FocusTimer.mode === "shortBreak" || FocusTimer.mode === "longBreak") ? "break" : FocusTimer.mode
            showOnlyActiveText: true

            onActivated: value => {
                const preset = model.find(p => p.value === value)
                if (preset) {
                    FocusTimer.setPreset(preset.value, preset.minutes)
                }
            }
        }

        // ── Floating HUD Visibility Toggle ───────────────────────────
        IconTextButton {
            id: hudToggleBtn
            Layout.fillWidth: true
            type: ButtonBase.Tonal
            isToggle: false

            readonly property bool isHudOpen: ShellState.forActive()?.timer ?? false

            internalChecked: hudToggleBtn.isHudOpen
            icon: hudToggleBtn.isHudOpen ? "visibility" : "visibility_off"
            text: hudToggleBtn.isHudOpen ? qsTr("Hide Floating HUD") : qsTr("Show Floating HUD")
            font: Tokens.font.label.medium
            verticalPadding: Tokens.padding.extraSmall
            onClicked: {
                const st = ShellState.forActive()
                if (st) st.timer = !st.timer
            }
        }
    }
}

