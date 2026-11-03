import QtQuick
import QtTest
import "../../plasmoid/contents/ui" as App

Item {
    width: 600; height: 500
    QtObject {
        id: backend
        property int calls: 0
        property string savedCurrency: ""
        property string message: ""
        function saveSettings(price, currency, interval, retention, log) {
            calls++
            savedCurrency = currency
            return true
        }
    }
    App.CurrencyChangePopup { id: dialog; backend: backend; previousCurrency: "EUR"; existingCurrencies: ["EUR"] }
    TestCase {
        name: "CurrencyChangeConfirmation"
        when: windowShown
        function init() { backend.calls=0; dialog.existingCurrencies=["EUR"] }
        function cleanup() { dialog.close(); tryCompare(dialog,"visible",false) }
        function test_cancel_preserves_settings() {
            dialog.requestSave(".25","USD",1,"")
            tryCompare(dialog,"visible",true)
            compare(backend.calls,0)
            findChild(dialog,"currencyCancel").clicked()
            compare(backend.calls,0)
        }
        function test_confirm_saves_once() {
            dialog.requestSave(".25"," usd ",1,"")
            tryCompare(dialog,"visible",true)
            compare(dialog.continuing,false)
            findChild(dialog,"currencyConfirm").clicked()
            compare(backend.calls,1)
            compare(backend.savedCurrency,"USD")
            tryCompare(dialog,"visible",false)
        }
        function test_existing_branch_continues() {
            dialog.existingCurrencies=["EUR","USD"]
            dialog.requestSave(".25","USD",1,"")
            tryCompare(dialog,"visible",true)
            compare(dialog.continuing,true)
            compare(backend.calls,0)
        }
        function test_same_currency_saves_without_confirmation() {
            dialog.requestSave(".25","EUR",1,"")
            compare(dialog.visible,false)
            compare(backend.calls,1)
        }
    }
}
