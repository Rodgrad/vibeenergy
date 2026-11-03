#include "instanceipc.h"
#include "collectorstop.h"
#include <QCoreApplication>
#include <QProcess>
#include <QProcessEnvironment>
#include <QTimer>
#include <QThread>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QSocketNotifier>
#include <csignal>
#include <cerrno>
#include <unistd.h>
#include <fcntl.h>
#include <sys/prctl.h>
#include <iostream>

static int terminationPipe=-1;
static void requestTermination(int signal) {
    const int saved=errno;
    const char value=char(signal);
    if(terminationPipe>=0)::write(terminationPipe,&value,1);
    errno=saved;
}

class Launcher : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface","com.techtoapes.VibeEnergy.Launcher")
    QProcess m_process;
    QTimer m_retry;
    QString m_token;
    QStringList m_command;
    bool m_pendingActivation=false;
    bool m_terminating=false;
    bool m_cleaningCollector=false;
    int m_attempts=0;
    bool m_ownsCollector=false;
    int m_signals[2]{-1,-1};
public:
    explicit Launcher(QObject *parent=nullptr):QObject(parent) {
        if(::pipe2(m_signals,O_CLOEXEC|O_NONBLOCK)==0) {
            terminationPipe=m_signals[1];
            auto *notifier=new QSocketNotifier(m_signals[0],QSocketNotifier::Read,this);
            connect(notifier,&QSocketNotifier::activated,this,[this]{
                char pending[32];while(::read(m_signals[0],pending,sizeof pending)>0){}
                m_retry.stop();m_terminating=true;m_pendingActivation=false;
                const qint64 pid=m_process.processId();
                if(pid>0) {
                    ::kill(-pid,SIGTERM);
                    QTimer::singleShot(3000,this,[this,pid]{
                        if(m_process.state()!=QProcess::NotRunning) {::kill(-pid,SIGKILL);m_process.kill();}
                    });
                } else if(!m_cleaningCollector)QCoreApplication::quit();
            });
            struct sigaction action{};action.sa_handler=requestTermination;sigemptyset(&action.sa_mask);
            for(int signal:{SIGTERM,SIGINT,SIGHUP})::sigaction(signal,&action,nullptr);
            const pid_t parentPid=::getppid();
            ::prctl(PR_SET_PDEATHSIG,SIGTERM);
            if(::getppid()!=parentPid)requestTermination(SIGTERM);
        }
        m_process.setProcessChannelMode(QProcess::ForwardedChannels);
        connect(&m_process,&QProcess::finished,this,[this](int code,QProcess::ExitStatus status){
            auto finish=[this,code,status]{
                m_cleaningCollector=false;
                if(m_pendingActivation && !m_terminating) {
                    m_pendingActivation=false;m_retry.stop();
                    start(m_command);
                } else QCoreApplication::exit(status==QProcess::NormalExit?code:1);
            };
            if(m_ownsCollector) {
                // Keep servicing activation requests while old collector cleanup runs.
                m_cleaningCollector=true;
                auto *cleanup=QThread::create([]{stopCollectorBlocking();});
                connect(cleanup,&QThread::finished,this,finish);
                connect(cleanup,&QThread::finished,cleanup,&QObject::deleteLater);
                cleanup->start();
            } else finish();
        });
        connect(&m_process,&QProcess::errorOccurred,this,[](QProcess::ProcessError error){if(error==QProcess::FailedToStart)QCoreApplication::exit(1);});
        m_retry.setInterval(100);
        connect(&m_retry,&QTimer::timeout,this,[this]{
            if(VibeInstance::activate(VibeInstance::WindowService,m_token)) {
                m_pendingActivation=false;m_retry.stop();
            } else if(++m_attempts>=200)m_retry.stop();
        });
    }
    void start(QStringList command) {
        m_command=command;
        m_ownsCollector=QFileInfo(command.first()).fileName()==QStringLiteral("AppRun") || QFileInfo(command.first()).fileName()==QStringLiteral("plasmawindowed");
        const pid_t launcherPid=::getpid();
        m_process.setChildProcessModifier([launcherPid]{
            ::setsid();
            ::prctl(PR_SET_PDEATHSIG,SIGTERM);
            if(::getppid()!=launcherPid)::_exit(143);
        });
        auto env=QProcessEnvironment::systemEnvironment();
        env.remove("VIBEENERGY_INSTANCE_OWNER");
        if(QFileInfo(command.first()).fileName()==QStringLiteral("AppRun")) {
            env.insert("VIBEENERGY_INSTANCE_OWNER","1");
            // AppRun uses the host shell; it restores bundled paths itself.
            env.remove("LD_LIBRARY_PATH");
            env.remove("LD_PRELOAD");
        }
        m_process.setProcessEnvironment(env);
        m_process.start(command.first(),command.mid(1));
    }
public slots:
    bool Activate(const QString &token) {
        // Acknowledge startup requests immediately; a busy GUI must not block
        // the launcher service while its first scene is being initialized.
        if(m_terminating)return false;
        m_pendingActivation=true;m_token=token;m_attempts=0;m_retry.start();return true;
    }
};
int main(int argc,char **argv) {
    QCoreApplication app(argc,argv);
    auto command=app.arguments().mid(1);
    if(command.isEmpty()){std::cerr<<"Usage: energytlk-instance PROGRAM [ARGUMENTS...]\n";return 2;}
    const QString token=qEnvironmentVariable("XDG_ACTIVATION_TOKEN");
    if(VibeInstance::activate(VibeInstance::WindowService,token) || VibeInstance::activate(VibeInstance::LauncherService,token))return 0;
    auto bus=QDBusConnection::sessionBus();
    if(!bus.isConnected()) {std::cerr<<"VibeEnergy requires a desktop session bus\n";return 1;}
    Launcher launcher;
    if(!bus.registerObject(QString::fromLatin1(VibeInstance::ObjectPath),&launcher,QDBusConnection::ExportAllSlots))return 1;
    QElapsedTimer claimDeadline;claimDeadline.start();
    while(!bus.registerService(QString::fromLatin1(VibeInstance::LauncherService))) {
        if(VibeInstance::activate(VibeInstance::LauncherService,token))return 0;
        // A terminating owner may refuse activation while releasing its child.
        // Keep the new request alive until it can claim the launcher service.
        if(!bus.isConnected() || claimDeadline.elapsed()>=10000) {
            std::cerr<<"The previous VibeEnergy instance is still shutting down. Try opening it again shortly.\n";
            return 1;
        }
        QThread::msleep(100);
    }
    launcher.start(command);
    return app.exec();
}
#include "instance.moc"
