pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root
    property string query: ""
    property var results: []
    signal resultSelected(var result)

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 26
        anchors.rightMargin: 26
        anchors.topMargin: 23
        anchors.bottomMargin: 14
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: root.query ? qsTr("Search results") : qsTr("Search your notes")
                font: Tokens.font.title.large
                color: Colours.palette.m3onSurface
            }
            StyledText {
                visible: !!root.query
                text: qsTr("%1 matches").arg(root.results.length)
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: root.query ? qsTr("Matches in concepts, code, and original captures")
                : qsTr("Find a rule, command, symbol, or a phrase from the original capture.")
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Colours.palette.m3outlineVariant
        }
        ListView {
            id: resultsList
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: root.results
            clip: true
            delegate: Item {
                id: resultRow
                required property var modelData
                width: resultsList.width
                height: 71
                Rectangle {
                    anchors.fill: parent
                    visible: resultMouse.containsMouse
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3surfaceContainerLow
                }
                Column {
                    anchors.left: parent.left
                    anchors.right: typeLabel.left
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    StyledText {
                        width: parent.width
                        text: (resultRow.modelData.topic || "") + "  /  " +
                            (resultRow.modelData.area || "") + "  /  " +
                            (resultRow.modelData.concept_title || "")
                        color: Colours.palette.m3primary
                        font: Tokens.font.label.medium
                        elide: Text.ElideRight
                    }
                    StyledText {
                        width: parent.width
                        text: resultRow.modelData.match_snippet || ""
                        color: Colours.palette.m3onSurface
                        font: (resultRow.modelData.block_kind === "code" ||
                            resultRow.modelData.block_kind === "command")
                            ? Tokens.font.mono.small : Tokens.font.body.small
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                    }
                }
                StyledText {
                    id: typeLabel
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: resultRow.modelData.block_kind === "source" ? qsTr("SOURCE")
                        : String(resultRow.modelData.block_kind || "").toUpperCase()
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)
                }
                MouseArea {
                    id: resultMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.resultSelected(resultRow.modelData)
                }
            }
        }
        StyledText {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !!root.query && root.results.length === 0
            text: qsTr("No matches yet")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.medium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
