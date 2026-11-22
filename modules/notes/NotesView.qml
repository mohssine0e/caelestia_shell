pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    signal closeRequested()
    signal moveRequested()

    NotesViewLegacy {
        anchors.fill: parent
        onCloseRequested: root.closeRequested()
        onMoveRequested: root.moveRequested()
    }
}
