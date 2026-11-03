import datetime
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from energytlk.database import Database
from energytlk.powerstat import PowerstatLog
from energytlk.powerstat_logger import Recorder


class RecorderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.log = self.root/'powerstat.log'
        self.log.touch()
        self.db = Database(self.root/'energy.sqlite3')
        self.addCleanup(self.db.close)
        self.now = datetime.datetime(2026, 10, 31, 23, 59, 59).timestamp()
        self.boot = 100
        self.price = .2
        self.recorder = self.new_recorder()
        self.recorder.accept('Time Watts pkg-0\n')

    def new_recorder(self):
        return Recorder(self.log, self.db, lambda: self.price, lambda: self.now, lambda: self.boot)

    def sample(self, seconds=1, watts=3600):
        self.now += seconds
        self.boot += seconds
        self.recorder.accept('12:00:00 999 '+str(watts)+'\n')

    def test_currency_switch_records_new_cpu_cost_in_its_own_branch(self):
        currency = ['EUR']
        self.recorder.currency = lambda: currency[0]
        self.sample(0); self.sample()
        currency[0] = 'USD'
        self.price = .5
        self.sample()
        rows = self.db.report(99)
        totals = {code: sum(r['cost'] for r in rows if r['currency'] == code) for code in ('EUR', 'USD')}
        self.assertAlmostEqual(totals['EUR'], .0002)
        self.assertAlmostEqual(totals['USD'], .0005)

    def test_midnight_summaries_survive_raw_cleanup_and_tariff_change(self):
        self.sample(0)
        self.sample(2)
        rows = self.db.report(.9)
        self.assertEqual([r['day'] for r in rows], ['2026-10-31','2026-11-01'])
        self.assertAlmostEqual(sum(r['kwh'] for r in rows), .002)
        self.assertAlmostEqual(sum(r['cost'] for r in rows), .0004)
        self.assertNotIn('# day=2026-10-31', self.log.read_text())
        self.assertIn('# day=2026-11-01', self.log.read_text())
        reader = PowerstatLog(self.log)
        self.assertEqual(reader.read(self.now, 3)[0][1], 3600)
        self.assertTrue(reader.accounted)

    def test_restart_after_days_off_never_bridges_gap(self):
        self.sample(0)
        self.sample()
        before = self.db.report(.2)
        self.now += 3*86400
        self.boot += 3*86400
        self.recorder = self.new_recorder()
        self.recorder.accept('Time Watts pkg-0\n')
        self.sample(0)
        self.assertEqual(self.db.report(.2), before)
        self.sample()
        self.assertAlmostEqual(sum(r['kwh'] for r in self.db.report(.2)), .002)
        self.assertNotIn('# day=2026-10-31', self.log.read_text())

    def test_size_cap_keeps_summary_and_header(self):
        self.sample(0)
        with patch('energytlk.powerstat_logger.MAX_RAW_BYTES', 512):
            for _ in range(30):
                self.sample()
                self.assertLessEqual(self.log.stat().st_size, 512)
        self.assertAlmostEqual(sum(r['kwh'] for r in self.db.report(.2)), .03)
        reader = PowerstatLog(self.log)
        self.assertIsNotNone(reader.read(self.now, 3)[0])

    def test_raw_file_contains_only_current_day_across_multiple_days(self):
        # Header timestamps must roll over too, not just the sample rows.
        for day in range(4):
            self.now = datetime.datetime(2026, 11, 1+day, 12).timestamp()
            self.boot += 86400
            for _ in range(10):
                self.sample()
            expected = datetime.datetime.fromtimestamp(self.now).date().isoformat()
            lines = self.log.read_text().splitlines()
            self.assertEqual(lines[1], '# day='+expected)
            for line in lines:
                if not line.startswith('#'):
                    self.assertTrue(line.startswith(expected+'T'), line)
        self.assertEqual(len({r['day'] for r in self.db.report(.2)}), 4)

    def test_real_40_mib_cap_truncates_file_without_erasing_daily_totals(self):
        from energytlk.powerstat_logger import MAX_RAW_BYTES
        self.sample(0)
        self.sample()
        before = sum(r['kwh'] for r in self.db.report(.2))
        with self.log.open('r+') as stream:
            stream.truncate(MAX_RAW_BYTES)
        self.sample()
        self.assertLess(self.log.stat().st_size, 1024)
        self.assertAlmostEqual(sum(r['kwh'] for r in self.db.report(.2)), before+.001)

    def test_raw_pruning_after_three_days_keeps_today_and_both_device_totals(self):
        from energytlk.sensors import reading
        today = datetime.datetime.combine(datetime.date.today(), datetime.time())
        readings = [reading('cpu:test','CPU','cpu','RAPL',100), reading('gpu:test','GPU','gpu','NVIDIA',200)]
        for age in (3, 0):
            stamp = (today-datetime.timedelta(days=age, hours=-12)).timestamp()
            day = datetime.datetime.fromtimestamp(stamp).date().isoformat()
            segments = {r['id']: [(day, 1, 1)] for r in readings}
            self.db.record(stamp, 'test', readings, segments, price=.2)
        before = self.db.report(.2)
        self.db.prune(1)
        remaining = self.db.db.execute('SELECT timestamp, kind FROM samples').fetchall()
        self.assertEqual(len(remaining), 2)
        self.assertTrue(all(stamp >= today.timestamp() for stamp, _ in remaining))
        self.assertEqual(self.db.report(.2), before)

    def test_clock_jump_and_powerstat_restart_do_not_bridge(self):
        self.sample(0)
        self.sample(10)
        self.recorder.accept('Running for 3600 seconds\n')
        self.sample()
        self.assertEqual(self.db.report(.2), [])

    def test_tariff_is_saved_when_energy_is_recorded(self):
        self.sample(0)
        self.sample()
        self.price = .4
        self.sample()
        self.assertAlmostEqual(sum(r['cost'] for r in self.db.report(99)), .0006)

    def test_cpu_and_gpu_keep_daily_costs_after_shared_raw_pruning(self):
        from energytlk.sensors import reading
        from datetime import date, timedelta
        from energytlk.energy import day_slices
        midnight = datetime.datetime.combine(date.today(), datetime.time()).timestamp()
        readings = [reading('cpu:test', 'CPU', 'cpu', 'RAPL', 100),
                    reading('gpu:test', 'GPU', 'gpu', 'NVIDIA', 200)]
        segments = {r['id']: list(day_slices(midnight-1, midnight+1, r['watts'], r['watts'])) for r in readings}
        self.db.record(midnight-1, 'test', readings, segments, price=.2)
        self.db.prune(1)
        self.assertEqual(self.db.db.execute('SELECT count(*) FROM samples').fetchone()[0], 0)
        rows = self.db.report(99)
        self.assertEqual(len(rows), 4)
        self.assertEqual({r['kind'] for r in rows}, {'cpu','gpu'})
        self.assertAlmostEqual(sum(r['kwh'] for r in rows), 600/3600000)
        self.assertAlmostEqual(sum(r['cost'] for r in rows), 600/3600000*.2)

    def test_database_failure_preserves_raw_data(self):
        before = self.log.read_text()
        with patch.object(self.db, 'record_powerstat', side_effect=RuntimeError('disk full')):
            with self.assertRaises(RuntimeError):
                self.sample()
        self.assertEqual(self.log.read_text(), before)
