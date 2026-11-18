import QtQuick
import QtQuick.Layouts
import Caelestia
import Caelestia.Blobs
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    property bool open
    readonly property real padding: Tokens.padding.large

    implicitWidth: btn.implicitWidth * 0.9
    implicitHeight: btn.implicitHeight * 0.9

    BlobGroup {
        id: blobGroup

        color: Colours.palette.m3surfaceContainerHighest
        smoothing: root.Tokens.rounding.medium
        cornerFill: false

        Behavior on color {
            CAnim {}
        }
    }

    BlobRect {
        id: btnRect

        anchors.fill: parent
        anchors.margins: !btn.pressed && btn.containsMouse ? -Tokens.padding.extraSmall : 0
        group: blobGroup
        radius: Tokens.rounding.medium

        Behavior on anchors.margins {
            Anim {}
        }
    }

    BlobRect {
        id: rect

        anchors.right: parent.right
        anchors.top: parent.top

        implicitWidth: parent.width
        implicitHeight: parent.height

        group: blobGroup
        radius: Tokens.rounding.medium
        deformScale: 0.00001

        states: State {
            name: "open"
            when: root.open

            PropertyChanges {
                rect.anchors.rightMargin: root.width - root.Tokens.spacing.small
                rect.anchors.topMargin: -root.Tokens.padding.medium
                rect.implicitWidth: Math.max(layout.implicitWidth, placeholder.implicitWidth) + root.padding * 2
                rect.implicitHeight: Math.max(layout.implicitHeight, placeholder.implicitHeight) + root.padding * 2
                content.opacity: 1
            }
        }

        transitions: Transition {
            Anim {
                properties: "rightMargin,implicitWidth"
            }
            Anim {
                properties: "topMargin,implicitHeight"
                easing: root.Tokens.anim.expressiveFastSpatial
            }
            Anim {
                property: "opacity"
                type: Anim.DefaultEffects
            }
        }

        Behavior on implicitWidth {
            Anim {}
        }

        Behavior on implicitHeight {
            Anim {}
        }

        Item {
            id: content

            anchors.fill: parent
            clip: true
            opacity: 0
            state: LyricsSource.status === "synced" || LyricsSource.status === "plain" ? "hasLyrics" : ""

            states: State {
                name: "hasLyrics"

                PropertyChanges {
                    layout.opacity: 1
                    placeholder.opacity: 0
                }
            }

            transitions: [
                Transition {
                    from: "hasLyrics"

                    SequentialAnimation {
                        Anim {
                            target: layout
                            property: "opacity"
                            type: Anim.FastEffects
                        }
                        Anim {
                            target: placeholder
                            property: "opacity"
                            type: Anim.DefaultEffects
                        }
                    }
                },
                Transition {
                    to: "hasLyrics"

                    SequentialAnimation {
                        Anim {
                            target: placeholder
                            property: "opacity"
                            type: Anim.FastEffects
                        }
                        Anim {
                            target: layout
                            property: "opacity"
                            type: Anim.DefaultEffects
                        }
                    }
                }
            ]

            ColumnLayout {
                id: layout

                anchors.centerIn: parent
                spacing: Tokens.spacing.extraSmall
                opacity: 0

                // The source actually on screen (the same one the desktop overlay uses).
                StyledText {
                    // TRANSLATORS: %1 = lyrics source name, e.g. LRCLIB
                    text: LyricsSource.provider === "shell" ? Tr.tr("Backend: %1").arg(CUtils.enumToString(Lyrics, "backend")) : Tr.tr("Source: %1").arg(LyricsSource.sourceLabel)
                    color: Colours.palette.m3onSurfaceVariant
                    animate: true
                }

                StyledText {
                    readonly property var match: LyricsSource.matchInfo
                    readonly property var player: LyricsSource.player
                    visible: match && player && (String(match.artistName).toLowerCase() !== String(player.trackArtist).toLowerCase()
                        || String(match.trackName).toLowerCase() !== String(player.trackTitle).toLowerCase())
                    Layout.maximumWidth: Tokens.sizes.dashboard.mediaTabWidth / 2
                    // TRANSLATORS: %1/%2 = artist and song identified by the lyrics catalog
                    text: match ? Tr.tr("Matched: %1 — %2").arg(match.artistName).arg(match.trackName) : ""
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.WordWrap
                    animate: true
                }

                StyledText {
                    visible: LyricsSource.status === "plain" || LyricsSource.approximate
                    Layout.maximumWidth: Tokens.sizes.dashboard.mediaTabWidth / 2
                    text: LyricsSource.status === "plain" ? Tr.tr("Not synced: no timed lyrics match this recording") : Tr.tr("Approximate match: the recording length differs, adjust the offset if needed")
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.WordWrap
                    animate: true
                }

                StyledText {
                    visible: LyricsSource.provider === "shell"
                    Layout.maximumWidth: Tokens.sizes.dashboard.mediaTabWidth / 2
                    // TRANSLATORS: %1/%2/%3 = matched track title, artist and album
                    text: Tr.tr("Selected candidate: %1 | %2 | %3").arg(Lyrics.selectedCandidate.title).arg(Lyrics.selectedCandidate.artist).arg(Lyrics.selectedCandidate.album)
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    animate: true
                }

                // Lyrics.offset is in seconds (it was shown as "0.5 ms" before). Saved per track.
                RowLayout {
                    visible: LyricsSource.status === "synced"
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        Layout.fillWidth: true
                        // TRANSLATORS: %1 = lyric timing offset, signed; ms is the millisecond unit, leave untranslated. Positive = later.
                        text: Tr.tr("Offset: %1 ms").arg((LyricsSource.offset > 0 ? "+" : "") + Math.round(LyricsSource.offset * 1000))
                        color: Colours.palette.m3onSurfaceVariant
                        animate: true
                    }

                    IconButton {
                        type: IconButton.Text
                        icon: "remove"
                        onClicked: LyricsSource.nudgeOffset(-LyricsSource.offsetStep)
                    }

                    IconButton {
                        type: IconButton.Text
                        icon: "restart_alt"
                        disabled: LyricsSource.offset === 0
                        onClicked: LyricsSource.resetOffset()
                    }

                    IconButton {
                        type: IconButton.Text
                        icon: "add"
                        onClicked: LyricsSource.nudgeOffset(LyricsSource.offsetStep)
                    }
                }
            }

            Item {
                id: placeholder

                anchors.centerIn: parent
                implicitWidth: placeholderText.implicitWidth
                implicitHeight: placeholderText.implicitHeight

                StyledText {
                    id: placeholderText

                    text: LyricsSource.status === "loading" ? Tr.tr("Loading...") : Tr.tr("No lyrics found")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                    animate: true
                }
            }
        }
    }

    MouseArea {
        id: btn

        anchors.centerIn: parent
        implicitWidth: implicitHeight
        implicitHeight: icon.implicitHeight + Tokens.padding.extraSmall * 2
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: root.open = !root.open

        MaterialIcon {
            id: icon

            anchors.centerIn: parent
            text: "more_vert"
            fontStyle: Tokens.font.icon.medium
        }
    }
}
