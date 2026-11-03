"""Session-local integration. Unknown intervals never produce energy."""
import math
from datetime import datetime, timedelta


def counter_delta(previous, current, maximum):
    if min(previous, current) < 0 or maximum <= 0 or max(previous, current) > maximum:
        raise ValueError('Invalid counter range')
    return current - previous if current >= previous else maximum - previous + current


def day_slices(start, end, watts0, watts1):
    """Split a linear power interval at local midnights, including DST days."""
    total = end - start
    if total <= 0:
        return
    cursor = start
    while cursor < end:
        local = datetime.fromtimestamp(cursor)
        midnight = datetime.combine(local.date()+timedelta(days=1), datetime.min.time()).timestamp()
        stop = min(end, midnight)
        a, b = (cursor-start)/total, (stop-start)/total
        wa, wb = watts0+(watts1-watts0)*a, watts0+(watts1-watts0)*b
        yield local.date().isoformat(), (wa+wb)/2*(stop-cursor)/3600, stop-cursor
        cursor = stop


class Integrator:
    def __init__(self):
        self.previous = {}

    def add(self, reading, wall, mono, boot, interval):
        key = reading['id']
        old = self.previous.pop(key, None)
        watts = reading.get('watts')
        if watts is None or not math.isfinite(watts) or watts < 0 or not reading.get('account', True):
            return []
        self.previous[key] = (wall, mono, boot, watts, reading['source'], reading['quality'])
        if old is None:
            return []
        ow, om, ob, op, source, quality = old
        dt = mono-om
        # CLOCK_BOOTTIME includes suspend; MONOTONIC does not. Reject either gaps or clock jumps.
        if (source != reading['source'] or quality != reading['quality'] or dt <= 0 or
                dt > interval*2.5 or abs((boot-ob)-dt) > 0.5 or abs((wall-ow)-dt) > 1):
            return []
        # RAPL is already interval-averaged, so use its exact counter-derived energy.
        p0 = watts if reading.get('interval_average') else op
        return list(day_slices(ow, wall, p0, watts))
