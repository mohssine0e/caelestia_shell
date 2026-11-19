#pragma once

#include <qcolor.h>
#include <qlist.h>
#include <qobject.h>
#include <qqmlengine.h>

namespace caelestia::shell::blobs {

class BlobShape;
class BlobInvertedRect;

class BlobGroup : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(qreal smoothing READ smoothing WRITE setSmoothing NOTIFY smoothingChanged)
    Q_PROPERTY(QColor color READ color WRITE setColor NOTIFY colorChanged)
    Q_PROPERTY(qreal outlineWidth READ outlineWidth WRITE setOutlineWidth NOTIFY outlineWidthChanged)
    Q_PROPERTY(QColor outlineColor READ outlineColor WRITE setOutlineColor NOTIFY outlineColorChanged)
    Q_PROPERTY(bool cornerFill READ cornerFill WRITE setCornerFill NOTIFY cornerFillChanged)

public:
    explicit BlobGroup(QObject* parent = nullptr);
    ~BlobGroup() override;

    [[nodiscard]] qreal smoothing() const;
    void setSmoothing(qreal s);

    [[nodiscard]] QColor color() const;
    void setColor(const QColor& c);

    [[nodiscard]] qreal outlineWidth() const;
    void setOutlineWidth(qreal width);
    [[nodiscard]] QColor outlineColor() const;
    void setOutlineColor(const QColor& color);

    [[nodiscard]] bool cornerFill() const;
    void setCornerFill(bool e);

    void addShape(BlobShape* shape);
    void removeShape(BlobShape* shape);

    void setInvertedRect(BlobInvertedRect* rect);
    void clearInvertedRect(BlobInvertedRect* rect);

    [[nodiscard]] const QList<BlobShape*>& shapes() const;
    [[nodiscard]] BlobInvertedRect* invertedRect() const;

    void markDirty();
    void markShapeDirty(BlobShape* source);
    void ensurePhysicsUpdated();

signals:
    void smoothingChanged();
    void colorChanged();
    void cornerFillChanged();
    void outlineWidthChanged();
    void outlineColorChanged();

private:
    qreal m_smoothing = 32.0;
    QColor m_color{ 0x44, 0x88, 0xff };
    qreal m_outlineWidth = 0;
    QColor m_outlineColor{ Qt::transparent };
    bool m_cornerFill = true;
    QList<BlobShape*> m_shapes;
    BlobInvertedRect* m_invertedRect = nullptr;
    bool m_physicsUpdated = false;
};

} // namespace caelestia::shell::blobs
