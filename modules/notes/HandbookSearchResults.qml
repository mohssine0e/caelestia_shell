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

    property string query: ""
    property var results: []

    signal resultSelected(var result)
    signal closeSearchRequested()

    function focusInput(): void {
        searchInput.forceActiveFocus()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        // Search Input Bar
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 42
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceContainerHigh
                border.color: searchInput.activeFocus ? Colours.palette.m3primary : Colours.palette.m3outlineVariant
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.medium
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "search"
                        color: searchInput.activeFocus ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        text: root.query
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                        selectionColor: Colours.palette.m3primaryContainer
                        selectedTextColor: Colours.palette.m3onPrimaryContainer
                        renderType: Text.NativeRendering
                        verticalAlignment: TextInput.AlignVCenter

                        onTextChanged: {
                            root.query = text
                            Notes.searchConcepts(text)
                        }

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                event.accepted = true
                                root.closeSearchRequested()
                            }
                        }

                        StyledText {
                            anchors.fill: parent
                            visible: !searchInput.text && !searchInput.activeFocus
                            text: qsTr("Search concepts, rules, code, caveats...")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.medium
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    IconButton {
                        visible: searchInput.text.length > 0
                        icon: "close"
                        type: ButtonBase.Text
                        onClicked: {
                            searchInput.clear()
                            root.query = ""
                        }
                    }
                }
            }

            IconButton {
                icon: "close"
                type: ButtonBase.Tonal
                onClicked: root.closeSearchRequested()
            }
        }

        // Search Results List
        ListView {
            id: resultsList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Tokens.spacing.small

            model: root.results

            delegate: Rectangle {
                id: resultCard
                required property var modelData
                required property int index

                width: resultsList.width
                implicitHeight: resCol.implicitHeight + Tokens.padding.medium * 2
                radius: Tokens.rounding.medium
                color: resMouse.containsMouse ? Colours.palette.m3surfaceContainerHigh : Colours.palette.m3surfaceContainerLow
                border.color: Colours.palette.m3outlineVariant
                border.width: 1

                ColumnLayout {
                    id: resCol
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        // Breadcrumb: topic > area > concept
                        StyledText {
                            Layout.fillWidth: true
                            text: (resultCard.modelData.topic || "") + " › " +
                                  (resultCard.modelData.area ? resultCard.modelData.area + " › " : "") +
                                  (resultCard.modelData.concept_title || "")
                            font: Tokens.font.label.medium
                            color: Colours.palette.m3primary
                            elide: Text.ElideRight
                        }

                        // Block Kind Badge
                        Rectangle {
                            implicitWidth: kindLabel.implicitWidth + 12
                            implicitHeight: 20
                            radius: Tokens.rounding.small
                            color: resultCard.modelData.block_kind === "code" || resultCard.modelData.block_kind === "command"
                                ? Qt.alpha(Colours.palette.m3secondary, 0.18)
                                : (resultCard.modelData.block_kind === "caveat"
                                    ? Qt.alpha(Colours.palette.m3tertiary, 0.18)
                                    : Qt.alpha(Colours.palette.m3primary, 0.18))

                            StyledText {
                                id: kindLabel
                                anchors.centerIn: parent
                                text: (resultCard.modelData.block_kind || "rule").toUpperCase()
                                font: Tokens.font.label.small
                                color: resultCard.modelData.block_kind === "code" || resultCard.modelData.block_kind === "command"
                                    ? Colours.palette.m3secondary
                                    : (resultCard.modelData.block_kind === "caveat"
                                        ? Colours.palette.m3tertiary
                                        : Colours.palette.m3primary)
                            }
                        }
                    }

                    // Matching Snippet
                    StyledText {
                        Layout.fillWidth: true
                        text: resultCard.modelData.match_snippet || ""
                        font: (resultCard.modelData.block_kind === "code" || resultCard.modelData.block_kind === "command")
                            ? Tokens.font.code.small
                            : Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                    }
                }

                MouseArea {
                    id: resMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.resultSelected(resultCard.modelData)
                }
            }

            // Empty state
            Item {
                anchors.centerIn: parent
                visible: root.results.length === 0 && root.query.trim().length > 0

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "search_off"
                        fontStyle: Tokens.font.icon.large
                        color: Colours.palette.m3outline
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("No matching blocks found for '%1'").arg(root.query)
                        font: Tokens.font.body.large
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }
    }
}
