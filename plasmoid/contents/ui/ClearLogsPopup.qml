pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

Controls.Popup {
    id: dialog
    property var backend
    property bool finished: false
    property string resultMessage: ""
    parent: Controls.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(500,parent ? parent.width-28 : 500)
    implicitHeight: content.implicitHeight+44
    padding: 22; modal: true; focus: true
    closePolicy: backend && backend.clearingHistory ? Controls.Popup.NoAutoClose : Controls.Popup.CloseOnEscape
    onOpened: {finished=false;resultMessage=""}
    Connections {
        target: dialog.backend
        function onClearLogsFinished(success,message) {dialog.finished=success;dialog.resultMessage=message}
    }
    background: Rectangle { color: "#202730"; radius: 12; border.color: "#3a4653" }
    contentItem: ColumnLayout {
        id: content; spacing: 14
        Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: dialog.finished ? qsTr("Logs and history cleared") : qsTr("Clear all logs and history?"); color: "#f0f3f6"; font.pointSize: 16; font.weight: Font.DemiBold }
        Controls.Label {
            visible: !dialog.finished
            Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"
            text: qsTr("This permanently deletes all recorded energy and cost history for every currency, including demo history, and clears app logs and the configured CPU log. Your settings are preserved. This cannot be undone. The app collector pauses during clearing and restarts afterward if it was running.")
        }
        Controls.Label { visible: !dialog.finished; Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#d6ae68"; text: qsTr("Stop Powerstat before clearing. Running recording sources can immediately create new data.") }
        Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"; visible: dialog.resultMessage.length>0; text: dialog.resultMessage }
        Flow {
            Layout.fillWidth: true; spacing: 8
            ActionButton { objectName: "clearLogsCancel"; text: dialog.finished ? qsTr("Done") : qsTr("Cancel"); enabled: !dialog.backend.clearingHistory; onClicked: dialog.close() }
            ActionButton { objectName: "clearLogsConfirm"; visible: !dialog.finished; text: dialog.backend.clearingHistory ? qsTr("Clearing…") : qsTr("Delete all logs & history"); enabled: !dialog.backend.clearingHistory; onClicked: dialog.backend.clearLogs() }
        }
    }
}
