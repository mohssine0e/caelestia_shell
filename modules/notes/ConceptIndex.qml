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

    property string topic: ""
    property string area: ""
    property var concepts: []

    signal conceptSelected(var concept)

    readonly property var filteredConcepts: {
        const list = root.concepts || []
        if (!root.area || root.area.toLowerCase() === "all")
            return list
        return list.filter(c => (c.area || "").toLowerCase() === root.area.toLowerCase())
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        // Empty state
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.filteredConcepts.length === 0

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Tokens.spacing.small

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "menu_book"
                    fontStyle: Tokens.font.icon.large
                    color: Colours.palette.m3outline
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("No concepts found in %1").arg(root.area || root.topic)
                    font: Tokens.font.body.large
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }

        // Concepts ListView
        ListView {
            id: conceptsList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.filteredConcepts.length > 0
            clip: true
            spacing: Tokens.spacing.small

            model: root.filteredConcepts

            delegate: Rectangle {
                id: conceptCard
                required property var modelData
                required property int index

                width: conceptsList.width
                implicitHeight: cardCol.implicitHeight + Tokens.padding.medium * 2
                radius: Tokens.rounding.medium
                color: mouseArea.containsMouse ? Colours.palette.m3surfaceContainerHigh : Colours.palette.m3surfaceContainerLow
                border.color: Colours.palette.m3outlineVariant
                border.width: 1

                ColumnLayout {
                    id: cardCol
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        StyledText {
                            Layout.fillWidth: true
                            text: conceptCard.modelData.title || qsTr("Untitled Concept")
                            font: Tokens.font.title.small
                            color: Colours.palette.m3onSurface
                        }

                        // Depth Preference Tag
                        Rectangle {
                            implicitWidth: depthLabel.implicitWidth + 12
                            implicitHeight: 20
                            radius: Tokens.rounding.small
                            color: (conceptCard.modelData.preferred_depth === "recall")
                                ? Qt.alpha(Colours.palette.m3secondary, 0.18)
                                : Qt.alpha(Colours.palette.m3primary, 0.18)

                            StyledText {
                                id: depthLabel
                                anchors.centerIn: parent
                                text: (conceptCard.modelData.preferred_depth === "recall") ? qsTr("Recall") : qsTr("Understand")
                                font: Tokens.font.label.small
                                color: (conceptCard.modelData.preferred_depth === "recall")
                                    ? Colours.palette.m3secondary
                                    : Colours.palette.m3primary
                            }
                        }

                        // Area Tag (visible if viewing "All")
                        Rectangle {
                            visible: root.area.toLowerCase() === "all" && (conceptCard.modelData.area || "") !== ""
                            implicitWidth: areaTagLabel.implicitWidth + 12
                            implicitHeight: 20
                            radius: Tokens.rounding.small
                            color: Colours.palette.m3surfaceContainerHighest

                            StyledText {
                                id: areaTagLabel
                                anchors.centerIn: parent
                                text: conceptCard.modelData.area || ""
                                font: Tokens.font.label.small
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: (conceptCard.modelData.definition || "") !== ""
                        text: conceptCard.modelData.definition || ""
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                    }
                }

                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.conceptSelected(conceptCard.modelData)
                }
            }
        }
    }
}
