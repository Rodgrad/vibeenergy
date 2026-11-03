pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "History.js" as History

ColumnLayout {
    id: graph
    property var rows: []
    property string startDate
    property string endDate
    property string currency: "EUR"
    property var points: History.timeline(rows, startDate, endDate, currency)
    property int selected: -1
    property real maximum: Math.max(0.000001, ...points.map(p => p.kwh))
    property bool useWh: maximum < 1
    property real displayFactor: useWh ? 1000 : 1
    property real tickScale: {
        const value=Math.max(maximum*displayFactor*1.1, .01)
        const magnitude=Math.pow(10, Math.floor(Math.log10(value)))
        const fraction=value/magnitude
        return (fraction<=1 ? 1 : fraction<=2 ? 2 : fraction<=5 ? 5 : 10)*magnitude
    }
    property color cpuColor: "#43b8d4"
    property color gpuColor: "#35c76a"
    property color ink: "#a7b3bf"
    property var selectedPoint: selected >= 0 && selected < points.length ? points[selected] : (points.length ? points[points.length-1] : null)
    spacing: Kirigami.Units.smallSpacing
    onPointsChanged: { if (selected >= points.length) selected = -1; plot.requestPaint() }
    onCpuColorChanged: plot.requestPaint()
    onGpuColorChanged: plot.requestPaint()
    onInkChanged: plot.requestPaint()
    RowLayout {
        Controls.Label { color: "#f0f3f6"; text: i18n("Daily energy · %1", graph.useWh ? "Wh" : "kWh"); opacity: .7; font.pointSize: 10; Layout.fillWidth: true }
        Rectangle { width: 9; height: 9; radius: 2; color: graph.cpuColor }
        Controls.Label { color: "#f0f3f6"; text: "CPU" }
        Rectangle { width: 9; height: 9; radius: 2; color: graph.gpuColor }
        Controls.Label { color: "#f0f3f6"; text: "GPU" }
    }
    Canvas {
        id: plot
        Layout.fillWidth: true; Layout.preferredHeight: 190
        activeFocusOnTab: true
        Keys.onLeftPressed: { graph.selected=Math.max(0,(graph.selected < 0 ? graph.points.length : graph.selected)-1); requestPaint() }
        Keys.onRightPressed: { graph.selected=Math.min(graph.points.length-1,graph.selected+1); requestPaint() }
        Accessible.role: Accessible.Chart
        Accessible.name: i18n("Daily CPU and GPU energy from %1 to %2", graph.startDate, graph.endDate)
        property real plotLeft: 44
        property real plotRight: 8
        property real plotBottom: 26
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d"); ctx.reset()
            const w = width-plotLeft-plotRight, h = height-plotBottom-10
            const scale = graph.tickScale / graph.displayFactor
            ctx.font = Math.max(11,Kirigami.Theme.smallFont.pixelSize) + "px " + Kirigami.Theme.defaultFont.family
            for (let i=0; i<=4; i++) {
                const y=10+h-i*h/4
                ctx.globalAlpha=.15; ctx.strokeStyle=graph.ink; ctx.beginPath(); ctx.moveTo(plotLeft,y); ctx.lineTo(width-plotRight,y); ctx.stroke()
                ctx.globalAlpha=.8; ctx.fillStyle=graph.ink; ctx.textAlign="right"
                ctx.fillText(String(Number((graph.tickScale*i/4).toFixed(graph.tickScale < .1 ? 3 : 2))),plotLeft-6,y+3)
            }
            if (!graph.points.length) return
            const step=w/graph.points.length
            graph.points.forEach(function(p,i) {
                const x=plotLeft+i*step, bar=Math.max(1,step*.7)
                ctx.globalAlpha=graph.selected < 0 || graph.selected === i ? 1 : .6
                if (!p.known) {
                    ctx.fillStyle=graph.ink; ctx.globalAlpha=.25
                    ctx.fillRect(x+step*.15,10+h-3,bar,3)
                } else {
                    const cpu=p.cpu/scale*h, gpu=p.gpu/scale*h
                    ctx.fillStyle=graph.cpuColor; ctx.fillRect(x+step*.15,10+h-cpu,bar,cpu)
                    ctx.fillStyle=graph.gpuColor; ctx.fillRect(x+step*.15,10+h-cpu-gpu,bar,gpu)
                    if (p.kwh === 0) { ctx.fillRect(x+step*.15,10+h-1,bar,1) }
                }
            })
            ctx.globalAlpha=.85; ctx.fillStyle=graph.ink
            const indices=[0,Math.floor((graph.points.length-1)/2),graph.points.length-1]
            indices.forEach(function(i,n) {
                if (n>0 && indices[n-1] === i) return
                ctx.textAlign=n===0 ? "left" : n===2 ? "right" : "center"
                const p=graph.points[i], date=new Date(p.day+"T12:00:00")
                ctx.fillText(date.toLocaleDateString(Qt.locale(),"d MMM"), n===0 ? plotLeft : n===2 ? width-plotRight : plotLeft+(i+.5)*step,height-4)
            })
        }
        MouseArea {
            id: graphPointer
            anchors.fill: parent; hoverEnabled: true
            function selectAt(x) {
                graph.selected = x < plot.plotLeft || x > width-plot.plotRight ? -1 : Math.min(graph.points.length-1,Math.floor((x-plot.plotLeft)/(width-plot.plotLeft-plot.plotRight)*graph.points.length))
                plot.requestPaint()
            }
            onPositionChanged: mouse => selectAt(mouse.x)
            onClicked: mouse => selectAt(mouse.x)
            onExited: { graph.selected=-1; plot.requestPaint() }
        }
        Controls.ToolTip {
            id: barTooltip
            objectName: "historyBarTooltip"
            visible: (graphPointer.containsMouse || graphPointer.pressed) && graph.selected >= 0 && graph.selectedPoint !== null
            delay: 150
            timeout: -1
            padding: 8
            width: Math.min(240, plot.width, tooltipText.implicitWidth+leftPadding+rightPadding)
            x: Math.max(0, Math.min(plot.width-width,
                plot.plotLeft+(graph.selected+.5)*(plot.width-plot.plotLeft-plot.plotRight)/Math.max(1,graph.points.length)-width/2))
            y: Math.max(0, 10+(plot.height-plot.plotBottom-10)*(1-(graph.selectedPoint ? graph.selectedPoint.kwh : 0)/(graph.tickScale/graph.displayFactor))-implicitHeight-8)
            text: {
                const point=graph.selectedPoint
                if(!point) return ""
                const date=new Date(point.day+"T12:00:00").toLocaleDateString(Qt.locale(),"d MMM yyyy")
                if(!point.known) return date+"\n"+i18n("No readings recorded")
                const unit=graph.useWh ? " Wh" : " kWh"
                const decimals=graph.useWh ? 1 : 3
                const cpuShare=point.kwh > 0 ? (point.cpu/point.kwh*100).toFixed(1)+"%" : "—"
                const gpuShare=point.kwh > 0 ? (point.gpu/point.kwh*100).toFixed(1)+"%" : "—"
                return date+"\n"+
                    i18n("Total: %1",(point.kwh*graph.displayFactor).toFixed(decimals)+unit)+"\n"+
                    "CPU: "+(point.cpu*graph.displayFactor).toFixed(decimals)+unit+" ("+cpuShare+")\n"+
                    "GPU: "+(point.gpu*graph.displayFactor).toFixed(decimals)+unit+" ("+gpuShare+")\n"+
                    History.formatCosts(point.costs).split(" · ").join("\n")
            }
            background: Rectangle { color: "#202730"; radius: 6; border.color: "#43b8d4" }
            contentItem: Controls.Label {
                id: tooltipText
                text: barTooltip.text; color: "#f0f3f6"; font.pointSize: 9
                wrapMode: Text.Wrap; textFormat: Text.PlainText
            }
        }
    }
    Rectangle {
        Layout.fillWidth: true; implicitHeight: daySummary.implicitHeight+20; radius: 10
        color: Qt.rgba(graph.ink.r,graph.ink.g,graph.ink.b,.04)
        ColumnLayout {
            id: daySummary; anchors.fill: parent; anchors.margins: 10; spacing: 4
            Controls.Label { color: "#f0f3f6";
                Layout.fillWidth: true; wrapMode: Text.Wrap; font.pointSize: 10; font.weight: Font.DemiBold
                text: graph.selectedPoint ? new Date(graph.selectedPoint.day+"T12:00:00").toLocaleDateString(Qt.locale(),"d MMM") + "   ·   " +
                    (graph.selectedPoint.known ? (graph.selectedPoint.kwh*graph.displayFactor).toFixed(graph.useWh ? 1 : 3)+" "+(graph.useWh ? "Wh" : "kWh")+"   ·   "+
                    History.formatCosts(graph.selectedPoint.costs) : i18n("No readings recorded")) : i18n("Waiting for your first reading")
            }
            Controls.Label { color: "#f0f3f6";
                Layout.fillWidth: true; wrapMode: Text.Wrap; font.pointSize: 9; opacity: .68
                text: graph.selected>=0 && graph.selectedPoint && graph.selectedPoint.known ?
                    "CPU "+(graph.selectedPoint.cpu*graph.displayFactor).toFixed(1)+" / GPU "+(graph.selectedPoint.gpu*graph.displayFactor).toFixed(1)+" "+(graph.useWh ? "Wh" : "kWh")+" · "+graph.selectedPoint.qualities.join(", ") :
                    i18n("Hover, tap or use arrow keys to explore. Gray marks: no data.")
            }
        }
    }
}
