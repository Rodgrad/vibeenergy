#pragma once
#include <QByteArray>
#include <QDir>
#include <QFile>
#include <QElapsedTimer>
#include <QThread>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QList>
#include <QString>
#include <cerrno>
#include <csignal>
#include <cstring>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

struct CollectorStopResult {
    bool success;
    QString message;
};

// Shutdown must not exec files or read resources from an AppImage mount: its
// runtime may already have been ended through the desktop process manager.
inline CollectorStopResult stopCollectorBlocking()
{
    auto request=QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.systemd1"),
        QStringLiteral("/org/freedesktop/systemd1"),QStringLiteral("org.freedesktop.systemd1.Manager"),QStringLiteral("StopUnit"));
    request<<QStringLiteral("energytlk.service")<<QStringLiteral("replace");
    QDBusConnection::sessionBus().call(request,QDBus::Block,500);

    QString state=qEnvironmentVariable("XDG_STATE_HOME");
    if(state.isEmpty())state=QDir::homePath()+QStringLiteral("/.local/state");
    const QByteArray path=QFile::encodeName(state+QStringLiteral("/energytlk/collector.lock"));
    const int fd=::open(path.constData(),O_RDWR|O_CLOEXEC);
    if(fd<0) {
        if(errno==ENOENT)return {true,{}};
        return {false,QStringLiteral("Cannot open the collector lock: ")+QString::fromLocal8Bit(::strerror(errno))};
    }
    auto unlocked=[fd]{
        if(::flock(fd,LOCK_EX|LOCK_NB)!=0)return false;
        ::flock(fd,LOCK_UN);return true;
    };
    if(unlocked()){::close(fd);return {true,{}};}
    struct stat lock{};
    if(::fstat(fd,&lock)!=0){::close(fd);return {false,QStringLiteral("Cannot identify the collector lock.")};}
    QList<pid_t> owners;
    for(const QString &name:QDir(QStringLiteral("/proc")).entryList(QDir::Dirs|QDir::NoDotAndDotDot)) {
        bool numeric=false;const qlonglong number=name.toLongLong(&numeric);
        if(!numeric || number<=0)continue;
        const QString process=QStringLiteral("/proc/")+name;
        struct stat info{};
        if(::stat(QFile::encodeName(process).constData(),&info)!=0 || info.st_uid!=::getuid())continue;
        QFile command(process+QStringLiteral("/cmdline"));
        if(!command.open(QIODevice::ReadOnly))continue;
        const auto args=command.readAll().split('\0');
        bool collector=false;
        for(qsizetype i=0;i+1<args.size();++i)
            if(args[i]=="-m" && (args[i+1]=="energytlk" || args[i+1]=="energytlk.collector"))collector=true;
        if(!collector)continue;
        for(const QString &file:QDir(process+QStringLiteral("/fd")).entryList(QDir::Files|QDir::System|QDir::NoDotAndDotDot)) {
            const QByteArray opened=QFile::encodeName(process+QStringLiteral("/fd/")+file);
            if(::stat(opened.constData(),&info)==0 && info.st_dev==lock.st_dev && info.st_ino==lock.st_ino) {
                owners.append(pid_t(number));break;
            }
        }
    }
    if(owners.isEmpty()) {
        const bool stopped=unlocked();::close(fd);
        return {stopped,stopped ? QString() : QStringLiteral("Collector lock owner could not be identified safely.")};
    }
    for(pid_t pid:owners)::kill(pid,SIGTERM);
    QElapsedTimer deadline;deadline.start();
    while(deadline.elapsed()<5000) {
        if(unlocked()){::close(fd);return {true,{}};}
        QThread::msleep(50);
    }
    ::close(fd);
    return {false,QStringLiteral("Collector did not stop within five seconds.")};
}
