pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Controls.Popup {
    id: dialog
    Kirigami.Theme.inherit: false
    Kirigami.Theme.backgroundColor: "#171c23"
    Kirigami.Theme.textColor: "#f0f3f6"
    Kirigami.Theme.highlightColor: "#2788c7"
    Kirigami.Theme.highlightedTextColor: "#f0f3f6"
    Kirigami.Theme.positiveTextColor: "#35c76a"
    Kirigami.Theme.neutralTextColor: "#d6ae68"
    property var backend
    property var setup: ({installed: false, running: false, logReady: false})
    property string resultMessage: ""
    property string installCommand: ["pamac build powerstat", "sudo apt update\nsudo apt install powerstat", "sudo pacman -S powerstat"][distro.currentIndex]
    Connections {
        target: dialog.backend
        function onCpuAutostartFinished(success,message) { dialog.resultMessage=message; dialog.setup=dialog.backend.powerstatSetup() }
    }
    Controls.Popup {
        id: cpuAutostartConfirm
        parent: Controls.Overlay.overlay; anchors.centerIn: parent
        width: Math.min(460,parent ? parent.width-32 : 460)
        implicitHeight: confirmationContent.implicitHeight+40
        padding: 20; modal: true; focus: true
        background: Rectangle { radius: 12; color: "#202730"; border.color: "#3a4653" }
        contentItem: ColumnLayout {
            id: confirmationContent; spacing: 16
            Controls.Label { text: i18n("Enable CPU recording at boot?"); color: "#f0f3f6"; font.pointSize: 15; font.weight: Font.DemiBold; Layout.fillWidth: true; wrapMode: Text.Wrap }
            Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"; text: i18n("Installs the Powerstat system service and starts one-second CPU recording now and after reboot. Administrator authorization is required for this service only. VibeEnergy keeps running as your normal user.") }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                ActionButton { text: i18n("Cancel"); onClicked: cpuAutostartConfirm.close() }
                ActionButton { text: i18n("Enable CPU autostart"); primary: true; onClicked: { cpuAutostartConfirm.close(); dialog.backend.enableCpuAutostart() } }
            }
        }
    }
    objectName: "cpuSetupPopup"
    parent: Controls.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(600, parent ? parent.width-28 : 600)
    height: Math.min(720, parent ? parent.height-28 : 720)
    padding: 22
    modal: true; focus: true
    closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
    function check() { setup=backend.powerstatSetup() }
    function confirmAutostart() { check(); cpuAutostartConfirm.open() }
    function copy(command) { backend.copyText(command); resultMessage=i18n("Copied. Run the command yourself in your terminal.") }
    onOpened: { check(); resultMessage="" }
    Timer { interval: 2000; running: dialog.opened; repeat: true; onTriggered: dialog.check() }
    component SectionDivider: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: "#f0f3f6"
        opacity: .14
    }
    background: Surface {}
    contentItem: ColumnLayout {
        spacing: 16
        Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; text: i18n("CPU monitoring setup"); font.pointSize: 18; font.weight: Font.DemiBold; wrapMode: Text.Wrap }
        Controls.ScrollView {
            id: instructions
            Layout.fillWidth: true; Layout.fillHeight: true
            contentWidth: availableWidth
            ColumnLayout {
                width: instructions.availableWidth; spacing: 18
                Controls.Label { color: "#f0f3f6";
                    Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: .75
                    text: i18n("Run a copied command in your terminal to start CPU tracking. Choose one recording method: temporary, service or cron.")
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 8
                    Controls.Label { color: "#f0f3f6"; text: i18n("Powerstat status"); font.weight: Font.DemiBold; font.pointSize: 12 }
                    Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: dialog.setup.installed ? i18n("✓ Powerstat is installed") : i18n("Powerstat is not installed"); color: dialog.setup.installed ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor }
                    Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: dialog.setup.running ? i18n("✓ A Powerstat process is running") : i18n("Powerstat is not running"); color: dialog.setup.running ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor }
                    Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: dialog.setup.logReady ? i18n("✓ Fresh CPU log found") : i18n("Waiting for fresh CPU log samples"); color: dialog.setup.logReady ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor }
                }
                ColumnLayout {
                    visible: !dialog.setup.installed; Layout.fillWidth: true; spacing: 10
                    SectionDivider {}
                    Controls.Label { color: "#f0f3f6"; text: i18n("Install Powerstat"); font.weight: Font.DemiBold; font.pointSize: 12 }
                    Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: .75; text: i18n("Please install Powerstat on your system. We do not install it automatically to keep VibeEnergy itself 100% rootless. Installing system packages requires administrator privileges. Then choose a recording method below.") }
                    DarkComboBox { palette.text: "#f0f3f6"; palette.buttonText: "#f0f3f6"; palette.windowText: "#f0f3f6"; palette.base: "#202730"; palette.button: "#202730"; palette.window: "#252d37"; id: distro; model: [i18n("Manjaro (Pamac / AUR)"),i18n("Ubuntu / Debian"),i18n("Arch / Manjaro (Pacman)")] }
                    Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: .7; text: distro.currentIndex===0 ? i18n("Requires Pamac with AUR support. Review the package build when prompted.") : distro.currentIndex===1 ? i18n("Package availability depends on your enabled repositories; Ubuntu provides Powerstat in Universe.") : i18n("Use this command if your enabled repositories provide Powerstat. If the package is not found, install it from the AUR using your preferred AUR helper; the Pamac option above requires AUR support.") }
                    CommandCopy { Layout.fillWidth: true; buttonText: i18n("Copy install command"); command: dialog.installCommand; onCopyRequested: command => dialog.copy(command) }
                }
                SectionDivider {}
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 10
                    Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; text: i18n("Autostart with cron — Pure Linux command"); font.weight: Font.DemiBold; font.pointSize: 12 }
                    Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: .75; text: i18n("Adds boot startup while preserving existing cron jobs and avoiding duplicate entries. Recording starts at the next boot. Requires an enabled cron daemon.") }
                    CommandCopy { Layout.fillWidth: true; buttonText: i18n("Copy cron autostart"); copyEnabled: dialog.setup.installed; command: dialog.setup.cronCommand || ""; onCopyRequested: command => dialog.copy(command) }
                }
                SectionDivider {}
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 10
                    Controls.Label { text: i18n("Recommended"); color: Kirigami.Theme.positiveTextColor; font.weight: Font.DemiBold; font.pointSize: 10 }
                    Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; text: i18n("Autostart with the vibeenergy service"); font.weight: Font.DemiBold; font.pointSize: 12 }
                    Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: .75; text: i18n("Starts recording now and after reboot. You can close the terminal. This activates the service prepared by the standalone installer.") }
                    ActionButton {
                        Layout.fillWidth: true; primary: true
                        text: dialog.backend.cpuAutostartBusy ? i18n("Waiting for system authorization…") : i18n("Enable CPU autostart")
                        enabled: dialog.setup.installed && dialog.setup.pkexecAvailable && !dialog.backend.cpuAutostartBusy
                        onClicked: dialog.confirmAutostart()
                    }
                    Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"; text: i18n("Uses the system authentication dialog to install and enable the Powerstat service. Your password is handled by the system, not VibeEnergy. Use only one recording method.") }
                    CommandCopy { Layout.fillWidth: true; buttonText: i18n("Copy vibeenergy Powerstat service runner"); copyEnabled: dialog.setup.installed; command: dialog.setup.serviceRunnerCommand || ""; onCopyRequested: command => dialog.copy(command) }
                }
                SectionDivider {}
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 10
                    Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; text: i18n("Temporary recording — Pure Linux command"); font.weight: Font.DemiBold; font.pointSize: 12 }
                    Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: .75; text: i18n("Starts recording now, taking one sample per second and restarting Powerstat every 12 hours. Keep the terminal open; press Ctrl+C to stop.") }
                    CommandCopy { Layout.fillWidth: true; buttonText: i18n("Copy temporary start command"); copyEnabled: dialog.setup.installed; command: dialog.setup.foregroundCommand || ""; onCopyRequested: command => dialog.copy(command) }
                }
                SectionDivider {}
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 8
                    Controls.Label { color: "#f0f3f6"; text: i18n("Logs and daily totals"); font.weight: Font.DemiBold; font.pointSize: 12 }
                    Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: .75; text: i18n("All methods write to ~/.vibeenergy/logs/powerstat.log. The collector saves combined CPU and GPU daily kWh and costs, then clears older raw output. Keep the collector running for accounting and cleanup.") }
                    Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: .65; text: i18n("Powerstat needs supported CPU package counters. Ambiguous offline samples are excluded. These are component readings, not whole-PC wall power.") }
                }
                SectionDivider {}
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 10
                    Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; text: i18n("Check the service"); font.weight: Font.DemiBold; font.pointSize: 12 }
                    Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: .75; text: i18n("Shows the Powerstat system service status and its recent messages.") }
                    CommandCopy { Layout.fillWidth: true; buttonText: i18n("Copy status command"); command: "systemctl status vibeenergy-powerstat.service\njournalctl -u vibeenergy-powerstat.service -n 30"; onCopyRequested: command => dialog.copy(command) }
                }
                SectionDivider {}
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 10
                    Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; text: i18n("Stop the service"); font.weight: Font.DemiBold; font.pointSize: 12 }
                    Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: .75; text: i18n("Stops service recording now and disables its boot startup. Logs and daily totals are kept. For cron, remove its entry with sudo crontab -e instead.") }
                    CommandCopy { Layout.fillWidth: true; buttonText: i18n("Copy stop command"); command: "sudo systemctl disable --now vibeenergy-powerstat.service"; onCopyRequested: command => dialog.copy(command) }
                }
            }
        }

        Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; visible: dialog.resultMessage.length>0; text: dialog.resultMessage }
        RowLayout {
            Layout.fillWidth: true
            ActionButton { text: i18n("Check again"); onClicked: { dialog.check(); dialog.backend.refresh() } }
            Item { Layout.fillWidth: true }
            ActionButton { text: i18n("Done"); onClicked: dialog.close() }
        }
    }
}
