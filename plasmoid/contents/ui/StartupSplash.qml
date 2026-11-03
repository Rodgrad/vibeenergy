import QtQuick
import QtQuick.Window
import QtMultimedia

Window {
    id: splash
    width: 620; height: 320
    // Native launcher selects the launch monitor before this window is shown.
    visible: false
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowTransparentForInput | Qt.WindowDoesNotAcceptFocus
    title: "VibeEnergy — Starting"
    property bool presented: false
    MediaPlayer {
        id: splashAudio
        source: splashElectricSource
        autoPlay: false
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput { volume: 0.03 }
    }
    property real phase: 0
    property real reveal: 0
    property real strike: 1
    property real emblem: 0
    property real ignition: 0
    onPresentedChanged: if(presented && String(splashElectricSource).length>0) splashAudio.play()
    NumberAnimation on ignition { running: splash.presented; from: 0; to: 1; duration: 2600 }
    SequentialAnimation {
        running: splash.presented
        NumberAnimation { target: splash; property: "strike"; from: 0; to: 1; duration: 110 }
        PauseAnimation { duration: 140 }
        ParallelAnimation {
            NumberAnimation { target: splash; property: "strike"; to: 0; duration: 480; easing.type: Easing.OutCubic }
            NumberAnimation { target: splash; property: "emblem"; to: 1; duration: 240; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: 100 }
                NumberAnimation { target: splash; property: "reveal"; to: 1; duration: 650; easing.type: Easing.OutCubic }
            }
        }
    }
    onStrikeChanged: field.requestPaint()
    onEmblemChanged: field.requestPaint()
    NumberAnimation on phase { running: splash.presented; from: 0; to: Math.PI*2; duration: 2200; loops: Animation.Infinite }
    onPhaseChanged: field.requestPaint()
    Canvas {
        id: skyBolt
        anchors.fill: parent
        Connections { target: splash; function onStrikeChanged() { skyBolt.requestPaint() } }
        onPaint: {
            const ctx=getContext("2d"); ctx.reset()
            if(splash.strike<=0) return
            ctx.translate(width/2-310,0)
            let points=[[330,-20],[278,height*.14],[339,height*.25],[267,height*.39],
                          [324,height*.49],[286,height*.61],[350,height*.73],[294,height*.87],[318,height+20]]
            const power=splash.strike
            ctx.lineJoin="round"; ctx.lineCap="round"
            const widths=[95,48,22,10], colors=["rgba(0,125,255,","rgba(0,175,255,","rgba(30,218,255,","rgba(255,255,255,"]
            const alphas=[.15,.4,.95,1]
            for(let n=0;n<widths.length;n++) {
                ctx.beginPath(); ctx.moveTo(points[0][0],points[0][1])
                for(let k=1;k<points.length;k++) ctx.lineTo(points[k][0],points[k][1])
                ctx.lineWidth=widths[n];ctx.strokeStyle=colors[n]+(alphas[n]*power)+")";ctx.stroke()
            }
        }
    }
    Item {
    id: artwork
    objectName: "splashArtwork"
    width: 620; height: 320
    anchors.centerIn: parent
    Canvas {
        id: field
        anchors.fill: parent
        onPaint: {
            const ctx=getContext("2d"); ctx.reset()
            const p=splash.phase
            ctx.lineCap="round"; ctx.lineJoin="round"
            function stroke(points,width,color) {
                ctx.beginPath(); ctx.moveTo(points[0][0],points[0][1])
                for(let i=1;i<points.length;i++) ctx.lineTo(points[i][0],points[i][1])
                ctx.lineWidth=width; ctx.strokeStyle=color; ctx.stroke()
            }
            // Soft layered light stays entirely inside this temporary window.
            // The impact leaves a solid lightning emblem behind the wordmark.
            const glow=ctx.createRadialGradient(310,154,6,310,154,100)
            glow.addColorStop(0,"rgba(0,190,255,"+(.16*splash.emblem)+")")
            glow.addColorStop(1,"rgba(0,145,255,0)")
            ctx.fillStyle=glow; ctx.fillRect(210,54,200,200)
            ctx.save(); ctx.globalAlpha=splash.emblem
            ctx.beginPath(); ctx.moveTo(330,67); ctx.lineTo(278,154)
            ctx.lineTo(308,154); ctx.lineTo(289,237); ctx.lineTo(350,133)
            ctx.lineTo(319,133); ctx.closePath()
            ctx.fillStyle="rgba(12,78,112,.85)"; ctx.fill()
            ctx.strokeStyle="rgba(48,167,208,.65)"; ctx.lineWidth=1.5; ctx.stroke()
            ctx.restore()
            // A moving head and fading tail follow the actual lightning outline.
            const outline=[[330,67],[278,154],[308,154],[289,237],[350,133],[319,133],[330,67]]
            let lengths=[], perimeter=0
            for(let k=1;k<outline.length;k++) {
                const dx=outline[k][0]-outline[k-1][0],dy=outline[k][1]-outline[k-1][1]
                const length=Math.sqrt(dx*dx+dy*dy); lengths.push(length); perimeter+=length
            }
            function edgePoint(distance) {
                distance=((distance%perimeter)+perimeter)%perimeter
                for(let k=0;k<lengths.length;k++) {
                    if(distance<=lengths[k]) {
                        const t=distance/lengths[k]
                        return [outline[k][0]+(outline[k+1][0]-outline[k][0])*t,
                                outline[k][1]+(outline[k+1][1]-outline[k][1])*t]
                    }
                    distance-=lengths[k]
                }
                return outline[0]
            }
            for(let head=0;head<2;head++) {
                const position=p/(Math.PI*2)*perimeter+head*perimeter/2
                for(let tail=23;tail>=0;tail--) {
                    const light=(1-tail/24)*splash.emblem
                    const segment=[edgePoint(position-tail*3),edgePoint(position-tail*3+3)]
                    stroke(segment,13,"rgba(0,170,255,"+(.12*light)+")")
                    stroke(segment,5,"rgba(0,215,255,"+(.45*light)+")")
                    stroke(segment,1.8,"rgba(210,255,255,"+light+")")
                }
            }
            // Bounded electrical forks crawl around the emblem and wordmark.
            const tick=Math.floor(p*14)
            for(let arm=0;arm<4;arm++) {
                const side=arm%2===0 ? -1 : 1
                const y0=arm<2 ? 117 : 204
                let arc=[[310+side*20,y0]]
                for(let j=1;j<=9;j++) {
                    const x=310+side*(20+j*23)
                    const y=y0+Math.sin(j*2.7+tick+arm)*9+Math.sin(j*.65+arm)*14
                    arc.push([x,y])
                }
                const intensity=(.35+.65*Math.pow(Math.max(0,Math.sin(p*3+arm)),4))*splash.emblem
                stroke(arc,12,"rgba(0,160,255,"+(.12*intensity)+")")
                stroke(arc,4,"rgba(0,195,255,"+(.35*intensity)+")")
                stroke(arc,1.3,"rgba(164,246,255,"+intensity+")")
                const fork=[arc[5],[arc[5][0]+side*15,arc[5][1]-18],[arc[5][0]+side*35,arc[5][1]-25]]
                stroke(fork,1,"rgba(90,223,255,"+(.7*intensity)+")")
            }
            for(let n=0;n<3;n++) {
                let points=[]
                for(let i=0;i<=100;i++) {
                    let a=i/100*Math.PI*2
                    points.push([310+245*Math.cos(a),168+58*Math.sin(a)+5*Math.sin(a*5+p+n)])
                }
                stroke(points,n===0?8:1,n===0?"rgba(0,160,255,.10)":"rgba(36,211,255,.32)")
            }
            for(let n=0;n<6;n++) {
                let a=p+n*Math.PI/3
                const x=310+245*Math.cos(a), y=168+58*Math.sin(a)
                ctx.fillStyle="#99f3ff"; ctx.beginPath(); ctx.arc(x,y,1.7,0,Math.PI*2); ctx.fill()
            }
        }
    }
    Row {
        objectName: "splashWordmark"
        anchors.centerIn: parent; spacing: 0
        Text {
            text: "Vibe"; color: "#f0f3f6"; font.pixelSize: 52; font.bold: true
            opacity: splash.reveal
            transform: Translate { x: -140*(1-splash.reveal) }
        }
        Text {
            text: "Energy"; color: "#bde8f5"; font.pixelSize: 52; font.bold: true
            opacity: splash.reveal
            transform: Translate { x: 140*(1-splash.reveal) }
        }
    }
    Text { anchors.horizontalCenter: parent.horizontalCenter; y: 247; text: "Starting your energy monitor…"; color: "#a7b3bf"; font.pixelSize: 14; opacity: splash.reveal }
    }
}
