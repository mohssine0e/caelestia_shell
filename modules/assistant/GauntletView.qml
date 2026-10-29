pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Caelestia
import Caelestia.Config
import qs.services
import qs.components
import qs.components.controls
import qs.components.containers

Item {
    id: root

    property int activeQuestionIndex: 0
    property var userAnswers: ({})

    readonly property var currentQuestions: {
        if (!Memory.activeChallenge) return []
        if (Array.isArray(Memory.activeChallenge.questions)) {
            return Memory.activeChallenge.questions
        }
        return [{
            "id": "q1",
            "type": Memory.activeChallenge.type || "edge_case",
            "title": "Technical Challenge",
            "question": Memory.activeChallenge.question || "",
            "criteria": Memory.activeChallenge.criteria || []
        }]
    }

    readonly property var activeQuestion: {
        const qList = root.currentQuestions
        if (!qList || qList.length === 0) return null
        const idx = Math.min(Math.max(0, root.activeQuestionIndex), qList.length - 1)
        return qList[idx]
    }

    function setAnswer(qId, val) {
        const updated = Object.assign({}, root.userAnswers)
        updated[qId] = val
        root.userAnswers = updated
    }

    function getAnswer(qId) {
        return (root.userAnswers && root.userAnswers[qId]) ? root.userAnswers[qId] : ""
    }

    function reset() {
        root.activeQuestionIndex = 0
        root.userAnswers = ({})
    }

    readonly property bool isInChallengeMode: (Memory.activeChallenge !== null || Memory.isGeneratingChallenge || Memory.isDailyGauntletLoading || Memory.lastGradeResult !== null || Memory.challengeError.length > 0 || Memory.dailyGauntletError.length > 0)

    signal finished()

    ColumnLayout {
        anchors.fill: parent
        spacing: 6
        visible: root.isInChallengeMode

            // Error state
            StyledRect {
                Layout.fillWidth: true
                implicitHeight: errCol.implicitHeight + 16
                radius: Tokens.rounding.medium
                color: Qt.alpha(Colours.palette.m3error, 0.15)
                border.width: 1
                border.color: Colours.palette.m3error
                visible: (Memory.challengeError.length > 0 || Memory.dailyGauntletError.length > 0)

                ColumnLayout {
                    id: errCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        spacing: 6
                        MaterialIcon {
                            text: "error"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3error
                        }
                        StyledText {
                            text: qsTr("Challenge Engine Error")
                            font: Tokens.font.label.large
                            color: Colours.palette.m3onSurface
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Memory.challengeError || Memory.dailyGauntletError
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurface
                        wrapMode: Text.Wrap
                    }

                    RowLayout {
                        Item { Layout.fillWidth: true }
                        TextButton {
                            text: qsTr("Dismiss")
                            type: TextButton.Tonal
                            onClicked: Memory.clearChallenge()
                        }
                    }
                }
            }

            // Loading state while generating challenge
            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Tokens.rounding.medium
                color: Colours.palette.m3surfaceContainerLow
                visible: Memory.isGeneratingChallenge || Memory.isDailyGauntletLoading

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "progress_activity"
                        fontStyle: Tokens.font.icon.medium
                        color: Colours.palette.m3primary

                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 1000
                            loops: Animation.Infinite
                            running: Memory.isGeneratingChallenge || Memory.isDailyGauntletLoading
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Memory.isDailyGauntletLoading ? qsTr("Crafting Daily Gauntlet…") : qsTr("Generating Mastery Assessment…")
                        font: Tokens.font.title.small
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Adaptive Concept Checks • Bug Hunts • Architectural Edge Cases")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                    }
                }
            }

            // ─────────────────────────────────────────────────────
            // ACTIVE GAUNTLET (Question Stepper)
            // ─────────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6
                visible: !Memory.isGeneratingChallenge && Memory.activeChallenge !== null && Memory.lastGradeResult === null

                // Top Stepper Navigation Tabs
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: root.currentQuestions

                        delegate: StyledRect {
                            id: tabRect
                            required property var modelData
                            required property int index

                            readonly property bool isActive: root.activeQuestionIndex === index
                            readonly property bool isHovered: tabMouse.containsMouse
                            readonly property bool isAnswered: root.getAnswer(modelData.id).trim().length > 0

                            Layout.fillWidth: true
                            implicitHeight: 32
                            radius: Tokens.rounding.small
                            clip: true
                            color: isActive 
                                ? Colours.palette.m3primaryContainer 
                                : (isHovered ? Colours.palette.m3surfaceContainerHigh : Colours.palette.m3surfaceContainerLow)
                            border.width: isActive ? 1.5 : 1
                            border.color: isActive 
                                ? Colours.palette.m3primary 
                                : Colours.palette.m3outlineVariant

                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeQuestionIndex = index
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6

                                MaterialIcon {
                                    text: {
                                        if (modelData.type === "qcm") return "radio_button_checked"
                                        if (modelData.type === "bug_hunt") return "bug_report"
                                        return "bolt"
                                    }
                                    fontStyle: Tokens.font.icon.small
                                    color: tabRect.isActive ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3outline
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: {
                                        const shortName = modelData.type === "qcm" ? "Conceptual" : 
                                                          modelData.type === "bug_hunt" ? "Bug Hunt" : 
                                                          modelData.type === "edge_case" ? "Edge Case" : "Trial";
                                        return qsTr("%1. %2").arg(index + 1).arg(shortName);
                                    }
                                    font: Tokens.font.label.small
                                    elide: Text.ElideRight
                                    color: tabRect.isActive ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                                }

                                MaterialIcon {
                                    visible: tabRect.isAnswered
                                    text: "check_circle"
                                    fontStyle: Tokens.font.icon.small
                                    color: tabRect.isActive ? Colours.palette.m3primary : Colours.palette.m3outline
                                }
                            }
                        }
                    }
                }

                // Active Question View Container
                StyledRect {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Tokens.rounding.medium
                    color: Colours.palette.m3surfaceContainerLow
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 10
                        contentWidth: width
                        contentHeight: questionContentCol.implicitHeight + 10
                        clip: true

                        ColumnLayout {
                            id: questionContentCol
                            width: parent.width
                            spacing: 8

                            // Question Title & Type Badge
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                AssistantBadge {
                                    text: root.activeQuestion ? String(root.activeQuestion.type).toUpperCase() : ""
                                    tone: Colours.palette.m3tertiary
                                    heightPx: 18
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.activeQuestion ? root.activeQuestion.title : ""
                                    font: Tokens.font.label.large
                                    color: Colours.palette.m3onSurface
                                }
                            }

                            // Question Text / Scenario
                            SelectableText {
                                Layout.fillWidth: true
                                text: root.activeQuestion ? root.activeQuestion.question : ""
                                textFormat: TextEdit.MarkdownText
                                color: Colours.palette.m3onSurface
                            }

                            // ── Case A: Multiple Choice (QCM) Options ──────────
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 5
                                visible: root.activeQuestion && root.activeQuestion.type === "qcm"

                                Repeater {
                                    model: (root.activeQuestion && root.activeQuestion.options) ? root.activeQuestion.options : []

                                    delegate: StyledRect {
                                        required property var modelData
                                        required property int index

                                        readonly property string optLetter: ["A", "B", "C", "D"][index] || "A"
                                        readonly property bool isSelected: root.getAnswer(root.activeQuestion ? root.activeQuestion.id : "q1") === optLetter

                                        Layout.fillWidth: true
                                        implicitHeight: optRow.implicitHeight + 8
                                        radius: Tokens.rounding.small
                                        color: isSelected ? Qt.alpha(Colours.palette.m3primary, 0.18) : Colours.palette.m3surfaceContainerLowest
                                        border.width: isSelected ? 2 : 1
                                        border.color: isSelected ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.activeQuestion) {
                                                    root.setAnswer(root.activeQuestion.id, optLetter)
                                                }
                                            }
                                        }

                                        RowLayout {
                                            id: optRow
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 8

                                            StyledRect {
                                                implicitWidth: 20
                                                implicitHeight: 20
                                                radius: Tokens.rounding.full
                                                color: isSelected ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh

                                                StyledText {
                                                    anchors.centerIn: parent
                                                    text: optLetter
                                                    font: Tokens.font.label.small
                                                    color: isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                                }
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: String(modelData)
                                                font: Tokens.font.body.small
                                                color: Colours.palette.m3onSurface
                                                wrapMode: Text.Wrap
                                            }

                                            MaterialIcon {
                                                visible: isSelected
                                                text: "check_circle"
                                                fontStyle: Tokens.font.icon.small
                                                color: Colours.palette.m3primary
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Case B: Open-Ended / Bug Hunt Answer Box ───────
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                visible: root.activeQuestion && root.activeQuestion.type !== "qcm"

                                StyledRect {
                                    Layout.fillWidth: true
                                    implicitHeight: 85
                                    radius: Tokens.rounding.small
                                    color: Colours.palette.m3surfaceContainerLowest
                                    border.width: 1
                                    border.color: answerEditArea.activeFocus ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

                                    Flickable {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        contentWidth: width
                                        contentHeight: answerEditArea.implicitHeight
                                        clip: true

                                        TextEdit {
                                            id: answerEditArea
                                            width: parent.width
                                            text: root.activeQuestion ? root.getAnswer(root.activeQuestion.id) : ""
                                            font.family: Tokens.font.body.small.family
                                            font.pointSize: Tokens.font.body.small.pointSize
                                            color: Colours.palette.m3onSurface
                                            wrapMode: TextEdit.Wrap
                                            selectByMouse: true
                                            onTextChanged: {
                                                if (root.activeQuestion) {
                                                    root.setAnswer(root.activeQuestion.id, text)
                                                }
                                            }

                                            StyledText {
                                                visible: answerEditArea.text.length === 0
                                                text: qsTr("Explain the flaw/fix (or speak using Super+Alt+V)...")
                                                font: Tokens.font.body.small
                                                color: Colours.palette.m3outline
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Bottom Stepper Controls
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    StyledText {
                        text: qsTr("🎙️ Super+Alt+V works on all text areas.")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                    }

                    Item { Layout.fillWidth: true }

                    TextButton {
                        enabled: root.activeQuestionIndex > 0
                        text: qsTr("← Back")
                        type: TextButton.Tonal
                        onClicked: root.activeQuestionIndex = Math.max(0, root.activeQuestionIndex - 1)
                    }

                    StyledText {
                        text: qsTr("%1 / %2").arg(root.activeQuestionIndex + 1).arg(root.currentQuestions.length)
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    IconTextButton {
                        visible: root.activeQuestionIndex < root.currentQuestions.length - 1
                        text: qsTr("Next →")
                        icon: "arrow_forward"
                        type: IconTextButton.Tonal
                        onClicked: root.activeQuestionIndex = Math.min(root.currentQuestions.length - 1, root.activeQuestionIndex + 1)
                    }

                    IconTextButton {
                        visible: root.activeQuestionIndex === root.currentQuestions.length - 1
                        enabled: !Memory.isGrading
                        text: Memory.isGrading ? qsTr("Grading…") : qsTr("Submit Trial 🚀")
                        icon: Memory.isGrading ? "progress_activity" : "verified"
                        type: IconTextButton.Filled
                        onClicked: {
                            if (Memory.activeChallenge && Memory.activeChallenge.card_id) {
                                Memory.submitAnswer(Memory.activeChallenge.card_id, root.userAnswers)
                            }
                        }
                    }
                }
            }

            // ─────────────────────────────────────────────────────
            // GAUNTLET REPORT CARD (Results View with Correct Answers)
            // ─────────────────────────────────────────────────────
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: reportCardCol.implicitHeight + 10
                clip: true
                visible: Memory.lastGradeResult !== null

                ColumnLayout {
                    id: reportCardCol
                    width: parent.width
                    spacing: 6

                    // Overall Verdict Banner
                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: verdictRow.implicitHeight + 14
                        radius: Tokens.rounding.medium
                        color: {
                            if (!Memory.lastGradeResult) return "transparent"
                            return Memory.lastGradeResult.verdict === "pass" 
                                ? Qt.alpha(Colours.palette.m3primary, 0.15) 
                                : Qt.alpha(Colours.palette.m3error, 0.15)
                        }
                        border.width: 1
                        border.color: {
                            if (!Memory.lastGradeResult) return "transparent"
                            return Memory.lastGradeResult.verdict === "pass" 
                                ? Colours.palette.m3primary 
                                : Colours.palette.m3error
                        }

                        RowLayout {
                            id: verdictRow
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8

                            MaterialIcon {
                                text: (Memory.lastGradeResult && Memory.lastGradeResult.verdict === "pass") ? "verified" : "error"
                                fontStyle: Tokens.font.icon.medium
                                color: (Memory.lastGradeResult && Memory.lastGradeResult.verdict === "pass") ? Colours.palette.m3primary : Colours.palette.m3error
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    text: {
                                        if (!Memory.lastGradeResult) return ""
                                        const score = Math.round((Memory.lastGradeResult.score || 0) * 100)
                                        return (Memory.lastGradeResult.verdict === "pass")
                                            ? qsTr("🟢 TRIAL PASSED (%1%) — CONCEPT MASTERED").arg(score)
                                            : qsTr("❌ TRIAL FAILED (%1%) — REMAINS IN LEARNING").arg(score)
                                    }
                                    font: Tokens.font.label.large
                                    color: Colours.palette.m3onSurface
                                }

                                StyledText {
                                    text: (Memory.lastGradeResult && Memory.lastGradeResult.verdict === "pass")
                                        ? qsTr("All criteria satisfied. Topic promoted to Mastered.")
                                        : qsTr("Study the canonical solutions below before retrying.")
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3onSurfaceVariant
                                }
                            }
                        }
                    }

                    // Per-Question Breakdown with Canonical Answers
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: Memory.lastGradeResult && Memory.lastGradeResult.q_results

                        Repeater {
                            model: {
                                if (!Memory.lastGradeResult || !Memory.lastGradeResult.q_results) return []
                                const res = Memory.lastGradeResult.q_results
                                return Object.keys(res).map(k => ({ "id": k, "info": res[k] }))
                            }

                            delegate: StyledRect {
                                required property var modelData
                                required property int index

                                readonly property bool isPassed: modelData.info.verdict === "pass"

                                Layout.fillWidth: true
                                implicitHeight: qResCol.implicitHeight + 12
                                radius: Tokens.rounding.small
                                color: Colours.palette.m3surfaceContainerLow
                                border.width: 1
                                border.color: isPassed ? Qt.alpha(Colours.palette.m3primary, 0.4) : Qt.alpha(Colours.palette.m3error, 0.4)

                                ColumnLayout {
                                    id: qResCol
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        MaterialIcon {
                                            text: isPassed ? "check_circle" : "cancel"
                                            fontStyle: Tokens.font.icon.small
                                            color: isPassed ? Colours.palette.m3primary : Colours.palette.m3error
                                        }

                                        StyledText {
                                            text: qsTr("Question %1: %2").arg(index + 1).arg(isPassed ? qsTr("Passed") : qsTr("Incorrect / Needs Work"))
                                            font: Tokens.font.label.large
                                            color: isPassed ? Colours.palette.m3primary : Colours.palette.m3error
                                        }
                                    }

                                    // Evaluation comment
                                    SelectableText {
                                        Layout.fillWidth: true
                                        text: String(modelData.info.comment || "")
                                        color: Colours.palette.m3onSurfaceVariant
                                    }

                                    // Canonical Correct Solution Box (Crucial for Learning!)
                                    StyledRect {
                                        visible: modelData.info.correct_solution && modelData.info.correct_solution.length > 0
                                        Layout.fillWidth: true
                                        implicitHeight: solCol.implicitHeight + 8
                                        radius: Tokens.rounding.small
                                        color: Qt.alpha(Colours.palette.m3primary, 0.08)
                                        border.width: 1
                                        border.color: Qt.alpha(Colours.palette.m3primary, 0.3)

                                        ColumnLayout {
                                            id: solCol
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            spacing: 2

                                            RowLayout {
                                                spacing: 4
                                                MaterialIcon {
                                                    text: "lightbulb"
                                                    fontStyle: Tokens.font.icon.small
                                                    color: Colours.palette.m3primary
                                                }
                                                StyledText {
                                                    text: qsTr("Canonical Correct Solution:")
                                                    font: Tokens.font.label.small
                                                    color: Colours.palette.m3primary
                                                }
                                            }

                                            SelectableText {
                                                Layout.fillWidth: true
                                                text: String(modelData.info.correct_solution || "")
                                                textFormat: TextEdit.MarkdownText
                                                color: Colours.palette.m3onSurface
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Strengths & Blindspots
                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: feedbackCol.implicitHeight + 12
                        radius: Tokens.rounding.medium
                        color: Colours.palette.m3surfaceContainerLow

                        ColumnLayout {
                            id: feedbackCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            SelectableText {
                                Layout.fillWidth: true
                                text: qsTr("**Strengths:** %1").arg(Memory.lastGradeResult ? Memory.lastGradeResult.strengths : "")
                                textFormat: TextEdit.MarkdownText
                                color: Colours.palette.m3onSurface
                            }

                            SelectableText {
                                Layout.fillWidth: true
                                text: qsTr("**Blindspots:** %1").arg(Memory.lastGradeResult ? Memory.lastGradeResult.blindspots : "")
                                textFormat: TextEdit.MarkdownText
                                color: Colours.palette.m3onSurface
                            }

                            SelectableText {
                                Layout.fillWidth: true
                                text: qsTr("**Mastery Rule:** %1").arg(Memory.lastGradeResult ? (Memory.lastGradeResult.compressed_summary || Memory.lastGradeResult.explanation) : "")
                                textFormat: TextEdit.MarkdownText
                                color: Colours.palette.m3primary
                            }
                        }
                    }

                    // Return Button
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }

                        IconTextButton {
                            text: qsTr("Return to Cards")
                            icon: "check"
                            type: IconTextButton.Filled
                            onClicked: {
                                Memory.clearChallenge()
                                root.reset()
                                root.finished()
                            }
                        }
                    }
                }
            }
        }

}
