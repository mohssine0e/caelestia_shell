pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    property string selectedTopic: "Java"
    property string selectedArea: "All"
    property var topics: []
    property var areas: []
    property bool searchActive: false
    property bool isLegacyActive: false
    property var unseenMap: ({})

    signal topicSelected(string topic)
    signal areaSelected(string area)
    signal searchToggled()
    signal legacyToggled()
    signal closeRequested()
    signal moveRequested()

    implicitHeight: navCol.implicitHeight + Tokens.padding.small * 2

    // Background drag region
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onPressed: root.moveRequested()
    }

    ColumnLayout {
        id: navCol
        anchors.fill: parent
        anchors.margins: Tokens.padding.small
        spacing: Tokens.spacing.small

        // Row 1: Topics + Search + Legacy toggle + Close
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            // Topic Pills Flickable
            Flickable {
                id: topicFlick
                Layout.fillWidth: true
                implicitHeight: 32
                contentWidth: topicRow.implicitWidth
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: topicRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Repeater {
                        model: root.topics

                        delegate: Rectangle {
                            id: topicPill
                            required property var modelData
                            required property int index

                            readonly property string topicName: String(modelData || "")
                            readonly property bool active: root.selectedTopic.toLowerCase() === topicName.toLowerCase()
                            readonly property bool hasUnseen: !!root.unseenMap[topicName.toLowerCase()]

                            implicitWidth: topicLabel.implicitWidth + (hasUnseen ? 28 : 20)
                            implicitHeight: 28
                            radius: Tokens.rounding.small
                            color: active ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHigh

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 4

                                StyledText {
                                    id: topicLabel
                                    text: topicPill.topicName
                                    color: topicPill.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.medium
                                }

                                Rectangle {
                                    visible: topicPill.hasUnseen
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: Colours.palette.m3primary
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.topicSelected(topicPill.topicName)
                            }
                        }
                    }
                }
            }

            // Search Toggle Button (P3.4, P3.5)
            IconButton {
                icon: "search"
                type: root.searchActive ? ButtonBase.Filled : ButtonBase.Tonal
                onClicked: root.searchToggled()
            }

            // Legacy Mode Switcher (P0.4 adapter)
            IconButton {
                icon: root.isLegacyActive ? "auto_stories" : "history"
                type: ButtonBase.Tonal
                onClicked: root.legacyToggled()
            }

            // Close Window Button
            IconButton {
                icon: "close"
                type: ButtonBase.Text
                onClicked: root.closeRequested()
            }
        }

        // Row 2: Area Sub-Navigation (Memory & References, Collections, Concurrency, etc.)
        Flickable {
            id: areaFlick
            Layout.fillWidth: true
            visible: !root.searchActive && !root.isLegacyActive && root.areas.length > 0
            implicitHeight: visible ? 26 : 0
            contentWidth: areaRow.implicitWidth
            contentHeight: height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: areaRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Repeater {
                    model: root.areas

                    delegate: Rectangle {
                        id: areaPill
                        required property var modelData
                        required property int index

                        readonly property string areaName: String(modelData || "")
                        readonly property bool active: root.selectedArea.toLowerCase() === areaName.toLowerCase()

                        implicitWidth: areaLabel.implicitWidth + 16
                        implicitHeight: 24
                        radius: Tokens.rounding.full
                        color: active ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.6)

                        StyledText {
                            id: areaLabel
                            anchors.centerIn: parent
                            text: areaPill.areaName
                            color: areaPill.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.areaSelected(areaPill.areaName)
                        }
                    }
                }
            }
        }
    }
}
