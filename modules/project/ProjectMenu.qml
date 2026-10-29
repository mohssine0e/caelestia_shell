pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.utils

Scope {
    id: root

    Variants {
        model: Screens.screens

        LazyLoader {
            id: loader
            required property ShellScreen modelData

            activeAsync: true

            StyledWindow {
                id: win

                name: "project"
                screen: loader.modelData
                readonly property ScreenState st: ShellState.forScreen(loader.modelData)

                visible: st?.project ?? false

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                WlrLayershell.keyboardFocus: win.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
                WlrLayershell.layer: WlrLayer.Overlay

                HyprlandFocusGrab {
                    id: focusGrab
                    active: win.visible
                    windows: [win]
                    onCleared: {
                        if (win.st) win.st.project = false;
                    }
                }

                property bool hasExternal: false
                property string externalName: ""
                property string externalDesc: ""
                property string currentMode: "extend"
                property int selectedIndex: 0

                readonly property var modes: [
                    { id: "pc_only", title: qsTr("PC screen only"), desc: qsTr("Disconnect external display"), icon: "laptop" },
                    { id: "duplicate", title: qsTr("Duplicate"), desc: qsTr("Mirror screen on all displays"), icon: "content_copy" },
                    { id: "extend", title: qsTr("Extend"), desc: qsTr("Extend desktop across all displays"), icon: "view_week" },
                    { id: "second_only", title: qsTr("Second screen only"), desc: qsTr("Show only on external display"), icon: "tv" }
                ]

                function refreshStatus(): void {
                    statusProc.running = true;
                }

                function cycle(): void {
                    if (!win.visible) {
                        if (win.st) win.st.project = true;
                        refreshStatus();
                    } else if (hasExternal) {
                        selectedIndex = (selectedIndex + 1) % modes.length;
                        autoApplyTimer.restart();
                    }
                }

                function applyCurrent(): void {
                    autoApplyTimer.stop();
                    if (!hasExternal) {
                        if (win.st) win.st.project = false;
                        return;
                    }
                    const target = modes[selectedIndex];
                    if (target) {
                        applyMode(target.id, target.title);
                    }
                }

                function applyMode(modeId: string, modeTitle: string): void {
                    autoApplyTimer.stop();
                    Quickshell.execDetached([Paths.home + "/.config/caelestia/scripts/display-mode.py", "--set", modeId]);
                    Toaster.toast(qsTr("Display Mode"), modeTitle, "tv");
                    if (win.st) win.st.project = false;
                }

                Timer {
                    id: autoApplyTimer
                    interval: 1400
                    onTriggered: win.applyCurrent()
                }

                Process {
                    id: statusProc
                    command: ["python3", Paths.home + "/.config/caelestia/scripts/display-mode.py", "--status"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            try {
                                const data = JSON.parse(text);
                                win.hasExternal = data.connected ?? false;
                                win.externalName = data.external ?? "";
                                win.externalDesc = data.external_description ?? "";
                                win.currentMode = data.mode ?? "extend";

                                // Match selection to current mode on open
                                const idx = win.modes.findIndex(m => m.id === win.currentMode);
                                win.selectedIndex = idx >= 0 ? idx : 0;
                            } catch (e) {
                                console.log("[Project] status parse error:", e);
                            }
                        }
                    }
                }

                onVisibleChanged: {
                    if (visible) {
                        refreshStatus();
                        Qt.callLater(() => card.forceActiveFocus());
                    } else {
                        autoApplyTimer.stop();
                    }
                }

                // Dimming scrim backdrop (clicks dismiss)
                Rectangle {
                    anchors.fill: parent
                    color: Colours.palette.m3scrim
                    opacity: 0.45

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            autoApplyTimer.stop();
                            if (win.st) win.st.project = false;
                        }
                    }
                }

                // Centered Floating Project Dialog
                Rectangle {
                    id: card

                    anchors.centerIn: parent
                    implicitWidth: 380
                    implicitHeight: contentCol.implicitHeight + Tokens.padding.large * 2
                    radius: Tokens.rounding.large
                    color: Colours.palette.m3surfaceContainerHigh
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant

                    focus: true

                    Keys.onDownPressed: {
                        if (win.hasExternal) {
                            win.selectedIndex = (win.selectedIndex + 1) % win.modes.length;
                            autoApplyTimer.restart();
                        }
                    }

                    Keys.onUpPressed: {
                        if (win.hasExternal) {
                            win.selectedIndex = (win.selectedIndex - 1 + win.modes.length) % win.modes.length;
                            autoApplyTimer.restart();
                        }
                    }

                    Keys.onReturnPressed: win.applyCurrent()
                    Keys.onEnterPressed: win.applyCurrent()
                    Keys.onEscapePressed: {
                        autoApplyTimer.stop();
                        if (win.st) win.st.project = false;
                    }

                    ColumnLayout {
                        id: contentCol
                        anchors.fill: parent
                        anchors.margins: Tokens.padding.large
                        spacing: Tokens.spacing.medium

                        // Header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                text: "devices"
                                fontStyle: Tokens.font.icon.medium
                                color: Colours.palette.m3primary
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                StyledText {
                                    text: qsTr("Project")
                                    font: Tokens.font.title.medium
                                    color: Colours.palette.m3onSurface
                                }

                                StyledText {
                                    text: win.hasExternal ? (win.externalDesc || win.externalName || qsTr("External Display")) : qsTr("No external display")
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3onSurfaceVariant
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            IconButton {
                                icon: "close"
                                isRound: true
                                type: IconButton.Text
                                font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                                padding: Tokens.padding.extraSmall
                                onClicked: {
                                    autoApplyTimer.stop();
                                    if (win.st) win.st.project = false;
                                }
                            }
                        }

                        // Divider
                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: Colours.palette.m3outlineVariant
                            opacity: 0.4
                        }

                        // Empty State (No External Display)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small
                            visible: !win.hasExternal
                            Layout.topMargin: Tokens.padding.medium
                            Layout.bottomMargin: Tokens.padding.medium

                            MaterialIcon {
                                text: "tv_off"
                                fontStyle: Tokens.font.icon.large
                                color: Colours.palette.m3outline
                                Layout.alignment: Qt.AlignHCenter
                            }

                            StyledText {
                                text: qsTr("No external display detected")
                                font: Tokens.font.title.small
                                color: Colours.palette.m3onSurface
                                Layout.alignment: Qt.AlignHCenter
                            }

                            StyledText {
                                text: qsTr("Connect an HDMI or DisplayPort cable to project your screen.")
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurfaceVariant
                                horizontalAlignment: Text.AlignHCenter
                                Layout.alignment: Qt.AlignHCenter
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }

                        // Mode Options List (When External Display Connected)
                        Repeater {
                            model: win.hasExternal ? win.modes : []

                            delegate: Rectangle {
                                id: modeItem
                                required property var modelData
                                required property int index

                                Layout.fillWidth: true
                                implicitHeight: 62
                                radius: Tokens.rounding.medium

                                readonly property bool isSelected: win.selectedIndex === modeItem.index
                                readonly property bool isCurrent: win.currentMode === modeItem.modelData.id

                                color: modeItem.isSelected ? Colours.palette.m3primaryContainer : "transparent"
                                border.width: modeItem.isSelected ? 2 : 1
                                border.color: modeItem.isSelected ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

                                Behavior on color {
                                    CAnim {}
                                }
                                Behavior on border.color {
                                    CAnim {}
                                }

                                StateLayer {
                                    id: stateLayer
                                    color: Colours.palette.m3onSurface
                                    radius: Tokens.rounding.medium
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onEntered: win.selectedIndex = modeItem.index
                                    onClicked: {
                                        win.selectedIndex = modeItem.index;
                                        win.applyMode(modeItem.modelData.id, modeItem.modelData.title);
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Tokens.padding.small
                                    spacing: Tokens.spacing.medium

                                    // Mode Icon Box
                                    Rectangle {
                                        width: 38
                                        height: 38
                                        radius: Tokens.rounding.small
                                        color: modeItem.isSelected ? Colours.palette.m3primary : Colours.palette.m3surfaceContainer

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            text: modeItem.modelData.icon
                                            fontStyle: Tokens.font.icon.medium
                                            color: modeItem.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                        }
                                    }

                                    // Title & Description
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        StyledText {
                                            text: modeItem.modelData.title
                                            font: Tokens.font.title.small
                                            color: modeItem.isSelected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                                        }

                                        StyledText {
                                            text: modeItem.modelData.desc
                                            font: Tokens.font.label.small
                                            color: modeItem.isSelected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    // Active Status Checkmark
                                    MaterialIcon {
                                        text: "check"
                                        fontStyle: Tokens.font.icon.small
                                        color: modeItem.isSelected ? Colours.palette.m3primary : Colours.palette.m3tertiary
                                        visible: modeItem.isCurrent
                                        Layout.rightMargin: Tokens.padding.extraSmall
                                    }
                                }
                            }
                        }

                        // Autocommit Countdown Indicator (When Cycled)
                        ProgressBar {
                            Layout.fillWidth: true
                            implicitHeight: 3
                            visible: autoApplyTimer.running
                            value: 1 - (autoApplyTimer.interval > 0 ? 0 : 0)
                            indeterminate: autoApplyTimer.running
                        }
                    }
                }

                IpcHandler {
                    target: "project"

                    function toggle(): void {
                        if (win.st) {
                            win.st.project = !win.st.project;
                            if (win.st.project) win.refreshStatus();
                        }
                    }

                    function cycle(): void {
                        win.cycle();
                    }

                    function status(): string {
                        return JSON.stringify({
                            connected: win.hasExternal,
                            mode: win.currentMode,
                            selected: win.modes[win.selectedIndex]?.id ?? ""
                        });
                    }
                }
            }
        }
    }
}
