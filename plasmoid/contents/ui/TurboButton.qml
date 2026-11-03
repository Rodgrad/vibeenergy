pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

Controls.Button {
    id: button
    property bool turboActive: false
    property bool compact: false
    property real glow: turboActive ? 1 : 0
    objectName: "turboButton"
    implicitWidth: compact ? 130 : 190
    implicitHeight: compact ? 48 : 88
    hoverEnabled: true
    Accessible.name: turboActive ? qsTr("Stop cosmetic Turbo Boost") : qsTr("Play cosmetic Turbo Boost")
    Accessible.description: qsTr("Visual effect only. Does not change hardware performance or sampling.")
    background: Item {
        // Static in normal mode; intensity follows the single cosmetic Turbo timeline.
        Repeater {
            model: 4
            delegate: Rectangle {
                required property int index
                anchors.fill: parent; anchors.margins: -4-index*3; radius: 17+index*3
                color: "transparent"; border.width: 3
                border.color: Qt.rgba(0,.85,1,button.glow*(.12-index*.022))
            }
        }
        Rectangle { anchors.fill: parent; anchors.margins: -4; radius: 18; color: "transparent"; border.width: 4; border.color: button.hovered || button.turboActive ? "#2636b6e5" : "#2636b6e5" }
        Rectangle { anchors.fill: parent; anchors.margins: -1; radius: 15; color: "transparent"; border.width: 3; border.color: "#3036b6e5" }
        Rectangle {
            anchors.fill: parent; radius: 13
            color: Qt.tint(button.down ? "#153f56" : button.hovered ? "#16364a" : "#102737",Qt.rgba(0,.45,.8,button.glow*.4))
            border.width: 2; border.color: Qt.tint("#43c9ea",Qt.rgba(.5,1,1,button.glow))
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }
    contentItem: Item {
        implicitWidth: content.implicitWidth
        implicitHeight: content.implicitHeight
        RowLayout {
            id: content
            anchors.centerIn: parent
            spacing: button.compact ? 6 : 12
            Image {
                Layout.preferredWidth: button.compact ? 22 : 42
                Layout.preferredHeight: button.compact ? 22 : 42
                Layout.alignment: Qt.AlignVCenter
                source: "../icons/rocket.svg"
                fillMode: Image.PreserveAspectFit
                smooth: true
            }
            ColumnLayout {
                spacing: 0
                Controls.Label { Layout.alignment: Qt.AlignHCenter; text: "TURBO"; color: "#f0f3f6"; font.italic: true; font.weight: Font.Bold; font.pointSize: button.compact ? 15 : 26; horizontalAlignment: Text.AlignHCenter }
                Controls.Label { Layout.alignment: Qt.AlignHCenter; text: "BOOST"; color: "#f0f3f6"; font.italic: true; font.weight: Font.DemiBold; font.pointSize: button.compact ? 8 : 12; font.letterSpacing: 2; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }
}
