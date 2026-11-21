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

    required property var conceptView
    property string highlightBlockId: ""
    property string activeMode: conceptView?.mode || "understand"

    signal backRequested()
    signal depthChanged(string depth)

    readonly property var concept: conceptView?.concept || ({})
    readonly property var blocks: conceptView?.blocks || []
    readonly property var expandableBlocks: conceptView?.expandable_blocks || []
    property bool showExpandedBlocks: false

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        // Top Concept Action Bar
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            IconTextButton {
                text: qsTr("Back")
                icon: "arrow_back"
                type: ButtonBase.Tonal
                onClicked: root.backRequested()
            }

            Item { Layout.fillWidth: true }

            // Understand vs Recall Toggle (P3.3)
            RowLayout {
                spacing: 4

                TextButton {
                    text: qsTr("Understand")
                    isToggle: true
                    checked: root.activeMode === "understand"
                    type: root.activeMode === "understand" ? ButtonBase.Filled : ButtonBase.Tonal
                    onClicked: {
                        root.activeMode = "understand"
                        root.depthChanged("understand")
                        Notes.getConcept(root.concept.id, "understand")
                        Notes.setConceptDepth(root.concept.id, "understand")
                    }
                }

                TextButton {
                    text: qsTr("Recall")
                    isToggle: true
                    checked: root.activeMode === "recall"
                    type: root.activeMode === "recall" ? ButtonBase.Filled : ButtonBase.Tonal
                    onClicked: {
                        root.activeMode = "recall"
                        root.depthChanged("recall")
                        Notes.getConcept(root.concept.id, "recall")
                        Notes.setConceptDepth(root.concept.id, "recall")
                    }
                }
            }

            IconButton {
                icon: "file_download"
                type: ButtonBase.Tonal
                onClicked: {
                    let md = "# " + (root.concept.title || "Concept") + "\n\n"
                    if (root.concept.definition) {
                        md += "**Definition:** " + root.concept.definition + "\n\n"
                    }
                    for (const b of root.blocks || []) {
                        if (b.kind === "code" || b.kind === "command") {
                            const lang = b.language || (b.kind === "command" ? "bash" : "")
                            md += "```" + lang + "\n" + b.content + "\n```\n\n"
                        } else if (b.kind === "caveat") {
                            md += "> [!WARNING]\n> " + b.content + "\n\n"
                        } else {
                            md += "- " + b.content + "\n"
                        }
                    }
                    Quickshell.clipboardText = md
                    Toaster.toast(qsTr("Exported"), qsTr("Copied concept Markdown to clipboard"), "content_copy")
                }
            }
        }

        // Concept Title & Definition Header
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                text: root.concept.title || qsTr("Untitled Concept")
                font: Tokens.font.title.large
                color: Colours.palette.m3onSurface
                wrapMode: Text.WordWrap
            }

            StyledText {
                Layout.fillWidth: true
                visible: (root.concept.definition || "") !== ""
                text: root.concept.definition || ""
                font: Tokens.font.body.large
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.WordWrap
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Colours.palette.m3outlineVariant
            }
        }

        // Structured Blocks View
        ListView {
            id: blocksList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Tokens.spacing.medium

            model: root.blocks

            delegate: Item {
                id: blockDelegate
                required property var modelData
                required property int index

                readonly property bool isHighlighted: root.highlightBlockId === modelData.id
                readonly property string kind: modelData.kind || "rule"

                width: blocksList.width
                implicitHeight: contentCol.implicitHeight + (isHighlighted ? 8 : 0)

                Rectangle {
                    anchors.fill: parent
                    radius: Tokens.rounding.medium
                    color: blockDelegate.isHighlighted ? Qt.alpha(Colours.palette.m3primary, 0.15) : "transparent"
                    border.color: blockDelegate.isHighlighted ? Colours.palette.m3primary : "transparent"
                    border.width: blockDelegate.isHighlighted ? 1 : 0
                }

                ColumnLayout {
                    id: contentCol
                    anchors.fill: parent
                    anchors.margins: blockDelegate.isHighlighted ? 4 : 0
                    spacing: 4

                    // 1. Code & Commands (P3.6)
                    Rectangle {
                        Layout.fillWidth: true
                        visible: blockDelegate.kind === "code" || blockDelegate.kind === "command"
                        radius: Tokens.rounding.medium
                        color: Colours.palette.m3surfaceContainerLowest || "#181c19"
                        border.color: Colours.palette.m3outlineVariant
                        border.width: 1
                        implicitHeight: codeCol.implicitHeight + Tokens.padding.medium * 2

                        ColumnLayout {
                            id: codeCol
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                visible: (blockDelegate.modelData.label || "") !== "" || (blockDelegate.modelData.language || "") !== ""

                                StyledText {
                                    text: blockDelegate.modelData.label || (blockDelegate.kind === "command" ? qsTr("Command") : qsTr("Snippet"))
                                    font: Tokens.font.label.medium
                                    color: Colours.palette.m3primary
                                }

                                Item { Layout.fillWidth: true }

                                StyledText {
                                    text: (blockDelegate.modelData.language || "bash").toUpperCase()
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3onSurfaceVariant
                                }

                                IconButton {
                                    icon: "content_copy"
                                    type: ButtonBase.Text
                                    onClicked: {
                                        Quickshell.clipboardText = blockDelegate.modelData.content
                                        Toaster.toast(qsTr("Copied"), qsTr("Code copied to clipboard"), "content_copy")
                                    }
                                }
                            }

                            Flickable {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.min(260, codeText.implicitHeight)
                                contentWidth: codeText.implicitWidth
                                contentHeight: codeText.implicitHeight
                                clip: true

                                StyledText {
                                    id: codeText
                                    text: blockDelegate.modelData.content || ""
                                    font: Tokens.font.code.medium
                                    color: Colours.palette.m3onSurface
                                    textFormat: Text.PlainText
                                }
                            }
                        }
                    }

                    // 2. Caveat / Gotcha Callout
                    Rectangle {
                        Layout.fillWidth: true
                        visible: blockDelegate.kind === "caveat"
                        radius: Tokens.rounding.medium
                        color: Qt.alpha(Colours.palette.m3tertiary, 0.12)
                        border.color: Colours.palette.m3tertiary
                        border.width: 1
                        implicitHeight: caveatRow.implicitHeight + Tokens.padding.medium * 2

                        RowLayout {
                            id: caveatRow
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                text: "report_problem"
                                color: Colours.palette.m3tertiary
                                fontStyle: Tokens.font.icon.medium
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: blockDelegate.modelData.content || ""
                                font: Tokens.font.body.medium
                                color: Colours.palette.m3onSurface
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // 3. Regular Rules, Mechanisms, Problems, Comparisons
                    RowLayout {
                        Layout.fillWidth: true
                        visible: blockDelegate.kind !== "code" && blockDelegate.kind !== "command" && blockDelegate.kind !== "caveat"
                        spacing: Tokens.spacing.small

                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 6
                            width: 6
                            height: 6
                            radius: 3
                            color: blockDelegate.kind === "rule" ? Colours.palette.m3primary : Colours.palette.m3secondary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: blockDelegate.modelData.content || ""
                            font: Tokens.font.body.medium
                            color: Colours.palette.m3onSurface
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            footer: Item {
                width: blocksList.width
                implicitHeight: root.expandableBlocks.length > 0 && root.activeMode === "recall" ? expandCol.implicitHeight + 20 : 0
                visible: implicitHeight > 0

                ColumnLayout {
                    id: expandCol
                    anchors.fill: parent
                    spacing: Tokens.spacing.small

                    TextButton {
                        text: root.showExpandedBlocks
                            ? qsTr("▴ Hide full explanation")
                            : qsTr("▸ Expand detailed mechanism (%1 blocks)").arg(root.expandableBlocks.length)
                        type: ButtonBase.Tonal
                        onClicked: root.showExpandedBlocks = !root.showExpandedBlocks
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.showExpandedBlocks
                        spacing: 8

                        Repeater {
                            model: root.expandableBlocks
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: 6
                                    width: 4
                                    height: 4
                                    radius: 2
                                    color: Colours.palette.m3outline
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.content || ""
                                    font: Tokens.font.body.medium
                                    color: Colours.palette.m3onSurfaceVariant
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
