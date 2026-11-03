#include <QGuiApplication>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQmlError>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
#include <KLocalizedContext>
#include <QFileInfo>
#include <QFile>
#include <QTimer>
#include <QSGRendererInterface>
#include <iostream>
#include <memory>
#include "instanceipc.h"

int main(int argc, char **argv) {
    QGuiApplication app(argc,argv);
    if(argc<2) return 2;
    QQmlEngine engine;
    engine.rootContext()->setContextObject(new KLocalizedContext(&engine));
    QQuickWindow window;
    if(qEnvironmentVariableIsSet("VIBEENERGY_TEST_ALPHA")) {
        auto format=window.requestedFormat();format.setAlphaBufferSize(8);window.setFormat(format);
        window.setColor(Qt::transparent);
    }
    window.resize(620,680);
    QObject::connect(&engine,&QQmlEngine::warnings,[](const QList<QQmlError> &warnings){
        for(const auto &w:warnings) std::cerr << w.toString().toStdString() << '\n';
    });
    QQmlComponent component(&engine,QUrl::fromLocalFile(QFileInfo(QString::fromLocal8Bit(argv[1])).absoluteFilePath()));
    const auto errors=component.errors();
    for(const auto &e:errors) std::cerr << e.toString().toStdString() << '\n';
    if(component.isError()) return 1;
    QObject *object=component.create();
    for(const auto &e:component.errors()) std::cerr << e.toString().toStdString() << '\n';
    if(!object) return 1;
    std::cout << "QML component instantiated: " << object->metaObject()->className() << std::endl;
    QObject *expanded=nullptr;
    if(auto *full=qvariant_cast<QQmlComponent *>(object->property("fullRepresentation"))) {
        expanded=full->create(qmlContext(object));
        for(const auto &e:full->errors()) std::cerr << e.toString().toStdString() << '\n';
        if(!expanded) { delete object; return 1; }
        if(auto *item=qobject_cast<QQuickItem *>(expanded)) { const int w=qEnvironmentVariableIntValue("ENERGYTLK_SMOKE_WIDTH") > 0 ? qEnvironmentVariableIntValue("ENERGYTLK_SMOKE_WIDTH") : int(item->implicitWidth());
            const int h=qEnvironmentVariableIntValue("ENERGYTLK_SMOKE_HEIGHT") > 0 ? qEnvironmentVariableIntValue("ENERGYTLK_SMOKE_HEIGHT") : int(item->implicitHeight());
            window.resize(w,h); item->setParentItem(window.contentItem()); item->setWidth(w); item->setHeight(h); }
        std::cout << "Expanded dashboard instantiated" << std::endl;
    }
    if(expanded) {
        if(auto *tabs=expanded->findChild<QObject *>("dashboardTabs"))
            tabs->setProperty("currentIndex", qEnvironmentVariableIntValue("ENERGYTLK_SMOKE_TAB"));
    }
    if(qEnvironmentVariableIsSet("ENERGYTLK_SMOKE_DUMP_CRON")) {
        for(auto *child:object->findChildren<QObject *>()) {
            if(QString::fromLatin1(child->metaObject()->className())=="EnergyBridge") {
                QVariantMap setup;
                QMetaObject::invokeMethod(child,"powerstatSetup",Q_RETURN_ARG(QVariantMap,setup));
                QFile commandFile(qEnvironmentVariable("ENERGYTLK_SMOKE_DUMP_CRON"));
                if(commandFile.open(QIODevice::WriteOnly)) commandFile.write(setup.value("cronCommand").toString().toUtf8());
            }
        }
    }
    const bool verifyTurbo=qEnvironmentVariableIsSet("ENERGYTLK_SMOKE_VERIFY_TURBO");
    QSize originalSize=window.size();
    if(expanded && qEnvironmentVariableIsSet("ENERGYTLK_SMOKE_TURBO"))
        QMetaObject::invokeMethod(expanded,"toggleTurbo");
    if(expanded && qEnvironmentVariableIsSet("ENERGYTLK_SMOKE_CANCEL_TURBO"))
        QTimer::singleShot(800,&app,[&]{ QMetaObject::invokeMethod(expanded,"toggleTurbo"); });
    int result=0;
    int activeFrames=0;
    QObject::connect(&window,&QQuickWindow::frameSwapped,&app,[&]{
        if(expanded && expanded->property("turboActive").toBool())++activeFrames;
    });
    QPointF originalPricePosition;
    bool havePricePosition=false;
    if(verifyTurbo && expanded) QTimer::singleShot(250,&app,[&]{
        // Capture after the compositor has negotiated the initial frameless size.
        originalSize=window.size();
        if(auto *price=expanded->findChild<QQuickItem *>("sidebarPrice")) {
            originalPricePosition=price->mapToScene(QPointF()); havePricePosition=true;
        }
    });
    if(expanded && qEnvironmentVariableIsSet("ENERGYTLK_SMOKE_ALWAYS_ON")) {
        QObject *backend=nullptr;
        for(auto *child:object->findChildren<QObject *>()) {
            if(QString::fromLatin1(child->metaObject()->className())=="EnergyBridge") { backend=child;break; }
        }
        if(backend) {
            backend->setProperty("turboAlwaysOn",true);
            QTimer::singleShot(8500,&app,[&,backend]{
                if(!expanded->property("turboActive").toBool() || (!expanded->property("reducedMotion").toBool() && expanded->property("turboTime").toDouble()<7.5)){std::cerr<<"Always-on Turbo stopped or its animation clock stalled"<<std::endl;result=1;}
                else std::cout<<"Always-on Turbo animation continued beyond eight seconds"<<std::endl;
                backend->setProperty("turboAlwaysOn",false);
            });
        } else {std::cerr<<"Missing appearance settings backend"<<std::endl;result=1;}
    }
    if(expanded && qEnvironmentVariableIsSet("ENERGYTLK_SMOKE_VERIFY_AUDIO")) {
        QTimer::singleShot(4400,&app,[&]{
            auto *audio=expanded->findChild<QObject *>("turboAudioOutput");
            if(!audio || !audio->property("ready").toBool() || audio->property("strikeCount").toInt()<1) {
                std::cerr<<"Lightning audio did not become ready and play"<<std::endl;result=1;
            } else std::cout<<"Lightning audio ready; synchronized plays: "<<audio->property("strikeCount").toInt()<<std::endl;
        });
    }
    if(expanded && qEnvironmentVariableIsSet("ENERGYTLK_SMOKE_VERIFY_AUDIO_RELEASE")) {
        QTimer::singleShot(1000,&app,[&]{
            if(!expanded->findChild<QObject *>("turboAudioOutput")) {
                std::cerr<<"Turbo audio players were not created during activation"<<std::endl;result=1;
            }
        });
    }
    if(expanded && qEnvironmentVariableIsSet("ENERGYTLK_SMOKE_VERIFY_TURBO_CLICKS")) {
        QTimer::singleShot(1000,&app,[&]{
            QMetaObject::invokeMethod(expanded,"toggleTurbo");
            auto *dashboard=expanded->findChild<QObject *>("dashboard");
            if(!dashboard || !dashboard->property("turboActive").toBool() || dashboard->property("turboDuration").toInt()!=5000) {
                std::cerr<<"First click failed to start Turbo"<<std::endl;result=1;
            }
        });
        QTimer::singleShot(1400,&app,[&]{ QMetaObject::invokeMethod(expanded,"toggleTurbo"); });
        QTimer::singleShot(2300,&app,[&]{
            auto *popup=expanded->findChild<QObject *>("splashSoundReminder");
            if(!popup || !popup->property("visible").toBool() || popup->property("modal").toBool()) {
                std::cerr<<"Splash reminder was missing or blocked Turbo input"<<std::endl;result=1;
            }
            if(popup) QMetaObject::invokeMethod(popup,"close");
        });
        QTimer::singleShot(2600,&app,[&]{
            QMetaObject::invokeMethod(expanded,"toggleTurbo");
            if(!expanded->property("turboActive").toBool()) {
                std::cerr<<"A single click did not restart Turbo"<<std::endl;result=1;
            }
        });
        QTimer::singleShot(2900,&app,[&]{ QMetaObject::invokeMethod(expanded,"toggleTurbo"); });
        QTimer::singleShot(3900,&app,[&]{
            auto *popup=expanded->findChild<QObject *>("splashSoundReminder");
            if(!popup || popup->property("visible").toBool() || expanded->property("turboActive").toBool()) {
                std::cerr<<"Splash reminder reopened after interrupting Turbo"<<std::endl;result=1;
            } else std::cout<<"Single-click Turbo restart verified; splash reminder stayed closed after interruption"<<std::endl;
        });
        QTimer::singleShot(4200,&app,[&]{ QMetaObject::invokeMethod(expanded,"toggleTurbo"); });
        QTimer::singleShot(10000,&app,[&]{
            auto *popup=expanded->findChild<QObject *>("splashSoundReminder");
            if(!popup || popup->property("visible").toBool() || expanded->property("turboActive").toBool()) {
                std::cerr<<"Splash reminder reopened after normal Turbo expiry"<<std::endl;result=1;
            } else std::cout<<"Splash reminder stayed closed after normal Turbo expiry"<<std::endl;
        });
    }
    if(expanded && qEnvironmentVariableIsSet("ENERGYTLK_SMOKE_VERIFY_NORMAL_STARTUP")) {
        QTimer::singleShot(1000,&app,[&]{
            if(expanded->property("turboActive").toBool() || window.opacity()<1) {
                std::cerr<<"Normal startup unexpectedly enabled Turbo or hid the window"<<std::endl;result=1;
            } else std::cout<<"Normal startup: window visible, Turbo off"<<std::endl;
        });
    }
    std::unique_ptr<QQuickWindow> duplicateWindow;
    if(expanded && qEnvironmentVariableIsSet("ENERGYTLK_SMOKE_VERIFY_SINGLE_INSTANCE")) {
        QTimer::singleShot(500,&app,[&]{window.showMinimized();});
        QTimer::singleShot(700,&app,[&]{
            if(!VibeInstance::activate(VibeInstance::WindowService,QString())) {
                std::cerr<<"Existing window activation failed"<<std::endl;result=1;
            }
        });
        QTimer::singleShot(1100,&app,[&]{
            if(!window.isVisible() || window.visibility()==QWindow::Minimized) {
                std::cerr<<"Existing window was not restored"<<std::endl;result=1;
            }
            duplicateWindow=std::make_unique<QQuickWindow>();duplicateWindow->resize(300,200);duplicateWindow->show();
            auto *item=new QQuickItem(duplicateWindow->contentItem());
            bool claimed=true;
            for(auto *child:object->findChildren<QObject *>()) {
                if(QString::fromLatin1(child->metaObject()->className())=="EnergyBridge") {
                    QMetaObject::invokeMethod(child,"prepareAppWindow",Q_RETURN_ARG(bool,claimed),Q_ARG(QQuickItem *,item));break;
                }
            }
            if(claimed){std::cerr<<"Duplicate standalone window was accepted"<<std::endl;result=1;}
        });
        QTimer::singleShot(1600,&app,[&]{
            if(!duplicateWindow || duplicateWindow->isVisible() || !window.isVisible()) {
                std::cerr<<"Single-window guard failed"<<std::endl;result=1;
            } else std::cout<<"Existing window restored; duplicate window closed; original retained"<<std::endl;
        });
    }
    window.show();
    if(qEnvironmentVariableIsSet("ENERGYTLK_SMOKE_MAXIMIZE"))window.showMaximized();
    if(expanded && qEnvironmentVariableIsSet("ENERGYTLK_SMOKE_CREDITS")) {
        if(auto *popup=expanded->findChild<QObject *>("creditsPopup"))
            QMetaObject::invokeMethod(popup,"open");
    }
    if(expanded && qEnvironmentVariableIsSet("ENERGYTLK_SMOKE_CPU_SETUP")) {
        if(auto *popup=expanded->findChild<QObject *>("cpuSetupPopup"))
            QMetaObject::invokeMethod(popup,"open");
    }
    QTimer::singleShot(qEnvironmentVariableIsSet("ENERGYTLK_SMOKE_WAIT_MS") ? qEnvironmentVariableIntValue("ENERGYTLK_SMOKE_WAIT_MS") : 400,&app,[&]{
        if(qEnvironmentVariableIsSet("ENERGYTLK_SMOKE_VERIFY_CHROME") && expanded) {
            auto *controls=expanded->findChild<QQuickItem *>("windowControls");
            if(!window.flags().testFlag(Qt::FramelessWindowHint) || !controls || !controls->isVisible()) {
                std::cerr<<"Frameless window controls verification failed"<<std::endl;result=1;
            } else std::cout<<"System frame removed; application window controls visible"<<std::endl;
        }
        if(qEnvironmentVariableIsSet("ENERGYTLK_SMOKE_VERIFY_MARGIN") && expanded) {
            const int margin=expanded->property("edgeMargin").toInt();
            const bool maximized=window.windowState()==Qt::WindowMaximized || window.windowState()==Qt::WindowFullScreen;
            const bool maskGood=window.mask().contains(QPoint(window.width()/2,window.height()/2)) &&
                (maximized ? margin==0 : margin==32 && !window.mask().contains(QPoint(1,1)));
            if(!maskGood || window.color().alpha()!=0) { std::cerr<<"Transparent margin/input mask check failed"<<std::endl;result=1; }
            else std::cout<<"Transparent surface/input mask verified; margin "<<margin<<std::endl;
        }
        if(qEnvironmentVariableIsSet("ENERGYTLK_SMOKE_VERIFY_ICON")) {
            if(window.icon().isNull() || QGuiApplication::desktopFileName()!=QStringLiteral("vibeenergy")) {
                std::cerr<<"App icon or desktop identity missing"<<std::endl;result=1;
            } else std::cout<<"VibeEnergy window icon and desktop identity verified"<<std::endl;
        }
        if(qEnvironmentVariableIsSet("ENERGYTLK_SMOKE_PRINT_RENDERER")) {
            std::cout << "Renderer API: " << window.rendererInterface()->graphicsApi() << std::endl;
            std::cout << "Active Turbo frames: " << activeFrames << std::endl;
            if(auto *effects=expanded ? expanded->findChild<QObject *>("turboEffects") : nullptr) {
                std::cout << "GPU effects available: " << effects->property("gpuAvailable").toBool() << std::endl;
            }
        }
        if(verifyTurbo && expanded) {
            auto *effects=expanded->findChild<QObject *>("turboEffects");
            auto *background=expanded->findChild<QObject *>("turboBackgroundEffects");
            const bool backgroundClean=background && !background->property("rendering").toBool();
            auto *price=expanded->findChild<QQuickItem *>("sidebarPrice");
            const bool priceStable=!havePricePosition || (price && price->mapToScene(QPointF())==originalPricePosition);
            const bool clean=backgroundClean && priceStable && !expanded->property("turboActive").toBool() &&
                expanded->property("turboStrength").toDouble()<.001 && effects &&
                !effects->property("rendering").toBool() && window.size()==originalSize;
            if(!clean) { qWarning()<<"Turbo cleanup details"<<"background"<<backgroundClean<<"price"<<priceStable<<"active"<<expanded->property("turboActive")<<"strength"<<expanded->property("turboStrength")<<"rendering"<<(effects?effects->property("rendering"):QVariant())<<"size"<<window.size()<<"baseline"<<originalSize; std::cerr << "Turbo did not restore idle state and geometry" << std::endl; result=1; }
            else std::cout << "Turbo restored normal state; renderer released; window geometry unchanged" << std::endl;
        }
        if(expanded && qEnvironmentVariableIsSet("ENERGYTLK_SMOKE_VERIFY_AUDIO_RELEASE")) {
            if(expanded->findChild<QObject *>("turboAudioOutput")) {
                std::cerr<<"Turbo audio players remained after shutdown"<<std::endl;result=1;
            } else std::cout<<"Turbo audio players released after shutdown"<<std::endl;
        }
        if(argc>2) window.grabWindow().save(QString::fromLocal8Bit(argv[2]));
        app.quit();
    });
    app.exec();
    delete expanded;
    delete object;
    return result;
}
