pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
import qs.services
import qs.components
import qs.components.controls

RowLayout {
    id: root

    property string text: ""
    property string sourceText: ""
    property string action: "ask"
    property int btnSize: 26
    property int btnType: IconButton.Text
    property bool showTTS: true
    property bool showSaveCard: true
    property bool showCopy: true

    spacing: 4

    IconButton {
        visible: root.showTTS && root.text.length > 0
        type: root.btnType
        icon: "volume_up"
        font: Tokens.font.icon.small
        implicitWidth: root.btnSize
        implicitHeight: root.btnSize
        onClicked: Assistant.speakText(root.text)
    }

    IconButton {
        id: cardBtn
        visible: root.showSaveCard && root.text.length > 0
        type: root.btnType
        property bool saved: false
        icon: saved ? "bookmark_added" : "bookmark_add"
        font: Tokens.font.icon.small
        implicitWidth: root.btnSize
        implicitHeight: root.btnSize
        onClicked: {
            Memory.createCardFromAssistant(root.sourceText || Assistant.selectedText || Assistant.activePrompt, root.text, root.action)
            saved = true
            resetSavedTimer.restart()
        }

        Timer {
            id: resetSavedTimer
            interval: 2500
            onTriggered: cardBtn.saved = false
        }
    }

    IconButton {
        id: copyBtn
        visible: root.showCopy && root.text.length > 0
        type: root.btnType
        property bool copied: false
        icon: copied ? "check" : "content_copy"
        font: Tokens.font.icon.small
        implicitWidth: root.btnSize
        implicitHeight: root.btnSize
        onClicked: {
            Quickshell.clipboardText = root.text
            copied = true
            resetCopyTimer.restart()
        }

        Timer {
            id: resetCopyTimer
            interval: 1500
            onTriggered: copyBtn.copied = false
        }
    }
}

