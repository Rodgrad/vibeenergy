#include <QGuiApplication>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQmlError>
#include <QJSValue>
#include <QTemporaryDir>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDateTime>
#include <QTimer>
#include <iostream>

int main(int argc,char **argv) {
    QGuiApplication app(argc,argv);
    if(argc!=2)return 2;
    QTemporaryDir temp;
    const QString state=temp.path()+"/energytlk";QDir().mkpath(state);
    qputenv("XDG_STATE_HOME",temp.path().toUtf8());
    qputenv("XDG_CONFIG_HOME",temp.path().toUtf8());
    QFile appearance(state+"/appearance.ini");
    if(!appearance.open(QIODevice::WriteOnly))return 1;
    appearance.write("[General]\nturboAlwaysOn=true\n");appearance.close();
    auto write=[&](double timestamp, bool running=true){
        QFile file(state+"/state.json");
        if(!file.open(QIODevice::WriteOnly))return false;
        const QJsonObject config{{"interval",1},{"currency",QStringLiteral("EUR")}};
        file.write(QJsonDocument(QJsonObject{{"running",running},{"timestamp",timestamp},{"config",config}}).toJson());return true;
    };
    if(!write(QDateTime::currentMSecsSinceEpoch()/1000.0-60))return 1;
    const QString path=QString::fromLocal8Bit(argv[1]);QFile file(path);if(!file.open(QIODevice::ReadOnly))return 1;
    QByteArray source=file.readAll();
    // The bare test engine has no Plasma containment; select the desktop view.
    source.replace("preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar ? fullRepresentation : compactRepresentation","preferredRepresentation: fullRepresentation");
    source.replace("    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground\n", "");
    QQmlEngine engine;QQmlComponent component(&engine);component.setData(source,QUrl::fromLocalFile(path));
    auto *widget=component.create();
    if(!widget){std::cerr<<component.errorString().toStdString();return 1;}
    int result=0;
    auto check=[&](bool condition,const char *message){if(!condition){std::cerr<<message<<'\n';result=1;}};
    QTimer::singleShot(1500,&app,[&]{check(widget->property("turboSettings").toString().contains("turboAlwaysOn=true"),"App Turbo setting was not read");check(widget->property("turboTime").toDouble()>0,"Turbo animation clock did not start");check(!widget->property("fresh").toBool(),"Stale snapshot marked recording");check(!widget->property("showWarning").toBool(),"Warning appeared before five seconds");});
    QTimer::singleShot(5600,&app,[&]{
        check(widget->property("showWarning").toBool(),"Unchanged snapshot did not trigger warning after five seconds");
        check(write(QDateTime::currentMSecsSinceEpoch()/1000.0),"Cannot write fresh test reading");
        QMetaObject::invokeMethod(widget,"refresh");
    });
    QTimer::singleShot(7500,&app,[&]{
        QFile::remove(state+"/appearance.ini");
        QFile burst(state+"/turbo.json");
        check(burst.open(QIODevice::WriteOnly),"Cannot write Turbo burst");
        burst.write(QJsonDocument(QJsonObject{{"until",QDateTime::currentMSecsSinceEpoch()/1000.0+2}}).toJson());burst.close();
        check(widget->property("fresh").toBool(),"New reading did not restore Recording");
        check(!widget->property("showWarning").toBool(),"Warning did not clear after new reading");
        
        check(write(QDateTime::currentMSecsSinceEpoch()/1000.0-60,false),"Cannot write stopped reading");
        QMetaObject::invokeMethod(widget,"refresh");
    });
    QTimer::singleShot(8500,&app,[&]{
        check(widget->property("turboSettings").toString().contains("until"),"Burst published by app did not reach widget");
        check(widget->property("turbo").value<QJSValue>().property("active").toBool(),"Five-second Turbo button state did not activate widget");
    });
    QTimer::singleShot(9500,&app,[&]{
        check(widget->property("showWarning").toBool(),"Stopped recording did not show warning");
        check(widget->property("noticeTitle").toString()=="You need the VibeEnergy app installed and running.","Stopped recording label is incorrect");
        QFile::remove(state+"/appearance.ini");
        QFile::remove(state+"/state.json");
        QMetaObject::invokeMethod(widget,"refresh");
    });
    QTimer::singleShot(11500,&app,[&]{
        check(!widget->property("turboSettings").toString().contains("turboAlwaysOn=true"),"Removed Turbo setting remained cached");
        check(!widget->property("turbo").value<QJSValue>().property("active").toBool(),"Expired burst did not stop widget animation");
        check(!widget->property("hasSnapshot").toBool(),"Deleted snapshot still available");
        check(widget->property("noticeTitle").toString()=="You need the VibeEnergy app installed and running.","Missing readings label is incorrect");
        if(!result)std::cout<<"Widget status verified: startup grace, stale timeout, live recovery, stopped recording, missing readings\n";
        app.exit(result);
    });
    const int code=app.exec();delete widget;return code;
}
