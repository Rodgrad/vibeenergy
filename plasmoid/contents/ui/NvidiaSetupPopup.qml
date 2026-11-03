pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

Controls.Popup {
    id: dialog
    property var backend
    property string notice: ""
    parent: Controls.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(520,parent ? parent.width-28 : 520)
    height: Math.min(content.implicitHeight+44,parent ? parent.height-28 : 720)
    padding: 22; modal: true; focus: true
    closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
    background: Rectangle { color: "#202730"; radius: 12; border.color: "#3a4653" }
    onOpened: notice=""
    contentItem: Controls.ScrollView {
        id: helpScroll
        clip: true; contentWidth: availableWidth
        Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
        ColumnLayout {
        id: content; width: helpScroll.availableWidth; spacing: 14
        Controls.Label { text: qsTr("Install nvidia-smi"); color: "#f0f3f6"; font.pointSize: 16; font.weight: Font.DemiBold }
        Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#f0f3f6"; text: qsTr("NVIDIA hardware detected. Its power-monitoring utility is missing.") }
        Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"; text: qsTr("Use your distribution’s Driver Manager or package manager to install NVIDIA driver utilities matching your installed driver. Package names vary by distribution and driver version. You do not need the CUDA toolkit.") }
        ActionButton {
            Layout.fillWidth: true
            text: qsTr("Open NVIDIA installation guide ↗")
            onClicked: Qt.openUrlExternally("https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/choose-an-installation-method.html")
        }
        CommandCopy {
            Layout.fillWidth: true; buttonText: qsTr("Copy check command")
            command: "nvidia-smi"
            onCopyRequested: command => { dialog.backend.copyText(command); dialog.notice=qsTr("Copied. Run nvidia-smi in your terminal after installing the utilities.") }
        }
        Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"; text: qsTr("VibeEnergy retries automatically within a minute. CPU and other supported GPU monitoring continue independently.") }
        Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#43b8d4"; visible: text.length>0; text: dialog.notice }
        ActionButton { Layout.alignment: Qt.AlignRight; text: qsTr("Done"); onClicked: dialog.close() }
        }
    }
}
