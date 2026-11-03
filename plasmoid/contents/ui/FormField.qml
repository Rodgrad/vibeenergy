import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Controls.TextField {
    selectionColor: "#2788c7"
    selectedTextColor: "#ffffff"
    palette.base: "#202730"
    palette.text: "#f0f3f6"
    color: "#f0f3f6"
    placeholderTextColor: "#a7b3bf"
    implicitHeight: 40
    leftPadding: 12; rightPadding: 12
    selectByMouse: true
    background: Rectangle {
        radius: 8; color: "#202730"
        border.width: parent.activeFocus ? 2 : 1
        border.color: parent.activeFocus ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r,Kirigami.Theme.textColor.g,Kirigami.Theme.textColor.b,.22)
    }
}
