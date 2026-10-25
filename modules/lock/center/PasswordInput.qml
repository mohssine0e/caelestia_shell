pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import M3Shapes
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    required property real centerScale
    required property int centerWidth
    required property var lock

    property string lastKnownLayout: "EN"
    readonly property string layoutCode: {
        const full = (Hypr.kbLayoutFull || "").toLowerCase();
        const code = (Hypr.kbLayout || "").toLowerCase();
        if (full.includes("english") || code === "us" || code === "en" || code === "gb")
            return lastKnownLayout = "EN";
        if (full.includes("arabic") || code === "ara" || code === "ar" || code === "ma")
            return lastKnownLayout = "AR";
        if (full.includes("french") || code === "fr")
            return lastKnownLayout = "FR";
        if (full.includes("spanish") || code === "es")
            return lastKnownLayout = "ES";
        if (full.includes("german") || code === "de")
            return lastKnownLayout = "DE";
        if (code && code !== "??" && code.length >= 2)
            return lastKnownLayout = code.slice(0, 2).toUpperCase();
        return lastKnownLayout;
    }

    property bool localCapsLock: Hypr.capsLock
    readonly property bool isCapsLockOn: localCapsLock || Hypr.capsLock

    Connections {
        target: Hypr
        function onCapsLockChanged(): void {
            root.localCapsLock = Hypr.capsLock;
        }
    }

    implicitWidth: {
        const baseW = Math.round(centerWidth * 0.85);
        const minW = inputField.placeholderWidth + iconWrapper.implicitWidth + enterButton.implicitWidth + kbLayoutBadge.implicitWidth + (isCapsLockOn ? 70 : 0) + input.spacing * 4 + Tokens.padding.medium * 2;
        return Math.max(baseW, minW);
    }
    implicitHeight: input.implicitHeight + Tokens.padding.small

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.full
    border.width: 1.5
    border.color: shakeAnim.running ? Colours.palette.m3error : Qt.alpha(Colours.palette.m3outlineVariant, 0.15)

    Behavior on border.color {
        CAnim {}
    }

    transform: Translate {
        id: shakeTranslate
    }

    SequentialAnimation {
        id: shakeAnim

        NumberAnimation { target: shakeTranslate; property: "x"; to: -10; duration: 45; easing.type: Easing.OutQuad }
        NumberAnimation { target: shakeTranslate; property: "x"; to: 10; duration: 45; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeTranslate; property: "x"; to: -7; duration: 45; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeTranslate; property: "x"; to: 7; duration: 45; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeTranslate; property: "x"; to: -3; duration: 45; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeTranslate; property: "x"; to: 0; duration: 45; easing.type: Easing.OutQuad }
    }

    Connections {
        target: root.lock.pam
        function onFlashMsg(): void {
            shakeAnim.restart();
        }
    }

    focus: true
    onActiveFocusChanged: {
        if (!activeFocus)
            forceActiveFocus();
    }

    Keys.onPressed: event => {
        if (root.lock.unlocking)
            return;

        if (event.key === Qt.Key_Escape) {
            if (root.lock.pam.pendingShutdown) {
                root.lock.pam.pendingShutdown = false;
                event.accepted = true;
                return;
            }
        }

        if (event.key === Qt.Key_CapsLock) {
            root.localCapsLock = !root.localCapsLock;
            Hypr.dispatch("global caelestia:refreshDevices");
        }

        // Direct media shortcut handling on lockscreen (SUPER+END for play/pause, SUPER+SHIFT+END for stop - only these two)
        if (event.modifiers & Qt.MetaModifier) {
            if (event.key === Qt.Key_End) {
                if (event.modifiers & Qt.ShiftModifier) {
                    Quickshell.execDetached(["playerctl", "stop"]);
                } else {
                    if (Players.active?.canTogglePlaying)
                        Players.active.togglePlaying();
                    else
                        Quickshell.execDetached(["playerctl", "play-pause"]);
                }
                event.accepted = true;
                return;
            }
        }

        if (event.key === Qt.Key_MediaPlay || event.key === Qt.Key_MediaPause || event.key === Qt.Key_MediaTogglePlayPause) {
            if (Players.active?.canTogglePlaying)
                Players.active.togglePlaying();
            else
                Quickshell.execDetached(["playerctl", "play-pause"]);
            event.accepted = true;
            return;
        } else if (event.key === Qt.Key_MediaNext) {
            if (Players.active?.canGoNext)
                Players.active.next();
            else
                Quickshell.execDetached(["playerctl", "next"]);
            event.accepted = true;
            return;
        } else if (event.key === Qt.Key_MediaPrevious) {
            if (Players.active?.canGoPrevious)
                Players.active.previous();
            else
                Quickshell.execDetached(["playerctl", "previous"]);
            event.accepted = true;
            return;
        } else if (event.key === Qt.Key_MediaStop) {
            Quickshell.execDetached(["playerctl", "stop"]);
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return)
            inputField.placeholder.animate = false;

        root.lock.pam.handleKey(event);
    }

    Behavior on implicitWidth {
        Anim {}
    }

    StateLayer {
        hoverEnabled: false
        cursorShape: Qt.IBeamCursor
        onClicked: parent.forceActiveFocus()
    }

    RowLayout {
        id: input

        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall
        spacing: Tokens.spacing.small

        Item {
            id: iconWrapper

            Layout.fillHeight: true
            implicitWidth: height

            StyledRect {
                id: biometricPulse

                anchors.centerIn: parent
                implicitWidth: parent.height
                implicitHeight: parent.height
                radius: Tokens.rounding.full
                color: Colours.palette.m3primary
                visible: (root.lock.pam.fprint.active || root.lock.pam.howdy.active) && !root.lock.pam.passwd.active

                SequentialAnimation on scale {
                    running: biometricPulse.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.9; to: 1.25; duration: 800; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1.25; to: 0.9; duration: 800; easing.type: Easing.InOutSine }
                }

                SequentialAnimation on opacity {
                    running: biometricPulse.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.28; to: 0.05; duration: 800; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.05; to: 0.28; duration: 800; easing.type: Easing.InOutSine }
                }
            }

            AnimLoader {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: sourceComponent === iconComp ? 1 : 0
                sourceComp: root.lock.pam.passwd.active || root.lock.pam.howdy.active ? loadingComp : iconComp
            }

            Component {
                id: iconComp

                MaterialIcon {
                    animate: true
                    text: {
                        if (inputField.showPassword)
                            return "visibility";
                        if (root.lock.pam.fprint.tries >= GlobalConfig.lock.maxFprintTries) {
                            if (root.lock.pam.howdy.canAttempt)
                                return "face";
                            return "fingerprint_off";
                        }
                        if (root.lock.pam.fprint.active)
                            return "fingerprint";
                        if (root.lock.pam.howdy.canAttempt)
                            return "face";
                        return "lock";
                    }
                    color: !root.lock.pam.howdy.canAttempt && root.lock.pam.fprint.tries >= GlobalConfig.lock.maxFprintTries ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.builders.medium.scale(root.centerScale).build()
                    fill: text === "face" || text === "visibility"

                    StateLayer {
                        anchors.fill: undefined
                        anchors.centerIn: parent
                        implicitWidth: {
                            const w = parent.implicitHeight + Tokens.padding.small * 2;
                            return w + (w % 2);
                        }
                        implicitHeight: implicitWidth
                        radius: Tokens.rounding.full

                        onClicked: {
                            parent.animate = false;
                            inputField.showPassword = !inputField.showPassword;
                            parent.animate = true;
                        }
                    }
                }
            }

            Component {
                id: loadingComp

                LoadingIndicator {
                    implicitSize: iconWrapper.height - Tokens.padding.small * 2
                }
            }
        }

        InputField {
            id: inputField

            Layout.fillWidth: true
            Layout.fillHeight: true

            centerScale: root.centerScale
            pam: root.lock.pam
        }

        StyledRect {
            id: capsLockBadge

            visible: root.isCapsLockOn
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: Math.round(enterButton.implicitHeight * 0.85)
            implicitWidth: visible ? Math.round(capsContent.implicitWidth + Tokens.padding.small * 2) : 0
            radius: Tokens.rounding.full
            color: Colours.palette.m3errorContainer

            opacity: visible ? 1 : 0
            scale: visible ? 1 : 0.85

            Behavior on opacity {
                Anim { type: Anim.DefaultEffects }
            }
            Behavior on scale {
                Anim { type: Anim.FastSpatial }
            }
            Behavior on implicitWidth {
                Anim { type: Anim.FastSpatial }
            }

            RowLayout {
                id: capsContent
                anchors.centerIn: parent
                spacing: Tokens.spacing.extraSmall

                MaterialIcon {
                    text: "keyboard_capslock"
                    color: Colours.palette.m3onErrorContainer
                    fontStyle: Tokens.font.icon.builders.small.scale(root.centerScale * 0.9).build()
                }

                StyledText {
                    text: Tr.tr("CAPS")
                    color: Colours.palette.m3onErrorContainer
                    font: Tokens.font.label.builders.small.scale(root.centerScale * 0.9).weight(Font.Bold).build()
                }
            }
        }

        StyledRect {
            id: kbLayoutBadge

            Layout.alignment: Qt.AlignVCenter
            implicitHeight: Math.round(enterButton.implicitHeight * 0.85)
            implicitWidth: Math.max(implicitHeight, kbText.implicitWidth + Tokens.padding.small * 2)
            radius: Tokens.rounding.full
            color: kbMouse.containsMouse ? Colours.layer(Colours.palette.m3surfaceContainerHighest, 2) : Colours.tPalette.m3surfaceContainerHigh

            Behavior on color {
                CAnim {}
            }

            StyledText {
                id: kbText
                anchors.centerIn: parent
                text: root.layoutCode
                color: kbMouse.containsMouse ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.builders.medium.scale(root.centerScale * 0.9).weight(Font.Bold).build()

                Behavior on color {
                    CAnim {}
                }
            }

            MouseArea {
                id: kbMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "next"]);
                }
            }
        }

        Item {
            id: enterButton

            implicitWidth: implicitHeight
            implicitHeight: {
                const h = enterIcon.implicitHeight + Tokens.padding.extraSmall * 2;
                return h % 2 === 0 ? h : h + 1;
            }

            MaterialShape {
                anchors.fill: parent

                color: root.lock.pam.pendingShutdown
                    ? (root.lock.pam.buffer ? Colours.palette.m3error : Colours.palette.m3errorContainer)
                    : (root.lock.pam.buffer ? Colours.palette.m3primary : Colours.layer(Colours.palette.m3surfaceContainerHigh, 2))
                shape: root.lock.pam.pendingShutdown ? MaterialShape.Cookie4Sided : (root.lock.pam.buffer ? MaterialShape.Arrow : MaterialShape.Circle)
                scale: !root.lock.pam.buffer ? 1 : mouse.pressed ? 0.6 : mouse.containsMouse ? 0.8 : 0.7
                rotation: 90

                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                Behavior on color {
                    CAnim {}
                }

                MouseArea {
                    id: mouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.lock.pam.buffer ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.lock.pam.buffer && root.lock.pam.passwd.start()
                }
            }

            MaterialIcon {
                id: enterIcon

                anchors.centerIn: parent
                text: root.lock.pam.pendingShutdown ? "power_settings_new" : "arrow_forward"
                color: root.lock.pam.pendingShutdown ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.builders.medium.scale(root.centerScale * 1.2).build()
                opacity: root.lock.pam.buffer ? 0 : 1

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }
        }
    }
}
