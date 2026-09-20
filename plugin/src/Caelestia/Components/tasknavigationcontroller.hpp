#pragma once

#include <qobject.h>
#include <qqmlintegration.h>
#include <qvariant.h>

namespace caelestia::components {

// TaskNavigationController — single source of truth for the task-list
// keyboard cursor, ported from the Scope-Based (Hierarchical Scope)
// Navigation Model in modules/tasks/behaviors.txt §2.
//
// Cursor triple: (selectedIndex, selectedSubtaskIndex, selectedNestedIndex)
//   (-1, -1, -1)              → nothing / task header level (subIdx -1)
//   (i, -1, -1)               → task header i
//   (i, s, -1)                → subtask s of task i (subtask scope)
//   (i, s, n)                 → nested child n of subtask s (nested scope, n ≥ 0)
//
// Navigation rules (scope-bounded, circular inside scope):
//   Up/Down on header → prev/next visible task (circular wrap).
//   Up/Down on subtask scope → prev/next subtask in same task (circular).
//   Up/Down on nested scope → prev/next nested child in same subtask (circular).
//   Right: collapsed header → expand + select subtask 0;
//          subtask row → expand if collapsed, else enter nested 0 if children;
//          nested child → no-op (terminal depth).
//   Left: nested child → parent subtask; subtask → task header (stays
//         expanded); header → collapse card.
//
// The controller is data-agnostic: QML feeds a lightweight `structure`
// snapshot (sizes only, no titles) and forwards mutation/scroll intents
// via signals. Data mutation stays in DataManager.qml.
class TaskNavigationController : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int selectedIndex READ selectedIndex WRITE setSelectedIndex NOTIFY selectedIndexChanged)
    Q_PROPERTY(int selectedSubtaskIndex READ selectedSubtaskIndex WRITE setSelectedSubtaskIndex NOTIFY
            selectedSubtaskIndexChanged)
    Q_PROPERTY(int selectedNestedIndex READ selectedNestedIndex WRITE setSelectedNestedIndex NOTIFY
            selectedNestedIndexChanged)

    // Expansion mirror (replaces delegate-local `expanded` bools):
    //   expandedTasks:    { todoId: bool }
    //   expandedSubtasks: { "todoId/subId": bool }
    Q_PROPERTY(QVariantMap expandedTasks READ expandedTasks NOTIFY expansionChanged)
    Q_PROPERTY(QVariantMap expandedSubtasks READ expandedSubtasks NOTIFY expansionChanged)

    // Structure snapshot fed from QML (see setStructure):
    //   [ { todoId, visible: bool, nSub: int, nestedCounts: [int…] } ]
    Q_PROPERTY(QVariantList structure READ structure WRITE setStructure NOTIFY structureChanged)

public:
    explicit TaskNavigationController(QObject* parent = nullptr);

    [[nodiscard]] int selectedIndex() const;
    void setSelectedIndex(int index);

    [[nodiscard]] int selectedSubtaskIndex() const;
    void setSelectedSubtaskIndex(int index);

    [[nodiscard]] int selectedNestedIndex() const;
    void setSelectedNestedIndex(int index);

    [[nodiscard]] QVariantMap expandedTasks() const;
    [[nodiscard]] QVariantMap expandedSubtasks() const;

    [[nodiscard]] QVariantList structure() const;
    void setStructure(const QVariantList& structure);

    // Key dispatch — QML Keys handler becomes a single call.
    // Returns true when the key was consumed.
    Q_INVOKABLE bool handleKey(int key, int modifiers = Qt::NoModifier);

    Q_INVOKABLE void moveUp();
    Q_INVOKABLE void moveDown();
    Q_INVOKABLE void moveLeft();
    Q_INVOKABLE void moveRight();
    Q_INVOKABLE void activate(); // Enter
    Q_INVOKABLE void beginEdit(); // F2
    Q_INVOKABLE void cancel(); // Escape (outside text fields)

    Q_INVOKABLE void selectTask(int listIndex);
    Q_INVOKABLE void selectSubtask(int listIndex, int subIdx);

    Q_INVOKABLE bool isTaskExpanded(const QString& taskId) const;
    Q_INVOKABLE bool isSubExpanded(const QString& taskId, const QString& subId) const;
    Q_INVOKABLE void setTaskExpanded(const QString& taskId, bool expanded);
    Q_INVOKABLE void setSubExpanded(const QString& taskId, const QString& subId, bool expanded);

    // Bounds check + auto-recovery (also runs on every setStructure).
    Q_INVOKABLE void clampToStructure();

signals:
    void selectedIndexChanged();
    void selectedSubtaskIndexChanged();
    void selectedNestedIndexChanged();
    void expansionChanged();
    void structureChanged();

    // Intents QML forwards to DataManager / focus helpers.
    void toggleTaskRequested(int listIndex);
    void toggleSubtaskRequested(int listIndex, int subIdx);
    void toggleNestedRequested(int listIndex, int subIdx, int nestedIdx);
    void editTaskRequested(int listIndex);
    void editSubtaskRequested(int listIndex, int subIdx);
    void editNestedRequested(int listIndex, int subIdx, int nestedIdx);
    void scrollToIndex(int listIndex);
    void focusListRequested();

private:
    [[nodiscard]] QList<int> visibleIndices() const;
    [[nodiscard]] int nextVisible(int from, int dir) const;
    [[nodiscard]] int subCount(int listIndex) const;
    [[nodiscard]] int nestedCount(int listIndex, int subIdx) const;
    [[nodiscard]] QString taskIdAt(int listIndex) const;
    void emitCursor(int listIndex, int subIdx, int nestedIdx);

    int m_selectedIndex = -1;
    int m_selectedSubtaskIndex = -1;
    int m_selectedNestedIndex = -1;
    QVariantMap m_expandedTasks;
    QVariantMap m_expandedSubtasks;
    QVariantList m_structure;
};

} // namespace caelestia::components
