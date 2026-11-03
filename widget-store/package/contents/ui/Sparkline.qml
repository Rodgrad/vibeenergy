import QtQuick
Canvas {
    id: graph
    property var points: []
    property string channel: "gpu"
    property color ink: "#35c76a"
    onPointsChanged: requestPaint()
    onChannelChanged: requestPaint()
    onInkChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    function reading(point) {
        if(channel!=="total") return point[channel]
        const cpu=typeof point.cpu==="number" && Number.isFinite(point.cpu)
        const gpu=typeof point.gpu==="number" && Number.isFinite(point.gpu)
        return cpu || gpu ? (cpu?point.cpu:0)+(gpu?point.gpu:0) : null
    }
    onPaint: {
        const c=getContext("2d");c.reset()
        let samples=[]
        for(const p of points.slice(-120)) {
            if(typeof reading(p)!=="number" || !Number.isFinite(reading(p))) { samples=[]; continue }
            if(samples.length && p.timestamp-samples[samples.length-1].timestamp>5)samples=[]
            samples.push(p)
        }
        const values=samples.map(p=>reading(p))
        if(values.length<2)return
        const low=Math.max(0,Math.min(...values)*.8),high=Math.max(low+1,Math.max(...values)*1.1)
        c.beginPath()
        values.forEach((v,i)=>{ const x=i/(values.length-1)*width,y=height-4-(v-low)/(high-low)*(height-8);i?c.lineTo(x,y):c.moveTo(x,y) })
        c.strokeStyle=ink;c.lineWidth=2;c.stroke()
        c.lineTo(width,height);c.lineTo(0,height);c.closePath();c.globalAlpha=.12;c.fillStyle=ink;c.fill()
    }
}
