pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.effects
import qs.services

Item {
    id: root

    required property NotifData notif

    Layout.fillWidth: true
    implicitHeight: flickable.contentHeight

    layer.enabled: true
    layer.smooth: true
    layer.effect: Mask {
        maskSource: gradientMask
    }

    Item {
        id: gradientMask

        anchors.fill: parent
        layer.enabled: true
        visible: false

        Rectangle {
            anchors.fill: parent

            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    position: 0
                    color: Qt.rgba(0, 0, 0, 0)
                }
                GradientStop {
                    position: 0.1
                    color: Qt.rgba(0, 0, 0, 1)
                }
                GradientStop {
                    position: 0.9
                    color: Qt.rgba(0, 0, 0, 1)
                }
                GradientStop {
                    position: 1
                    color: Qt.rgba(0, 0, 0, 0)
                }
            }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left

            implicitWidth: parent.width / 2
            opacity: flickable.contentX > 0 ? 0 : 1

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right

            implicitWidth: parent.width / 2
            opacity: flickable.contentX < flickable.contentWidth - parent.width ? 0 : 1

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }
    }

    StyledFlickable {
        id: flickable

        anchors.fill: parent
        contentWidth: Math.max(width, actionList.implicitWidth)
        contentHeight: actionList.implicitHeight

        RowLayout {
            id: actionList

            anchors.fill: parent
            spacing: Tokens.spacing.extraSmall

            Item {
                Layout.fillWidth: true
                visible: (root.notif?.actions?.length ?? 0) === 0
            }

            Repeater {
                model: [
                    ...(root.notif?.actions ?? []),
                    {
                        isCopy: true
                    },
                    {
                        isClose: true
                    }
                ]

                StyledRect {
                    id: action

                    required property var modelData
                    readonly property bool isCompactIcon: Boolean(modelData.isClose || modelData.isCopy)

                    Layout.fillWidth: !isCompactIcon
                    Layout.fillHeight: true
                    implicitWidth: isCompactIcon ? implicitHeight + Tokens.padding.small : actionInner.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: actionInner.implicitHeight + Tokens.padding.extraSmall * 2

                    Layout.preferredWidth: implicitWidth + (actionStateLayer.pressed ? Tokens.padding.small : 0)
                    radius: isCompactIcon ? Tokens.rounding.full : (actionStateLayer.pressed ? Tokens.rounding.medium / 2 : Tokens.rounding.medium)
                    color: Colours.layer(Colours.palette.m3surfaceContainerHighest, 4)

                    Timer {
                        id: copyTimer

                        interval: 3000
                        onTriggered: (actionInner.item as MaterialIcon).text = "content_copy"
                    }

                    StateLayer {
                        id: actionStateLayer

                        onClicked: {
                            if (action.modelData.isClose) {
                                root.notif.close();
                            } else if (action.modelData.isCopy) {
                                Quickshell.clipboardText = root.notif.body;
                                (actionInner.item as MaterialIcon).text = "inventory";
                                copyTimer.start();
                            } else {
                                if (action.modelData.invoke)
                                    action.modelData.invoke();
                                if (!root.notif.resident)
                                    root.notif.close();
                            }
                        }
                    }

                    Loader {
                        id: actionInner

                        anchors.centerIn: parent
                        sourceComponent: action.isCompactIcon ? iconBtn : (root.notif?.hasActionIcons && Quickshell.hasThemeIcon(action.modelData.identifier)) ? iconComp : textComp
                    }

                    Component {
                        id: iconBtn

                        MaterialIcon {
                            animate: action.modelData.isCopy ?? false
                            text: action.modelData.isCopy ? "content_copy" : "close"
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }

                    Component {
                        id: iconComp

                        IconImage {
                            asynchronous: true
                            source: Quickshell.iconPath(action.modelData.identifier)
                        }
                    }

                    Component {
                        id: textComp

                        StyledText {
                            text: action.modelData.text
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }

                    Behavior on Layout.preferredWidth {
                        Anim {
                            type: Anim.FastSpatial
                        }
                    }

                    Behavior on radius {
                        Anim {
                            type: Anim.FastSpatial
                        }
                    }
                }
            }
        }
    }
}
