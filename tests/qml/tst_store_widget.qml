import QtQuick
import QtTest
import "../../widget-store/package/contents/ui/Metrics.js" as Metrics
TestCase {
    name:"StoreCompanionMetrics"
    function test_recording_timeout_is_always_five_seconds() {
        const reading={running:true,timestamp:100,config:{interval:300}}
        compare(Metrics.isFresh(reading,104.999),true)
        compare(Metrics.isFresh(reading,105),false)
        compare(Metrics.isFresh({running:false,timestamp:100},101),false)
        compare(Metrics.isFresh({running:true,timestamp:1000},100),false)
    }
    function test_warning_waits_five_seconds_and_resets_on_new_reading() {
        compare(Metrics.warningDue(100,104.999),false)
        compare(Metrics.warningDue(100,105),true)
        compare(Metrics.warningDue(100,110),true)
        compare(Metrics.warningDue(110,110),false)
        compare(Metrics.warningDue(110,114.999),false)
        compare(Metrics.warningDue(110,115),true)
    }
    function test_turbo_sync_and_optional_files() {
        compare(Metrics.turboState("",100).active,false)
        compare(Metrics.turboState("[General]\nturboAlwaysOn=true\n",100).continuous,true)
        const burst="turboAlwaysOn=false\n---VIBEENERGY-TURBO---\n{\"until\":105}"
        compare(Metrics.turboState(burst,100).active,true)
        compare(Metrics.turboState(burst,105).active,false)
        compare(Metrics.turboState(burst,0).active,false)
        compare(Metrics.turboState("\n---VIBEENERGY-TURBO---\ninvalid",100).active,false)
    }
    function test_power_excludes_shared_and_missing_domains(){
        const devices=[{kind:"cpu",watts:40},{kind:"gpu",watts:100},{kind:"gpu",watts:50,account:false},{kind:"gpu",watts:null}]
        compare(Metrics.watts(devices,"cpu"),40)
        compare(Metrics.watts(devices,"gpu"),100)
        compare(Metrics.watts(devices,""),140)
        compare(Metrics.watts([],"cpu"),null)
    }
    function test_selected_currency_cost_and_combined_energy(){
        const rows=[{day:"2026-11-03",currency:"EUR",kwh:1,cost:.2},{day:"2026-11-03",currency:"USD",kwh:2,cost:.5},{day:"2026-10-01",currency:"EUR",kwh:9,cost:9}]
        const total=Metrics.summary(rows,"EUR","2026-11-01","2026-11-03")
        compare(total.kwh,3);compare(total.cost,.2);compare(total.hasCost,true)
        compare(Metrics.summary(rows,"CAD","2026-11-01","2026-11-03").hasCost,false)
    }
    function test_unknown_history_and_date(){
        const total=Metrics.summary([],"EUR","0000-01-01","2026-11-03")
        compare(total.hasEnergy,false);compare(total.hasCost,false)
        compare(Metrics.day(new Date(2026,10,3)),"2026-11-03")
    }
}
