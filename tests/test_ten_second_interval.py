"""Exercise the collector with a saved 10-second interval and 1-second CPU logs."""
import datetime
import json
import os
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from energytlk import collector
from energytlk.config import DEFAULTS
from energytlk.sensors import reading


class TenSecondIntervalTests(unittest.TestCase):
    def test_saved_interval_across_midnight(self):
        with tempfile.TemporaryDirectory(prefix='vibeenergy-10s-') as temp:
            root = Path(temp)
            home = root / 'home'
            log = home / '.vibeenergy/logs/powerstat.log'
            log.parent.mkdir(parents=True)
            log.write_text('Time Watts core pkg-0\n')
            inode = log.stat().st_ino
            settings = dict(DEFAULTS, interval=10, price=.2, currency='EUR', history_currencies=[])
            start = datetime.datetime(2026, 4, 1, 23, 59, 40).timestamp()
            clock = {'elapsed': 0., 'last': int(start)-1}
            def sleep(duration):
                clock['elapsed'] += duration
            fake_time = types.SimpleNamespace(
                time=lambda: start+clock['elapsed'],
                monotonic=lambda: clock['elapsed'],
                clock_gettime=lambda _: clock['elapsed'], CLOCK_BOOTTIME=7,
                sleep=sleep, localtime=collector.time.localtime)
            sensors = Mock()
            def sample(interval):
                self.assertEqual(interval, 10)
                now = int(round(start+clock['elapsed']))
                with log.open('a') as writer:
                    for stamp in range(clock['last']+1, now+1):
                        writer.write(datetime.datetime.fromtimestamp(stamp).strftime('%H:%M:%S')+' 999 800 120\n')
                clock['last'] = now
                os.utime(log, (now, now))
                return [reading('cpu:0', 'CPU', 'cpu', 'RAPL', error='Permission denied'),
                        reading('gpu:0', 'GPU', 'gpu', 'NVIDIA', 100)]
            sensors.sample.side_effect = sample
            snapshots = []
            real_atomic = collector.atomic_json
            def capture(path, snapshot):
                snapshots.append(json.loads(json.dumps(snapshot)))
                real_atomic(path, snapshot)
            old_umask = os.umask(0o077)
            try:
                with patch.object(collector, 'paths', return_value=(root/'config', root/'data', root/'state')), \
                     patch.object(collector, 'load', return_value=settings), \
                     patch('energytlk.config.load', return_value=settings), \
                     patch.object(Path, 'home', return_value=home), \
                     patch('energytlk.powerstat.DEFAULT_LOG_PATH', log), \
                     patch.object(collector, 'time', fake_time), \
                     patch.object(collector, 'Sensors', return_value=sensors), \
                     patch.object(collector.signal, 'signal'), \
                     patch.object(collector, 'atomic_json', side_effect=capture), \
                     patch.dict(os.environ, {'APPIMAGE': ''}), \
                     patch('sys.argv', ['vibeenergy', '--samples', '5']):
                    collector.main()
            finally:
                os.umask(old_umask)
            active = [s for s in snapshots if s['running']]
            self.assertEqual(len(active), 5)
            cpu_seconds = [sum(r['covered_seconds'] for r in s['daily'] if r['kind']=='cpu') for s in active]
            self.assertEqual(cpu_seconds, [0, 10, 20, 20, 30])
            rows = active[-1]['daily']
            cpu = [r for r in rows if r['kind']=='cpu']
            gpu = [r for r in rows if r['kind']=='gpu']
            self.assertEqual(sum(r['covered_seconds'] for r in gpu), 40)
            self.assertAlmostEqual(sum(r['kwh'] for r in cpu), 120*30/3600000)
            self.assertAlmostEqual(sum(r['cost'] for r in cpu), 120*30/3600000*.2)
            self.assertAlmostEqual(sum(r['kwh'] for r in gpu), 100*40/3600000)
            self.assertEqual(log.stat().st_ino, inode)
            self.assertIn('# vibeenergy-collector-v3', log.read_text())
            print('\nSaved app interval=10s, Powerstat rows=1s: CPU covered seconds '
                  '[0, 10, 20, 20, 30] at 23:59:40, 23:59:50, 00:00:00, 00:00:10, 00:00:20. '
                  'CPU omits 00:00:00–00:00:10; GPU accounts all 40 seconds.', flush=True)
