import QtQuick
import QtTest
import "../../plasmoid/contents/ui" as App

Item {
    width: 500; height: 300
    App.DarkComboBox { id: choices; x: 10; y: 10; width: 220; model: ["First", "Second"] }
    App.DarkComboBox { id: editable; x: 10; y: 100; width: 220; editable: true; model: ["EUR", "USD"] }
    TestCase {
        name: "DropdownPointerInteraction"
        when: windowShown
        function cleanup() { choices.popup.close(); editable.popup.close(); tryCompare(choices.popup,"visible",false); tryCompare(editable.popup,"visible",false) }
        function test_eur_field_stays_white_on_focus_and_selection() {
            editable.currentIndex=0
            editable.editText="EUR"
            compare(editable.contentItem.color.toString(),"#ffffff")
            mouseClick(editable,70,editable.height/2)
            tryCompare(editable.popup,"visible",true)
            editable.contentItem.selectAll()
            compare(editable.contentItem.color.toString(),"#ffffff")
            compare(editable.contentItem.selectedTextColor.toString(),"#ffffff")
            editable.popup.close()
            compare(editable.contentItem.text,"EUR")
            compare(editable.contentItem.color.toString(),"#ffffff")
        }
        function test_selected_currency_text_is_readable_including_first_item() {
            for(let index=0;index<2;index++) {
                editable.currentIndex=index
                editable.popup.open()
                tryCompare(editable.popup,"visible",true)
                tryVerify(()=>editable.popup.contentItem.itemAtIndex(index)!==null)
                const item=editable.popup.contentItem.itemAtIndex(index)
                item.highlighted=true
                compare(item.contentItem.color.toString(),"#ffffff")
                compare(item.palette.highlightedText.toString(),"#ffffff")
                item.highlighted=false
                compare(item.contentItem.color.toString(),"#ffffff")
                editable.popup.close()
                tryCompare(editable.popup,"visible",false)
            }
        }
        function test_click_label_opens_menu() {
            mouseClick(choices,70,choices.height/2)
            tryCompare(choices.popup,"visible",true)
        }
        function test_click_padding_opens_menu() {
            mouseClick(choices,4,choices.height/2)
            tryCompare(choices.popup,"visible",true)
        }
        function test_click_again_closes_menu() {
            mouseClick(choices,70,choices.height/2)
            tryCompare(choices.popup,"visible",true)
            mouseClick(choices,70,choices.height/2)
            tryCompare(choices.popup,"visible",false)
        }
        function test_select_item_still_works() {
            choices.currentIndex=0
            mouseClick(choices,70,choices.height/2)
            tryCompare(choices.popup,"visible",true)
            tryVerify(()=>choices.popup.contentItem.itemAtIndex(1)!==null)
            const second=choices.popup.contentItem.itemAtIndex(1)
            mouseClick(second,second.width/2,second.height/2)
            compare(choices.currentIndex,1)
            tryCompare(choices.popup,"visible",false)
        }
        function test_editable_click_opens_and_typing_still_works() {
            mouseClick(editable,70,editable.height/2)
            tryCompare(editable.popup,"visible",true)
            editable.contentItem.selectAll()
            keyClick(Qt.Key_E);keyClick(Qt.Key_U);keyClick(Qt.Key_R)
            compare(editable.editText.toLowerCase(),"eur")
        }
    }
}
