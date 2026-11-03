#pragma once
#include <QQuickItem>

class PlasmaField : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(qreal time READ time WRITE setTime NOTIFY appearanceChanged)
    Q_PROPERTY(qreal intensity READ intensity WRITE setIntensity NOTIFY appearanceChanged)
    Q_PROPERTY(QRectF frame READ frame WRITE setFrame NOTIFY appearanceChanged)
    Q_PROPERTY(QPointF origin READ origin WRITE setOrigin NOTIFY appearanceChanged)
    Q_PROPERTY(bool backgroundLayer READ backgroundLayer WRITE setBackgroundLayer NOTIFY appearanceChanged)
    Q_PROPERTY(bool borderOnly READ borderOnly WRITE setBorderOnly NOTIFY appearanceChanged)
    Q_PROPERTY(bool continuous READ continuous WRITE setContinuous NOTIFY appearanceChanged)
    Q_PROPERTY(bool reducedMotion READ reducedMotion WRITE setReducedMotion NOTIFY appearanceChanged)
public:
    explicit PlasmaField(QQuickItem *parent=nullptr);
    qreal time() const { return m_time; }
    qreal intensity() const { return m_intensity; }
    QRectF frame() const { return m_frame; }
    QPointF origin() const { return m_origin; }
    bool backgroundLayer() const { return m_background; }
    bool borderOnly() const { return m_borderOnly; }
    void setBorderOnly(bool v);
    bool continuous() const { return m_continuous; }
    void setContinuous(bool v);
    bool reducedMotion() const { return m_reduced; }
    void setTime(qreal v);
    void setIntensity(qreal v);
    void setFrame(QRectF v);
    void setOrigin(QPointF v);
    void setBackgroundLayer(bool v);
    void setReducedMotion(bool v);
signals:
    void lightningHit();
    void appearanceChanged();
protected:
    QSGNode *updatePaintNode(QSGNode *,UpdatePaintNodeData *) override;
private:
    qreal m_time=0, m_intensity=0;
    QRectF m_frame;
    QPointF m_origin;
    bool m_borderOnly=false, m_background=false, m_reduced=false, m_continuous=false;
};
