#include <QGuiApplication>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQuickWindow>
#include <QQuickItem>
#include <QTimer>
#include <QFile>
#include <QDir>
#include <KLocalizedContext>
#include <iostream>
#include <array>
#include <memory>

struct Dashboard {
    std::unique_ptr<QQuickWindow> window;
    QObject *root=nullptr,*view=nullptr;
    ~Dashboard(){delete view;delete root;}
};
int main(int argc,char **argv) {
    QGuiApplication app(argc,argv);
    if(argc!=2)return 2;
    QQmlEngine engine;
    engine.rootContext()->setContextObject(new KLocalizedContext(&engine));
    QQmlComponent component(&engine,QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    if(component.isError()){qWarning()<<component.errors();return 1;}
    std::array<Dashboard,3> dashboards;
    int result=0;
    auto fail=[&](const char *message){std::cerr<<message<<'\n';result=1;};
    auto create=[&](int index){
        auto &d=dashboards[index];d.root=component.create();
        if(!d.root){fail("Dashboard root failed to load");return;}
        auto *full=qvariant_cast<QQmlComponent *>(d.root->property("fullRepresentation"));
        d.view=full?full->create(qmlContext(d.root)):nullptr;
        auto *item=qobject_cast<QQuickItem *>(d.view);
        if(!item){fail("Dashboard view failed to load");return;}
        d.window=std::make_unique<QQuickWindow>();d.window->resize(620,680);
        item->setParentItem(d.window->contentItem());item->setSize(QSizeF(620,680));
        d.window->show();
        for(auto *child:d.root->findChildren<QObject *>())
            if(QString::fromLatin1(child->metaObject()->className())=="EnergyBridge" && index>0 && !child->property("startupComplete").toBool())
                fail("Additional window repeated a completed splash handoff");
    };
    const QString closed=qEnvironmentVariable("VIBEENERGY_SPLASH_CLOSED");
    create(0);
    QTimer::singleShot(200,&app,[&]{QFile file(closed);if(!file.open(QIODevice::WriteOnly))fail("Cannot write test handoff");});
    QTimer::singleShot(500,&app,[&]{QFile::remove(closed);});
    QTimer::singleShot(700,&app,[&]{create(1);create(2);});
    QTimer::singleShot(850,&app,[&]{
        auto backend=[](QObject *root)->QObject * {
            for(auto *child:root->findChildren<QObject *>())
                if(child->metaObject()->indexOfProperty("turboAlwaysOn")>=0)return child;
            return nullptr;
        };
        auto *first=backend(dashboards[0].root),*second=backend(dashboards[1].root);
        if(!first || !second){fail("Missing multi-window appearance backend");return;}
        first->setProperty("turboAlwaysOn",true);
        for(auto &d:dashboards)if(!d.view->findChild<QObject *>("dashboard")->property("alwaysOn").toBool())fail("Always-on preference did not reach another window");
        second->setProperty("turboAlwaysOn",false);
        for(auto &d:dashboards)if(d.view->findChild<QObject *>("dashboard")->property("alwaysOn").toBool())fail("Another window retained stale always-on state");
        if(!result)std::cout<<"Always-on controls synchronize across all three windows\n";
    });
    QTimer::singleShot(1000,&app,[&]{
        for(auto &d:dashboards) {
            auto *dashboard=d.view?d.view->findChild<QObject *>("dashboard"):nullptr;
            if(dashboard)QMetaObject::invokeMethod(dashboard,"startTurbo",Q_ARG(QVariant,QVariant(10000)));
        }
    });
    QTimer check;
    check.setInterval(100);
    QObject::connect(&check,&QTimer::timeout,&app,[&]{
        for(auto &d:dashboards) {
            auto *v=d.view;auto *effect=v?v->findChild<QObject *>("turboEffects"):nullptr;
            auto *audio=v?v->findChild<QObject *>("turboAudioOutput"):nullptr;
            if(!v || !v->property("turboActive").toBool() || v->property("turboTime").toDouble()<1.7 ||
                !effect || !effect->property("ready").toBool() || !audio || !audio->property("outputActive").toBool())return;
        }
        check.stop();
        for(auto &d:dashboards) {
            auto *audio=d.view->findChild<QObject *>("turboAudioOutput");
            const int before=audio->property("strikeCount").toInt();
            QMetaObject::invokeMethod(audio,"playStrike");
            if(audio->property("strikeCount").toInt()!=before+1)fail("A window could not mix a zap into its running output");
        }
        if(!result)std::cout<<"All three windows animate and play sound concurrently\n";
        QMetaObject::invokeMethod(dashboards[0].view,"toggleTurbo");
        QTimer::singleShot(1800,&app,[&]{
            if(dashboards[0].view->findChild<QObject *>("turboAudioOutput"))fail("Stopped window retained audio");
            for(int i=1;i<3;++i){
                auto *v=dashboards[i].view;auto *audio=v->findChild<QObject *>("turboAudioOutput");
                if(!v->property("turboActive").toBool() || !audio || !audio->property("outputActive").toBool())fail("Stopping one window affected another window");
                QMetaObject::invokeMethod(v,"toggleTurbo");
            }
            QTimer::singleShot(1800,&app,[&]{
                for(auto &d:dashboards)if(d.view && d.view->findChild<QObject *>("turboAudioOutput"))fail("Audio remained after all windows stopped");
                if(!result)std::cout<<"Window shutdown is independent; all audio outputs released\n";
                app.exit(result);
            });
        });
    });
    check.start();
    QTimer::singleShot(14000,&app,[&]{fail("Multi-window audio/animation check timed out");app.exit(1);});
    return app.exec();
}
