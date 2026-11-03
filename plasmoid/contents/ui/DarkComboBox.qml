pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

T.ComboBox {
    id: control
    Kirigami.Theme.inherit: false
    Kirigami.Theme.textColor: "#f0f3f6"
    Kirigami.Theme.highlightedTextColor: "#ffffff"
    Kirigami.Theme.backgroundColor: "#202730"
    implicitHeight: 40
    implicitWidth: Math.max(100, implicitContentWidth+leftPadding+rightPadding)
    baselineOffset: contentItem.y+contentItem.baselineOffset
    palette.base: "#202730"
    palette.window: "#252d37"
    palette.button: "#202730"
    palette.text: "#f0f3f6"
    palette.buttonText: "#f0f3f6"
    palette.windowText: "#f0f3f6"
    palette.highlight: "#2788c7"
    palette.highlightedText: "#ffffff"
    leftPadding: 12; rightPadding: 30
    background: Rectangle {
        radius: 8; color: "#202730"
        border.color: control.activeFocus ? "#43b8d4" : "#3a4653"
        border.width: control.activeFocus ? 2 : 1
    }
    contentItem: TextInput {
        text: control.editable ? control.editText : control.displayText
        color: control.enabled ? "#ffffff" : "#a7b3bf"
        font: control.font
        readOnly: !control.editable
        autoScroll: control.editable
        selectByMouse: control.editable
        selectionColor: "#2788c7"; selectedTextColor: "#ffffff"
        verticalAlignment: TextInput.AlignVCenter
        validator: control.validator
        inputMethodHints: control.inputMethodHints
    }
    MouseArea {
        anchors.fill: parent
        z: 1
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if(control.editable)control.contentItem.forceActiveFocus()
            else control.forceActiveFocus()
            if(control.popup.visible)control.popup.close()
            else control.popup.open()
        }
    }
    indicator: Text {
        x: control.width-width-11; anchors.verticalCenter: parent.verticalCenter
        text: "⌄"; color: "#a7b3bf"; font.pixelSize: 19
    }
    delegate: Controls.ItemDelegate {
        id: option
        Kirigami.Theme.inherit: false
        Kirigami.Theme.textColor: "#f0f3f6"
        Kirigami.Theme.highlightedTextColor: "#ffffff"
        palette.text: "#f0f3f6"
        palette.buttonText: "#f0f3f6"
        palette.highlightedText: "#ffffff"
        required property int index
        width: control.width
        text: control.textAt(index)
        highlighted: control.highlightedIndex===index
        contentItem: Text { text: option.text; font: control.font; color: "#ffffff"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
        background: Rectangle { color: option.highlighted ? "#24465e" : option.hovered ? "#303b48" : "#202730" }
    }
    popup: Controls.Popup {
        parent: control
        closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutsideParent
        y: control.height+4
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight+8,300)
        padding: 4
        background: Rectangle { color: "#202730"; radius: 8; border.color: "#3a4653" }
        contentItem: ListView {
            clip: true; implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            Controls.ScrollIndicator.vertical: Controls.ScrollIndicator {}
        }
    }
}
