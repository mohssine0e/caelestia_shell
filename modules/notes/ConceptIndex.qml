pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root
    property string topic: "All"
    property string area: "All"
    property var concepts: []
    signal conceptSelected(var concept)

    readonly property var filteredConcepts: (root.concepts || []).filter(c =>
        (root.topic === "All" || String(c.topic).toLowerCase() === root.topic.toLowerCase())
        && (root.area === "All" || String(c.area).toLowerCase() === root.area.toLowerCase()))

    readonly property var rows: {
        const sorted = root.filteredConcepts.slice().sort((a, b) =>
            String(a.topic).localeCompare(String(b.topic)) ||
            String(a.area).localeCompare(String(b.area)) ||
            String(a.title).localeCompare(String(b.title)))
        const rows = []
        let lastGroup = ""
        for (const concept of sorted) {
            const group = root.topic === "All"
                ? String(concept.topic || "General") + "  /  " + String(concept.area || "General")
                : String(concept.area || "General")
            if (group !== lastGroup) {
                rows.push({ type: "heading", label: group })
                lastGroup = group
            }
            rows.push({ type: "concept", value: concept })
        }
        return rows
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 26
        anchors.rightMargin: 26
        anchors.topMargin: 23
        anchors.bottomMargin: 14
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            StyledText {
                Layout.fillWidth: true
                text: root.topic === "All" ? qsTr("Your knowledge") : root.topic
                font: Tokens.font.title.large
                color: Colours.palette.m3onSurface
                elide: Text.ElideRight
            }
            StyledText {
                text: qsTr("%1 concepts").arg(root.filteredConcepts.length)
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: root.topic === "All"
                ? qsTr("Choose a concept to understand it, or return later for a quick recall.")
                : qsTr("Ideas, rules, and examples collected under this topic.")
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.WordWrap
        }

        GapSuggestions {
            Layout.fillWidth: true
            visible: root.topic !== "All"
            scope: root.area === "All" ? "topic" : "area"
            topic: root.topic
            area: root.area
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Colours.palette.m3outlineVariant
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 0
            model: root.rows
            delegate: Item {
                id: row
                required property var modelData
                readonly property bool heading: modelData.type === "heading"
                readonly property var concept: modelData.value || ({})
                width: list.width
                height: heading ? 42 : Math.max(62, titleText.implicitHeight + description.implicitHeight + 20)

                StyledText {
                    visible: row.heading
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    text: row.modelData.label || ""
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3primary
                }

                Rectangle {
                    visible: !row.heading && rowMouse.containsMouse
                    anchors.fill: parent
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3surfaceContainerLow
                }

                Column {
                    visible: !row.heading
                    anchors.left: parent.left
                    anchors.right: arrow.left
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Row {
                        width: parent.width
                        spacing: 7
                        Rectangle {
                            visible: !!row.concept.unseen
                            anchors.verticalCenter: titleText.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: Colours.palette.m3primary
                        }
                        StyledText {
                            id: titleText
                            width: Math.max(0, parent.width - (row.concept.unseen ? 15 : 0))
                            text: row.concept.title || ""
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.title.small
                            elide: Text.ElideRight
                        }
                    }
                    StyledText {
                        id: description
                        width: parent.width
                        text: row.concept.definition || ""
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
                MaterialIcon {
                    id: arrow
                    visible: !row.heading
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "chevron_right"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }
                Rectangle {
                    visible: !row.heading
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Qt.alpha(Colours.palette.m3outlineVariant, 0.35)
                }
                MouseArea {
                    id: rowMouse
                    visible: !row.heading
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.conceptSelected(row.concept)
                }
            }
        }
        StyledText {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.rows.length === 0
            text: qsTr("No concepts here yet. Your original captures remain in Sources.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.medium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
        }
    }
}
