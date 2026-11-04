pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls

Controls.SpinBox {
    id: control
    function resetValue(savedValue) {
        value = savedValue
        contentItem.text = Qt.binding(function() { return control.displayText })
    }
    implicitHeight: 40
    leftPadding: 12; rightPadding: 30
    palette.base: "#202730"; palette.text: "#f0f3f6"
    palette.button: "#202730"; palette.buttonText: "#f0f3f6"
    palette.highlight: "#2788c7"; palette.highlightedText: "#ffffff"
    background: Rectangle {
        radius: 8; color: "#202730"
        border.color: control.activeFocus ? "#43b8d4" : "#3a4653"
        border.width: control.activeFocus ? 2 : 1
    }
    contentItem: TextInput {
        text: control.displayText
        color: control.enabled ? "#f0f3f6" : "#a7b3bf"
        font: control.font
        readOnly: !control.editable
        selectByMouse: true
        selectionColor: "#2788c7"; selectedTextColor: "#ffffff"
        verticalAlignment: TextInput.AlignVCenter
        validator: control.validator
        inputMethodHints: control.inputMethodHints
    }
    up.indicator: Rectangle {
        x: control.width-width; y: 0; implicitWidth: 26; implicitHeight: control.height/2
        color: control.up.pressed ? "#24465e" : "#2b3540"; radius: 4
        Text { anchors.centerIn: parent; text: "⌃"; color: control.up.enabled ? "#f0f3f6" : "#778593" }
    }
    down.indicator: Rectangle {
        x: control.width-width; y: control.height-height; implicitWidth: 26; implicitHeight: control.height/2
        color: control.down.pressed ? "#24465e" : "#2b3540"; radius: 4
        Text { anchors.centerIn: parent; text: "⌄"; color: control.down.enabled ? "#f0f3f6" : "#778593" }
    }
}
