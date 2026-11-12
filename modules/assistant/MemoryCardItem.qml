pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: cardItem

    property var card: null
    property bool showArchived: false
    property string editingCardId: ""
    property string expandedCardId: ""
    property string editingLinesText: ""

    signal startEditingRequested(var cardData)
    signal cancelEditingRequested()
    signal saveEditingRequested(string cardId, string text)
    signal toggleExpandRequested(string cardId)
    signal startChallengeRequested(string cardId)
    signal editLinesTextChanged(string text)

    readonly property string cardType: card ? (card.type || "knowledge") : "knowledge"

    width: ListView.view ? ListView.view.width : parent ? parent.width : 0
    implicitHeight: delegateLoader.implicitHeight
    height: delegateLoader.implicitHeight

    Loader {
        id: delegateLoader
        width: parent.width

        sourceComponent: {
            if (cardItem.cardType === "context") return contextComp
            if (cardItem.cardType === "fact") return factComp
            return knowledgeComp
        }
    }

    Component {
        id: contextComp
        ContextCardDelegate {
            card: cardItem.card
        }
    }

    Component {
        id: factComp
        FactCardDelegate {
            card: cardItem.card
            expandedCardId: cardItem.expandedCardId
            editingCardId: cardItem.editingCardId
            editingLinesText: cardItem.editingLinesText

            onToggleExpandRequested: cid => cardItem.toggleExpandRequested(cid)
            onStartEditingRequested: cdata => cardItem.startEditingRequested(cdata)
            onCancelEditingRequested: () => cardItem.cancelEditingRequested()
            onSaveEditingRequested: (cid, txt) => cardItem.saveEditingRequested(cid, txt)
            onStartChallengeRequested: cid => cardItem.startChallengeRequested(cid)
        }
    }

    Component {
        id: knowledgeComp
        KnowledgeCardDelegate {
            card: cardItem.card
            expandedCardId: cardItem.expandedCardId
            editingCardId: cardItem.editingCardId
            editingLinesText: cardItem.editingLinesText

            onToggleExpandRequested: cid => cardItem.toggleExpandRequested(cid)
            onStartEditingRequested: cdata => cardItem.startEditingRequested(cdata)
            onCancelEditingRequested: () => cardItem.cancelEditingRequested()
            onSaveEditingRequested: (cid, txt) => cardItem.saveEditingRequested(cid, txt)
            onStartChallengeRequested: cid => cardItem.startChallengeRequested(cid)
        }
    }
}
