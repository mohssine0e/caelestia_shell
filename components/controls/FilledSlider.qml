import QtQuick
import QtQuick.Templates
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services

Slider {
    id: root

    required property string icon
    property real oldValue
    property bool initialized
    readonly property bool overAmplified: root.value > 1.0

    orientation: Qt.Vertical

    background: StyledRect {
        color: Colours.palette.m3surfaceContainerHighest
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3outline, 0.35)
        radius: Tokens.rounding.full

        // 100% threshold marker when over-amplification is supported (to > 1.0)
        Rectangle {
            id: threshold100

            visible: root.to > 1.0 && root.from < 1.0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            height: 1.5
            z: 2
            y: {
                if (root.to <= root.from)
                    return 0;
                const ratio = Math.max(0, Math.min(1, (1.0 - root.from) / (root.to - root.from)));
                return Math.round((1.0 - ratio) * (root.availableHeight - handle.height) + handle.height / 2);
            }
            color: Qt.alpha(Colours.palette.m3outline, 0.45)
            radius: 1
        }

        StyledRect {
            anchors.left: parent.left
            anchors.right: parent.right

            y: root.handle.y
            implicitHeight: parent.height - y

            color: root.overAmplified ? Colours.palette.m3error : Colours.palette.m3secondary
            radius: parent.radius
        }
    }

    handle: Item {
        id: handle

        property alias moving: icon.moving

        y: root.visualPosition * (root.availableHeight - height)
        implicitWidth: root.width
        implicitHeight: root.width
        transformOrigin: Item.Center

        Elevation {
            anchors.fill: parent
            radius: rect.radius
            level: handleInteraction.containsMouse ? 2 : 1
        }

        StyledRect {
            id: rect

            anchors.fill: parent

            color: root.overAmplified ? Colours.palette.m3error : Colours.palette.m3inverseSurface
            radius: Tokens.rounding.full

            MouseArea {
                id: handleInteraction

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.NoButton
            }

            MaterialIcon {
                id: icon

                property bool moving

                anchors.centerIn: parent
                anchors.verticalCenterOffset: 1
                text: moving ? Math.round(root.value * 100) : root.icon
                color: root.overAmplified ? Colours.palette.m3onError : Colours.palette.m3inverseOnSurface
                font: moving ? Tokens.font.body.small : Tokens.font.icon.medium

                Behavior on color {
                    CAnim {}
                }

                Behavior on moving {
                    SequentialAnimation {
                        Anim {
                            target: icon
                            property: "scale"
                            to: 0.3
                            duration: Tokens.anim.durations.small / 2
                            easing: Tokens.anim.standardAccel
                        }
                        PropertyAction {}
                        Anim {
                            target: icon
                            property: "scale"
                            to: 1
                            duration: Tokens.anim.durations.normal / 2
                            easing: Tokens.anim.standardDecel
                        }
                    }
                }
            }
        }
    }

    onOverAmplifiedChanged: {
        if (root.initialized && root.overAmplified)
            pulseAnim.restart();
    }

    SequentialAnimation {
        id: pulseAnim

        Anim {
            target: handle
            property: "scale"
            to: 1.12
            duration: Tokens.anim.durations.small / 2
            easing.type: Easing.OutQuad
        }
        Anim {
            target: handle
            property: "scale"
            to: 1.0
            duration: Tokens.anim.durations.normal / 2
            easing.type: Easing.OutBack
        }
    }

    onPressedChanged: handle.moving = pressed

    onValueChanged: {
        if (!initialized) {
            initialized = true;
            return;
        }
        if (Math.abs(value - oldValue) < 0.01)
            return;
        oldValue = value;
        handle.moving = true;
        stateChangeDelay.restart();
    }

    Timer {
        id: stateChangeDelay

        interval: 500
        onTriggered: {
            if (!root.pressed)
                handle.moving = false;
        }
    }

    Behavior on value {
        Anim {
            type: Anim.StandardLarge
        }
    }
}
