#include <QQmlExtensionPlugin>
#include <qqml.h>
#include <QTimer>
#include <QFile>
#include <QSaveFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QStandardPaths>
#include <QDir>
#include <QProcess>
#include <QProcessEnvironment>
#include <QDate>
#include <QDateTime>
#include <QGuiApplication>
#include <QClipboard>
#include <QFileInfo>
#include <cmath>
#include <unistd.h>
#include <QQuickWindow>
#include <QPointer>
#include <QSettings>
#include <QFileSystemWatcher>
#include <QQmlProperty>
#include <QRegion>
#include <QScreen>
#include <QPainterPath>
#include <QIcon>
#include <QEvent>
#include <sys/file.h>
#include <fcntl.h>
#include <cerrno>
#include <QQmlContext>
#include "plasmafield.h"
#include "turboaudiomixer.h"
#include "instanceipc.h"
#include "collectorstop.h"
#include <KWindowSystem>
#include <KStatusNotifierItem>
#include <QApplication>
#include <QMenu>
#include <QDBusConnectionInterface>

// The splash handoff belongs to this process, not to an individual window.
// Plasma can create more dashboards after the launcher removes its temp files.
class UiSessionState : public QObject {
    Q_OBJECT
    bool m_complete=true;
    QTimer m_poll;
    QFileSystemWatcher m_appearanceWatcher;
    QString m_appearancePath;
    QByteArray m_appearanceBytes;
public:
    explicit UiSessionState(QObject *parent):QObject(parent) {
        m_appearancePath=QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)+"/energytlk/appearance.ini";
        QFile current(m_appearancePath);
        if(current.open(QIODevice::ReadOnly))m_appearanceBytes=current.readAll();
        const QString directory=QFileInfo(m_appearancePath).absolutePath();
        if(QDir(directory).exists())m_appearanceWatcher.addPath(directory);
        if(QFile::exists(m_appearancePath))m_appearanceWatcher.addPath(m_appearancePath);
        connect(&m_appearanceWatcher,&QFileSystemWatcher::directoryChanged,this,[this]{refreshAppearance();});
        connect(&m_appearanceWatcher,&QFileSystemWatcher::fileChanged,this,[this]{refreshAppearance();});
        const QString path=qEnvironmentVariable("VIBEENERGY_SPLASH_CLOSED");
        m_complete=path.isEmpty() || QFile::exists(path) || !QFileInfo(path).absoluteDir().exists();
        if(m_complete)return;
        auto finish=[this]{
            if(m_complete)return;
            m_complete=true;m_poll.stop();emit completed();
        };
        connect(&m_poll,&QTimer::timeout,this,[path,finish]{
            if(QFile::exists(path) || !QFileInfo(path).absoluteDir().exists())finish();
        });
        QTimer::singleShot(17000,this,finish);
        m_poll.start(50);
    }
    void refreshAppearance() {
        if(QFile::exists(m_appearancePath) && !m_appearanceWatcher.files().contains(m_appearancePath))m_appearanceWatcher.addPath(m_appearancePath);
        QFile file(m_appearancePath);
        const QByteArray bytes=file.open(QIODevice::ReadOnly)?file.readAll():QByteArray();
        if(bytes==m_appearanceBytes)return;
        m_appearanceBytes=bytes;
        QSettings settings(m_appearancePath,QSettings::IniFormat);settings.sync();
        emit appearanceChanged();
    }
    bool complete() const { return m_complete; }
    static UiSessionState &instance() {
        static QPointer<UiSessionState> shared;
        if(!shared)shared=new UiSessionState(QCoreApplication::instance());
        return *shared;
    }
signals:
    void appearanceChanged();
    void completed();
};

class StandaloneWindow : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface","com.techtoapes.VibeEnergy.Window")
    QPointer<QQuickWindow> m_window;
    bool m_uninstalling=false;
    bool m_registered=false;
    KStatusNotifierItem *m_tray=nullptr;
    bool m_initializingTray=false;
    bool m_stoppingCollector=false;
    bool m_clearingHistory=false;
    QTimer m_runtimeWatch;
protected:
    bool eventFilter(QObject *object,QEvent *event) override {
        // PlasmaWindowedView deletes its applet in hideEvent unless launched
        // with its own tray option. We own the tray, so keep the applet alive
        // when hiding it or remapping its Wayland identity.
        if(object==m_window && event->type()==QEvent::Hide &&
           (m_tray || m_initializingTray || m_window->property("vibeenergyIdentityPrepared").toBool()))return true;
        if(object==m_window && event->type()==QEvent::Close && m_window->inherits("PlasmaWindowedView")) {
            auto *bus=QDBusConnection::sessionBus().interface();
            if((m_tray || m_initializingTray) && bus && bus->isServiceRegistered(QStringLiteral("org.kde.StatusNotifierWatcher")).value()) {
                event->ignore();
                m_window->hide();
                return true;
            }
            // Plasma's host can remain alive after its last window closes.
            // Do this after event delivery so a rejected close stays open.
            const QPointer<QQuickWindow> window=m_window;
            QTimer::singleShot(0,this,[this,window]{
                if(window && window->isVisible())return;
                auto bus=QDBusConnection::sessionBus();
                if(m_registered)bus.unregisterService(QString::fromLatin1(VibeInstance::WindowService));
                m_registered=false;m_window=nullptr;
                QCoreApplication::quit();
            });
        }
        return QObject::eventFilter(object,event);
    }
