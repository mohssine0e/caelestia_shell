pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    readonly property color colour: Colours.palette.m3tertiary
    readonly property int padding: Config.bar.clock.background ? Tokens.padding.medium : Tokens.padding.extraSmall
    readonly property var font: Tokens.font.body.builders.small.scale(1.1)

    function fontFor(text: string, metricWidth: int): font {
        // We don't count seconds for the max width because it changes too often
        const scale = text === "11" ? 1.15 : Math.min(1.05, Math.max(hourMetrics.width, minMetrics.width) / metricWidth);
        return root.font.width(scale * 100).letterSpacing(scale).build();
    }

    required property var bar
    required property var popouts
    readonly property alias timerBtn: timerBtn

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: layout.implicitHeight + root.padding * 2

    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, Config.bar.clock.background ? Colours.tPalette.m3surfaceContainer.a : 0)
    radius: Tokens.rounding.full

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        spacing: Tokens.spacing.extraSmall

        Loader {
            Layout.alignment: Qt.AlignHCenter
            asynchronous: true
            active: Config.bar.clock.showIcon
            visible: active

            sourceComponent: MaterialIcon {
                text: "calendar_month"
                color: root.colour
            }
        }

        Loader {
            Layout.alignment: Qt.AlignHCenter
            asynchronous: true
            active: Config.bar.clock.showDate
            visible: active

            sourceComponent: ColumnLayout {
                spacing: layout.spacing - 4

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Time.format("ddd")
                    font: Tokens.font.body.builders.small.scale(0.9).build()
                    color: root.colour
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Time.format("d")
                    font: root.font.scale(1.1).build()
                    color: root.colour
                }

                StyledRect {
                    Layout.fillWidth: true
                    Layout.leftMargin: -Tokens.padding.extraSmall
                    Layout.rightMargin: -Tokens.padding.extraSmall
                    Layout.topMargin: 4
                    Layout.bottomMargin: Tokens.padding.extraSmall / 2
                    implicitHeight: 1
                    color: Colours.palette.m3outlineVariant
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Time.hourStr
            font: root.fontFor(text, hourMetrics.width)
            color: root.colour

            TextMetrics {
                id: hourMetrics

                font: root.font.build()
                text: Time.hourStr
            }
        }

        StyledText {
            Layout.topMargin: -parent.spacing - 4
            Layout.alignment: Qt.AlignHCenter
            text: Time.minuteStr
            font: root.fontFor(text, minMetrics.width)
            color: root.colour

            TextMetrics {
                id: minMetrics

                font: root.font.build()
                text: Time.minuteStr
            }
        }

        Loader {
            Layout.topMargin: -parent.spacing - 4
            Layout.alignment: Qt.AlignHCenter
            asynchronous: true
            active: Config.bar.clock.showSeconds
            visible: active

            sourceComponent: StyledText {
                text: Time.format("ss")
                font: root.fontFor(text, secMetrics.width)
                color: root.colour

                TextMetrics {
                    id: secMetrics

                    font: root.font.build()
                    text: Time.format("ss")
                }
            }
        }

        Loader {
            Layout.topMargin: -parent.spacing - 4
            Layout.alignment: Qt.AlignHCenter
            asynchronous: true
            active: Units.twelveHourClock
            visible: active

            sourceComponent: StyledText {
                text: Time.amPmStr.toLowerCase()
                font: Tokens.font.body.builders.small.scale(0.9).build()
                color: root.colour
            }
        }

        // ── Timer Launcher Button (Popout trigger) ───────────────────
        Item {
            id: timerBtn
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.extraSmall / 2
            implicitWidth: 24
            implicitHeight: 24

            readonly property bool isRunning: FocusTimer.isRunning
            readonly property bool isWinOpen: ShellState.forActive()?.timer ?? false
            readonly property bool isPopoutOpen: root.popouts?.hasCurrent && root.popouts?.currentName === "timer"

            StyledRect {
                anchors.fill: parent
                radius: Tokens.rounding.full
                color: timerBtn.isRunning ? Colours.palette.m3primary
                    : (timerBtn.isPopoutOpen || timerBtn.isWinOpen) ? Colours.tPalette.m3surfaceContainerHigh
                    : "transparent"

                Behavior on color { CAnim {} }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: timerBtn.isRunning
                        ? (FocusTimer.mode === "stopwatch" ? "timer" : (FocusTimer.mode === "work" ? "bolt" : "coffee"))
                        : "hourglass_top"
                    fontStyle: Tokens.font.icon.small
                    color: timerBtn.isRunning ? Colours.palette.m3onPrimary : root.colour
                }
            }

            StateLayer {
                radius: Tokens.rounding.full
                onClicked: {
                    if (root.popouts) {
                        if (root.popouts.hasCurrent && root.popouts.currentName === "timer") {
                            root.popouts.hasCurrent = false;
                        } else {
                            root.popouts.currentName = "timer";
                            root.popouts.currentCenter = Qt.binding(() => timerBtn.mapToItem(root.bar, 0, timerBtn.implicitHeight / 2).y);
                            root.popouts.hasCurrent = true;
                        }
                    }
                }
            }
        }
    }
}
