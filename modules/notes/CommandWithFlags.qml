pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Caelestia.Config
import qs.services
import "FlagCatalog.js" as FlagCatalog

Item {
    id: root

    property string command: ""
    property bool isRecent: false
    signal flagHovered(string flag, string explanation, real globalX, real globalY)
    signal flagUnhovered()

    implicitWidth: tokenRow.implicitWidth
    implicitHeight: tokenRow.implicitHeight

    readonly property var tokens: FlagCatalog.parseTokens(root.command)

    Flickable {
        id: commandScroll
        anchors.fill: parent
        contentWidth: tokenRow.implicitWidth
        contentHeight: height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
        interactive: contentWidth > width
        HoverHandler { id: commandHover }
        ToolTip.visible: commandHover.hovered && contentWidth > width
        ToolTip.delay: 500
        ToolTip.text: root.command

        Row {
            id: tokenRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5

            Text {
                text: "$"
                color: root.isRecent ? Colours.palette.m3success : Colours.palette.m3primary
                font: Qt.font({ family: Tokens.font.mono.small.family, pixelSize: 14 })
                opacity: 0.6
            }

            Repeater {
                model: root.tokens
                delegate: Item {
                    id: tokenItem
                    required property var modelData
                    implicitWidth: modelData.isFlag ? (flagChip.implicitWidth + 4) : plainText.implicitWidth
                    implicitHeight: modelData.isFlag ? (flagChip.implicitHeight + 2) : plainText.implicitHeight

                    Text {
                        id: plainText
                        visible: !tokenItem.modelData.isFlag
                        anchors.verticalCenter: parent.verticalCenter
                        text: tokenItem.modelData.text
                        color: root.isRecent ? Colours.palette.m3success : Colours.palette.m3primary
                        font: Qt.font({ family: Tokens.font.mono.small.family, pixelSize: 14 })
                        wrapMode: Text.NoWrap
                    }

                    Rectangle {
                        id: flagChip
                        visible: tokenItem.modelData.isFlag
                        anchors.centerIn: parent
                        implicitWidth: flagText.implicitWidth + 6
                        implicitHeight: flagText.implicitHeight + 2
                        radius: 3
                        color: flagHover.hovered
                            ? Qt.alpha(Colours.palette.m3primary, 0.22)
                            : "transparent"

                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            id: flagText
                            anchors.centerIn: parent
                            text: tokenItem.modelData.text
                            color: root.isRecent ? Colours.palette.m3success : Colours.palette.m3primary
                            font: Qt.font({
                                family: Tokens.font.mono.small.family,
                                pixelSize: 14,
                                weight: flagHover.hovered ? Font.Bold : Font.Normal
                            })
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: Qt.alpha(Colours.palette.m3primary, flagHover.hovered ? 0.9 : 0.4)
                            opacity: 0.8
                        }

                        HoverHandler {
                            id: flagHover
                            cursorShape: Qt.PointingHandCursor
                            onHoveredChanged: {
                                if (hovered) {
                                    const exp = FlagCatalog.getExplanation(
                                        tokenItem.modelData.tool, tokenItem.modelData.text,
                                        tokenItem.modelData.subcommand)
                                    const pt = flagChip.mapToItem(null, 0, 0)
                                    root.flagHovered(tokenItem.modelData.text,
                                        exp || qsTr("No help for this tool and subcommand."), pt.x, pt.y)
                                } else {
                                    root.flagUnhovered()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
