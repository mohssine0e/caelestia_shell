pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import "center"

Item {
    id: root

    required property var lock

    Center {
        anchors.fill: parent
        lock: root.lock
    }
}
