#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QQuickItem>
#include <QFile>
#include <QTimer>
#include <QScreen>
#include <QCursor>
#include <QQmlContext>
#include <QFileInfo>
#include <QDir>
#include <QSettings>
#include <QStandardPaths>
#include <QElapsedTimer>
#include <QLockFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPointer>
#include <LayerShellQt/Window>
#include <LayerShellQt/Shell>

int main(int argc, char **argv)
{
    // The splash must not consume the activation token belonging to the app.
    qunsetenv("XDG_ACTIVATION_TOKEN");
    qunsetenv("DESKTOP_STARTUP_ID");
    const QString requestedPlatform=qEnvironmentVariable("QT_QPA_PLATFORM");
    if(requestedPlatform.startsWith("wayland") || (requestedPlatform.isEmpty() && qEnvironmentVariable("XDG_SESSION_TYPE")=="wayland"))
        LayerShellQt::Shell::useLayerShell();
    QQuickWindow::setDefaultAlphaBuffer(true);
    QGuiApplication app(argc, argv);
    const bool wayland=QGuiApplication::platformName().startsWith("wayland");
    // Wayland clients cannot reliably query the global pointer position. Let the
    // compositor select the launch output when the layer surface is mapped.
    QPointer<QScreen> launchScreen;
    if(!wayland)launchScreen=QGuiApplication::screenAt(QCursor::pos());
    if(!launchScreen)launchScreen=QGuiApplication::primaryScreen();
    QLockFile splashLock(QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation)+"/vibeenergy-splash.lock");
    if(!splashLock.tryLock(0)) return 0;
    QQmlApplicationEngine engine;
    if (argc < 2) return 1;
    const QString qmlPath=QString::fromLocal8Bit(argv[1]);
    const QString electricPath=QFileInfo(qmlPath).dir().filePath("../sounds/electricity.mp3");
    QSettings settings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)+"/energytlk/appearance.ini",QSettings::IniFormat);
    if(!settings.value("splashEnabled",true).toBool()) return 0;
    engine.rootContext()->setContextProperty("splashElectricSource",
        settings.value("splashSoundEnabled",true).toBool() && QFile::exists(electricPath) ? QUrl::fromLocalFile(electricPath) : QUrl());
    engine.load(QUrl::fromLocalFile(qmlPath));
    if (engine.rootObjects().isEmpty()) return 1;
    QElapsedTimer presentedTime;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    if (window) {
        QObject::connect(window, &QQuickWindow::frameSwapped, &app, [window, &presentedTime]{
            presentedTime.start();
            window->setProperty("presented",true);
            const QString debug=qEnvironmentVariable("VIBEENERGY_SPLASH_DEBUG_FILE");
            if(!debug.isEmpty()) {
                QJsonObject info{{"screen",window->screen()?window->screen()->name():QString()},
                    {"width",window->width()},{"height",window->height()},
                    {"contentWidth",window->contentItem()->width()},{"contentHeight",window->contentItem()->height()}};
                if(auto *artwork=window->findChild<QQuickItem *>("splashArtwork")) {
                    const QPointF center=artwork->mapToScene(QPointF(artwork->width()/2,artwork->height()/2));
                    info.insert("artworkCenterX",center.x());info.insert("artworkCenterY",center.y());
                }
                QFile file(debug);if(file.open(QIODevice::WriteOnly))file.write(QJsonDocument(info).toJson());
            }
            const QString shown=qEnvironmentVariable("VIBEENERGY_SPLASH_SHOWN");
            if(!shown.isEmpty()) {
                QFile file(shown);
                if(file.open(QIODevice::WriteOnly)) file.close();
            }
        }, Qt::SingleShotConnection);
        QScreen *screen=launchScreen?launchScreen.data():QGuiApplication::primaryScreen();
        if (screen) {
            window->setScreen(screen);
            const QRect bounds = screen->geometry();
            window->resize(bounds.size());
            if (wayland) {
                auto *layer=LayerShellQt::Window::get(window);
                layer->setScreenConfiguration(LayerShellQt::Window::ScreenFromCompositor);
                layer->setLayer(LayerShellQt::Window::LayerOverlay);
                layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop)|LayerShellQt::Window::AnchorBottom|LayerShellQt::Window::AnchorLeft|LayerShellQt::Window::AnchorRight);
                layer->setExclusiveZone(-1);
                layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
                layer->setScope(QStringLiteral("vibeenergy-splash"));
                window->show();
            } else {
                window->setPosition(bounds.topLeft());
                window->show();
            }
            if(!wayland) QObject::connect(screen,&QScreen::geometryChanged,window,[window](const QRect &geometry){
                window->setGeometry(geometry);
            });
        }
    }
    if(window && qEnvironmentVariableIsSet("VIBEENERGY_SPLASH_CAPTURE")) {
        QTimer::singleShot(1400,window,[window]{
            window->grabWindow().save(qEnvironmentVariable("VIBEENERGY_SPLASH_CAPTURE"));
            auto *artwork=window->findChild<QQuickItem *>("splashArtwork");
            auto *wordmark=window->findChild<QQuickItem *>("splashWordmark");
            QJsonObject info{{"windowWidth",window->width()},{"windowHeight",window->height()},
                {"contentWidth",window->contentItem()->width()},{"contentHeight",window->contentItem()->height()}};
            for(auto *item:{artwork,wordmark}) if(item) {
                const QPointF center=item->mapToScene(QPointF(item->width()/2,item->height()/2));
                info.insert(item->objectName()+"CenterX",center.x());info.insert(item->objectName()+"CenterY",center.y());
            }
            QFile file(qEnvironmentVariable("VIBEENERGY_SPLASH_CAPTURE")+".json");
            if(file.open(QIODevice::WriteOnly))file.write(QJsonDocument(info).toJson());
        });
    }
    const QString ready = qEnvironmentVariable("VIBEENERGY_SPLASH_READY");
    QTimer poll;
    QObject::connect(&poll, &QTimer::timeout, &app, [&]{
        if(presentedTime.isValid() && presentedTime.elapsed()>=2000 && !ready.isEmpty() && QFile::exists(ready)) app.quit();
    });
    poll.start(100);
    QTimer::singleShot(15000, &app, &QCoreApplication::quit);
    return app.exec();
}
