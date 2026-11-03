pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

Controls.Popup {
    id: dialog
    property var backend
    property string previousCurrency
    property var existingCurrencies: []
    property var pending: ({})
    property string errorMessage: ""
    readonly property bool continuing: existingCurrencies.indexOf(pending.currency) >= 0
    function requestSave(price, currency, interval, log) {
        errorMessage = ""
        const code = currency.trim().toUpperCase()
        pending = {price: price, currency: code, interval: interval, log: log}
        if (/^[A-Z]{3}$/.test(code) && code !== previousCurrency) open()
        else backend.saveSettings(price, code, interval, 1, log)
    }
    parent: Controls.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(500, parent ? parent.width-28 : 500)
    implicitHeight: content.implicitHeight+44
    padding: 22; modal: true; focus: true
    closePolicy: Controls.Popup.CloseOnEscape
    background: Rectangle { color: "#202730"; radius: 12; border.color: "#3a4653" }
    contentItem: ColumnLayout {
        id: content; spacing: 16
        Controls.Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: dialog.continuing ? qsTr("Continue %1 history?").arg(dialog.pending.currency || "") : qsTr("Start %1 history?").arg(dialog.pending.currency || "")
            color: "#f0f3f6"; font.pointSize: 16; font.weight: Font.DemiBold
        }
        Controls.Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"
            text: qsTr("New measurements will be recorded in %1. Your %2 history will be preserved and available in History. No currency conversion will be applied. Make sure the electricity price is entered in %1.").arg(dialog.pending.currency || "").arg(dialog.previousCurrency)
        }
        Flow {
            Layout.fillWidth: true; spacing: 8
            ActionButton { objectName: "currencyCancel"; text: qsTr("Cancel"); onClicked: dialog.close() }
            ActionButton {
                objectName: "currencyConfirm"; primary: true
                text: dialog.continuing ? qsTr("Save and continue %1 history").arg(dialog.pending.currency || "") : qsTr("Save and start %1 history").arg(dialog.pending.currency || "")
                onClicked: {
                    if(dialog.backend.saveSettings(dialog.pending.price,dialog.pending.currency,dialog.pending.interval,1,dialog.pending.log)) dialog.close()
                    else dialog.errorMessage=dialog.backend.message
                }
            }
        }
        Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"; visible: dialog.errorMessage.length > 0; text: dialog.errorMessage }
    }
}
