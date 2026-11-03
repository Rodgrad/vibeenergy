import QtQuick
import org.kde.kirigami as Kirigami

Rectangle {
    Kirigami.Theme.colorSet: Kirigami.Theme.View
    Kirigami.Theme.inherit: true
    property real energy: 0
    radius: 14
    color: energy > 0 ? Qt.tint("#252d37", Qt.rgba(0,.12,.2,energy*.65)) : "#252d37"
    border.width: 1
    border.color: energy > 0 ? Qt.tint("#3a4653", Qt.rgba(.2,.8,1,energy*.8)) : "#3a4653"
}
