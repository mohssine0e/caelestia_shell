pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
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
    readonly property bool isRedundantSummary: {
        const sum = (root.modelData?.summary ?? "").trim().toLowerCase();
        const app = (root.modelData?.appName ?? "").trim().toLowerCase();
        return sum.length === 0 || sum === app;
    }
    readonly property real nonAnimHeight: expanded
        ? (isRedundantSummary ? 0 : summary.implicitHeight + expandedContent.anchors.topMargin) + expandedContent.implicitHeight + 20
        : summaryHeightMetrics.height

    implicitHeight: nonAnimHeight

    radius: Tokens.rounding.medium
    color: {
        const c = root.modelData?.urgency === NotificationUrgency.Critical ? Colours.palette.m3secondaryContainer : Colours.layer(Colours.palette.m3surfaceContainerHigh, 2);
        return expanded ? c : Qt.alpha(c, 0);
    }

    state: expanded ? "expanded" : ""

    states: State {
        name: "expanded"

        PropertyChanges {
            summary.anchors.margins: 10
            dummySummary.anchors.margins: 10
            compactBody.anchors.margins: 10
            timeStr.anchors.margins: 10
            expandedContent.anchors.margins: 10
            summary.width: root.width - 20 - timeStr.implicitWidth - root.Tokens.spacing.small
            summary.maximumLineCount: Number.MAX_SAFE_INTEGER
        }
    }

    transitions: Transition {
        Anim {
            properties: "margins,width,maximumLineCount"
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
        color: root.modelData?.urgency === NotificationUrgency.Critical ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
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
            color: root.modelData?.urgency === NotificationUrgency.Critical ? Colours.palette.m3secondary : Colours.palette.m3outline
            elide: Text.ElideRight
        }
    }

    WrappedLoader {
        id: timeStr

        shouldBeActive: root.expanded && !root.isRedundantSummary
        anchors.top: parent.top
        anchors.right: parent.right

        sourceComponent: StyledText {
            animate: true
            text: root.modelData?.timeStr ?? ""
            color: Colours.palette.m3outline
            font: Tokens.font.body.small
        }
    }

    WrappedLoader {
        id: expandedContent

        shouldBeActive: root.expanded
        anchors.top: root.isRedundantSummary ? parent.top : summary.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.isRedundantSummary ? 0 : Tokens.spacing.extraSmall

        sourceComponent: ExpandedBody {}
    }

    Behavior on implicitHeight {
        Anim {}
    }

    component ExpandedBody: ColumnLayout {
        readonly property alias body: bodyText
        readonly property string rawBody: root.modelData?.body ?? ""
        readonly property bool isHtml: /<[a-z][\s\S]*>/i.test(rawBody)
        readonly property bool isMarkdown: !isHtml && /[*_`#\[\]]/.test(rawBody)

        spacing: Tokens.spacing.extraSmall

        StyledText {
            id: bodyText

            Layout.fillWidth: true
            textFormat: parent.isHtml ? Text.RichText : (parent.isMarkdown ? Text.MarkdownText : Text.PlainText)
            text: parent.isHtml ? parent.rawBody : (parent.isMarkdown ? String(parent.rawBody).replace(/(.)\n(?!\n)/g, "$1\n\n") : String(parent.rawBody)) || Tr.tr("No body here! :/")
            color: root.modelData?.urgency === NotificationUrgency.Critical ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
            wrapMode: Text.WordWrap

            onLinkActivated: link => {
                Qt.openUrlExternally(link);
                root.screenState.sidebar = false;
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                visible: root.isRedundantSummary
                animate: true
                text: root.modelData?.timeStr ?? ""
                color: Colours.palette.m3outline
                font: Tokens.font.body.small
            }

            NotifActionList {
                notif: root.modelData
            }
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
