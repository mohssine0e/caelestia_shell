import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.filedialog
import qs.services
import qs.modules.dashboard.dash

ColumnLayout {
    id: root

    required property ScreenState screenState
    required property FileDialog facePicker

    spacing: Tokens.spacing.medium
    implicitWidth: 680

    DashboardHeader {
        screenState: root.screenState
        facePicker: root.facePicker
        Layout.fillWidth: true
    }

    Calendar {
        id: calendar
        screenState: root.screenState
        Layout.fillWidth: true
    }
}
