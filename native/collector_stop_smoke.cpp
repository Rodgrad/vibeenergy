#include "collectorstop.h"
#include <QCoreApplication>
#include <QProcess>
#include <QProcessEnvironment>
#include <QTemporaryDir>
#include <QStandardPaths>
#include <QJsonDocument>
#include <QJsonObject>
#include <iostream>

int main(int argc,char **argv) {
    QCoreApplication app(argc,argv);
    if(argc==3 && QByteArray(argv[1])=="--lock") {
        const int fd=::open(argv[2],O_CREAT|O_RDWR,0600);
        if(fd<0 || ::flock(fd,LOCK_EX)!=0)return 2;
        std::cout<<"locked"<<std::endl;
        QThread::sleep(10);::close(fd);return 0;
    }
    if(argc!=2)return 2;
    QTemporaryDir temp;
    const QString state=temp.path()+"/state";
    QDir().mkpath(state+"/energytlk/demo");
    qputenv("XDG_STATE_HOME",state.toUtf8());
    auto env=QProcessEnvironment::systemEnvironment();
    env.insert("XDG_CONFIG_HOME",temp.path()+"/config");env.insert("XDG_DATA_HOME",temp.path()+"/data");
    env.remove("PYTHONHOME");env.remove("PYTHONPATH");env.remove("APPIMAGE");env.remove("APPDIR");env.remove("LD_PRELOAD");env.remove("LD_LIBRARY_PATH");
    QProcess collector;collector.setWorkingDirectory(QString::fromLocal8Bit(argv[1]));collector.setProcessEnvironment(env);
    collector.start(QStandardPaths::findExecutable("python3"),{"-m","energytlk","--simulate","--interval","1"});
    if(!collector.waitForStarted(3000))return 1;
    QElapsedTimer wait;wait.start();
    const QString snapshot=state+"/energytlk/demo/state.json";
    while(!QFile::exists(snapshot) && wait.elapsed()<5000)QThread::msleep(25);
    if(!QFile::exists(snapshot)){collector.kill();collector.waitForFinished();return 1;}
    if(!QFile::link(state+"/energytlk/demo/collector.lock",state+"/energytlk/collector.lock"))return 1;
    // No Python executable, mounted helper, or resource is needed by this call.
    qputenv("APPDIR","/tmp/vibeenergy-missing-mount");qputenv("PYTHONHOME","/tmp/vibeenergy-missing-python");qputenv("PATH","/tmp/vibeenergy-no-executables");
    const auto result=stopCollectorBlocking();
    if(!result.success || !collector.waitForFinished(5000) || collector.exitCode()!=0){std::cerr<<result.message.toStdString();collector.kill();collector.waitForFinished();return 1;}
    QFile file(snapshot);file.open(QIODevice::ReadOnly);
    if(QJsonDocument::fromJson(file.readAll()).object().value("running").toBool())return 1;
    if(!stopCollectorBlocking().success)return 1;
    const QString unknown=temp.path()+"/unknown";QDir().mkpath(unknown+"/energytlk");
    qputenv("XDG_STATE_HOME",unknown.toUtf8());
    QProcess owner;owner.start(app.applicationFilePath(),{"--lock",unknown+"/energytlk/collector.lock"});
    if(!owner.waitForStarted(3000) || !owner.waitForReadyRead(3000))return 1;
    const auto rejected=stopCollectorBlocking();
    if(rejected.success || owner.state()!=QProcess::Running)return 1;
    owner.terminate();owner.waitForFinished(3000);
    std::cout<<"Native collector shutdown passed with missing mount/Python/PATH; unrelated lock owner preserved\n";
    return 0;
}
