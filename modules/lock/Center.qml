import "center"
import QtQuick
import QtQuick.Layouts
import Quickshell
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

    readonly property string userName: {
        const raw = SysInfo.user || Quickshell.env("USER") || "Mohssine";
        return raw.charAt(0).toUpperCase() + raw.slice(1);
    }

    readonly property string greetingText: {
        const hour = new Date().getHours();
        if (hour >= 5 && hour < 12)
            return Tr.tr("Good morning, %1").arg(userName);
        if (hour >= 12 && hour < 18)
            return Tr.tr("Good afternoon, %1").arg(userName);
        if (hour >= 18 && hour < 23)
            return Tr.tr("Good evening, %1").arg(userName);
        return Tr.tr("Welcome back, %1").arg(userName);
    }

    readonly property var quotesPool: [
        Tr.tr("Done beats perfect."),
        Tr.tr("Discipline equals freedom."),
        Tr.tr("Trust the process."),
        Tr.tr("Stay hungry."),
        Tr.tr("You miss 100% of the shots you don't take."),
        Tr.tr("It always seems impossible until it's done."),
        Tr.tr("Be the change that you wish to see in the world."),
        Tr.tr("You are never too old to set another goal or to dream a new dream."),
        Tr.tr("Success is not final, failure is not fatal: it is the courage to continue that counts."),
        Tr.tr("One day or day one. You decide."),
        Tr.tr("The secret of getting ahead is getting started."),
        Tr.tr("Small deeds done are better than great deeds planned."),
        Tr.tr("Slow is smooth. Smooth is fast."),
        Tr.tr("Energy flows where attention goes."),
        Tr.tr("Less reaction. More response.")
    ]

    property string quoteText: ""

    function pickRandomQuote(): void {
        quoteText = quotesPool[Math.floor(Math.random() * quotesPool.length)];
    }

    Component.onCompleted: pickRandomQuote()

    Connections {
        target: root.lock?.lock ?? null
        function onLockedChanged(): void {
            if (target && target.locked)
                root.pickRandomQuote();
        }
    }

    spacing: Tokens.spacing.medium

    // ── Status Bar (Read-Only WiFi & Battery) ─────────
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Tokens.padding.medium
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
        Layout.topMargin: -12

        text: Time.format("dddd • d MMMM").toUpperCase()
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.title.builders.small.vaxis("wght", 500).build()
    }

    ProfilePic {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Tokens.spacing.small * root.centerScale
        Layout.bottomMargin: Tokens.spacing.extraSmall * root.centerScale
        centerWidth: root.centerWidth
    }

    ColumnLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Tokens.spacing.small
        Layout.bottomMargin: Tokens.spacing.extraSmall
        spacing: 3

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: root.greetingText
            color: Colours.palette.m3onSurface
            font: Tokens.font.title.builders.large.size(23).vaxis("wght", 600).build()
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: root.centerWidth - 20
            text: root.quoteText
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.builders.medium.vaxis("wght", 400).size(13).build()
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
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

    // ── Now Playing Media Card / Pill ─────────────────
    StyledRect {
        id: mediaPill
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Tokens.spacing.small
        Layout.bottomMargin: Tokens.padding.medium
        visible: Boolean(Players.active && (Players.active.isPlaying || Players.active.trackTitle))
        opacity: visible ? 1.0 : 0.0

        Behavior on opacity {
            Anim { type: Anim.DefaultEffects }
        }

        implicitHeight: 42
        implicitWidth: Math.min(436, mediaLayout.implicitWidth + 32)
        radius: Tokens.rounding.full

        color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.7)
        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.25)
        border.width: 1

        RowLayout {
            id: mediaLayout
            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "music_note"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.builders.medium.scale(1.1).build()
            }

            StyledText {
                text: Players.active?.trackTitle || Tr.tr("Unknown track")
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.builders.medium.vaxis("wght", 550).size(13).build()
                elide: Text.ElideRight
                Layout.maximumWidth: 165
            }

            StyledText {
                visible: Boolean(Players.active?.trackArtist)
                text: "•"
                color: Colours.palette.m3outline
                font: Tokens.font.body.builders.medium.build()
            }

            StyledText {
                visible: Boolean(Players.active?.trackArtist)
                text: Players.active?.trackArtist || ""
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.medium.vaxis("wght", 400).size(13).build()
                elide: Text.ElideRight
                Layout.maximumWidth: 165
            }

            // Dedicated Play / Pause Button
            StyledRect {
                id: playPauseBtn
                implicitWidth: 30
                implicitHeight: 30
                radius: Tokens.rounding.full

                color: btnMouse.pressed 
                    ? Colours.palette.m3primary 
                    : (btnMouse.containsMouse ? Qt.alpha(Colours.palette.m3primary, 0.35) : Qt.alpha(Colours.palette.m3primary, 0.18))
                border.color: Qt.alpha(Colours.palette.m3primary, 0.5)
                border.width: 1

                scale: btnMouse.pressed ? 0.92 : (btnMouse.containsMouse ? 1.06 : 1.0)
                Behavior on scale {
                    Anim { type: Anim.FastSpatial }
                }
                Behavior on color {
                    Anim { type: Anim.FastEffects }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: Players.active?.isPlaying ? "pause" : "play_arrow"
                    color: btnMouse.pressed ? Colours.palette.m3onPrimary : Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.builders.small.build()
                }

                MouseArea {
                    id: btnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (Players.active?.canTogglePlaying)
                            Players.active.togglePlaying();
                        else
                            Quickshell.execDetached(["playerctl", "play-pause"]);
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            z: -1
            onClicked: {
                if (Players.active?.canTogglePlaying)
                    Players.active.togglePlaying();
                else
                    Quickshell.execDetached(["playerctl", "play-pause"]);
            }
        }
    }
}
