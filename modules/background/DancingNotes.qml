import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    property bool running: true
    property color noteColor: Colours.palette.m3primary
    property real noteSize: 26
    property real noteSpacing: 16

    implicitWidth: rowLayout.implicitWidth
    implicitHeight: 48

    Row {
        id: rowLayout
        anchors.centerIn: parent
        spacing: root.noteSpacing

        Repeater {
            model: [
                { symbol: "♪", delay: 0,   maxAngle: -14, bounce: -16 },
                { symbol: "♫", delay: 150, maxAngle: 12,  bounce: -20 },
                { symbol: "♩", delay: 300, maxAngle: -10, bounce: -15 },
                { symbol: "♬", delay: 450, maxAngle: 14,  bounce: -22 },
                { symbol: "♪", delay: 600, maxAngle: -12, bounce: -17 }
            ]

            Item {
                id: noteContainer
                required property var modelData
                required property int index

                width: noteText.implicitWidth + 8
                height: root.implicitHeight

                StyledText {
                    id: noteText
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: (parent.height - implicitHeight) / 2
                    text: noteContainer.modelData.symbol
                    color: root.noteColor
                    font.pixelSize: root.noteSize
                    font.bold: true
                    transformOrigin: Item.Center

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Colours.palette.m3primary
                        shadowOpacity: 0.65
                        shadowBlur: 0.5
                    }

                    SequentialAnimation {
                        id: danceAnim
                        running: root.running && root.visible
                        loops: Animation.Infinite

                        PauseAnimation {
                            duration: noteContainer.modelData.delay
                        }

                        ParallelAnimation {
                            NumberAnimation {
                                target: noteText
                                property: "y"
                                to: ((noteContainer.height - noteText.implicitHeight) / 2) + noteContainer.modelData.bounce
                                duration: 320
                                easing.type: Easing.OutSine
                            }
                            NumberAnimation {
                                target: noteText
                                property: "rotation"
                                to: noteContainer.modelData.maxAngle
                                duration: 320
                                easing.type: Easing.OutSine
                            }
                            NumberAnimation {
                                target: noteText
                                property: "scale"
                                to: 1.25
                                duration: 320
                                easing.type: Easing.OutSine
                            }
                        }

                        ParallelAnimation {
                            NumberAnimation {
                                target: noteText
                                property: "y"
                                to: (noteContainer.height - noteText.implicitHeight) / 2
                                duration: 340
                                easing.type: Easing.InSine
                            }
                            NumberAnimation {
                                target: noteText
                                property: "rotation"
                                to: 0
                                duration: 340
                                easing.type: Easing.InSine
                            }
                            NumberAnimation {
                                target: noteText
                                property: "scale"
                                to: 1.0
                                duration: 340
                                easing.type: Easing.InSine
                            }
                        }

                        PauseAnimation {
                            duration: Math.max(0, 750 - noteContainer.modelData.delay)
                        }
                    }
                }
            }
        }
    }
}
