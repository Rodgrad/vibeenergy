import QtQuick
import QtTest
import "../../plasmoid/contents/ui/History.js" as History

TestCase {
    name: "EnergyHistory"
    function test_small_costs_use_normal_rounding_without_less_than() {
        compare(History.money([{cost:0,currency:"CAD"}],"EUR"),"0.000 CAD")
        compare(History.money([{cost:.0001,currency:"CAD"}],"EUR"),"0.000 CAD")
        compare(History.money([{cost:.0009,currency:"EUR"}],"EUR"),"0.001 EUR")
        compare(History.money([{cost:.5,currency:"USD"}],"EUR"),"0.500 USD")
    }
    function test_graph_cost_labels_include_currency_for_older_rows() {
        const rows = [
            {day:"2026-11-03",kind:"cpu",kwh:1,cost:.2,quality:"measured"},
            {day:"2026-11-03",kind:"gpu",kwh:1,cost:.3,currency:"USD",quality:"measured"}
        ]
        const point = History.timeline(rows,"2026-11-03","2026-11-03","EUR")[0]
        compare(History.formatCosts(point.costs), "0.200 EUR · 0.300 USD")
    }
    function test_currency_costs_are_never_added_together() {
        const rows = [
            {day:"2026-11-03",kind:"cpu",kwh:1,cost:2,currency:"EUR",quality:"measured"},
            {day:"2026-11-03",kind:"gpu",kwh:2,cost:3,currency:"USD",quality:"measured"},
            {day:"2026-11-03",kind:"gpu",kwh:1,cost:1,currency:"EUR",quality:"measured"}
        ]
        compare(History.money(rows,"USD"), "3.000 EUR · 3.000 USD")
        const point = History.timeline(rows,"2026-11-03","2026-11-03")[0]
        compare(point.kwh, 4)
        compare(point.cost, null)
        compare(History.formatCosts(point.costs), "3.000 EUR · 3.000 USD")
        const selected = rows.filter(r => r.currency === "EUR")
        compare(History.money(selected,"USD"), "3.000 EUR")
        compare(History.timeline(selected,"2026-11-03","2026-11-03")[0].kwh, 2)
    }
    function test_thirty_calendar_days_and_gaps() {
        const points = History.timeline([{day:"2026-11-02",kind:"gpu",kwh:.5,cost:.1,quality:"measured"}],"2026-10-04","2026-11-02")
        compare(points.length,30)
        compare(points[0].day,"2026-10-04")
        compare(points[0].known,false)
        compare(points[29].day,"2026-11-02")
        compare(points[29].gpu,.5)
        compare(points[29].known,true)
    }
    function test_stack_multiple_devices_and_quality() {
        const points = History.timeline([
            {day:"2026-11-02",kind:"cpu",kwh:1,cost:.2,quality:"imported from log"},
            {day:"2026-11-02",kind:"gpu",kwh:2,cost:.4,quality:"measured"},
            {day:"2026-11-02",kind:"gpu",kwh:3,cost:.6,quality:"measured"}
        ],"2026-11-02","2026-11-02")
        compare(points[0].cpu,1)
        compare(points[0].gpu,5)
        compare(points[0].kwh,6)
        fuzzyCompare(points[0].cost,1.2,.000001)
        compare(points[0].qualities.length,2)
    }
    function test_measured_zero_differs_from_missing() {
        const points=History.timeline([{day:"2026-11-01",kind:"gpu",kwh:0,cost:0,quality:"measured"}],"2026-11-01","2026-11-02")
        compare(points[0].known,true)
        compare(points[1].known,false)
    }
    function test_leap_day_and_invalid_range() {
        const points=History.timeline([],"2024-02-28","2024-03-01")
        compare(points.length,3)
        compare(points[1].day,"2024-02-29")
        compare(History.timeline([],"2026-11-02","2026-11-01").length,0)
        compare(History.timeline([],"invalid","2026-11-01").length,0)
    }
}
