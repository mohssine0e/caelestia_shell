import QtQuick
import Quickshell
import Quickshell.Services.UPower
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Services

Scope {
    id: root

    readonly property list<var> warnLevels: [...GlobalConfig.general.battery.warnLevels.values].sort((a, b) => a.level - b.level)
    property real lastPercentage: 100

    function playAlertSound(): void {
        Quickshell.execDetached(["pw-play", "/usr/share/sounds/freedesktop/stereo/suspend-error.oga"]);
    }

    function handleBatteryWarnings(): void {
        const p = Math.round(UPower.displayDevice.percentage * 100);

        if (!UPower.onBattery) {
            root.lastPercentage = p;
            return;
        }

        if (root.lastPercentage >= 0) {
            let warnedLevel = -1;
            for (const level of root.warnLevels) {
                if (p <= level.level && root.lastPercentage > level.level) {
                    Toaster.toast(Tr.trMarked(level.title ?? Tr.tr("Battery warning")), Tr.trMarked(level.message ?? Tr.tr("Battery level is low")), level.icon ?? "battery_android_alert", level.critical ? Toast.Error : Toast.Warning);
                    warnedLevel = level.level;
                    break;
                }
            }

            const crossed10 = p <= 10 && root.lastPercentage > 10;
            const crossed5  = p <= 5  && root.lastPercentage > 5;
            if (crossed10 || crossed5 || (warnedLevel > 0 && warnedLevel <= 10)) {
                root.playAlertSound();
            }
        }

        if (!hibernateTimer.running && p <= GlobalConfig.general.battery.criticalLevel) {
            Toaster.toast(Tr.tr("Hibernating in 5 seconds"), Tr.tr("Hibernating to prevent data loss"), "battery_android_alert", Toast.Error);
            hibernateTimer.start();
        }

        root.lastPercentage = p;
    }

    Connections {
        function onOnBatteryChanged(): void {
            if (!UPower.displayDevice.ready)
                return;

            if (UPower.onBattery) {
                if (GlobalConfig.utilities.toasts.chargingChanged)
                    Toaster.toast(Tr.tr("Charger unplugged"), Tr.tr("Battery is discharging"), "power_off");
                root.handleBatteryWarnings();
            } else {
                if (GlobalConfig.utilities.toasts.chargingChanged)
                    Toaster.toast(Tr.tr("Charger plugged in"), Tr.tr("Battery is charging"), "power");
                root.lastPercentage = 100;
            }
        }

        target: UPower
    }

    Connections {
        function onReadyChanged(): void {
            if (!UPower.displayDevice.ready)
                return;
            root.handleBatteryWarnings();
        }

        target: UPower.displayDevice
    }

    Connections {
        function onPercentageChanged(): void {
            if (!UPower.displayDevice.ready)
                return;
            root.handleBatteryWarnings();
        }

        target: UPower.displayDevice
    }

    Timer {
        id: hibernateTimer

        interval: 5000
        onTriggered: SessionManager.hibernate()
    }
}
