pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

ColumnLayout {
    id: root
    property string buttonText
    property string command
    property bool copyEnabled: true
    signal copyRequested(string command)
    spacing: 6
    Flow {
        Layout.fillWidth: true
        spacing: 8
        ActionButton {
            text: root.buttonText
            enabled: root.copyEnabled
            onClicked: root.copyRequested(root.command)
        }
        ActionButton {
            id: toggle
            text: checked ? i18n("Hide command") : i18n("View command")
            checkable: true
            Accessible.name: i18n("View command: %1", root.buttonText)
        }
    }
    Controls.TextArea { palette.text: "#f0f3f6"; palette.buttonText: "#f0f3f6"; palette.windowText: "#f0f3f6"; palette.base: "#202730"; palette.button: "#202730"; palette.window: "#252d37";
        Layout.fillWidth: true
        visible: toggle.checked
        color: "#f0f3f6"
        selectionColor: "#2788c7"; selectedTextColor: "#ffffff"
        background: Rectangle { color: "#202730"; radius: 8; border.color: "#3a4653" }
        readOnly: true
        selectByMouse: true
        text: root.command
        wrapMode: TextEdit.WrapAnywhere
        font.family: "monospace"
        font.pointSize: 10
        Accessible.name: root.buttonText
    }
}
