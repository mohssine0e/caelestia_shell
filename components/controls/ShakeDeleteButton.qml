pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

IconButton {
    id: root

    signal confirmed()

    icon: "delete_outline"
    font: Tokens.font.icon.small
    type: IconButton.Text
    transformOrigin: Item.Center

    property bool isShaking: false

    function handleSingleClick() {
        if (root.isShaking) {
            handleConfirm();
        } else {
            root.isShaking = true;
            armTimer.restart();
            shakeAnim.restart();
            root.clicked();
        }
    }

    function handleConfirm() {
        armTimer.stop();
        shakeAnim.stop();
        root.rotation = 0;
        root.isShaking = false;
        root.confirmed();
    }

    Timer {
        id: armTimer
        interval: 1500
        onTriggered: {
            root.isShaking = false;
            root.rotation = 0;
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: root.disabled ? undefined : Qt.PointingHandCursor

        onClicked: root.handleSingleClick()
        onDoubleClicked: root.handleConfirm()
    }

    SequentialAnimation {
        id: shakeAnim

        onFinished: {
            root.rotation = 0;
        }

        PropertyAnimation { target: root; property: "rotation"; from: -8; to: 8; duration: 80 }
        PropertyAnimation { target: root; property: "rotation"; from: 8; to: -8; duration: 80 }
        PropertyAnimation { target: root; property: "rotation"; from: -8; to: 8; duration: 80 }
        PropertyAnimation { target: root; property: "rotation"; from: 8; to: -8; duration: 80 }
        PropertyAnimation { target: root; property: "rotation"; from: -4; to: 4; duration: 50 }
        PropertyAnimation { target: root; property: "rotation"; from: 4; to: 0; duration: 50 }
    }
}
