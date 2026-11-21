pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root
    property string selectedTopic: "All"
    property string selectedArea: "All"
    property var topics: []
    property var areas: []
    property var unseenMap: ({})
    property var unseenAreas: ({})
    property string searchText: ""
    property bool isLegacyActive: false

    signal topicSelected(string topic)
    signal areaSelected(string area)
    signal searchRequested()
    signal searchEdited(string query)
    signal legacyToggled()
    signal closeRequested()
    signal moveRequested()

    function focusSearch(): void { searchInput.forceActiveFocus() }
    function releaseSearchFocus(): bool {
        if (!searchInput.activeFocus) return false
        root.forceActiveFocus()
        return true
    }

    implicitHeight: 92

    Rectangle {
        anchors.fill: parent
        color: Colours.palette.m3surfaceContainerLow
        radius: Tokens.rounding.medium
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onPressed: root.moveRequested()
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 14
        anchors.topMargin: 10
        anchors.bottomMargin: 8
        spacing: 9
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            MaterialIcon {
                id: bookIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "auto_stories"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.medium
            }
            Flickable {
                id: topicsScroll
                anchors.left: bookIcon.right
                anchors.right: searchBox.left
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                height: 32
                contentWidth: topicsRow.implicitWidth
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Row {
                    id: topicsRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    Repeater {
                        model: root.topics
                        delegate: Rectangle {
                            id: topicPill
                            required property var modelData
                            readonly property string topic: String(modelData)
                            readonly property bool active: root.selectedTopic === topic
                            readonly property bool unseen: !!root.unseenMap[topic.toLowerCase()]
                            implicitWidth: topicRow.implicitWidth + 18
                            implicitHeight: 29
                            radius: Tokens.rounding.small
                            color: active ? Colours.palette.m3secondaryContainer : "transparent"
                            Row {
                                id: topicRow
                                anchors.centerIn: parent
                                spacing: 5
                                StyledText {
                                    text: topicPill.topic
                                    font: Tokens.font.label.medium
                                    color: topicPill.active ? Colours.palette.m3onSecondaryContainer
                                        : Colours.palette.m3onSurfaceVariant
                                }
                                Rectangle {
                                    visible: topicPill.unseen
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 5
                                    height: 5
                                    radius: 3
                                    color: Colours.palette.m3primary
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.topicSelected(topicPill.topic)
                            }
                        }
                    }
                }
            }
            Rectangle {
                id: searchBox
                anchors.right: legacyButton.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 192
                height: 32
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh
                border.width: searchInput.activeFocus ? 1 : 0
                border.color: Colours.palette.m3primary
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    spacing: 6
                    MaterialIcon {
                        text: "search"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }
                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        text: root.searchText
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.body.small
                        selectByMouse: true
                        clip: true
                        verticalAlignment: TextInput.AlignVCenter
                        onActiveFocusChanged: if (activeFocus) root.searchRequested()
                        onTextEdited: {
                            root.searchText = text
                            root.searchEdited(text)
                        }
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                root.releaseSearchFocus()
                                event.accepted = true
                            }
                        }
                        StyledText {
                            visible: !searchInput.text
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Search  /")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                        }
                    }
                }
            }
            IconButton {
                id: legacyButton
                anchors.right: closeButton.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32
                icon: root.isLegacyActive ? "menu_book" : "inventory_2"
                type: ButtonBase.Text
                onClicked: root.legacyToggled()
            }
            IconButton {
                id: closeButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32
                icon: "close"
                type: ButtonBase.Text
                onClicked: root.closeRequested()
            }
        }
        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            contentWidth: areasRow.implicitWidth
            contentHeight: height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Row {
                id: areasRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Repeater {
                    model: root.areas
                    delegate: Rectangle {
                        id: areaPill
                        required property var modelData
                        readonly property string area: String(modelData)
                        readonly property bool active: root.selectedArea === area
                        readonly property bool unseen: area === "All"
                            ? Object.keys(root.unseenAreas).length > 0
                            : !!root.unseenAreas[area.toLowerCase()]
                        implicitWidth: areaRow.implicitWidth + 16
                        implicitHeight: 23
                        radius: Tokens.rounding.small
                        color: active ? Qt.alpha(Colours.palette.m3primary, 0.17) : "transparent"
                        Row {
                            id: areaRow
                            anchors.centerIn: parent
                            spacing: 5
                            StyledText {
                                text: areaPill.area
                                color: areaPill.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                            }
                            Rectangle {
                                visible: areaPill.unseen
                                anchors.verticalCenter: parent.verticalCenter
                                width: 5
                                height: 5
                                radius: 3
                                color: Colours.palette.m3primary
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.areaSelected(areaPill.area)
                        }
                    }
                }
            }
        }
    }
}
