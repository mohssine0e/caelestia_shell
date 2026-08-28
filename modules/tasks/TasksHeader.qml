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

    signal pageChanged(string page)
    signal captureAccepted(string text)
    signal habitIconSelected(string icon)

    // remove the big icons or the onte represented as Text
    readonly property var habitIcons: [
            // ── No Icon (clear) ── (1)
        "block",  // or "cancel" or "clear"


        // ── Engineering & Coding ── (8)
        "code", "terminal", "build", "engineering", 
        "analytics", "dashboard",
        
        // ── Productivity ── (6)
        "task_alt", "check_circle", "pending", "today",
        "calendar_today", "trending_up",
        
        // ── Health & Wellness ── (6)
        "directions_run", "fitness_center", "water_drop",
        "bedtime", "spa", "self_improvement",
        
        // ── Learning ── (6)
        "menu_book", "school", "book",
        "lightbulb",
        
        // ── Focus & Mindfulness ── (4)
        "balance",
        
        // ── Social & Networking ── (4)
        "group", "handshake", "volunteer_activism",
        
        // ── Finance ── (4)
        "savings", "receipt", "payments", "account_balance",
        
        // ── Daily Life ── (6)
        "restaurant", "local_cafe", "cleaning_services",
        "home", "pets"
    ]

    implicitHeight: headerColumn.implicitHeight

    function focusCapture() {
        captureField.forceActiveFocus()
    }

    // ── Icon picker visibility ──────────────────────────────────
    readonly property bool iconPickerVisible: root.activePage === "daily" && (captureField.activeFocus || captureField.text.length > 0)

    ColumnLayout {
        id: headerColumn
        anchors.fill: parent
        spacing: Tokens.spacing.small

        // ── Top Row: Capture Field + Page Switcher ────────────
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
                    ? qsTr("Add a habit")
                    : qsTr("Capture a task")
                onAccepted: {
                    root.captureAccepted(text)
                    clear()
                }
                Keys.onEscapePressed: {
                    clear()
                    focus = false
                }
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
            Layout.preferredHeight: root.iconPickerVisible ? pageSwitch.implicitHeight : 0
            visible: root.iconPickerVisible
            opacity: root.iconPickerVisible ? 1 : 0
            Behavior on opacity { Anim { type: Anim.DefaultEffects } }
            Behavior on Layout.preferredHeight { Anim { type: Anim.FastSpatial } }
            
            color: "transparent"
            clip: true
            radius: Tokens.rounding.small

            // ── ListView with built-in scrolling ──────────────
            ListView {
                id: iconListView
                anchors {
                    fill: parent
                    margins: 2
                }
                orientation: ListView.Horizontal
                spacing: Tokens.spacing.small
                clip: true
                
                // ── Enable smooth scrolling ─────────────────────
                snapMode: ListView.SnapToItem
                highlightMoveDuration: 200
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: 2500
                maximumFlickVelocity: 900
                
                model: root.habitIcons

                delegate: Rectangle {
                    required property string modelData
                    required property int index

                    readonly property bool selected:modelData === root.habitIcon

                    
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
                        onClicked:root.habitIconSelected(modelData);
                        enabled: !iconListView.moving
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
}