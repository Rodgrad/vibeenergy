.pragma library

function costTotals(rows, fallback) {
    const totals = {}
    rows.forEach(function(row) {
        const code = row.currency || fallback || ""
        totals[code] = (totals[code] || 0) + Number(row.cost || 0)
    })
    return totals
}

function formatCosts(totals) {
    return Object.keys(totals).sort().map(function(code) {
        const cost = totals[code]
        return cost.toFixed(3) + (code ? " " + code : "")
    }).join(" · ")
}

function money(rows, fallback) {
    return rows.length ? formatCosts(costTotals(rows, fallback)) : "—"
}

// Calendar arithmetic keeps every local date visible, including DST transitions.
function timeline(rows, start, end, fallbackCurrency) {
    const buckets = {}
    rows.forEach(function(row) {
        if (!buckets[row.day]) buckets[row.day] = {cpu: 0, gpu: 0, cost: 0, costs: {}, known: false, qualities: []}
        const bucket = buckets[row.day]
        bucket[row.kind] = (bucket[row.kind] || 0) + Number(row.kwh || 0)
        const code = row.currency || fallbackCurrency || ""
        bucket.costs[code] = (bucket.costs[code] || 0) + Number(row.cost || 0)
        bucket.cost = Object.keys(bucket.costs).length === 1 ? bucket.costs[code] : null
        bucket.known = true
        if (bucket.qualities.indexOf(row.quality) < 0) bucket.qualities.push(row.quality)
    })
    const cursor = new Date(start + "T12:00:00")
    const last = new Date(end + "T12:00:00")
    const result = []
    if (isNaN(cursor.getTime()) || isNaN(last.getTime())) return result
    while (cursor <= last && result.length < 36600) {
        const day = cursor.getFullYear() + "-" + String(cursor.getMonth()+1).padStart(2,"0") + "-" + String(cursor.getDate()).padStart(2,"0")
        const bucket = buckets[day] || {cpu: 0, gpu: 0, cost: 0, costs: {}, known: false, qualities: []}
        result.push({day: day, cpu: bucket.cpu, gpu: bucket.gpu, kwh: bucket.cpu+bucket.gpu,
                     cost: bucket.cost, costs: bucket.costs, known: bucket.known, qualities: bucket.qualities})
        cursor.setDate(cursor.getDate()+1)
    }
    return result
}
