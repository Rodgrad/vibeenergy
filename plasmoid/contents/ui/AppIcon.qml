import QtQuick
Canvas {
    id: icon
    property string kind: "cpu"
    property color ink: "#a7b3bf"
    implicitWidth: 24; implicitHeight: 24
    onKindChanged: requestPaint()
    onInkChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const c=getContext("2d"); c.reset(); c.scale(width/24,height/24)
        c.strokeStyle=ink; c.fillStyle=ink; c.lineWidth=1.7; c.lineJoin="round"; c.lineCap="round"
        function line(x,y,a,b) { c.beginPath(); c.moveTo(x,y); c.lineTo(a,b); c.stroke() }
        if (kind === "home") {
            c.beginPath(); c.moveTo(2,11); c.lineTo(12,2); c.lineTo(22,11); c.stroke()
            c.beginPath(); c.moveTo(5,9); c.lineTo(5,22); c.lineTo(10,22); c.lineTo(10,15); c.lineTo(15,15); c.lineTo(15,22); c.lineTo(19,22); c.lineTo(19,9); c.stroke()
        } else if (kind === "history") {
            line(2,22,22,22); c.strokeRect(4,12,3,8); c.strokeRect(10,6,3,14); c.strokeRect(16,2,3,18)
        } else if (kind === "settings") {
            c.beginPath(); c.arc(12,12,7,0,Math.PI*2); c.stroke(); c.beginPath(); c.arc(12,12,2.5,0,Math.PI*2); c.stroke()
            for(let i=0;i<8;i++){const a=i*Math.PI/4;line(12+Math.cos(a)*7,12+Math.sin(a)*7,12+Math.cos(a)*10,12+Math.sin(a)*10)}
        } else if (kind === "gpu") {
            c.strokeRect(3,5,18,13); line(1,3,1,20); line(5,21,9,21); line(12,21,16,21)
            c.beginPath(); c.arc(11,11.5,4,0,Math.PI*2); c.stroke(); line(18,8,18,10); line(18,13,18,15)
        } else if (kind === "bolt") {
            c.beginPath();c.moveTo(14,1);c.lineTo(4,14);c.lineTo(11,14);c.lineTo(9,23);c.lineTo(21,9);c.lineTo(13,9);c.closePath();c.fill()
        } else if (kind === "wave") {
            c.beginPath();c.moveTo(1,13);c.lineTo(6,13);c.lineTo(9,3);c.lineTo(13,22);c.lineTo(17,9);c.lineTo(20,13);c.lineTo(23,13);c.stroke()
        } else if (kind === "calendar") {
            c.strokeRect(3,5,18,16);line(3,10,21,10);line(7,2,7,7);line(17,2,17,7)
            for(let x=7;x<20;x+=5)for(let y=14;y<20;y+=4)c.fillRect(x,y,1.5,1.5)
        } else if (kind === "infinity") {
            c.beginPath();c.moveTo(12,12);c.bezierCurveTo(3,-2,-4,24,8,16);c.bezierCurveTo(14,12,17,2,21,8);c.bezierCurveTo(28,18,17,23,12,12);c.stroke()
        } else {
            c.strokeRect(5,5,14,14);c.strokeRect(8,8,8,8)
            for(let n=7;n<20;n+=4){line(n,1,n,4);line(n,20,n,23);line(1,n,4,n);line(20,n,23,n)}
        }
    }
}
