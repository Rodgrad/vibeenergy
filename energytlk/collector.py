import argparse
import ctypes
import fcntl
import json
import logging
import math
import os
import signal
import time
import uuid
from .config import paths, load, atomic_json, DEFAULTS
from .database import Database
from .energy import Integrator, day_slices
from .powerstat import discover_log
from .plain_powerstat import PlainPowerstat
from pathlib import Path
from .sensors import Sensors, reading


def main():
    parser = argparse.ArgumentParser(description='Unprivileged local CPU/GPU energy collector')
    parser.add_argument('--simulate', action='store_true', help='Use isolated demonstration database/state')
    parser.add_argument('--samples', type=int, default=0, help='Stop after N samples (0 means continuous)')
    parser.add_argument('--interval', type=int, help='Override interval for smoke testing')
    args = parser.parse_args()
    if os.geteuid() == 0:
        parser.error('Run as your regular user, never as root')
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
    os.umask(0o077)
    _, data, state = paths()
    if args.simulate:
        data, state = data/'demo', state/'demo'
    data.mkdir(parents=True, exist_ok=True)
    state.mkdir(parents=True, exist_ok=True)
    lock = (state/'collector.lock').open('w')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        parser.exit(0, 'Collector already running\n')
    # Signal handlers must not acquire locks. systemd and parent-death shutdown
    # can deliver overlapping SIGTERMs; Event.set() can deadlock on its own lock.
    stopping = False
    def request_stop(*_):
        nonlocal stopping
        stopping = True
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, request_stop)
    if os.environ.get('APPIMAGE'):
        # If the AppImage runtime is killed, stop before its mount disappears.
        parent = os.getppid()
        ctypes.CDLL(None).prctl(1, signal.SIGTERM, 0, 0, 0)
        if os.getppid() != parent:
            request_stop()
    db = Database(data/'energy.sqlite3')
    try:
        history_generation = json.loads((state/'state.json').read_text()).get('history_generation')
    except (OSError, ValueError):
        history_generation = None
    sensors, integrator = Sensors(), Integrator()
    session, count, previous, importer = str(uuid.uuid4()), 0, None, None
    config = DEFAULTS.copy()
    last_valid = db.last_valid()
    try:
        while not stopping:
            error = ''
            try:
                config = load()
            except (OSError, ValueError, TypeError) as exc:
                error = 'Settings rejected; using last valid settings: '+str(exc)
            if args.interval:
                config['interval'] = max(1, min(5, args.interval))
            interval = config['interval']
            wall, mono = time.time(), time.monotonic()
            boot = time.clock_gettime(time.CLOCK_BOOTTIME)
            resumed = previous and abs((boot-previous[2])-(mono-previous[1])) > .5
            if resumed:
                integrator.previous.clear()
                sensors.counters.clear()
            if args.simulate:
                readings = [reading('demo:cpu', 'Demo CPU package', 'cpu', 'simulation', 35+5*math.sin(count/4)),
                            reading('demo:gpu', 'Demo GPU', 'gpu', 'simulation', 80+10*math.sin(count/3))]
                for r in readings:
                    r['quality'] = 'estimated'
            else:
                readings = sensors.sample(interval)
            powerstat_path = discover_log(config['powerstat_log']) if not args.simulate else ''
            if powerstat_path:
                if importer is None or str(importer.path) != powerstat_path:
                    importer = PlainPowerstat(powerstat_path, db, cleanup=Path(powerstat_path).resolve() == (Path.home()/'.vibeenergy/logs/powerstat.log').resolve())
                cpus = [r for r in readings if r['kind'] == 'cpu']
                managed = False
                try:
                    with importer.path.open() as stream:
                        managed = stream.readline().startswith('# vibeenergy-accounted-v2')
                    managed = managed and 0 <= wall-importer.path.stat().st_mtime <= interval*2.5
                except OSError:
                    pass
                fallback = managed or all(r['watts'] is None for r in cpus)
                try:
                    sample, note, _ = importer.read(wall, interval*2.5, config['price'], account=fallback, currency=config['currency'])
                except OSError as exc:
                    sample, note = None, str(exc)
                if fallback:
                    item = reading('cpu:powerstat', 'CPU (external Powerstat scope)', 'cpu', 'Powerstat log', error=note)
                    if sample:
                        item.update(accounted_from_log=True, watts=sample[1], quality='imported from log',
                                    sample_timestamp=sample[0], energy_eligible=True)
                    readings = [r for r in readings if r['kind'] != 'cpu']+[item]
            segments = {}
            for r in readings:
                if r.get('accounted_from_log'):
                    integrator.previous.pop(r['id'], None)
                    continue
                if r.get('energy_eligible') is False:
                    integrator.previous.pop(r['id'], None)
                    continue
                if r.get('new_import') is False:
                    continue
                stamp = r.get('sample_timestamp', wall)
                segments[r['id']] = integrator.add(r, stamp, mono, boot, max(interval, r.get('logger_interval', interval)))
            # Clear disconnected devices, preventing reconnection from bridging missing measurements.
            active = {r['id'] for r in readings}
            integrator.previous = {k:v for k,v in integrator.previous.items() if k in active}
            observed = []
            if previous:
                ow, om, ob = previous
                dt = mono-om
                if 0 < dt <= interval*2.5 and abs((boot-ob)-dt) < .5 and abs(wall-ow-dt) < 1:
                    observed = list(day_slices(ow, wall, 0, 0))
            db.record(wall, session, readings, segments, observed, price=config['price'], currency=config['currency'])
            if count == 0 or count % 60 == 0 or (previous and time.localtime(previous[0]).tm_yday != time.localtime(wall).tm_yday):
                db.prune(config['retention_days'])
            for r in readings:
                if r['watts'] is not None:
                    last_valid[r['id']] = wall
                r['last_valid'] = last_valid.get(r['id'])
            snapshot = dict(timestamp=wall, session=session, running=True, simulated=args.simulate,
                config=config, history_generation=history_generation, error=error, powerstat_log=powerstat_path, devices=readings, daily=db.report(config['price']), currencies=db.branches(),
                observation=db.observations(), partial=any(r['watts'] is None or r.get('energy_eligible') is False for r in readings if r.get('account', True)))
            atomic_json(state/'state.json', snapshot)
            previous = wall, mono, boot
            count += 1
            if args.samples and count >= args.samples:
                break
            deadline = mono+max(.05, interval)
            while not stopping and time.monotonic()<deadline:
                time.sleep(min(.1, max(0, deadline-time.monotonic())))
    finally:
        sensors.close()
        db.close()
        try:
            snapshot['running'] = False
            atomic_json(state/'state.json', snapshot)
        except UnboundLocalError:
            pass
        lock.close()


if __name__ == '__main__':
    main()
