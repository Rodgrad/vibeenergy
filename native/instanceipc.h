#pragma once
#include <QDBusConnection>
#include <QDBusMessage>
#include <QString>
namespace VibeInstance {
inline constexpr auto LauncherService="com.techtoapes.VibeEnergy.Launcher";
inline constexpr auto WindowService="com.techtoapes.VibeEnergy.Window";
inline constexpr auto ObjectPath="/VibeEnergy";
inline bool activate(const char *service,const QString &token) {
    auto request=QDBusMessage::createMethodCall(QString::fromLatin1(service),QString::fromLatin1(ObjectPath),QString::fromLatin1(service),"Activate");
    request<<token;
    const auto reply=QDBusConnection::sessionBus().call(request,QDBus::Block,500);
    return reply.type()==QDBusMessage::ReplyMessage && !reply.arguments().isEmpty() && reply.arguments().first().toBool();
}
}
