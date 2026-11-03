#include <QQuickWindow>
#include <QSurfaceFormat>
#include <QtGlobal>

// The portable launcher loads this before plasmawindowed creates any windows.
// Requesting alpha from the QML plugin is too late on some Wayland backends.
static void prepareWindowAlpha()
{
    QQuickWindow::setDefaultAlphaBuffer(true);
    QSurfaceFormat format = QSurfaceFormat::defaultFormat();
    format.setAlphaBufferSize(8);
    QSurfaceFormat::setDefaultFormat(format);
}
Q_CONSTRUCTOR_FUNCTION(prepareWindowAlpha)