public:
    explicit StandaloneWindow(QObject *parent):QObject(parent) {}
    void setUninstalling(bool value) {m_uninstalling=value;}
    void setHistoryClearing(bool value) {m_clearingHistory=value;}
    void quitWithCollector() {
        if(m_clearingHistory) {if(m_tray)m_tray->showMessage(tr("History reset in progress"),tr("Wait for the reset to finish before quitting."),QStringLiteral("dialog-information"));return;}
        if(m_stoppingCollector)return;
        m_stoppingCollector=true;
        if(m_tray)m_tray->setToolTipSubTitle(tr("Stopping background recording…"));
        QTimer::singleShot(0,this,[this]{
            const auto result=stopCollectorBlocking();
            if(!result.success && m_tray)m_tray->showMessage(tr("VibeEnergy closed"),tr("Recording shutdown could not be confirmed: ")+result.message,QStringLiteral("dialog-warning"));
            // Quit must never reopen a broken or half-unmounted interface.
            QCoreApplication::quit();
        });
    }

    bool hideToTray() {
        auto *bus=QDBusConnection::sessionBus().interface();
        if((!m_tray && !m_initializingTray) || !m_window || !bus || !bus->isServiceRegistered(QStringLiteral("org.kde.StatusNotifierWatcher")).value())return false;
        m_window->hide();
        return true;
    }
    void ensureTray(const QIcon &icon) {
        if(m_tray || m_initializingTray || !m_window || !m_window->inherits("PlasmaWindowedView") || !qobject_cast<QApplication *>(qApp))return;
        auto *bus=QDBusConnection::sessionBus().interface();
        if(!bus || !bus->isServiceRegistered(QStringLiteral("org.kde.StatusNotifierWatcher")).value())return;
        m_initializingTray=true;
        QGuiApplication::setQuitOnLastWindowClosed(false);
        m_tray=new KStatusNotifierItem(QStringLiteral("vibeenergy"),this);
        m_initializingTray=false;
        m_tray->setCategory(KStatusNotifierItem::ApplicationStatus);
        m_tray->setTitle(QStringLiteral("VibeEnergy"));
        m_tray->setStatus(KStatusNotifierItem::Active);
        m_tray->setIconByPixmap(icon);
        m_tray->setToolTipTitle(QStringLiteral("VibeEnergy"));
        m_tray->setToolTipSubTitle(tr("CPU and GPU energy monitoring"));
        m_tray->setStandardActionsEnabled(false);
        auto *menu=new QMenu;
        connect(menu->addAction(tr("Show VibeEnergy")),&QAction::triggered,this,[this]{Activate(QString());});
        connect(menu->addAction(tr("Hide window")),&QAction::triggered,this,[this]{if(m_window)m_window->hide();});
        menu->addSeparator();
        auto *quit=menu->addAction(tr("Quit VibeEnergy"));
        quit->setToolTip(tr("Stop the background collector and quit VibeEnergy. Powerstat is managed separately."));
        connect(quit,&QAction::triggered,this,&StandaloneWindow::quitWithCollector);
        m_tray->setContextMenu(menu);
        connect(m_tray,&KStatusNotifierItem::activateRequested,this,[this](bool,const QPoint &){Activate(QString());});
        QGuiApplication::setQuitOnLastWindowClosed(false);
        m_runtimeWatch.setInterval(1000);
        connect(&m_runtimeWatch,&QTimer::timeout,this,[this]{
            if(m_stoppingCollector || m_clearingHistory || m_uninstalling)return;
            const QString appdir=qEnvironmentVariable("APPDIR");
            if(!qEnvironmentVariableIsEmpty("APPIMAGE") && !appdir.isEmpty() && !QFile::exists(appdir+"/AppRun")) {
                quitWithCollector();return;
            }
            // Collector loss is an Offline state, not a reason to close the UI.
            // A pending service stop may finish well after a failed uninstall.
        });
        m_runtimeWatch.start();
        connect(qApp,&QCoreApplication::aboutToQuit,this,[this]{
            // Covers desktop/session termination too, including a launcher
            // killed before it can run its own shutdown callback.
            if(m_stoppingCollector)return;
            m_stoppingCollector=true;
            stopCollectorBlocking();
        });
    }
    static StandaloneWindow &instance() {
        static QPointer<StandaloneWindow> shared;
        if(!shared)shared=new StandaloneWindow(QCoreApplication::instance());
        return *shared;
    }
    bool claim(QQuickWindow *window) {
        if(m_window==window)return true;
        if(m_window) {
            Activate(qEnvironmentVariable("XDG_ACTIVATION_TOKEN"));
            QTimer::singleShot(0,window,&QWindow::close);
            return false;
        }
        if(!m_registered) {
            auto bus=QDBusConnection::sessionBus();
            if(bus.isConnected()) {
                bus.registerObject(QString::fromLatin1(VibeInstance::ObjectPath),this,QDBusConnection::ExportAllSlots);
                if(!bus.registerService(QString::fromLatin1(VibeInstance::WindowService))) {
                    if(VibeInstance::activate(VibeInstance::WindowService,qEnvironmentVariable("XDG_ACTIVATION_TOKEN"))) {
                        QTimer::singleShot(0,window,&QWindow::close);return false;
                    }
                } else m_registered=true;
            }
        }
        m_window=window;
        window->installEventFilter(this);
        return true;
    }
public slots:
    bool Activate(const QString &token) {
        if(!m_window){quitWithCollector();return false;}
        m_window->setWindowStates(m_window->windowStates() & ~Qt::WindowMinimized);
        m_window->show();m_window->raise();
        if(!token.isEmpty())KWindowSystem::setCurrentXdgActivationToken(token);
        KWindowSystem::activateWindow(m_window);
        return true;
    }
};

class EnergyBridge : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap state READ state NOTIFY changed)
    Q_PROPERTY(bool serviceBusy READ serviceBusy NOTIFY changed)
    Q_PROPERTY(bool clearingHistory READ clearingHistory NOTIFY clearingHistoryChanged)
    Q_PROPERTY(QString message READ message NOTIFY changed)
    Q_PROPERTY(bool demo READ demo WRITE setDemo NOTIFY changed)
    Q_PROPERTY(bool reducedMotion READ reducedMotion CONSTANT)
    Q_PROPERTY(double turboSoundVolume READ turboSoundVolume WRITE setTurboSoundVolume NOTIFY turboSoundVolumeChanged)
    Q_PROPERTY(bool cpuAutostartBusy READ cpuAutostartBusy NOTIFY cpuAutostartBusyChanged)
    Q_PROPERTY(bool splashEnabled READ splashEnabled WRITE setSplashEnabled NOTIFY splashEnabledChanged)
    Q_PROPERTY(bool splashSoundEnabled READ splashSoundEnabled WRITE setSplashSoundEnabled NOTIFY splashSoundEnabledChanged)
    Q_PROPERTY(bool splashSoundPromptDismissed READ splashSoundPromptDismissed WRITE setSplashSoundPromptDismissed NOTIFY splashSoundPromptDismissedChanged)
    Q_PROPERTY(bool startupComplete READ startupComplete NOTIFY startupCompleteChanged)
    Q_PROPERTY(bool launchedWithSplash READ launchedWithSplash CONSTANT)
    Q_PROPERTY(bool turboSoundEnabled READ turboSoundEnabled WRITE setTurboSoundEnabled NOTIFY turboSoundEnabledChanged)
    Q_PROPERTY(bool turboAlwaysOn READ turboAlwaysOn WRITE setTurboAlwaysOn NOTIFY turboAlwaysOnChanged)
    QVariantMap m_state;
    QString m_message;
    bool m_demo = false;
    bool m_clearingHistory=false;
    bool m_serviceBusy = false;
    bool m_cpuAutostartBusy = false;
    QTimer m_timer;
    QString statePath() const {
        QString base = qEnvironmentVariable("XDG_STATE_HOME");
        if (base.isEmpty()) base = QDir::homePath()+"/.local/state";
        return base+"/energytlk/"+(m_demo ? "demo/" : "")+"state.json";
    }
