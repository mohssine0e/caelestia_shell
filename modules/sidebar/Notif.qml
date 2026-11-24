pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services
import qs.utils

StyledRect {
    id: root

    required property NotifData modelData
    required property Props props
    required property bool expanded
    required property ScreenState screenState

    readonly property StyledText body: (expandedContent.item as ExpandedBody)?.body ?? null
    readonly property bool isCritical: root.modelData?.urgency === NotificationUrgency.Critical
    readonly property bool isRedundantSummary: {
        const sum = (root.modelData?.summary ?? "").trim().toLowerCase();
        const app = (root.modelData?.appName ?? "").trim().toLowerCase();
        return sum.length === 0 || sum === app;
    }
    readonly property real headerHeight: isRedundantSummary
        ? Math.max(leftTime.implicitHeight, topActions.implicitHeight)
        : Math.max(summary.implicitHeight + 2, topActions.implicitHeight)
    readonly property real nonAnimHeight: expanded
        ? headerHeight + Tokens.spacing.small + expandedContent.implicitHeight + 20
        : summaryHeightMetrics.height

    implicitHeight: nonAnimHeight

    radius: Tokens.rounding.medium
    color: {
        const c = isCritical ? Colours.palette.m3secondaryContainer : Colours.layer(Colours.palette.m3surfaceContainerHigh, 2);
        return expanded ? c : Qt.alpha(c, 0);
    }
    border.width: expanded ? 1 : 0
    border.color: isCritical ? Qt.alpha(Colours.palette.m3error, 0.5) : Qt.alpha(Colours.palette.m3outlineVariant, 0.55)

    state: expanded ? "expanded" : ""

    states: State {
        name: "expanded"

        PropertyChanges {
            summary.anchors.margins: 10
            summary.anchors.topMargin: 12
            dummySummary.anchors.margins: 10
            compactBody.anchors.margins: 10
            summary.width: root.width - 20 - topActions.implicitWidth - root.Tokens.spacing.small
            summary.maximumLineCount: Number.MAX_SAFE_INTEGER
        }
    }

    transitions: Transition {
        Anim {
            properties: "margins,topMargin,width,maximumLineCount"
        }
    }

    TextMetrics {
        id: summaryHeightMetrics

        font: summary.font
        text: " " // Use this height to prevent weird characters from changing the line height
    }

    StyledText {
        id: summary

        anchors.top: parent.top
        anchors.left: parent.left

        visible: !root.isRedundantSummary
        width: parent.width
        text: root.isRedundantSummary ? "" : (root.modelData?.summary ?? "")
        color: root.isCritical ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
        elide: Text.ElideRight
        wrapMode: Text.WordWrap
        maximumLineCount: 1
    }

    StyledText {
        id: dummySummary

        anchors.top: parent.top
        anchors.left: parent.left

        visible: false
        text: summary.visible ? summary.text : ""
    }

    WrappedLoader {
        id: compactBody

        shouldBeActive: !root.expanded
        anchors.top: parent.top
        anchors.left: dummySummary.right
        anchors.right: parent.right
        anchors.leftMargin: dummySummary.text.length > 0 ? Tokens.spacing.small : 0

        sourceComponent: StyledText {
            text: Strings.stripHtml(root.modelData?.body ?? "")
            color: root.isCritical ? Colours.palette.m3secondary : Colours.palette.m3outline
            elide: Text.ElideRight
        }
    }

    WrappedLoader {
        id: leftTime

        shouldBeActive: root.expanded && root.isRedundantSummary
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: 13
        anchors.leftMargin: 10

        sourceComponent: StyledText {
            animate: true
            text: root.modelData?.timeStr ?? ""
            color: Colours.palette.m3outline
            font: Tokens.font.body.small
        }
    }

    WrappedLoader {
        id: topActions

        shouldBeActive: root.expanded
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 10
        anchors.rightMargin: 10

        sourceComponent: RowLayout {
            spacing: Tokens.spacing.extraSmall

            Timer {
                id: copyTimer

                interval: 2500
            }

            StyledText {
                visible: !root.isRedundantSummary
                Layout.rightMargin: Tokens.spacing.extraSmall
                animate: true
                text: root.modelData?.timeStr ?? ""
                color: Colours.palette.m3outline
                font: Tokens.font.body.small
            }

            StyledRect {
                implicitWidth: 24
                implicitHeight: 24
                radius: Tokens.rounding.full
                color: copyLayer.containsMouse ? Colours.layer(Colours.palette.m3surfaceContainerHighest, 3) : Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.5)

                StateLayer {
                    id: copyLayer

                    color: Colours.palette.m3onSurface
                    onClicked: {
                        Quickshell.clipboardText = Strings.stripHtml(root.modelData?.body ?? "");
                        copyTimer.restart();
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    animate: true
                    text: copyTimer.running ? "check" : "content_copy"
                    color: copyTimer.running ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }
            }

            StyledRect {
                implicitWidth: 24
                implicitHeight: 24
                radius: Tokens.rounding.full
                color: closeLayer.containsMouse ? Qt.alpha(Colours.palette.m3errorContainer, 0.8) : Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.5)

                StateLayer {
                    id: closeLayer

                    color: Colours.palette.m3onErrorContainer
                    onClicked: root.modelData?.close()
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "close"
                    color: closeLayer.containsMouse ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }
            }
        }
    }

    WrappedLoader {
        id: expandedContent

        shouldBeActive: root.expanded
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: root.expanded ? 10 + root.headerHeight + Tokens.spacing.small : 0

        sourceComponent: ExpandedBody {}
    }

    Behavior on implicitHeight {
        Anim {}
    }

    component ExpandedBody: ColumnLayout {
        readonly property alias body: bodyText
        readonly property string cleanedBody: Strings.cleanNotifBody(root.modelData?.body ?? "")
        readonly property bool isHtml: /<[a-z][\s\S]*>/i.test(cleanedBody)
        readonly property bool isMarkdown: !isHtml && /[*_`#\[\]]/.test(cleanedBody)

        spacing: Tokens.spacing.small

        StyledText {
            id: bodyText

            Layout.fillWidth: true
            textFormat: parent.isHtml ? Text.RichText : (parent.isMarkdown ? Text.MarkdownText : Text.PlainText)
            text: parent.isHtml ? parent.cleanedBody : (parent.isMarkdown ? String(parent.cleanedBody).replace(/(.)\n(?!\n)/g, "$1\n\n") : parent.cleanedBody) || Tr.tr("No body here! :/")
            color: root.isCritical ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
            linkColor: Colours.palette.m3primary
            wrapMode: Text.WordWrap

            onLinkActivated: link => {
                Qt.openUrlExternally(link);
                root.screenState.sidebar = false;
            }
        }

        NotifActionList {
            visible: (root.modelData?.actions?.length ?? 0) > 0
            notif: root.modelData
        }
    }

    component WrappedLoader: Loader {
        id: comp

        required property bool shouldBeActive

        active: false
        opacity: 0

        // Makes the loader load on the same frame shouldBeActive becomes true, which ensures size is set
        states: State {
            name: "active"
            when: comp.shouldBeActive

            PropertyChanges {
                comp.opacity: 1
                comp.active: true
            }
        }

        transitions: [
            Transition {
                from: ""
                to: "active"

                SequentialAnimation {
                    PropertyAction {
                        property: "active"
                    }
                    Anim {
                        type: Anim.DefaultEffects
                        property: "opacity"
                    }
                }
            },
            Transition {
                from: "active"
                to: ""

                SequentialAnimation {
                    Anim {
                        type: Anim.DefaultEffects
                        property: "opacity"
                    }
                    PropertyAction {
                        property: "active"
                    }
                }
            }
        ]
    }
}
