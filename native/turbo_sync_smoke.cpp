#include <QGuiApplication>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QFile>
#include <QDir>
#include <QTimer>
#include <QJSValue>
#include <QJsonDocument>
#include <QDateTime>
#include <KLocalizedContext>
#include <iostream>
#include <memory>

int main(int argc,char **argv) {
    QGuiApplication app(argc,argv);
    if(argc!=3)return 2;
    QTemporaryDir temp;
    qputenv("XDG_STATE_HOME",temp.path().toUtf8());
    qputenv("XDG_CONFIG_HOME",temp.path().toUtf8());
    QDir().mkpath(temp.path()+"/energytlk");
    QFile settings(temp.path()+"/energytlk/appearance.ini");
    if(!settings.open(QIODevice::WriteOnly))return 1;
    settings.write(qEnvironmentVariableIsSet("VIBEENERGY_SYNC_TEST_AUDIO") ? "[General]\nturboSoundEnabled=true\nsplashEnabled=false\n" : "[General]\nturboSoundEnabled=false\nsplashEnabled=false\n");settings.close();
    QQmlEngine engine;
    engine.rootContext()->setContextObject(new KLocalizedContext(&engine));
    QQmlComponent appComponent(&engine,QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    std::unique_ptr<QObject> root(appComponent.create());
    if(!root){std::cerr<<appComponent.errorString().toStdString();return 1;}
    auto *full=qvariant_cast<QQmlComponent *>(root->property("fullRepresentation"));
    std::unique_ptr<QObject> view(full?full->create(qmlContext(root.get())):nullptr);
    if(!view)return 1;
    QQuickWindow window;
    auto *item=qobject_cast<QQuickItem *>(view.get());
    item->setParentItem(window.contentItem());item->setWidth(1200);item->setHeight(900);window.resize(1200,900);window.show();
    QObject *bridge=nullptr;
    for(auto *child:root->findChildren<QObject *>())if(child->metaObject()->indexOfProperty("turboAlwaysOn")>=0){bridge=child;break;}
    auto *dashboard=view->findChild<QObject *>("dashboard");
    auto *button=dashboard?dashboard->findChild<QObject *>("turboButton"):nullptr;
    if(!bridge || !button)return 1;
    QFile widgetFile(QString::fromLocal8Bit(argv[2]));if(!widgetFile.open(QIODevice::ReadOnly))return 1;
    auto source=widgetFile.readAll();source.replace("    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground\n","");
    QQmlComponent widgetComponent(&engine);widgetComponent.setData(source,QUrl::fromLocalFile(QString::fromLocal8Bit(argv[2])));
    std::unique_ptr<QObject> widget(widgetComponent.create());
    if(!widget){std::cerr<<widgetComponent.errorString().toStdString();return 1;}
    int result=0;
    auto verify=[&](bool active,const char *stage){
        const bool appActive=view->property("turboActive").toBool();
        const bool widgetActive=widget->property("turbo").value<QJSValue>().property("active").toBool();
        if(appActive!=active || widgetActive!=active){std::cerr<<stage<<": app="<<appActive<<" widget="<<widgetActive<<" expected="<<active<<'\n';result=1;}
    };
    auto click=[&]{QMetaObject::invokeMethod(button,"clicked");};
    QTimer::singleShot(400,&app,[&]{click();});
    QTimer::singleShot(1700,&app,[&]{verify(true,"Button starts burst");click();});
    QTimer::singleShot(3000,&app,[&]{verify(false,"Button cancels burst");bridge->setProperty("turboAlwaysOn",true);});
    QTimer::singleShot(4300,&app,[&]{verify(true,"Settings enable continuous Turbo");click();});
    QTimer::singleShot(5600,&app,[&]{verify(false,"Button stops continuous Turbo");click();});
    QTimer::singleShot(6900,&app,[&]{verify(true,"Button restarts burst after continuous mode");window.hide();});
    QTimer::singleShot(8200,&app,[&]{
        if(!widget->property("turbo").value<QJSValue>().property("active").toBool()) {
            std::cerr<<"Hiding the app cancelled the widget burst\n";result=1;
        }
    });
    QTimer::singleShot(12000,&app,[&]{verify(false,"Burst expires in both app and widget");if(!result)std::cout<<"Turbo app/widget sync verified: button on/off, settings on, button off, burst restart and expiry\n";app.exit(result);});
    return app.exec();
}
