import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Controls.Button {
    property bool primary: false
    implicitHeight: 38
    leftPadding: 14; rightPadding: 14
    background: Rectangle {
        radius: 8
        color: parent.primary ? (parent.down ? "#226fa3" : "#2788c7") : parent.hovered ? "#303c49" : "#202730"
        border.width: parent.activeFocus ? 2 : 1
        border.color: parent.activeFocus ? "#2788c7" : "#3a4653"
    }
    contentItem: Controls.Label { text: parent.text; font: parent.font; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; color: "#f0f3f6" }
}
