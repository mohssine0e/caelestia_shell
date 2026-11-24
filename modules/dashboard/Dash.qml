import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.filedialog
import qs.services
import qs.modules.dashboard.dash

GridLayout {
    id: root

    required property ScreenState screenState
    required property FileDialog facePicker

    rowSpacing: Tokens.spacing.medium
    columnSpacing: Tokens.spacing.medium

    Rect {
        Layout.row: 0
        Layout.column: 0
        Layout.preferredWidth: Math.max(Tokens.sizes.dashboard.weatherWidth, 350)
        Layout.preferredHeight: weather.implicitHeight

        // Same corner radius as the profile and calendar cards beside it.
        radius: Tokens.rounding.extraLarge

        SmallWeather {
            id: weather
        }
    }

    Rect {
        Layout.row: 0
        Layout.column: 1
        Layout.preferredWidth: Math.max(Tokens.sizes.dashboard.userWidth, 450)
        Layout.fillHeight: true

        radius: Tokens.rounding.extraLarge

        User {
            id: user

            screenState: root.screenState
            facePicker: root.facePicker
        }
    }

    Rect {
        Layout.row: 1
        Layout.column: 0
        Layout.columnSpan: 2
        Layout.fillWidth: true
        Layout.preferredHeight: calendar.implicitHeight

        radius: Tokens.rounding.extraLarge

        Calendar {
            id: calendar

            screenState: root.screenState
        }
    }

    component Rect: StyledRect {
        color: Colours.tPalette.m3surfaceContainer
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.7)
    }
}
