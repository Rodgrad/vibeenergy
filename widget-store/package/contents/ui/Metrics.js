.pragma library
function watts(devices, kind) {
    const values=devices.filter(r => (!kind || r.kind===kind) && r.account!==false && typeof r.watts==='number' && isFinite(r.watts) && r.watts>=0)
    return values.length ? values.reduce((total,r)=>total+r.watts,0) : null
}
function summary(rows,currency,start,end) {
    const selected=rows.filter(r=>typeof r.day==='string' && r.day>=start && r.day<=end)
    return {
        kwh:selected.reduce((total,r)=>total+(typeof r.kwh==='number' && isFinite(r.kwh) ? r.kwh : 0),0),
        cost:selected.filter(r=>(r.currency || currency)===currency).reduce((total,r)=>total+(typeof r.cost==='number' && isFinite(r.cost) ? r.cost : 0),0),
        hasEnergy:selected.length>0,
        hasCost:selected.some(r=>(r.currency || currency)===currency)
    }
}
function day(date) {
    return date.getFullYear()+'-'+String(date.getMonth()+1).padStart(2,'0')+'-'+String(date.getDate()).padStart(2,'0')
}

function isFresh(snapshot, now) {
    if(snapshot.running !== true || typeof snapshot.timestamp !== "number" || !isFinite(snapshot.timestamp)) return false
    const age=now-snapshot.timestamp
    return age>=-5 && age<5
}
function warningDue(lastRefresh, now) {
    return now-lastRefresh>=5
}

// Appearance settings remain readable even with older app versions.
function turboState(text, now) {
    const parts=String(text).split("\n---VIBEENERGY-TURBO---\n")
    const alwaysOn=/^turboAlwaysOn\s*=\s*true\s*$/m.test(parts[0])
    let until=0
    try { until=JSON.parse(parts[1]).until } catch(error) {}
    return {continuous:alwaysOn, active:alwaysOn || (typeof until==="number" && isFinite(until) && until>now && until<=now+60)}
}
