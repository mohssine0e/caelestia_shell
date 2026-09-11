pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.containers
import qs.services

Item {
    id: root

    required property string activePage
    required property string habitIcon
    required property string habitType

    signal pageChanged(string page)
    signal captureAccepted(string text)
    signal escapePressed()
    signal habitIconSelected(string icon)
    signal habitTypeSelected(string type)

    // ── Icon lists per type ──────────────────────────────────────
    readonly property var buildIcons: [
        "block",
        // Engineering & Coding
        "code", "terminal", "build", "engineering", "analytics", "dashboard",
        // Productivity
        "pending", "today", "calendar_today", "trending_up",
        // Health & Wellness
        "directions_run", "fitness_center", "water_drop",
        "bedtime", "spa", "self_improvement",
        // Learning
        "menu_book", "school", "book", "lightbulb",
        // Focus & Mindfulness
        "balance",
        // Social & Networking
        "group", "handshake", "volunteer_activism",
        // Finance
        "savings", "receipt", "payments", "account_balance",
        // Daily Life
        "restaurant", "local_cafe", "cleaning_services",
        "home", "pets"
    ]

    readonly property var avoidIcons: [
        "block", "do_not_disturb", "do_not_disturb_on",
        "phone_disabled", "wifi_off", "no_food",
        "no_drinks", "smoke_free", "no_accounts",
        "cancel", "close", "not_interested",
        "hourglass_disabled", "mobiledata_off",
        "visibility_off", "volume_off", "notifications_off"
    ]

    readonly property var habitIcons: root.habitType === "avoid" ? avoidIcons : buildIcons

    // Reset icon when type changes
    onHabitTypeChanged: {
        // If the current icon isn't in the new list, reset to first
        if (root.habitIcons.indexOf(root.habitIcon) === -1) {
            root.habitIconSelected(root.habitIcons[0])
        }
    }

    implicitHeight: headerColumn.implicitHeight

    function focusCapture() {
        captureField.forceActiveFocus()
    }

    readonly property bool showHabitControls: root.activePage === "daily" && (captureField.activeFocus || captureField.text.length > 0)

    ColumnLayout {
        id: headerColumn
        anchors.fill: parent
        spacing: Tokens.spacing.small

        // ── Top Row: Capture Field + Type + Page Switcher ────
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            // ── Capture Field ──────────────────────────────────
            StyledTextField {
                id: captureField
                Layout.preferredWidth: 500
                implicitHeight: pageSwitch.implicitHeight + 4
                leadingIcon: root.activePage === "daily" ? root.habitIcon : "checklist"
                borderWidth: 1
                placeholderText: root.activePage === "daily"
                    ? (root.habitType === "avoid"
                        ? qsTr("Avoid a habit")
                        : qsTr("Add a habit"))
                    : qsTr("Capture a task")
                onAccepted: {
                    root.captureAccepted(text)
                    clear()
                }
                Keys.onEscapePressed: {
                    clear()
                    focus = false
                    root.escapePressed()
                }
            }

            // ── Habit Type Switcher (daily only) ───────────────
            BtnSwitcher {
                id: habitTypeSwitch
                visible: root.showHabitControls
                Layout.fillHeight: true
                model: [
                    { icon: "build", text: qsTr("Build"), value: "build" },
                    { icon: "block", text: qsTr("Avoid"), value: "avoid" }
                ]
                currentValue: root.habitType
                onActivated: {
                    root.habitType = value
                    root.habitTypeSelected(value)
                }
                showOnlyActiveText: true
            }

            // ── Spacer ──────────────────────────────────────────
            Item {
                Layout.fillWidth: true
            }

            // ── Page Switcher ──────────────────────────────────
            BtnSwitcher {
                id: pageSwitch
                Layout.fillHeight: true
                model: [
                    { icon: "checklist", text: "Tasks", value: "tasks", action: () => root.pageChanged("tasks") },
                    { icon: "wb_sunny", text: "Daily", value: "daily", action: () => root.pageChanged("daily") }
                ]
                currentValue: root.activePage
                onActivated: root.pageChanged(value)
                showOnlyActiveText: true
            }
        }

        // ── Bottom Row: Icon Picker ─────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.showHabitControls ? pageSwitch.implicitHeight : 0
            visible: root.showHabitControls
            opacity: root.showHabitControls ? 1 : 0
            Behavior on opacity { Anim { type: Anim.DefaultEffects } }
            Behavior on Layout.preferredHeight { Anim { type: Anim.FastSpatial } }

            color: "transparent"
            clip: true
            radius: Tokens.rounding.small

            ListView {
                id: iconListView
                anchors {
                    fill: parent
                    margins: 2
                }
                orientation: ListView.Horizontal
                spacing: Tokens.spacing.small
                clip: true

                snapMode: ListView.SnapToItem
                highlightMoveDuration: 200
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: 2500
                maximumFlickVelocity: 900

                model: root.habitIcons

                delegate: Rectangle {
                    required property string modelData
                    required property int index

                    readonly property bool selected: modelData === root.habitIcon

                    width: 36
                    height: iconListView.height - 4
                    radius: Tokens.rounding.small
                    color: selected ? Colours.palette.m3primary
                            : iconHover.hovered
                            ? Colours.tPalette.m3surfaceContainerHigh
                            : "transparent"
                    Behavior on color { CAnim {} }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: modelData
                        fontStyle: Tokens.font.icon.medium
                        color: selected ? Colours.palette.m3onPrimary
                            : Colours.palette.m3onSurfaceVariant
                        Behavior on color { CAnim {} }
                    }

                    HoverHandler {
                        id: iconHover
                        enabled: !iconListView.moving
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.habitIconSelected(modelData)
                        enabled: !iconListView.moving
                    }
                }
            }

            // ── Left Shadow Edge ─────────────────────────────
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 16
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Colours.tPalette.m3surfaceContainerLow }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                visible: iconListView.contentX > 0
            }

            // ── Right Shadow Edge ────────────────────────────
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 16
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: Colours.tPalette.m3surfaceContainerLow }
                }
                visible: iconListView.contentX < iconListView.contentWidth - iconListView.width
            }
        }
    }
}