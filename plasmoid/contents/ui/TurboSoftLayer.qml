pragma ComponentBehavior: Bound
import QtQuick
Canvas {
    id: plasma
    property var effect
    property int interiorSlot: -1
    property int interiorSoundSlot: -1
    property var interiorPaths: []
    property var interiorHits: []
    property int strikeSlot: -1
    property int soundSlot: -1
    property var strikePoints: []
    property var strikeBranches: []
    property var impactVelocities: []
    property real strikeDelay: 0
    property real strikeDuration: .35
    renderStrategy: Canvas.Immediate
    onEffectChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Connections { target: plasma.effect || null; function onStrengthChanged() { plasma.requestPaint() } }
    Timer { interval: 33; repeat: true; running: plasma.effect && !plasma.effect.reducedMotion && plasma.visible; onTriggered: plasma.requestPaint() }
    onPaint: {
        const c=getContext("2d");c.reset()
        if(!effect)return
        const f=effect.frame, t=effect.reducedMotion?0:effect.time, o=effect.origin
        function ribbon(path,alpha) {
            for(const layer of [[40,.018],[24,.045],[12,.09],[5,.24],[1.5,.75],[.6,.8]]) {
                c.beginPath();path();c.lineWidth=layer[0];c.globalAlpha=alpha*layer[1]*effect.strength
                c.strokeStyle=effect.borderOnly ? (layer[0]<1?"#ebffdf":"#29ff70") : (layer[0]<1?"#b6faff":"#00cfff");c.stroke()
            }
        }
        function lightning(points,age,duration,scale) {
            if(points.length<2 || age<0 || age>duration+.4)return
            const end=Math.min(1,age/.09)*(points.length-1),whole=Math.floor(end),path=points.slice(0,whole+1)
            if(whole+1<points.length){const a=points[whole],b=points[whole+1];path.push(Qt.point(a.x+(b.x-a.x)*(end-whole),a.y+(b.y-a.y)*(end-whole)))}
            const light=age<.09?.8:age<duration?.55+.45*Math.exp(-(age-.09)*16):.18*Math.pow(1-(age-duration)/.4,2)
            for(const layer of [[85,.10],[34,.28],[5,.6],[2.1,.85],[.9,1]]) {
                if(layer[0]<1 && age>=duration)continue
                c.beginPath();path.forEach((p,j)=>j?c.lineTo(p.x,p.y):c.moveTo(p.x,p.y))
                c.lineWidth=layer[0];c.globalAlpha=light*scale*layer[1]*effect.strength
                c.strokeStyle=layer[0]<1?"#ebffff":"#00cfff";c.stroke()
            }
        }
        function flowRibbon(points,alpha,phase) {
            function periodic(d) { return Math.atan2(Math.sin(d*Math.PI*2),Math.cos(d*Math.PI*2))/(Math.PI*2) }
            for(let first=0;first<points.length-1;first+=4) {
                const last=Math.min(first+4,points.length-1),u=(first+last)/2/(points.length-1)
                const head=periodic(u-phase),tail=periodic(u-phase+.11)
                const light=.045+.72*Math.exp(-head*head/.004)+.26*Math.exp(-tail*tail/.033)
                ribbon(()=>{c.moveTo(points[first].x,points[first].y);for(let j=first+1;j<=last;j++)c.lineTo(points[j].x,points[j].y)},alpha*light)
            }
        }
        if(effect.reducedMotion) {
            if(!effect.backgroundLayer)ribbon(()=>c.rect(f.x+2,f.y+2,f.width-4,f.height-4),.7)
            return
        }
        if(effect.backgroundLayer) {
            for(let k=0;k<3;k++)ribbon(()=>{
                for(let i=0;i<=100;i++) {
                    const u=i/100,x=f.x+u*f.width,y=f.y+f.height*[.085,.46,.92][k]+Math.sin(u*7+t*.9+k)*26+Math.sin(u*13-t*.6)*8
                    i?c.lineTo(x,y):c.moveTo(x,y)
                }
            },k===0?.75:.3)
            return
        }
        const radius=effect.borderOnly?14:24,horizontal=Math.max(1,f.width-radius*2),vertical=Math.max(1,f.height-radius*2),arc=Math.PI/2*radius,perimeter=2*(horizontal+vertical)+4*arc
        function boundary(u) {
            let d=((u+1)%1)*perimeter
            if(d<horizontal)return Qt.point(f.x+radius+d,f.y);d-=horizontal
            if(d<arc){const a=-Math.PI/2+d/radius;return Qt.point(f.x+f.width-radius+Math.cos(a)*radius,f.y+radius+Math.sin(a)*radius)}d-=arc
            if(d<vertical)return Qt.point(f.x+f.width,f.y+radius+d);d-=vertical
            if(d<arc){const a=d/radius;return Qt.point(f.x+f.width-radius+Math.cos(a)*radius,f.y+f.height-radius+Math.sin(a)*radius)}d-=arc
            if(d<horizontal)return Qt.point(f.x+f.width-radius-d,f.y+f.height);d-=horizontal
            if(d<arc){const a=Math.PI/2+d/radius;return Qt.point(f.x+radius+Math.cos(a)*radius,f.y+f.height-radius+Math.sin(a)*radius)}d-=arc
            if(d<vertical)return Qt.point(f.x,f.y+f.height-radius-d);d-=vertical
            const a=Math.PI+d/radius;return Qt.point(f.x+radius+Math.cos(a)*radius,f.y+radius+Math.sin(a)*radius)
        }
        const originPhase=(horizontal+arc+Math.max(0,Math.min(vertical,o.y-f.y-radius)))/perimeter
        for(let k=0;k<2;k++) {
            const points=[]
            for(let i=0;i<=200;i++) {
                const u=i/200,p=boundary(u),next=boundary(u+.0001),dx=next.x-p.x,dy=next.y-p.y,length=Math.max(.001,Math.sqrt(dx*dx+dy*dy))
                const wave=-2+k*5+Math.sin(u*Math.PI*6-t*.85+k)*6+Math.sin(u*Math.PI*14+t*.55)*2
                const swell=effect.borderOnly?-1+k*5+wave*1.5:wave
                points.push(Qt.point(p.x+dy/length*swell,p.y-dx/length*swell))
            }
            flowRibbon(points,effect.borderOnly?(k===0?2:1.4):(k===0?1.55:1.05),(originPhase+t*(k===0?.18:-.13)+k*.42+2)%1)
        }
        if(effect.borderOnly)return
        for(let k=0;k<3;k++) {
            const points=[]
            for(let i=0;i<=100;i++){
                const a=i/100*Math.PI*2,r=1+.12*Math.sin(a*2-t*1.5+k)+.05*Math.sin(a*5+t*.7)
                points.push(Qt.point(o.x+Math.cos(a)*(100+k*15)*r,o.y+Math.sin(a)*(45+k*11)*r))
            }
            flowRibbon(points,.85-k*.15,(t*.28+k*.31)%1)
        }
        if(t<1)ribbon(()=>c.ellipse(o.x-t*f.width,o.y-t*f.height,t*f.width*2,t*f.height*2),.5*(1-t))
        if(t%1.25<.18)ribbon(()=>{
            for(let i=0;i<=20;i++){
                const u=i/20,x=o.x+(f.x+f.width-o.x)*u,y=o.y-90*u+Math.sin(i*2.1+t*13)*4*Math.sin(u*Math.PI)
                i?c.lineTo(x,y):c.moveTo(x,y)
            }
        },.65)
        const slot=Math.floor((t-.8)/2.1)
        if(slot>=0 && (effect.continuous || slot<2)) {
            if(strikeSlot!==slot) {
                strikeSlot=slot;strikeDelay=Math.random()*.3;strikeDuration=.32+Math.random()*.12
                const direction=Math.floor(Math.random()*4)
                let from,to
                if(direction===0){from=Qt.point(f.x+f.width*(.2+Math.random()*.6),f.y+20);to=Qt.point(f.x+f.width*(.2+Math.random()*.6),f.y+f.height)}
                else if(direction===1){from=Qt.point(f.x+20,f.y+20);to=Qt.point(f.x+f.width,f.y+f.height)}
                else if(direction===2){from=Qt.point(f.x+f.width-20,f.y+20);to=Qt.point(f.x,f.y+f.height)}
                else{from=Qt.point(f.x+20,f.y+f.height*(.2+Math.random()*.6));to=Qt.point(f.x+f.width,f.y+f.height*(.2+Math.random()*.6))}
                const dx=to.x-from.x,dy=to.y-from.y,length=Math.max(1,Math.sqrt(dx*dx+dy*dy)),points=[]
                for(let i=0;i<=32;i++){const u=i/32,offset=(Math.random()-.5)*65*Math.sin(u*Math.PI);points.push(Qt.point(from.x+dx*u-dy/length*offset,from.y+dy*u+dx/length*offset))}
                strikePoints=points
                const branches=[]
                if(slot%2===1) for(let branch=0;branch<2;branch++) {
                    const start=points[branch===0?11:22],side=branch===0?1:-1
                    const end=Qt.point(Math.max(f.x+12,Math.min(f.x+f.width-12,start.x+dx*.16-dy/length*side*Math.min(180,length*.22))),Math.max(f.y+12,Math.min(f.y+f.height-12,start.y+dy*.16+dx/length*side*Math.min(180,length*.22))))
                    const path=[]
                    for(let i=0;i<=12;i++){const u=i/12,offset=(Math.random()-.5)*30*Math.sin(u*Math.PI);path.push(Qt.point(start.x+(end.x-start.x)*u-dy/length*offset,start.y+(end.y-start.y)*u+dx/length*offset))}
                    branches.push(path)
                }
                strikeBranches=branches
                const inward=Math.atan2(f.y+f.height/2-to.y,f.x+f.width/2-to.x),velocities=[]
                for(let i=0;i<48;i++){let a=inward+(Math.random()-.5)*3.4,speed=110+Math.random()*260;if(i<12){a=inward+Math.PI+(Math.random()-.5)*1.2;speed=38+Math.random()*22}velocities.push(Qt.point(Math.cos(a)*speed,Math.sin(a)*speed))}
                impactVelocities=velocities
            }
            const age=t-(.8+slot*2.1+strikeDelay)
            lightning(strikePoints,age,strikeDuration,1)
            strikeBranches.forEach((path,j)=>lightning(path,age-.025*(j+1),strikeDuration,.7))
            const impactAge=age-.09
            if(impactAge>=0 && impactAge<.95 && strikePoints.length) {
                if(soundSlot!==slot){soundSlot=slot;effect.lightningHit()}
                const tips=[strikePoints[strikePoints.length-1],...strikeBranches.map(branch=>branch[branch.length-1])]
                for(const hit of tips) {
                const edgeDistance=Math.min(Math.abs(hit.x-f.x),Math.abs(hit.x-f.x-f.width),Math.abs(hit.y-f.y),Math.abs(hit.y-f.y-f.height))
                if(edgeDistance>1)continue
                const fade=Math.pow(1-impactAge/.95,2),radius=100+impactAge*65
                const glow=c.createRadialGradient(hit.x,hit.y,0,hit.x,hit.y,radius)
                glow.addColorStop(0,"#b6faff");glow.addColorStop(.15,"#00d9ff");glow.addColorStop(1,"transparent")
                c.globalAlpha=fade*effect.strength*.85;c.fillStyle=glow;c.fillRect(hit.x-radius,hit.y-radius,radius*2,radius*2)
                for(const v of impactVelocities) {
                    const x=hit.x+v.x*impactAge,y=hit.y+v.y*impactAge+65*impactAge*impactAge
                    c.beginPath();c.moveTo(x,y);c.lineTo(x-v.x*.04,y-v.y*.04);c.globalAlpha=fade*effect.strength*.8;c.strokeStyle="#b6faff";c.lineWidth=2;c.stroke()
                }
                }
            }
        }
        const interior=Math.floor((t-1.8)/3.5)
        if(interior>=0 && (effect.continuous || interior===0)) {
            if(interiorSlot!==interior) {
                interiorSlot=interior
                const origin=Qt.point(f.x+f.width*(.25+Math.random()*.5),f.y+f.height*(.25+Math.random()*.5)),heading=Math.random()*Math.PI*2,paths=[],hits=[]
                for(let branch=0;branch<3;branch++) {
                    const angle=heading+branch*Math.PI*2/3+(Math.random()-.5)*.6,dx=Math.cos(angle),dy=Math.sin(angle)
                    const edge=Math.min(dx>0?(f.x+f.width-origin.x)/dx:(f.x-origin.x)/dx,dy>0?(f.y+f.height-origin.y)/dy:(f.y-origin.y)/dy)
                    const hit=branch===0 || Math.random()<.35,distance=hit?edge:edge*(.3+Math.random()*.35),path=[]
                    for(let j=0;j<=20;j++){const u=j/20,offset=(Math.random()-.5)*42*Math.sin(u*Math.PI);path.push(Qt.point(origin.x+dx*distance*u-dy*offset,origin.y+dy*distance*u+dx*offset))}
                    paths.push(path);hits.push(hit)
                }
                interiorPaths=paths;interiorHits=hits
            }
            const age=t-(1.8+interior*3.5)
            for(const path of interiorPaths)lightning(path,age,.38,.8)
            if(age>=.09 && age<.8) {
                if(interiorSoundSlot!==interior){interiorSoundSlot=interior;effect.lightningHit()}
                const elapsed=age-.09,fade=Math.pow(1-elapsed/.71,2)
                for(let branch=0;branch<interiorPaths.length;branch++) if(interiorHits[branch]) {
                    const path=interiorPaths[branch],hit=path[path.length-1],radius=65,glow=c.createRadialGradient(hit.x,hit.y,0,hit.x,hit.y,radius)
                    glow.addColorStop(0,"#b6faff");glow.addColorStop(.2,"#00d9ff");glow.addColorStop(1,"transparent")
                    c.globalAlpha=fade*effect.strength*.7;c.fillStyle=glow;c.fillRect(hit.x-radius,hit.y-radius,radius*2,radius*2)
                    for(let j=0;j<20;j++){const a=j*2.399963,vx=Math.cos(a)*(65+j*5),vy=Math.sin(a)*(65+j*5),x=hit.x+vx*elapsed,y=hit.y+vy*elapsed;c.beginPath();c.moveTo(x,y);c.lineTo(x-vx*.035,y-vy*.035);c.globalAlpha=fade*effect.strength*.9;c.strokeStyle="#b6faff";c.lineWidth=1.6;c.stroke()}
                }
            }
        }
        for(let k=0;k<3;k++) {
            const age=(effect.continuous?t%5.2:t)-(1.5+k*1.13)
            if(age<0 || age>.27)continue
            const from=boundary(.13+k*.29),dx=f.x+f.width/2-from.x,dy=f.y+f.height/2-from.y,length=Math.max(1,Math.sqrt(dx*dx+dy*dy))
            ribbon(()=>{for(let i=0;i<=12;i++){const u=i/12,offset=Math.sin(i*2.7+k)*9*Math.sin(u*Math.PI),x=from.x+dx/length*u*(90+k*24)-dy/length*offset,y=from.y+dy/length*u*(90+k*24)+dx/length*offset;i?c.lineTo(x,y):c.moveTo(x,y)}},Math.sin(age/.27*Math.PI)*.65)
        }
        for(let i=0;i<32;i++){
            const u=(i/32+t*.027)%1,x=i%2?f.x+f.width-10-Math.sin(t+i)*15:f.x+u*f.width,y=i%2?f.y+u*f.height:f.y+12+Math.sin(u*7+t)*18
            c.globalAlpha=effect.strength*.55;c.fillStyle="#9cefff";c.fillRect(x,y,2,2)
        }
    }
}
