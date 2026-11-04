import QtQuick
import QtTest
import "../../plasmoid/contents/ui" as App

Item {
    width: 400; height: 200
    App.DarkSpinBox { id: seconds; x: 20; y: 20; width: 200; from: 1; to: 5; editable: true }
    TestCase {
        name: "SamplingIntervalControl"
        when: windowShown
        function init() { seconds.resetValue(3) }
        function test_reloading_settings_keeps_display_in_sync() {
            seconds.contentItem.text="2"
            seconds.resetValue(3)
            mouseClick(seconds,seconds.width-13,seconds.height/4)
            compare(seconds.value,4)
            compare(seconds.contentItem.text,"4")
        }
        function test_arrow_buttons_change_seconds() {
            mouseClick(seconds,seconds.width-13,seconds.height/4)
            compare(seconds.value,4)
            compare(seconds.contentItem.text,"4")
            mouseClick(seconds,seconds.width-13,seconds.height*3/4)
            compare(seconds.value,3)
            compare(seconds.contentItem.text,"3")
        }
        function test_buttons_respect_limits() {
            seconds.value=5
            mouseClick(seconds,seconds.width-13,seconds.height/4)
            compare(seconds.value,5)
            seconds.value=1
            mouseClick(seconds,seconds.width-13,seconds.height*3/4)
            compare(seconds.value,1)
        }
        function test_typed_seconds_commit() {
            mouseClick(seconds,50,seconds.height/2)
            seconds.contentItem.selectAll()
            keyClick(Qt.Key_4)
            keyClick(Qt.Key_Return)
            compare(seconds.value,4)
        }
    }
}
