import QtQuick
import QtTest
import "../../plasmoid/contents/ui" as App
Item {
    width:600; height:600
    QtObject {
        id: backend
        property bool clearingHistory: false
        property int calls: 0
        signal clearLogsFinished(bool success,string message)
        function clearLogs(){calls++;clearingHistory=true}
    }
    App.ClearLogsPopup {id: dialog;backend:backend}
    TestCase {
        name: "ClearLogsConfirmation"
        when: windowShown
        function init(){backend.calls=0;backend.clearingHistory=false;dialog.open();tryCompare(dialog,"visible",true)}
        function cleanup(){backend.clearingHistory=false;dialog.close();tryCompare(dialog,"visible",false)}
        function test_cancel_does_not_clear(){findChild(dialog,"clearLogsCancel").clicked();compare(backend.calls,0)}
        function test_confirmation_starts_clear_and_disables_buttons(){
            findChild(dialog,"clearLogsConfirm").clicked()
            compare(backend.calls,1)
            compare(findChild(dialog,"clearLogsConfirm").enabled,false)
            compare(findChild(dialog,"clearLogsCancel").enabled,false)
            backend.clearingHistory=false;backend.clearLogsFinished(true,"Cleared")
            compare(dialog.finished,true)
            compare(dialog.resultMessage,"Cleared")
        }
        function test_failure_keeps_confirmation_and_message(){
            backend.clearLogsFinished(false,"Log is not writable")
            compare(dialog.finished,false)
            compare(dialog.resultMessage,"Log is not writable")
        }
    }
}
