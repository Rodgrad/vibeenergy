pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
Controls.Button {
    id: button
    property bool selected: false
    property string symbol: "home"
    implicitHeight: 52
    leftPadding: 16; rightPadding: 12
    hoverEnabled: true
    background: Rectangle {
        radius: 10
        color: button.selected ? "#194b6a" : button.hovered ? "#293742" : "transparent"
        border.width: button.selected || button.activeFocus ? 1 : 0
        border.color: button.activeFocus ? "#43b8d4" : "#265873"
    }
    contentItem: RowLayout {
        spacing: 14
        AppIcon { kind: button.symbol; ink: button.selected ? "#18c8ef" : "#b2c8dd"; Layout.preferredWidth: 26; Layout.preferredHeight: 26 }
        Controls.Label { text: button.text; color: "#f0f3f6"; font.pointSize: 14; font.weight: button.selected ? Font.DemiBold : Font.Normal; Layout.fillWidth: true }
    }
}
