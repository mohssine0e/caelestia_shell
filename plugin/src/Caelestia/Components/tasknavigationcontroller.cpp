#include "tasknavigationcontroller.hpp"

#include <qnamespace.h>

namespace caelestia::components {

namespace {

constexpr int kHeaderSub = -1;
constexpr int kHeaderNested = -1;
constexpr int kParentNested = -1;

int toInt(const QVariant& v, int fallback = 0) {
    bool ok = false;
    const int n = v.toInt(&ok);
    return ok ? n : fallback;
}

} // namespace

TaskNavigationController::TaskNavigationController(QObject* parent)
    : QObject(parent) {}

int TaskNavigationController::selectedIndex() const {
    return m_selectedIndex;
}

void TaskNavigationController::setSelectedIndex(int index) {
    if (m_selectedIndex == index) {
        return;
    }
    m_selectedIndex = index;
    if (m_selectedSubtaskIndex != kHeaderSub) {
        m_selectedSubtaskIndex = kHeaderSub;
        emit selectedSubtaskIndexChanged();
    }
    if (m_selectedNestedIndex != kHeaderNested) {
        m_selectedNestedIndex = kHeaderNested;
        emit selectedNestedIndexChanged();
    }
    emit selectedIndexChanged();
    emit scrollToIndex(m_selectedIndex);
}

int TaskNavigationController::selectedSubtaskIndex() const {
    return m_selectedSubtaskIndex;
}

void TaskNavigationController::setSelectedSubtaskIndex(int index) {
    if (m_selectedSubtaskIndex == index) {
        return;
    }
    m_selectedSubtaskIndex = index;
    if (index == kHeaderSub && m_selectedNestedIndex != kHeaderNested) {
        m_selectedNestedIndex = kHeaderNested;
        emit selectedNestedIndexChanged();
    }
    emit selectedSubtaskIndexChanged();
}

int TaskNavigationController::selectedNestedIndex() const {
    return m_selectedNestedIndex;
}

void TaskNavigationController::setSelectedNestedIndex(int index) {
    if (m_selectedNestedIndex == index) {
        return;
    }
    m_selectedNestedIndex = index;
    emit selectedNestedIndexChanged();
}

QVariantMap TaskNavigationController::expandedTasks() const {
    return m_expandedTasks;
}

QVariantMap TaskNavigationController::expandedSubtasks() const {
    return m_expandedSubtasks;
}

QVariantList TaskNavigationController::structure() const {
    return m_structure;
}

void TaskNavigationController::setStructure(const QVariantList& structure) {
    m_structure = structure;
    emit structureChanged();
    clampToStructure();
}

bool TaskNavigationController::handleKey(int key, int modifiers) {
    Q_UNUSED(modifiers);
    switch (key) {
    case Qt::Key_Down:
        moveDown();
        return true;
    case Qt::Key_Up:
        moveUp();
        return true;
    case Qt::Key_Left:
        moveLeft();
        return true;
    case Qt::Key_Right:
        moveRight();
        return true;
    case Qt::Key_Return:
    case Qt::Key_Enter:
        activate();
        return true;
    case Qt::Key_F2:
        beginEdit();
        return true;
    case Qt::Key_Escape:
        cancel();
        return true;
    default:
        return false;
    }
}
void TaskNavigationController::moveDown() {
    // Nested scope: circular inside the current subtask's children.
    if (m_selectedSubtaskIndex >= 0 && m_selectedNestedIndex >= 0) {
        const int n = nestedCount(m_selectedIndex, m_selectedSubtaskIndex);
        if (n > 0) {
            setSelectedNestedIndex((m_selectedNestedIndex + 1) % n);
            emit scrollToIndex(m_selectedIndex);
        }
        return;
    }
    // Subtask scope: circular inside the current task.
    if (m_selectedSubtaskIndex >= 0) {
        const int n = subCount(m_selectedIndex);
        if (n > 0) {
            setSelectedSubtaskIndex((m_selectedSubtaskIndex + 1) % n);
            emit scrollToIndex(m_selectedIndex);
        }
        return;
    }
    // Header scope: next visible task (circular wrap).
    const int next = nextVisible(m_selectedIndex, 1);
    if (next >= 0) {
        emitCursor(next, kHeaderSub, kHeaderNested);
    }
}

void TaskNavigationController::moveUp() {
    // Nested scope: circular inside the current subtask's children.
    if (m_selectedSubtaskIndex >= 0 && m_selectedNestedIndex >= 0) {
        const int n = nestedCount(m_selectedIndex, m_selectedSubtaskIndex);
        if (n > 0) {
            setSelectedNestedIndex((m_selectedNestedIndex - 1 + n) % n);
            emit scrollToIndex(m_selectedIndex);
        }
        return;
    }
    // Subtask scope: circular inside the current task.
    if (m_selectedSubtaskIndex >= 0) {
        const int n = subCount(m_selectedIndex);
        if (n > 0) {
            setSelectedSubtaskIndex((m_selectedSubtaskIndex - 1 + n) % n);
            emit scrollToIndex(m_selectedIndex);
        }
        return;
    }
    // Header scope: prev visible task (circular wrap).
    const int next = nextVisible(m_selectedIndex, -1);
    if (next >= 0) {
        emitCursor(next, kHeaderSub, kHeaderNested);
    }
}

void TaskNavigationController::moveLeft() {
    // Nested child → parent subtask.
    if (m_selectedNestedIndex >= 0) {
        setSelectedNestedIndex(kParentNested);
        return;
    }
    // Subtask row → task header (card stays expanded).
    if (m_selectedSubtaskIndex >= 0) {
        setSelectedSubtaskIndex(kHeaderSub);
        emit focusListRequested();
        return;
    }
    // Task header → collapse card.
    if (m_selectedIndex >= 0) {
        const QString id = taskIdAt(m_selectedIndex);
        if (!id.isEmpty() && isTaskExpanded(id)) {
            setTaskExpanded(id, false);
        }
        emit focusListRequested();
    }
}

void TaskNavigationController::moveRight() {
    if (m_selectedIndex < 0) {
        return;
    }
    const QString taskId = taskIdAt(m_selectedIndex);
    if (taskId.isEmpty()) {
        return;
    }
    // Nested child → no-op (terminal depth).
    if (m_selectedNestedIndex >= 0) {
        return;
    }
    // Collapsed header → expand + select subtask 0.
    if (m_selectedSubtaskIndex < 0) {
        if (!isTaskExpanded(taskId)) {
            setTaskExpanded(taskId, true);
        }
        if (subCount(m_selectedIndex) > 0) {
            setSelectedSubtaskIndex(0);
        }
        emit scrollToIndex(m_selectedIndex);
        return;
    }
    // Subtask row → enter nested 0 when children exist.
    // Sub-expansion is driven by QML `SubtaskCard.expanded` for now
    // (see Phase 3); nestedCount guards the drill-in.
    if (nestedCount(m_selectedIndex, m_selectedSubtaskIndex) > 0) {
        setSelectedNestedIndex(0);
        emit scrollToIndex(m_selectedIndex);
    }
}

void TaskNavigationController::activate() {
    if (m_selectedIndex < 0) {
        return;
    }
    if (m_selectedSubtaskIndex >= 0 && m_selectedNestedIndex >= 0) {
        emit toggleNestedRequested(m_selectedIndex, m_selectedSubtaskIndex, m_selectedNestedIndex);
    } else if (m_selectedSubtaskIndex >= 0) {
        emit toggleSubtaskRequested(m_selectedIndex, m_selectedSubtaskIndex);
    } else {
        emit toggleTaskRequested(m_selectedIndex);
    }
}

void TaskNavigationController::beginEdit() {
    if (m_selectedIndex < 0) {
        return;
    }
    if (m_selectedSubtaskIndex >= 0 && m_selectedNestedIndex >= 0) {
        emit editNestedRequested(m_selectedIndex, m_selectedSubtaskIndex, m_selectedNestedIndex);
    } else if (m_selectedSubtaskIndex >= 0) {
        emit editSubtaskRequested(m_selectedIndex, m_selectedSubtaskIndex);
    } else {
        emit editTaskRequested(m_selectedIndex);
    }
}

void TaskNavigationController::cancel() {
    emit focusListRequested();
}

void TaskNavigationController::selectTask(int listIndex) {
    emitCursor(listIndex, kHeaderSub, kHeaderNested);
}

void TaskNavigationController::selectSubtask(int listIndex, int subIdx) {
    emitCursor(listIndex, subIdx, kHeaderNested);
}
bool TaskNavigationController::isTaskExpanded(const QString& taskId) const {
    return m_expandedTasks.value(taskId, false).toBool();
}

bool TaskNavigationController::isSubExpanded(const QString& taskId, const QString& subId) const {
    return m_expandedSubtasks.value(taskId + QStringLiteral("/") + subId, false).toBool();
}

void TaskNavigationController::setTaskExpanded(const QString& taskId, bool expanded) {
    if (taskId.isEmpty() || isTaskExpanded(taskId) == expanded) {
        return;
    }
    if (expanded) {
        m_expandedTasks.insert(taskId, true);
    } else {
        m_expandedTasks.remove(taskId);
    }
    emit expansionChanged();
}

void TaskNavigationController::setSubExpanded(const QString& taskId, const QString& subId, bool expanded) {
    if (taskId.isEmpty() || subId.isEmpty()) {
        return;
    }
    const QString key = taskId + QStringLiteral("/") + subId;
    if (m_expandedSubtasks.value(key, false).toBool() == expanded) {
        return;
    }
    if (expanded) {
        m_expandedSubtasks.insert(key, true);
    } else {
        m_expandedSubtasks.remove(key);
    }
    emit expansionChanged();
}
void TaskNavigationController::clampToStructure() {
    // 1. Cursor task must be a visible row.
    const QList<int> visible = visibleIndices();
    if (visible.isEmpty()) {
        emitCursor(-1, kHeaderSub, kHeaderNested);
        return;
    }
    if (m_selectedIndex < 0 || m_selectedIndex >= m_structure.size()
        || !m_structure.at(m_selectedIndex).toMap().value(QStringLiteral("visible"), true).toBool()) {
        int next = nextVisible(m_selectedIndex, 1);
        if (next < 0) {
            next = visible.first();
        }
        emitCursor(next, kHeaderSub, kHeaderNested);
        return;
    }
    // 2. Subtask index within bounds.
    const int nSub = subCount(m_selectedIndex);
    if (nSub <= 0) {
        if (m_selectedSubtaskIndex != kHeaderSub || m_selectedNestedIndex != kHeaderNested) {
            emitCursor(m_selectedIndex, kHeaderSub, kHeaderNested);
        }
    } else if (m_selectedSubtaskIndex >= nSub) {
        emitCursor(m_selectedIndex, nSub - 1, kHeaderNested);
        return;
    }
    // 3. Nested index within bounds.
    if (m_selectedSubtaskIndex >= 0) {
        const int n = nestedCount(m_selectedIndex, m_selectedSubtaskIndex);
        if (n <= 0) {
            if (m_selectedNestedIndex != kHeaderNested) {
                setSelectedNestedIndex(kHeaderNested);
            }
        } else if (m_selectedNestedIndex >= n) {
            setSelectedNestedIndex(n - 1);
        }
    } else if (m_selectedNestedIndex != kHeaderNested) {
        setSelectedNestedIndex(kHeaderNested);
    }
    // 4. Prune expansion entries for unknown task ids.
    bool pruned = false;
    QList<QString> deadTasks;
    for (auto it = m_expandedTasks.constBegin(); it != m_expandedTasks.constEnd(); ++it) {
        bool known = false;
        for (const QVariant& row : std::as_const(m_structure)) {
            if (row.toMap().value(QStringLiteral("todoId")).toString() == it.key()) {
                known = true;
                break;
            }
        }
        if (!known) {
            deadTasks.append(it.key());
        }
    }
    for (const QString& k : std::as_const(deadTasks)) {
        m_expandedTasks.remove(k);
        pruned = true;
    }
    QList<QString> deadSubs;
    for (auto it = m_expandedSubtasks.constBegin(); it != m_expandedSubtasks.constEnd(); ++it) {
        const QString taskPart = it.key().section(QLatin1Char('/'), 0, 0);
        bool known = false;
        for (const QVariant& row : std::as_const(m_structure)) {
            if (row.toMap().value(QStringLiteral("todoId")).toString() == taskPart) {
                known = true;
                break;
            }
        }
        if (!known) {
            deadSubs.append(it.key());
        }
    }
    for (const QString& k : std::as_const(deadSubs)) {
        m_expandedSubtasks.remove(k);
        pruned = true;
    }
    if (pruned) {
        emit expansionChanged();
    }
}

QList<int> TaskNavigationController::visibleIndices() const {
    QList<int> out;
    for (int i = 0; i < m_structure.size(); ++i) {
        if (m_structure.at(i).toMap().value(QStringLiteral("visible"), true).toBool()) {
            out.append(i);
        }
    }
    return out;
}

int TaskNavigationController::nextVisible(int from, int dir) const {
    const QList<int> visible = visibleIndices();
    if (visible.isEmpty()) {
        return -1;
    }
    if (from < 0) {
        return dir > 0 ? visible.first() : visible.last();
    }
    int pos = visible.indexOf(from);
    if (pos < 0) {
        return visible.first();
    }
    pos = (pos + dir + visible.size()) % visible.size();
    return visible.at(pos);
}

int TaskNavigationController::subCount(int listIndex) const {
    if (listIndex < 0 || listIndex >= m_structure.size()) {
        return 0;
    }
    return toInt(m_structure.at(listIndex).toMap().value(QStringLiteral("nSub")), 0);
}

int TaskNavigationController::nestedCount(int listIndex, int subIdx) const {
    if (listIndex < 0 || listIndex >= m_structure.size() || subIdx < 0) {
        return 0;
    }
    const QVariantList counts = m_structure.at(listIndex).toMap().value(QStringLiteral("nestedCounts")).toList();
    if (subIdx >= counts.size()) {
        return 0;
    }
    return toInt(counts.at(subIdx), 0);
}

QString TaskNavigationController::taskIdAt(int listIndex) const {
    if (listIndex < 0 || listIndex >= m_structure.size()) {
        return {};
    }
    return m_structure.at(listIndex).toMap().value(QStringLiteral("todoId")).toString();
}

void TaskNavigationController::emitCursor(int listIndex, int subIdx, int nestedIdx) {
    if (m_selectedIndex != listIndex) {
        m_selectedIndex = listIndex;
        emit selectedIndexChanged();
    }
    if (m_selectedSubtaskIndex != subIdx) {
        m_selectedSubtaskIndex = subIdx;
        emit selectedSubtaskIndexChanged();
    }
    if (m_selectedNestedIndex != nestedIdx) {
        m_selectedNestedIndex = nestedIdx;
        emit selectedNestedIndexChanged();
    }
    emit scrollToIndex(m_selectedIndex);
}

} // namespace caelestia::components
