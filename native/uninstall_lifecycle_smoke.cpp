#include <QApplication>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QProcess>
#include <QTimer>
#include <QFile>
#include <QDir>
#include <QDBusConnection>
#include <KLocalizedContext>
#include <iostream>
#include <memory>

class PlasmaWindowedView : public QQuickWindow { Q_OBJECT };
class Watcher : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface","org.kde.StatusNotifierWatcher")
    Q_PROPERTY(bool IsStatusNotifierHostRegistered READ host)
    Q_PROPERTY(int ProtocolVersion READ version)
    Q_PROPERTY(QStringList RegisteredStatusNotifierItems READ items)
public:
    bool host() const{return true;}
    int version() const{return 0;}
    QStringList items() const{return {};}
public slots:
    void RegisterStatusNotifierItem(const QString &){}
    void RegisterStatusNotifierHost(const QString &){}
};

int main(int argc,char **argv) {
    QApplication app(argc,argv);
    if(argc!=3)return 2;
    const bool success=QByteArray(argv[2])=="success";
    QTemporaryDir temp;
    qputenv("XDG_STATE_HOME",(temp.path()+"/state").toUtf8());
    qputenv("XDG_CONFIG_HOME",(temp.path()+"/config").toUtf8());
    qputenv("XDG_DATA_HOME",(temp.path()+"/data").toUtf8());
    qputenv("APPDIR",temp.path().toUtf8());
    qunsetenv("APPIMAGE");
    QDir().mkpath(temp.path()+"/usr/bin");
    QFile python(temp.path()+"/usr/bin/python3");if(!python.open(QIODevice::WriteOnly))return 1;
    python.write(success ? "#!/bin/sh\nsleep .2\necho 'Uninstalled.'\nexit 0\n" : "#!/bin/sh\nsleep .2\necho 'Uninstall cancelled. No files removed.' >&2\nexit 1\n");python.close();
    python.setPermissions(QFile::ReadOwner|QFile::WriteOwner|QFile::ExeOwner);
    auto bus=QDBusConnection::sessionBus();Watcher watcher;
    if(!bus.registerObject("/StatusNotifierWatcher",&watcher,QDBusConnection::ExportAllSlots|QDBusConnection::ExportAllProperties) || !bus.registerService("org.kde.StatusNotifierWatcher"))return 1;
    QQmlEngine engine;engine.rootContext()->setContextObject(new KLocalizedContext(&engine));
    QQmlComponent component(&engine,QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    std::unique_ptr<QObject> root(component.create());
    if(!root){std::cerr<<component.errorString().toStdString();return 1;}
    auto *full=qvariant_cast<QQmlComponent *>(root->property("fullRepresentation"));
    std::unique_ptr<QObject> view(full?full->create(qmlContext(root.get())):nullptr);
    if(!view)return 1;
    PlasmaWindowedView window;window.resize(1200,900);
    auto *item=qobject_cast<QQuickItem *>(view.get());item->setParentItem(window.contentItem());item->setWidth(1200);item->setHeight(900);window.show();
    QObject *backend=nullptr;
    for(auto *child:root->findChildren<QObject *>())if(child->metaObject()->indexOfProperty("turboAlwaysOn")>=0){backend=child;break;}
    if(!backend)return 1;
    auto *popup=view->findChild<QObject *>("uninstallPopup");
    if(!popup){std::cerr<<"Uninstall popup not found\n";return 1;}
    // Simulate a recorder whose delayed stop completes after the worker reports.
    QDir().mkpath(temp.path()+"/state/energytlk");
    QProcess recorder;
    recorder.start("python3",{"-c","import fcntl,sys,time; f=open(sys.argv[1],'w'); fcntl.flock(f,fcntl.LOCK_EX); print('ready',flush=True); time.sleep(30)",temp.path()+"/state/energytlk/collector.lock"});
    if(!recorder.waitForStarted(3000) || !recorder.waitForReadyRead(3000))return 1;
    bool verified=false;int result=0;
    QTimer::singleShot(1400,&app,[&]{
        QMetaObject::invokeMethod(popup,"open");
        auto *button=popup->findChild<QObject *>("uninstallConfirm");
        if(button)QMetaObject::invokeMethod(button,"clicked");else {result=1;app.quit();}
    });
    QTimer::singleShot(2300,&app,[&]{recorder.terminate();recorder.waitForFinished(3000);});
    QTimer::singleShot(4500,&app,[&]{
        verified=true;
        const bool busy=popup->property("busy").toBool();
        const bool removed=popup->property("removed").toBool();
        if(busy || removed!=success || !window.isVisible())result=1;
        if(!success && popup->property("errorMessage").toString().isEmpty())result=1;
        if(!result)std::cout<<(success ? "Successful uninstall stays open until user closes the app\n" : "Failed uninstall clears busy state and stays open after delayed recorder stop\n");
        if(success && !result) {
            auto *close=popup->findChild<QObject *>("uninstallCancel");
            if(!close || !QMetaObject::invokeMethod(close,"clicked")){result=1;app.quit();}
        } else app.quit();
    });
    QTimer::singleShot(5500,&app,[&]{std::cerr<<"Close app did not exit the UI\n";result=1;app.quit();});
    app.exec();
    if(recorder.state()!=QProcess::NotRunning){recorder.kill();recorder.waitForFinished();}
    if(!verified){std::cerr<<"App exited before user chose Close app\n";return 1;}
    return result;
}
#include "uninstall_lifecycle_smoke.moc"