public:
    explicit EnergyBridge(QObject *parent=nullptr) : QObject(parent) {
        connect(&m_timer, &QTimer::timeout, this, &EnergyBridge::refresh);
        m_timer.start(1000);
        refresh();
        connect(&UiSessionState::instance(),&UiSessionState::completed,this,&EnergyBridge::startupCompleteChanged);
        connect(&UiSessionState::instance(),&UiSessionState::appearanceChanged,this,[this]{
            emit turboAlwaysOnChanged();emit turboSoundEnabledChanged();emit turboSoundVolumeChanged();
            emit splashEnabledChanged();emit splashSoundEnabledChanged();emit splashSoundPromptDismissedChanged();
        });
    }
    bool startupComplete() const { return UiSessionState::instance().complete(); }
    QVariantMap state() const { return m_state; }
    QString message() const { return m_message; }
    bool demo() const { return m_demo; }
    void setDemo(bool value) { m_demo=value; refresh(); }
    double turboSoundVolume() const {
        QSettings settings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)+"/energytlk/appearance.ini",QSettings::IniFormat);
        return qBound(0.0,settings.value("turboSoundVolume",0.10).toDouble(),1.0);
    }
    void setTurboSoundVolume(double value) {
        value=qBound(0.0,value,1.0);
        if(qFuzzyCompare(turboSoundVolume()+1,value+1))return;
        QSettings settings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)+"/energytlk/appearance.ini",QSettings::IniFormat);
        settings.setValue("turboSoundVolume",value);settings.sync();
        if(settings.status()!=QSettings::NoError){m_message=tr("Could not save sound volume");emit changed();return;}
        UiSessionState::instance().refreshAppearance();
    }
    bool launchedWithSplash() const { return !qEnvironmentVariable("VIBEENERGY_SPLASH_READY").isEmpty(); }
    bool splashEnabled() const {
        QSettings settings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)+"/energytlk/appearance.ini",QSettings::IniFormat);
        return settings.value("splashEnabled",true).toBool();
    }
    void setSplashEnabled(bool value) {
        QSettings settings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)+"/energytlk/appearance.ini",QSettings::IniFormat);
        settings.setValue("splashEnabled",value);
        if(!value) settings.setValue("splashSoundEnabled",false);
        settings.sync();
        if(settings.status()!=QSettings::NoError){m_message=tr("Could not save splash settings");emit changed();return;}
        UiSessionState::instance().refreshAppearance();
    }
    bool splashSoundEnabled() const {
        QSettings settings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)+"/energytlk/appearance.ini",QSettings::IniFormat);
        return splashEnabled() && settings.value("splashSoundEnabled",true).toBool();
    }
    bool splashSoundPromptDismissed() const {
        QSettings settings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)+"/energytlk/appearance.ini",QSettings::IniFormat);
        return settings.value("splashSoundPromptDismissed",false).toBool();
    }
    void setSplashSoundEnabled(bool value) {
        value=value && splashEnabled();
        QSettings settings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)+"/energytlk/appearance.ini",QSettings::IniFormat);
        settings.setValue("splashSoundEnabled",value);settings.sync();
        if(settings.status()!=QSettings::NoError){m_message=tr("Could not save splash sound settings");emit changed();return;}
        UiSessionState::instance().refreshAppearance();
    }
    void setSplashSoundPromptDismissed(bool value) {
        QSettings settings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)+"/energytlk/appearance.ini",QSettings::IniFormat);
        settings.setValue("splashSoundPromptDismissed",value);settings.sync();
        if(settings.status()!=QSettings::NoError){m_message=tr("Could not save splash reminder settings");emit changed();return;}
        UiSessionState::instance().refreshAppearance();
    }
    bool turboSoundEnabled() const {
        QSettings settings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)+"/energytlk/appearance.ini",QSettings::IniFormat);
        return settings.value("turboSoundEnabled",true).toBool();
    }
    void setTurboSoundEnabled(bool value) {
        if(turboSoundEnabled()==value)return;
        QSettings settings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)+"/energytlk/appearance.ini",QSettings::IniFormat);
        settings.setValue("turboSoundEnabled",value);settings.sync();
        if(settings.status()!=QSettings::NoError){m_message=tr("Could not save sound settings");emit changed();return;}
        UiSessionState::instance().refreshAppearance();
    }
    Q_INVOKABLE void publishTurbo(bool active, int duration=5000) {
        QString base=qEnvironmentVariable("XDG_STATE_HOME");
        if(base.isEmpty())base=QDir::homePath()+"/.local/state";
        const QString dir=base+"/energytlk";
        if(!QDir().mkpath(dir))return;
        QSaveFile file(dir+"/turbo.json");
        if(!file.open(QIODevice::WriteOnly))return;
        const double now=QDateTime::currentMSecsSinceEpoch()/1000.0;
        file.write(QJsonDocument(QJsonObject{{"until",active ? now+qBound(0,duration,60000)/1000.0 : 0.0}}).toJson());
        file.commit();
    }
    bool turboAlwaysOn() const {
        QSettings settings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)+"/energytlk/appearance.ini",QSettings::IniFormat);
        return settings.value("turboAlwaysOn",false).toBool();
    }
    void setTurboAlwaysOn(bool value) {
        if(turboAlwaysOn()==value)return;
        QSettings settings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)+"/energytlk/appearance.ini",QSettings::IniFormat);
        settings.setValue("turboAlwaysOn",value);settings.sync();
        if(settings.status()!=QSettings::NoError){m_message=tr("Could not save appearance settings");emit changed();return;}
        UiSessionState::instance().refreshAppearance();
    }
    bool reducedMotion() const {
        QSettings settings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)+"/kdeglobals",QSettings::IniFormat);
        return qEnvironmentVariableIntValue("VIBEENERGY_REDUCED_MOTION")==1 || settings.value("KDE/AnimationDurationFactor",1.0).toDouble()<=0;
    }
    Q_INVOKABLE void dashboardReady() {
        const QString path=qEnvironmentVariable("VIBEENERGY_SPLASH_READY");
        if(path.isEmpty() || QFile::exists(path)) return;
        QFile file(path);
        if(file.open(QIODevice::WriteOnly)) file.close();
    }
    Q_INVOKABLE bool prepareAppWindow(QQuickItem *item) {
        auto *window=item?item->window():nullptr;
        if(!window || (!window->inherits("PlasmaWindowedView") && qEnvironmentVariableIntValue("VIBEENERGY_TEST_ALPHA")!=1))return false;
        if((window->inherits("PlasmaWindowedView") || qEnvironmentVariableIntValue("VIBEENERGY_TEST_SINGLE_INSTANCE")==1) && !StandaloneWindow::instance().claim(window))return false;
        QGuiApplication::setDesktopFileName("vibeenergy");
        if(auto *context=qmlContext(item)) {
            const QIcon icon(context->resolvedUrl(QUrl(QStringLiteral("../icons/vibeenergy.svg"))).toLocalFile());
            if(!icon.isNull())window->setIcon(icon);
        }
        StandaloneWindow::instance().ensureTray(window->icon());
        window->setFlag(Qt::FramelessWindowHint,true);
        window->setProperty("vibeenergyOwnChrome",true);
        if(window->inherits("PlasmaWindowedView") && QGuiApplication::platformName().startsWith("wayland") && !window->property("vibeenergyIdentityPrepared").toBool()) {
            window->setProperty("vibeenergyIdentityPrepared",true);
            // plasmawindowed maps its surface before loading the applet. Qt only
            // sends the desktop ID when creating a shell surface, so remap once
            // after startup with our identity instead of the Plasma host's.
            const QPointer<QQuickWindow> safeWindow(window);
            QTimer::singleShot(0,window,[safeWindow]{
                if(safeWindow && safeWindow->isVisible()) {
                    safeWindow->hide();
                    safeWindow->show();
                }
            });
        }
        return true;
    }
    Q_INVOKABLE void initializeWindowSize(QQuickItem *item,int preferredWidth,int preferredHeight) {
        auto *window=item?item->window():nullptr;
        if(!window || !window->inherits("PlasmaWindowedView") || window->property("vibeenergySizeInitialized").toBool())return;
        window->setProperty("vibeenergySizeInitialized",true);
        const QPointer<QQuickWindow> safeWindow(window);
        QTimer::singleShot(0,window,[safeWindow,preferredWidth,preferredHeight]{
            if(!safeWindow)return;
            auto *screen=safeWindow->screen();if(!screen)screen=QGuiApplication::primaryScreen();
            if(!screen)return;
            QSettings settings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)+"/energytlk/appearance.ini",QSettings::IniFormat);
            const QSize available=screen->availableGeometry().size();
            const QSize minimum=safeWindow->minimumSize().boundedTo(available);
            if(minimum!=safeWindow->minimumSize())safeWindow->setMinimumSize(minimum);
            const QSize requested(settings.value("window/width",preferredWidth).toInt(),settings.value("window/height",preferredHeight).toInt());
            if(safeWindow->windowState()!=Qt::WindowMaximized && safeWindow->windowState()!=Qt::WindowFullScreen)
                safeWindow->resize(requested.expandedTo(minimum).boundedTo(available));
            // Debounce real resize events; preserve the last normal size when maximized.
            auto *saveTimer=new QTimer(safeWindow);saveTimer->setSingleShot(true);saveTimer->setInterval(350);
            connect(saveTimer,&QTimer::timeout,safeWindow,[safeWindow]{
                if(!safeWindow || safeWindow->windowState()==Qt::WindowMaximized || safeWindow->windowState()==Qt::WindowFullScreen)return;
                QSettings saved(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)+"/energytlk/appearance.ini",QSettings::IniFormat);
                saved.setValue("window/width",safeWindow->width());saved.setValue("window/height",safeWindow->height());saved.sync();
            });
            connect(safeWindow,&QWindow::widthChanged,saveTimer,[saveTimer](int){saveTimer->start();});
            connect(safeWindow,&QWindow::heightChanged,saveTimer,[saveTimer](int){saveTimer->start();});
        });
    }
    Q_INVOKABLE bool moveAppWindow(QQuickItem *item) {
        auto *window=item?item->window():nullptr;
        return window && window->property("vibeenergyOwnChrome").toBool() && window->startSystemMove();
    }
    Q_INVOKABLE bool resizeAppWindow(QQuickItem *item,int edges) {
        auto *window=item?item->window():nullptr;
        return window && window->property("vibeenergyOwnChrome").toBool() && window->startSystemResize(Qt::Edges(edges));
    }
    Q_INVOKABLE void windowAction(QQuickItem *item,QString action) {
        auto *window=item?item->window():nullptr;
        if(!window || !window->property("vibeenergyOwnChrome").toBool())return;
        if(action=="quit")QCoreApplication::quit();
        else if(action=="close") {
            if(!StandaloneWindow::instance().hideToTray())window->close();
        }
        else if(action=="minimize")window->showMinimized();
        else if(action=="maximize") {
            if(window->windowState()==Qt::WindowMaximized)window->showNormal();else window->showMaximized();
        }
    }
    Q_INVOKABLE bool prepareTurboSurface(QQuickItem *viewport) {
        if(!viewport || !viewport->window())return false;
        auto *window=viewport->window();
        auto recordDebug=[viewport=QPointer<QQuickItem>(viewport),window=QPointer<QQuickWindow>(window)]() {
            if(!viewport || !window)return;
            QString path=qEnvironmentVariable("VIBEENERGY_TURBO_DEBUG_FILE");
            const QString directory=qEnvironmentVariable("VIBEENERGY_TURBO_DEBUG_DIR");
            if(!directory.isEmpty()) {
                QDir().mkpath(directory);
                path=directory+"/window-"+QString::number(quintptr(window.data()),16)+".json";
            }
            if(path.isEmpty())return;
            QFile output(path);
            if(output.open(QIODevice::WriteOnly|QIODevice::Truncate)) {
                QJsonObject info{{"host",QString::fromLatin1(window->metaObject()->className())},
                    {"platform",QGuiApplication::platformName()},{"alpha",window->format().alphaBufferSize()},
                    {"opacity",window->opacity()},{"exposed",window->isExposed()},
                    {"visible",window->isVisible()},{"frames",window->property("vibeenergyDebugFrames").toInt()},
                    {"width",window->width()},{"height",window->height()},
                    {"availableHeight",window->screen()?window->screen()->availableGeometry().height():0},
                    {"margin",viewport->property("edgeMargin").toInt()},
                    {"active",viewport->property("turboActive").toBool()},
                    {"time",viewport->property("turboTime").toDouble()},
                    {"reducedMotion",viewport->property("reducedMotion").toBool()},
                    {"cornerAcceptsInput",window->mask().isEmpty() || window->mask().contains(QPoint(1,1))}};
                if(auto *effect=viewport->findChild<QObject*>("turboEffects")) {
                    info.insert("gpuAvailable",effect->property("gpuAvailable").toBool());
                    if(auto *loader=effect->findChild<QObject*>("turboEffectLoader")) {
                        info.insert("rendererStatus",loader->property("status").toInt());
                        info.insert("rendererSource",loader->property("source").toUrl().toString());
                    }
                }
                output.write(QJsonDocument(info).toJson());
                const QString capture=qEnvironmentVariable("VIBEENERGY_TURBO_CAPTURE");
                const int frame=viewport->property("turboTime").toDouble()>=4?4:viewport->property("turboTime").toDouble()>=2?2:0;
                const QByteArray key=QByteArray("vibeenergyCaptured")+QByteArray::number(frame);
                if(!capture.isEmpty() && frame && !viewport->property(key.constData()).toBool()) {
                    viewport->setProperty(key.constData(),true);window->grabWindow().save(capture+QString::number(frame)+".png");
                }
            }
        };
        recordDebug();
        if((qEnvironmentVariableIsSet("VIBEENERGY_TURBO_DEBUG_FILE") || qEnvironmentVariableIsSet("VIBEENERGY_TURBO_DEBUG_DIR")) && !viewport->property("vibeenergyDiagnosticTimer").toBool()) {
            viewport->setProperty("vibeenergyDiagnosticTimer",true);
            connect(window,&QQuickWindow::frameSwapped,viewport,[window]{
                window->setProperty("vibeenergyDebugFrames",window->property("vibeenergyDebugFrames").toInt()+1);
            });
            auto *timer=new QTimer(viewport);timer->setInterval(1000);
            connect(timer,&QTimer::timeout,viewport,recordDebug);timer->start();
        }
        const bool test=qEnvironmentVariableIntValue("VIBEENERGY_TEST_ALPHA")==1;
        if(qEnvironmentVariableIsSet("VIBEENERGY_TURBO_DEBUG"))qInfo()<<"Turbo surface capability"<<window->metaObject()->className()<<QGuiApplication::platformName()<<window->format().alphaBufferSize();
        // Plasma desktop widgets must never modify their shared shell window.
        if(!test && (!window->inherits("PlasmaWindowedView") || !QGuiApplication::platformName().startsWith("wayland")))return false;
        if(window->property("vibeenergyTurboPrepared").toBool())return true;
        auto format=window->requestedFormat();format.setAlphaBufferSize(8);window->setFormat(format);
        if(window->isVisible() && window->format().alphaBufferSize()<8)return false;
        window->setColor(Qt::transparent);
        for(auto *parent=viewport->parentItem();parent && parent!=window->contentItem();parent=parent->parentItem()) {
            if(parent->metaObject()->indexOfProperty("color")>=0)QQmlProperty(parent,"color").write(QColor(Qt::transparent));
        }
        const QPointer<QQuickItem> safeViewport(viewport);
        const QPointer<QQuickWindow> safeWindow(window);
        auto updateMask=[safeViewport,safeWindow]() {
            if(!safeViewport || !safeWindow)return;
            bool bounded=safeWindow->windowState()==Qt::WindowMaximized || safeWindow->windowState()==Qt::WindowFullScreen;
            int margin=bounded?0:32;
            safeViewport->setProperty("edgeMargin",margin);
            QPointF offset=safeViewport->mapToScene(QPointF());
            QRect inside(qRound(offset.x())+margin,qRound(offset.y())+margin,
                         qMax(1,int(safeViewport->width())-2*margin),qMax(1,int(safeViewport->height())-2*margin));
            QPainterPath hitRegion;hitRegion.addRoundedRect(QRectF(inside),bounded?0:14,bounded?0:14);
            safeWindow->setMask(QRegion(hitRegion.toFillPolygon().toPolygon()));
        };
        connect(viewport,&QQuickItem::widthChanged,viewport,updateMask);
        connect(viewport,&QQuickItem::heightChanged,viewport,updateMask);
        connect(window,&QWindow::windowStateChanged,viewport,[updateMask](Qt::WindowState){updateMask();});
        connect(viewport,&QObject::destroyed,window,[safeWindow](){if(safeWindow){safeWindow->setMask(QRegion());safeWindow->setProperty("vibeenergyTurboPrepared",false);}});
        window->setProperty("vibeenergyTurboPrepared",true);updateMask();recordDebug();
        if(qEnvironmentVariableIsSet("VIBEENERGY_TURBO_DEBUG"))qInfo()<<"Turbo transparent margin"<<viewport->property("edgeMargin")<<"alpha"<<window->format().alphaBufferSize()<<QGuiApplication::platformName();
        return true;
    }
    Q_INVOKABLE QString today() const { return QDate::currentDate().toString(Qt::ISODate); }
    Q_INVOKABLE QString daysAgo(int days) const { return QDate::currentDate().addDays(-days).toString(Qt::ISODate); }
    Q_INVOKABLE QString monthStart() const { const auto d=QDate::currentDate(); return QDate(d.year(), d.month(), 1).toString(Qt::ISODate); }
    Q_INVOKABLE QVariantMap powerstatSetup() const {
        const QString logPath=QDir::homePath()+"/.vibeenergy/logs/powerstat.log";
        auto quote=[](QString value) { value.replace("'", "'\"'\"'"); return "'"+value+"'"; };
        const QString dataPath=QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)+"/energytlk";
        const QString appPath=dataPath+"/app";
        const QString foreground="sudo sh -c 'while stdbuf -oL powerstat -R -D -d 0 1 43200; do sleep 1; done' |\n  tee -a \"$HOME/.vibeenergy/logs/powerstat.log\"";
        QString cronEntry="@reboot /bin/sh -c 'while /usr/bin/stdbuf -oL /usr/bin/powerstat -R -D -d 0 1 43200; do sleep 1; done' >> "+quote(logPath)+" 2>/dev/null";
        cronEntry.replace("%", "\\%");
        const QString cronCommand="sudo /bin/sh <<'VIBEENERGY_CRON'\n"
            "entry="+quote(cronEntry)+"\n"
            "existing=$(LC_ALL=C crontab -l 2>&1) || {\n"
            "  case \"$existing\" in\n"
            "    \"no crontab for \"*) existing= ;;\n"
            "    *) printf '%s\\n' \"$existing\" >&2; exit 1 ;;\n"
            "  esac\n"
            "}\n"
            "if ! printf '%s\\n' \"$existing\" | grep -Fqx -- \"$entry\"; then\n"
            "  printf '%s\\n' \"$existing\" \"$entry\" | crontab -\n"
            "fi\n"
            "VIBEENERGY_CRON";
        bool running=false;
        const auto entries=QDir("/proc").entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        for(const auto &pid:entries) {
            bool numeric=false; pid.toLongLong(&numeric);
            if(!numeric) continue;
            QFile comm("/proc/"+pid+"/comm");
            if(comm.open(QIODevice::ReadOnly) && comm.readAll().trimmed()=="powerstat") { running=true; break; }
        }
        QFileInfo log(logPath);
        const auto logs=QDir(QDir::homePath()+"/.vibeenergy/logs").entryInfoList({"*.log"}, QDir::Files | QDir::NoSymLinks, QDir::Time);
        if(!log.isFile() || log.size()==0) {
            for(const auto &candidate:logs) { if(candidate.size()>0) { log=candidate; break; } }
        }
        const auto age=log.lastModified().secsTo(QDateTime::currentDateTime());
        QFile serviceFile("/etc/systemd/system/vibeenergy-powerstat.service");
        QByteArray existingUnit;
        if(serviceFile.open(QIODevice::ReadOnly)) existingUnit=serviceFile.readAll();
        const bool serviceInstalled=existingUnit.contains("ExecStart=/usr/bin/stdbuf -oL /usr/bin/powerstat") && existingUnit.contains("SystemCallErrorNumber=EPROTONOSUPPORT") && existingUnit.contains(logPath.toUtf8());
        const QString serviceRunner="sudo install -m 644 "+quote(appPath+"/vibeenergy-powerstat.service")+
            " /etc/systemd/system/vibeenergy-powerstat.service &&\n"
            "sudo systemctl daemon-reload &&\n"
            "sudo systemctl enable vibeenergy-powerstat.service && sudo systemctl restart vibeenergy-powerstat.service";
        return {{"serviceRunnerCommand", serviceRunner},
                {"cronCommand", cronCommand},
                {"cronEntry", cronEntry},
                {"pkexecAvailable", !QStandardPaths::findExecutable("pkexec").isEmpty()},
                {"installed", !QStandardPaths::findExecutable("powerstat").isEmpty()},
                {"running", running}, {"logReady", log.isFile() && log.size()>0 && log.isReadable() && age>=0 && age<=30},
                {"serviceInstalled", serviceInstalled},
                {"logPath", logPath}, {"foregroundCommand", foreground}};
    }
    bool cpuAutostartBusy() const { return m_cpuAutostartBusy; }
    Q_INVOKABLE void enableCpuAutostart() {
        if(m_cpuAutostartBusy)return;
        const QString pkexec=QStandardPaths::findExecutable("pkexec");
        const QString logPath=QDir::homePath()+"/.vibeenergy/logs/powerstat.log";
        if(pkexec.isEmpty() || !QFileInfo("/usr/bin/powerstat").isExecutable() || !QFileInfo(logPath).isFile()) {
            emit cpuAutostartFinished(false,tr("Install Powerstat and prepare the app logs first. If system authentication is unavailable, use the copy command."));return;
        }
        QString outputPath=logPath;
        outputPath.replace("\\","\\x5c").replace("\"","\\x22").replace("\n","\\x0a").replace("\r","\\x0d").replace(" ","\\x20").replace("%","%%");
        const QByteArray unit=(QStringLiteral(
            "[Unit]\nDescription=Powerstat CPU measurements for VibeEnergy\nAfter=local-fs.target\n"
            "[Service]\nType=simple\nExecStart=/usr/bin/stdbuf -oL /usr/bin/powerstat -R -D -d 0 1 43200\n"
            "StandardOutput=append:")+outputPath+QStringLiteral(
            "\nStandardError=journal\nRestart=always\nRestartSec=1\nUMask=0077\n"
            "NoNewPrivileges=yes\nCapabilityBoundingSet=\nPrivateTmp=yes\nPrivateDevices=yes\n"
            "ProtectSystem=strict\nProtectHome=read-only\nSystemCallArchitectures=native\n"
            "SystemCallFilter=~socket\nSystemCallErrorNumber=EPROTONOSUPPORT\n"
            "[Install]\nWantedBy=multi-user.target\n")).toUtf8();
        // The privileged process receives only a fixed Powerstat unit, never application code.
        const QString command=QStringLiteral(
            "set -eu; temp=$(/usr/bin/mktemp /etc/systemd/system/.vibeenergy-powerstat.XXXXXX); "
            "trap '/usr/bin/rm -f \"$temp\"' EXIT; /usr/bin/cat > \"$temp\"; /usr/bin/chmod 644 \"$temp\"; "
            "/usr/bin/mv -f \"$temp\" /etc/systemd/system/vibeenergy-powerstat.service; "
            "/usr/bin/systemctl daemon-reload; /usr/bin/systemctl enable vibeenergy-powerstat.service; "
            "/usr/bin/systemctl restart vibeenergy-powerstat.service");
        auto *process=new QProcess(this);
        auto environment=QProcessEnvironment::systemEnvironment();
        for(const auto &key:{"LD_LIBRARY_PATH","LD_PRELOAD","PYTHONHOME","PYTHONPATH","QT_PLUGIN_PATH","QML_IMPORT_PATH","QML2_IMPORT_PATH","FONTCONFIG_FILE","FONTCONFIG_PATH"})environment.remove(key);
        if(environment.contains("VIBEENERGY_HOST_PATH"))environment.insert("PATH",environment.value("VIBEENERGY_HOST_PATH"));
        process->setProcessEnvironment(environment);
        m_cpuAutostartBusy=true;emit cpuAutostartBusyChanged();
        connect(process,&QProcess::started,process,[process,unit]{process->write(unit);process->closeWriteChannel();});
        connect(process,&QProcess::errorOccurred,this,[this,process](QProcess::ProcessError error){
            if(error!=QProcess::FailedToStart)return;
            m_cpuAutostartBusy=false;emit cpuAutostartBusyChanged();emit cpuAutostartFinished(false,process->errorString());process->deleteLater();
        });
        connect(process,&QProcess::finished,this,[this,process](int code,QProcess::ExitStatus status){
            m_cpuAutostartBusy=false;emit cpuAutostartBusyChanged();
            const bool success=code==0 && status==QProcess::NormalExit;
            const QString message=success ? tr("CPU recording enabled now and at boot. Waiting for fresh readings.") : code==126 ? tr("Authorization cancelled. CPU autostart was not enabled.") : tr("Could not enable CPU autostart. ")+QString::fromUtf8(process->readAllStandardError());
            emit cpuAutostartFinished(success,message);process->deleteLater();
        });
        process->start(pkexec,{"/bin/sh","-c",command});
    }
    Q_INVOKABLE void copyText(const QString &text) { QGuiApplication::clipboard()->setText(text); }
    Q_INVOKABLE void refresh() {
        QFile file(statePath());
        if (!file.open(QIODevice::ReadOnly)) { m_state.clear(); emit changed(); return; }
        const auto document = QJsonDocument::fromJson(file.readAll());
        if (document.isObject()) m_state = document.object().toVariantMap();
        emit changed();
    }
    bool serviceBusy() const { return m_serviceBusy; }
    Q_INVOKABLE QString autostartState() const {
        const QString path=QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)+"/autostart/vibeenergy.desktop";
        if(!QFileInfo::exists(path))return QStringLiteral("disabled");
        QFile file(path);
        if(!file.open(QIODevice::ReadOnly))return QStringLiteral("unknown");
        QSettings entry(path,QSettings::IniFormat);
        entry.beginGroup("Desktop Entry");
        if(entry.value("Type").toString()!="Application" || entry.value("Exec").toString().isEmpty())return QStringLiteral("unknown");
        return entry.value("Hidden",false).toBool() || !entry.value("X-GNOME-Autostart-enabled",true).toBool() ? QStringLiteral("disabled") : QStringLiteral("enabled");
    }
    Q_INVOKABLE void service(const QString &action) {
        const QStringList allowed={"start", "stop", "restart", "enable", "disable"};
        if (!allowed.contains(action) || m_serviceBusy) return;
        const auto finish=[this,action](bool success) {
            m_serviceBusy=false;emit changed();emit serviceFinished(action,success,m_message);
        };
        if(action=="enable" || action=="disable") {
            const QString directory=QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)+"/autostart";
            const QString target=directory+"/vibeenergy.desktop";
            if(action=="enable") {
                QFile desktop(QStandardPaths::locate(QStandardPaths::ApplicationsLocation,QStringLiteral("vibeenergy.desktop")));
                if(!desktop.open(QIODevice::ReadOnly)) {
                    m_message=tr("Cannot find VibeEnergy's installed application entry. Open the installed app before enabling autostart.");finish(false);return;
                }
                const QByteArray contents=desktop.readAll();
                if(!QDir().mkpath(directory)) {m_message=tr("Cannot create the Startup Apps directory.");finish(false);return;}
                QSaveFile file(target);
                if(!file.open(QIODevice::WriteOnly) || file.write(contents)!=contents.size() || !file.commit()) {
                    m_message=tr("Could not save the Startup Apps entry: ")+file.errorString();finish(false);return;
                }
            } else if(QFile::exists(target) && !QFile::remove(target)) {
                m_message=tr("Could not remove VibeEnergy from Startup Apps.");finish(false);return;
            }
        }
        auto *process=new QProcess(this);
        m_serviceBusy=true;emit changed();
        QStringList args={"--user", action};
        if (action=="enable") args << "--now";
        args << "energytlk.service";
        connect(process, &QProcess::errorOccurred, this, [this,process,finish](QProcess::ProcessError error){
            if(error!=QProcess::FailedToStart)return;
            m_message=process->errorString(); finish(false); process->deleteLater();
        });
        connect(process, &QProcess::finished, this, [this,process,action,finish](int code, QProcess::ExitStatus status){
            const bool success=code==0 && status==QProcess::NormalExit;
            if(action=="enable" || action=="disable") {
                m_message=action=="enable" ? tr("VibeEnergy added to Startup Apps.") : tr("VibeEnergy removed from Startup Apps. Current recording continues.");
                if(!success)m_message+=tr(" Collector service update failed: ")+QString::fromUtf8(process->readAllStandardError());
            } else m_message=success ? tr("Collector setting updated") : QString::fromUtf8(process->readAllStandardError());
            finish(success); process->deleteLater();
        });
        QTimer::singleShot(10000, process, [process]{ if(process->state()!=QProcess::NotRunning) process->kill(); });
        process->start("systemctl", args);
    }
    bool clearingHistory() const {return m_clearingHistory;}
    Q_INVOKABLE void clearLogs() {
        if(m_clearingHistory)return;
        if(m_serviceBusy || m_cpuAutostartBusy){emit clearLogsFinished(false,tr("Wait for the current background operation to finish, then try again."));return;}
        m_clearingHistory=true;emit clearingHistoryChanged();
        StandaloneWindow::instance().setHistoryClearing(true);
        auto *process=new QProcess(this);
        auto env=QProcessEnvironment::systemEnvironment();
        const QString image=qEnvironmentVariable("APPIMAGE");
        QString program;
        QStringList args;
        if(!image.isEmpty() && QFileInfo(image).isExecutable()) {
            program=image;args={"--appimage-extract-and-run","--clear-history"};
            for(const auto *key:{"APPDIR","APPIMAGE","LD_LIBRARY_PATH","LD_PRELOAD","PYTHONHOME","PYTHONPATH","QT_PLUGIN_PATH","QML_IMPORT_PATH","QML2_IMPORT_PATH"})env.remove(QString::fromLatin1(key));
            if(env.contains("VIBEENERGY_HOST_PATH"))env.insert("PATH",env.value("VIBEENERGY_HOST_PATH"));
        } else {
            program=QStandardPaths::findExecutable("python3");args={"-m","energytlk.clear_history"};
            env.insert("PYTHONPATH",QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)+"/energytlk/app");
        }
        process->setProcessEnvironment(env);
        auto finish=[this](bool success,const QString &message){
            m_clearingHistory=false;StandaloneWindow::instance().setHistoryClearing(false);
            m_message=message;emit clearingHistoryChanged();refresh();emit clearLogsFinished(success,message);
        };
        connect(process,&QProcess::errorOccurred,this,[process,finish](QProcess::ProcessError error){
            if(error==QProcess::FailedToStart){finish(false,process->errorString());process->deleteLater();}
        });
        connect(process,&QProcess::finished,this,[process,finish](int code,QProcess::ExitStatus status){
            const bool success=code==0 && status==QProcess::NormalExit;
            QString message=QString::fromUtf8(process->readAllStandardError()).trimmed();
            if(message.isEmpty())message=tr("History clearing failed. Reopen VibeEnergy if recording did not restart.");
            finish(success,success ? tr("All recorded history and logs cleared. Settings preserved.") : message);
            process->deleteLater();
        });
        QTimer::singleShot(60000,process,[process]{if(process->state()!=QProcess::NotRunning)process->kill();});
        process->start(program,args);
    }
    Q_INVOKABLE void uninstallApp() {
        if(m_serviceBusy || m_cpuAutostartBusy){m_message=tr("A collector operation is still running. Try again in a moment.");emit changed();emit uninstallFinished(false);return;}
        m_serviceBusy=true;
        StandaloneWindow::instance().setUninstalling(true);
        auto *process=new QProcess(this);
        auto environment=QProcessEnvironment::systemEnvironment();
        const QString appdir=qEnvironmentVariable("APPDIR");
        QString python;
        if(!appdir.isEmpty()) {
            python=appdir+"/usr/bin/python3";
            environment.insert("PYTHONPATH",appdir+"/app");
        } else {
            python=QStandardPaths::findExecutable("python3");
            environment.insert("PYTHONPATH",QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)+"/energytlk/app");
        }
        process->setProcessEnvironment(environment);
        connect(process,&QProcess::errorOccurred,this,[this,process](QProcess::ProcessError error){
            if(error!=QProcess::FailedToStart)return;
            StandaloneWindow::instance().setUninstalling(false);
            m_message=process->errorString();m_serviceBusy=false;emit changed();emit uninstallFinished(false);process->deleteLater();
        });
        connect(process,&QProcess::finished,this,[this,process](int code,QProcess::ExitStatus status){
            const bool success=code==0 && status==QProcess::NormalExit;
            m_message=success ? tr("VibeEnergy removed. History and settings kept. Close the app and delete the AppImage file; opening it again prepares the app again.") : QString::fromUtf8(process->readAllStandardError());
            if(!success) {
                StandaloneWindow::instance().setUninstalling(false);
                if(process->property("uninstallTimedOut").toBool())m_message=tr("Uninstall timed out. Close and reopen VibeEnergy, then try again.");
                else if(m_message.trimmed().isEmpty())m_message=tr("Uninstall did not finish. Close and reopen VibeEnergy, then try again.");
            }
            m_serviceBusy=false;emit changed();emit uninstallFinished(success);process->deleteLater();
        });
        QTimer::singleShot(45000,process,[process]{if(process->state()!=QProcess::NotRunning){process->setProperty("uninstallTimedOut",true);process->kill();}});
        process->start(python,{"-m","energytlk.uninstall"});
    }
    Q_INVOKABLE QVariantMap savedSettings() const {
        QVariantMap settings{{"price",.177},{"currency",QStringLiteral("EUR")},{"interval",1},{"powerstat_log",QString()}};
        const auto snapshot=m_state.value("config").toMap();
        for(auto it=snapshot.cbegin();it!=snapshot.cend();++it) settings.insert(it.key(),it.value());
        QFile file(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)+"/energytlk/config.json");
        if(file.open(QIODevice::ReadOnly)) {
            const auto saved=QJsonDocument::fromJson(file.readAll()).object().toVariantMap();
            for(auto it=saved.cbegin();it!=saved.cend();++it) settings.insert(it.key(),it.value());
        }
        settings.insert("interval",qBound(1,settings.value("interval").toInt(),5));
        return settings;
    }
    Q_INVOKABLE bool saveSettings(QString priceText, QString currency, int interval, int retention, QString log) {
        const auto finish=[this](bool success) {
            emit changed();emit settingsSaveFinished(success,m_message);return success;
        };
        bool ok=false;
        double price=priceText.replace(',', '.').toDouble(&ok);
        currency=currency.trimmed().toUpper();
        bool currencyValid=currency.size()==3;
        for(const auto c:currency) currencyValid=currencyValid && c>='A' && c<='Z';
        if(!ok || !std::isfinite(price) || price<0 || price>10000 || interval<1 || interval>5 || retention<1 || retention>36500 || !currencyValid || (!log.isEmpty() && !QDir::isAbsolutePath(log))) {
            m_message=tr("Check price, currency, interval, retention, and absolute log path."); return finish(false);
        }
        const QString dir=QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)+"/energytlk";
        if(!QDir().mkpath(dir)) { m_message=tr("Cannot create settings directory"); return finish(false); }
        // Remember the original unit even if settings change while collection is stopped.
        QFile previousFile(dir+"/config.json");
        QJsonObject previous;
        if(previousFile.open(QIODevice::ReadOnly)) previous=QJsonDocument::fromJson(previousFile.readAll()).object();
        const QString oldCurrency=previous.value("currency").toString(m_state.value("config").toMap().value("currency",QStringLiteral("EUR")).toString());
        QJsonArray histories=previous.value("history_currencies").toArray();
        for(const QString &code:{oldCurrency,currency}) if(!histories.contains(code)) histories.append(code);
        QSaveFile file(dir+"/config.json");
        if(!file.open(QIODevice::WriteOnly)) { m_message=file.errorString(); return finish(false); }
        file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
        QJsonObject settings{{"price",price},{"currency",currency},{"interval",interval},{"retention_days",retention},{"powerstat_log",log}};
        settings.insert("history_currency",previous.value("history_currency").toString(oldCurrency));
        settings.insert("history_price",previous.value("history_price").toDouble(previous.value("price").toDouble(.177)));
        settings.insert("history_currencies",histories);
        const auto payload=QJsonDocument(settings).toJson();
        if(file.write(payload)!=payload.size() || !file.commit()) { m_message=file.errorString(); return finish(false); }
        m_message=tr("Saved; collector applies changes at its next sample."); return finish(true);
    }
signals:
    void settingsSaveFinished(bool success,QString message);
    void serviceFinished(QString action,bool success,QString message);
    void clearLogsFinished(bool success,QString message);
    void clearingHistoryChanged();
    void startupCompleteChanged();
    void cpuAutostartBusyChanged();
    void cpuAutostartFinished(bool success,QString message);
    void uninstallFinished(bool success);
    void splashEnabledChanged();
    void splashSoundEnabledChanged();
    void splashSoundPromptDismissedChanged();
    void turboSoundEnabledChanged();
    void turboSoundVolumeChanged();
    void turboAlwaysOnChanged();
    void changed();
};

class EnergyPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override {
        qmlRegisterType<EnergyBridge>(uri, 1, 0, "EnergyBridge"); qmlRegisterType<PlasmaField>(uri, 1, 0, "PlasmaField"); qmlRegisterType<TurboAudioMixer>(uri, 1, 0, "TurboAudioMixer"); }
};
#include "plugin.moc"
