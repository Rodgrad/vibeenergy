pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

Controls.Popup {
    id: dialog
    objectName: "uninstallPopup"
    property var backend
    property bool busy: false
    property bool removed: false
    property string errorMessage: ""
    signal closeAppRequested()
    parent: Controls.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(500,parent ? parent.width-28 : 500)
    implicitHeight: content.implicitHeight+44
    padding: 22; modal: true; focus: true
    closePolicy: busy ? Controls.Popup.NoAutoClose : Controls.Popup.CloseOnEscape
    background: Rectangle { color: "#202730"; radius: 12; border.color: "#3a4653" }
    onOpened: { busy=false; removed=false; errorMessage="" }
    Connections {
        target: dialog.backend
        function onUninstallFinished(success) { dialog.busy=false; dialog.removed=success; dialog.errorMessage=success ? "" : dialog.backend.message }
    }
    contentItem: ColumnLayout {
        id: content; spacing: 16
        Controls.Label { text: dialog.removed ? qsTr("VibeEnergy removed") : qsTr("Uninstall VibeEnergy?"); color: "#f0f3f6"; font.pointSize: 16; font.weight: Font.DemiBold }
        Controls.Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"
            text: dialog.removed ? qsTr("Your history, settings, and logs are kept. Close this window, then delete the AppImage file. Opening the AppImage again will prepare the app again.") : qsTr("This stops the background collector, disables its autostart, and removes VibeEnergy’s user service and desktop integration. Your history, settings, CPU logs, and AppImage file are kept. Separate Powerstat recording is unaffected.")
        }
        Controls.Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#d6ae68"
            text: qsTr("Do not forget to stop Powerstat. Uninstalling VibeEnergy does not stop or disable Powerstat recording.")
        }
        Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"; visible: !dialog.busy && !dialog.removed && dialog.errorMessage.length>0; text: dialog.errorMessage }
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            ActionButton { objectName: "uninstallCancel"; text: dialog.removed ? qsTr("Close app") : qsTr("Cancel"); enabled: !dialog.busy; onClicked: { dialog.close(); if(dialog.removed)dialog.closeAppRequested() } }
            ActionButton { objectName: "uninstallConfirm"; visible: !dialog.removed; text: dialog.busy ? qsTr("Removing…") : qsTr("Uninstall"); enabled: !dialog.busy; onClicked: { dialog.busy=true; dialog.backend.uninstallApp() } }
        }
    }
}
