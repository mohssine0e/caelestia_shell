import "center"
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services
import qs.utils

ColumnLayout {
    id: root

    required property var lock
    readonly property real centerScale: Math.min(1, (lock.screen?.height ?? 1440) / 1440)
    readonly property int centerWidth: Math.min(380, width)

    spacing: Tokens.spacing.large

    // ── Status Bar (Read-Only WiFi & Battery) ─────────
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Tokens.padding.large
        Layout.bottomMargin: Tokens.padding.small
        spacing: Tokens.spacing.large

        // WiFi
        RowLayout {
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: Nmcli.activeEthernet ? "cable" : Nmcli.active ? Icons.getNetworkIcon(Nmcli.active.strength ?? 0) : "wifi_off"
                color: (Nmcli.activeEthernet || Nmcli.active) ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3outline
                fontStyle: Tokens.font.icon.builders.medium.scale(root.centerScale * 1.05).build()
            }

            StyledText {
                text: Nmcli.activeEthernet ? Tr.tr("Ethernet") : (Nmcli.active?.ssid || Tr.tr("Offline"))
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.builders.medium.scale(root.centerScale * 1.05).weight(Font.Medium).build()
                elide: Text.ElideRight
                Layout.maximumWidth: 160
            }
        }

        // Separator dot
        StyledText {
            visible: weatherItem.visible
            text: "•"
            color: Colours.palette.m3outlineVariant
            font: Tokens.font.label.builders.medium.scale(root.centerScale * 1.05).build()
        }

        // Weather
        RowLayout {
            id: weatherItem
            visible: Boolean(Weather.cc && Weather.temp)
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: Weather.icon
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.builders.medium.scale(root.centerScale * 1.05).build()
            }

            StyledText {
                text: Weather.temp
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.builders.medium.scale(root.centerScale * 1.05).weight(Font.Medium).build()
            }
        }

        // Separator dot
        StyledText {
            visible: batteryItem.visible
            text: "•"
            color: Colours.palette.m3outlineVariant
            font: Tokens.font.label.builders.medium.scale(root.centerScale * 1.05).build()
        }

        // Battery
        RowLayout {
            id: batteryItem
            visible: UPower.displayDevice.isLaptopBattery || UPower.onBattery
            spacing: Tokens.spacing.small

            readonly property bool isCharging: [UPowerDeviceState.Charging, UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge].includes(UPower.displayDevice.state)

            MaterialIcon {
                text: Icons.getBatteryIcon(UPower.displayDevice.percentage, batteryItem.isCharging)
                color: batteryItem.isCharging ? Colours.palette.m3primary : (UPower.displayDevice.percentage <= 0.2 ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant)
                fontStyle: Tokens.font.icon.builders.medium.scale(root.centerScale * 1.05).build()
            }

            StyledText {
                text: `${Math.round(UPower.displayDevice.percentage * 100)}%`
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.builders.medium.scale(root.centerScale * 1.05).weight(Font.Medium).build()
            }
        }
    }

    Clock {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Tokens.padding.small
        centerScale: root.centerScale
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter

        text: Time.format("dddd • d MMMM").toUpperCase()
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.title.builders.small.weight(Font.DemiBold).build()
    }

    ProfilePic {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Tokens.spacing.medium * root.centerScale
        Layout.bottomMargin: Tokens.spacing.extraSmall * root.centerScale
        centerWidth: root.centerWidth
    }

    PasswordInput {
        Layout.alignment: Qt.AlignHCenter
        centerScale: Math.max(0.8, root.centerScale)
        centerWidth: root.centerWidth
        lock: root.lock
    }

    StateMessage {
        Layout.fillWidth: true
        pam: root.lock.pam
    }

    // ── Ambient Now Playing (Single-Line Whispering Note) ─
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Tokens.spacing.extraSmall
        visible: Boolean(Players.active && (Players.active.isPlaying || Players.active.trackTitle))
        opacity: visible ? 0.8 : 0
        spacing: Tokens.spacing.extraSmall

        Behavior on opacity {
            Anim { type: Anim.DefaultEffects }
        }

        MaterialIcon {
            text: Players.active?.isPlaying ? "music_note" : "pause"
            color: Colours.palette.m3primary
            fontStyle: Tokens.font.icon.builders.small.scale(root.centerScale * 0.8).build()
        }

        StyledText {
            text: Players.active ? `${Players.active.trackTitle || Tr.tr("Unknown track")}${Players.active.trackArtist ? " — " + Players.active.trackArtist : ""}` : ""
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.builders.small.scale(root.centerScale * 0.85).weight(Font.Normal).build()
            elide: Text.ElideRight
            Layout.maximumWidth: root.centerWidth - 40
        }
    }
}
