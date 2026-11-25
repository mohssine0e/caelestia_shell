import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import Caelestia.State
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    readonly property real nonAnimHeight: layout.implicitHeight + Tokens.padding.medium * 2

    implicitHeight: nonAnimHeight

    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer
    border.width: RuntimeState.inhibitIdle ? 2 : 1
    border.color: RuntimeState.inhibitIdle ? Qt.alpha(Colours.palette.m3primary, 0.75) : Qt.alpha(Colours.palette.m3outlineVariant, 0.7)
    clip: true

    Behavior on border.color {
        CAnim {}
    }

    RowLayout {
        id: layout

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        StyledRect {
            implicitWidth: implicitHeight
            implicitHeight: icon.implicitHeight + Tokens.padding.large

            radius: Tokens.rounding.full
            color: RuntimeState.inhibitIdle ? Colours.palette.m3secondary : Colours.palette.m3secondaryContainer

            MaterialIcon {
                id: icon

                anchors.centerIn: parent
                text: "coffee"
                color: RuntimeState.inhibitIdle ? Colours.palette.m3onSecondary : Colours.palette.m3onSecondaryContainer
                fontStyle: Tokens.font.icon.large
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledText {
                    text: RuntimeState.inhibitIdle ? Tr.trCtx("Awake since: ", "idle inhibitor") : Tr.trCtx("Keep awake", "idle inhibitor")
                    font: Tokens.font.body.medium
                    elide: Text.ElideRight
                }

                StyledRect {
                    id: sinceBadge

                    visible: opacity > 0
                    opacity: RuntimeState.inhibitIdle ? 1 : 0
                    scale: RuntimeState.inhibitIdle ? 1 : 0.85
                    implicitWidth: activeText.implicitWidth + Tokens.padding.small * 2
                    implicitHeight: activeText.implicitHeight + 4
                    radius: Tokens.rounding.small
                    color: Qt.alpha(Colours.palette.m3tertiaryContainer, 0.9)
                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3tertiary, 0.45)

                    StyledText {
                        id: activeText

                        anchors.centerIn: parent
                        // TRANSLATORS: %1 = a clock time, e.g. 14:30
                        // text: Tr.tr("Awake since: %1").arg(Tr.formatDateTime(new Date(RuntimeState.inhibitingIdleSince), Units.twelveHourClock ? "hh:mm a" : "hh:mm"))
                        text: Tr.formatDateTime(new Date(RuntimeState.inhibitingIdleSince), Units.twelveHourClock ? "hh:mm a" : "hh:mm")
                        color: Colours.palette.m3onTertiaryContainer
                        font: Tokens.font.label.small
                    }

                    Behavior on opacity {
                        Anim {
                            type: Anim.StandardSmall
                        }
                    }

                    Behavior on scale {
                        Anim {}
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: RuntimeState.inhibitIdle ? Tr.trCtx("Preventing sleep mode", "idle inhibitor") : Tr.trCtx("Normal power management", "idle inhibitor")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }
        }

        StyledSwitch {
            checked: RuntimeState.inhibitIdle
            onToggled: RuntimeState.inhibitIdle = checked
        }
    }
}
