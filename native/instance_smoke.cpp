#include "instanceipc.h"
#include <QCoreApplication>
#include <QProcess>
#include <QTimer>
#include <QFile>
#include <QTemporaryDir>
#include <QDBusConnectionInterface>
#include <iostream>
class MockWindow : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface","com.techtoapes.VibeEnergy.Window")
    QString m_log;
public:
    explicit MockWindow(QString log):m_log(log) {
        append("spawn");
        QTimer::singleShot(600,this,[this]{
            auto bus=QDBusConnection::sessionBus();
            bus.registerObject(QString::fromLatin1(VibeInstance::ObjectPath),this,QDBusConnection::ExportAllSlots);
            if(!bus.registerService(QString::fromLatin1(VibeInstance::WindowService)))QCoreApplication::exit(1);
            append("ready");
        });
    }
    void append(const QByteArray &line){QFile f(m_log);if(f.open(QIODevice::Append))f.write(line+'\n');}
public slots:
    bool Activate(const QString &){append("activate");return true;}
    void Quit(){QTimer::singleShot(20,qApp,&QCoreApplication::quit);}
};
int main(int argc,char **argv) {
    QCoreApplication app(argc,argv);
    if(argc==3 && QString::fromLocal8Bit(argv[1])=="--mock") {MockWindow window(QString::fromLocal8Bit(argv[2]));return app.exec();}
    if(argc!=2)return 2;
    const QString launcher=QString::fromLocal8Bit(argv[1]);
    QTemporaryDir temp;
    const QString log=temp.path()+"/window log";
    const QStringList command{app.applicationFilePath(),"--mock",log};
    QProcess primary;primary.setProcessChannelMode(QProcess::ForwardedChannels);primary.start(launcher,command);
    int result=0;
    auto lines=[&]{QFile f(log);return f.open(QIODevice::ReadOnly)?f.readAll().split('\n'):QList<QByteArray>();};
    auto repeat=[&](int count){for(int i=0;i<count;++i)if(QProcess::execute(launcher,command)!=0)result=1;};
    auto quit=[&]{auto msg=QDBusMessage::createMethodCall(QString::fromLatin1(VibeInstance::WindowService),QString::fromLatin1(VibeInstance::ObjectPath),QString::fromLatin1(VibeInstance::WindowService),"Quit");QDBusConnection::sessionBus().call(msg);};
    QTimer::singleShot(200,&app,[&]{repeat(5);});
    QTimer::singleShot(1500,&app,[&]{
        auto before=lines();
        if(before.count("spawn")!=1 || before.count("ready")!=1 || before.count("activate")<1)result=1;
        const int activations=before.count("activate");repeat(8);
        auto after=lines();
        if(after.count("spawn")!=1 || after.count("activate")!=activations+8)result=1;
        if(!result)std::cout<<"Rapid and repeated launches activated one existing window\n";
        quit();
        if(!primary.waitForFinished(3000) || primary.exitCode()!=0)result=1;
        primary.start(launcher,command);
        QTimer::singleShot(1200,&app,[&]{
            if(lines().count("spawn")!=2 || lines().count("ready")!=2)result=1;
            quit();if(!primary.waitForFinished(3000) || primary.exitCode()!=0)result=1;
            if(!result)std::cout<<"Window can relaunch after exit; instance service cleaned up\n";
            primary.start(launcher,command);
            QTimer::singleShot(1000,&app,[&]{
                primary.terminate();
                if(!primary.waitForFinished(5000) || QDBusConnection::sessionBus().interface()->isServiceRegistered(QString::fromLatin1(VibeInstance::WindowService)).value())result=1;
                primary.start(launcher,command);
                QTimer::singleShot(1000,&app,[&]{
                    if(lines().count("spawn")!=4 || lines().count("ready")!=4)result=1;
                    quit();if(!primary.waitForFinished(3000) || primary.exitCode()!=0)result=1;
                    if(!result)std::cout<<"Terminating launcher also stopped its child; relaunch succeeded\n";
                    app.exit(result);
                });
            });
        });
    });
    QTimer::singleShot(12000,&app,[&]{primary.kill();app.exit(1);});
    return app.exec();
}
#include "instance_smoke.moc"
