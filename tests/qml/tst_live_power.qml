import QtQuick
import QtTest
import "../../plasmoid/contents/ui" as UI
TestCase {
    name: "LivePowerGraph"
    width: 600; height: 400; visible: true
    UI.LivePowerGraph { id: graph; width: 560; height: 300 }
    function cleanup() { graph.points=[]; graph.rangeSeconds=3600 }
    function test_empty_graph_has_safe_scale() {
        compare(graph.visiblePoints.length,0)
        verify(graph.ceiling>0)
    }
    function test_range_filters_real_timestamps() {
        graph.points=[{timestamp:1000,cpu:4,gpu:20},{timestamp:1400,cpu:5,gpu:30},{timestamp:1500,cpu:6,gpu:40}]
        graph.rangeSeconds=300
        compare(graph.now,1500)
        compare(graph.visiblePoints.length,2)
        compare(graph.visiblePoints[1].gpu,40)
        verify(graph.ceiling>=40)
    }
    function test_all_four_ranges_filter_and_scale() {
        const points=[]
        for(let stamp=0;stamp<=3600;stamp++)points.push({timestamp:stamp,cpu:4,gpu:20})
        graph.points=points
        for(const seconds of [300,600,900,3600]) {
            graph.rangeSeconds=seconds
            compare(graph.start,3600-seconds)
            compare(graph.visiblePoints.length,seconds+1)
            compare(graph.visiblePoints[0].timestamp,3600-seconds)
        }
    }
    function test_short_history_keeps_selected_time_span() {
        graph.points=[{timestamp:3599,cpu:4,gpu:20},{timestamp:3600,cpu:5,gpu:21}]
        for(const seconds of [300,600,900,3600]) {
            graph.rangeSeconds=seconds
            compare(graph.now-graph.start,seconds)
            compare(graph.visiblePoints.length,2)
        }
    }
    function test_unknown_cpu_is_preserved_as_unknown() {
        graph.points=[{timestamp:1000,cpu:null,gpu:20},{timestamp:1001,cpu:null,gpu:22}]
        compare(graph.visiblePoints[0].cpu,null)
        compare(graph.visiblePoints[1].gpu,22)
    }
}
