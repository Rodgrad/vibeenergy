pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

ColumnLayout {
    id: graph
    property var points: []
    property real energy: 0
    property int rangeSeconds: 3600
    property real maxGapSeconds: 3
    property real now: points.length ? points[points.length-1].timestamp : Date.now()/1000
    property var visiblePoints: points.filter(p => p.timestamp >= now-rangeSeconds)
    property real maximum: Math.max(10,...visiblePoints.map(p => Math.max(p.cpu || 0,p.gpu || 0)))
    property real ceiling: Math.ceil(maximum*1.15/10)*10
    property real start: now-rangeSeconds
    onEnergyChanged: plot.requestPaint()
    onPointsChanged: plot.requestPaint()
    onRangeSecondsChanged: plot.requestPaint()
    Canvas {
        id: plot
        Layout.fillWidth: true; Layout.preferredHeight: 208
        Accessible.role: Accessible.Chart
        Accessible.name: qsTr("Live CPU and GPU power in watts. Only observed samples are shown.")
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const c=getContext("2d");c.reset()
            const l=46,r=8,t=8,b=28,w=width-l-r,h=height-t-b
            const span=Math.max(1,graph.now-graph.start)
            c.font="11px sans-serif"
            for(let i=0;i<=6;i++) {
                const y=t+h-i*h/6
                c.strokeStyle="#35414d";c.lineWidth=1;c.beginPath();c.moveTo(l,y);c.lineTo(width-r,y);c.stroke()
                c.fillStyle="#c3ccd5";c.textAlign="right";c.fillText(Math.round(graph.ceiling*i/6)+" W",l-8,y+4)
            }
            for(let i=0;i<=6;i++) {
                const x=l+w*i/6
                c.strokeStyle="#303c47";c.beginPath();c.moveTo(x,t);c.lineTo(x,t+h);c.stroke()
                const date=new Date((graph.start+span*i/6)*1000)
                const clock=String(date.getHours()).padStart(2,"0")+":"+String(date.getMinutes()).padStart(2,"0")+(span<600 ? ":"+String(date.getSeconds()).padStart(2,"0") : "")
                const label=i===6 ? qsTr("Now") : clock
                c.textAlign=i===0?"left":i===6?"right":"center";c.fillStyle="#c3ccd5";c.fillText(label,x,height-6)
            }
            for(const kind of ["gpu","cpu"]) {
                const color=kind==="gpu"?"#35c76a":"#43b8d4"
                let group=[]
                function draw() {
                    if(!group.length)return
                    c.beginPath()
                    group.forEach((p,i)=> {const x=l+(p.timestamp-graph.start)/span*w,y=t+h-p[kind]/graph.ceiling*h;i?c.lineTo(x,y):c.moveTo(x,y)})
                    c.strokeStyle=color;c.lineWidth=2.5;c.shadowColor=color;c.shadowBlur=graph.energy*8;c.stroke();c.shadowBlur=0
                    if(kind==="gpu" && group.length>1) {
                        c.lineTo(l+(group[group.length-1].timestamp-graph.start)/span*w,t+h)
                        c.lineTo(l+(group[0].timestamp-graph.start)/span*w,t+h);c.closePath()
                        c.globalAlpha=.16;c.fillStyle=color;c.fill();c.globalAlpha=1
                    }
                    group=[]
                }
                for(const p of graph.visiblePoints) {
                    if(typeof p[kind]!=="number" || (group.length && p.timestamp-group[group.length-1].timestamp>graph.maxGapSeconds))draw()
                    if(typeof p[kind]==="number")group.push(p)
                }
                draw()
            }
        }
    }
    RowLayout {
        Layout.leftMargin: 46; spacing: 8
        Rectangle { width: 10; height: 10; radius: 2; color: "#43b8d4" }
        Controls.Label { text: "CPU"; color: "#d6dfe8" }
        Rectangle { Layout.leftMargin: 12; width: 10; height: 10; radius: 2; color: "#35c76a" }
        Controls.Label { text: "GPU"; color: "#d6dfe8" }
        Item { Layout.fillWidth: true }
        Controls.Label { text: graph.visiblePoints.length < 2 ? qsTr("Waiting for live samples") : qsTr("Live history since window opened"); color: "#a7b3bf"; font.pointSize: 9 }
    }
}
