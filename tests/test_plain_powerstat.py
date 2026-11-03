import datetime
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from energytlk.database import Database
from energytlk.plain_powerstat import PlainPowerstat


class PlainLogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)/'powerstat.log'
        self.path.write_text('Time Watts core pkg-0\n')
        self.db = Database(Path(self.temp.name)/'energy.sqlite3')
        self.addCleanup(self.db.close)
        self.now = datetime.datetime(2026,11,1,23,59,57).timestamp()
        self.reader = PlainPowerstat(self.path, self.db, cleanup=True)

    def append(self, seconds=1):
        self.now += seconds
        with self.path.open('a') as stream:
            stream.write(datetime.datetime.fromtimestamp(self.now).strftime('%H:%M:%S')+' 999 100 3600\n')
        os.utime(self.path, (self.now,self.now))

    def read(self):
        return self.reader.read(self.now, 5, .2)

    def total(self):
        return sum(r['kwh'] for r in self.db.report(99))

    def test_each_new_plain_sample_accounted_once_across_collector_restart(self):
        self.append(0)
        self.read()
        self.assertEqual(self.total(),0)
        self.append()
        self.read()
        self.assertAlmostEqual(self.total(),.001)
        self.reader = PlainPowerstat(self.path,self.db,cleanup=True)
        self.read()
        self.assertAlmostEqual(self.total(),.001)
        self.append()
        self.read()
        self.assertAlmostEqual(self.total(),.002)
        self.assertAlmostEqual(sum(r['cost'] for r in self.db.report(99)),.0004)

    def test_currency_switch_keeps_cursor_and_separates_costs(self):
        self.append(0)
        self.reader.read(self.now,5,.2,currency='EUR')
        self.append()
        self.reader.read(self.now,5,.2,currency='EUR')
        self.append()
        self.reader.read(self.now,5,.5,currency='USD')
        rows = {r['currency']:r for r in self.db.report(99)}
        self.assertAlmostEqual(rows['EUR']['cost'], .0002)
        self.assertAlmostEqual(rows['USD']['cost'], .0005)
        self.reader.read(self.now,5,.5,currency='USD')
        self.assertAlmostEqual(self.total(),.002)

    def test_midnight_cleanup_preserves_inode_and_open_append_writer(self):
        self.now += 2
        self.append(0)
        self.read()
        inode=self.path.stat().st_ino
        with self.path.open('a') as writer:
            self.append()
            self.read()
            self.assertEqual(self.path.stat().st_ino,inode)
            self.assertNotIn('23:59:59',self.path.read_text())
            self.assertAlmostEqual(self.total(),.001)
            for clock in ('00:00:01','00:00:02'):
                self.now += 1
                writer.write(clock+' 999 100 3600\n');writer.flush()
                os.utime(self.path,(self.now,self.now))
                self.read()
        self.assertAlmostEqual(self.total(),.002)
        self.assertEqual({r['day'] for r in self.db.report(99)}, {'2026-11-01','2026-11-02'})

    def test_three_days_off_does_not_assign_dates_to_old_clock_samples(self):
        self.append(0); self.read()
        self.append(); self.read()
        before=self.total()
        self.now += 3*86400
        self.append(0)
        self.reader=PlainPowerstat(self.path,self.db,cleanup=True)
        self.read()
        self.assertEqual(self.total(),before)
        self.assertLess(self.path.stat().st_size,100)

    def test_all_samples_in_a_batch_are_accounted(self):
        self.append(0); self.read()
        self.append(); self.append(); self.read()
        self.assertAlmostEqual(self.total(),.002)

    def test_failed_transaction_prevents_cleanup_and_cursor_advance(self):
        self.append(0); self.read()
        self.append()
        before=self.path.read_bytes()
        with patch.object(self.db,'commit_powerstat',side_effect=RuntimeError('disk full')):
            with self.assertRaises(RuntimeError): self.read()
        self.assertEqual(self.path.read_bytes(),before)
        self.reader=PlainPowerstat(self.path,self.db,cleanup=True)
        self.read()
        self.assertAlmostEqual(self.total(),.001)

    def test_size_cleanup_only_after_committing_consumed_samples(self):
        self.append(0); self.read()
        self.append()
        with patch('energytlk.plain_powerstat.MAX_RAW_BYTES',64): self.read()
        self.assertLess(self.path.stat().st_size,100)
        self.assertAlmostEqual(self.total(),.001)

    def test_incomplete_sample_is_not_consumed_or_truncated(self):
        self.append(0); self.read()
        with self.path.open('a') as stream: stream.write('23:59:58 999')
        before=self.path.read_bytes()
        with patch('energytlk.plain_powerstat.MAX_RAW_BYTES',1): self.read()
        self.assertEqual(self.path.read_bytes(),before)
        self.assertEqual(self.total(),0)
        self.now += 1
        with self.path.open('a') as stream: stream.write(' 100 3600\n')
        os.utime(self.path,(self.now,self.now))
        self.read()
        self.assertAlmostEqual(self.total(),.001)

    def test_cold_multi_batch_clock_history_is_not_invented(self):
        # More than one read batch, with old clock rows coincidentally matching now.
        clock=datetime.datetime.fromtimestamp(self.now).strftime('%H:%M:%S')
        with self.path.open('a') as stream:
            for _ in range(10010): stream.write(clock+' 999 100 3600\n')
        os.utime(self.path,(self.now,self.now))
        self.read(); self.read()
        self.assertEqual(self.total(),0)

    def test_direct_cpu_source_switch_does_not_overlap_log_energy(self):
        self.append(0); self.read()
        self.append()
        self.reader.read(self.now,5,.2,account=False)
        self.append(); self.read()
        self.assertEqual(self.total(),0)
        self.append(); self.read()
        self.assertAlmostEqual(self.total(),.001)

    def test_collector_accounts_plain_cpu_and_gpu_in_combined_daily_totals(self):
        import json
        import time
        from unittest.mock import Mock
        from energytlk import collector
        from energytlk.sensors import reading
        root=Path(self.temp.name)
        log=root/'live.log'
        log.write_text('Time Watts pkg-0\n')
        sensors=Mock()
        def sample(_):
            with log.open('a') as stream:
                stream.write(time.strftime('%H:%M:%S')+' 999 42\n')
            return [reading('cpu:0','CPU','cpu','RAPL',error='Permission denied'),
                    reading('gpu:0','GPU','gpu','NVIDIA',100)]
        sensors.sample.side_effect=sample
        env=dict(XDG_CONFIG_HOME=str(root/'config'), XDG_DATA_HOME=str(root/'data'), XDG_STATE_HOME=str(root/'state'))
        with patch.dict(os.environ,env),patch('energytlk.powerstat.DEFAULT_LOG_PATH',log),patch.object(collector,'Sensors',return_value=sensors),patch.object(collector.signal,'signal'),patch('sys.argv',['vibeenergy','--samples','3','--interval','1']):
            collector.main()
        snapshot=json.loads((root/'state/energytlk/state.json').read_text())
        rows=snapshot['daily']
        self.assertEqual({r['kind'] for r in rows},{'cpu','gpu'})
        self.assertGreater(sum(r['kwh'] for r in rows),0)
        self.assertAlmostEqual(sum(r['cost'] for r in rows),sum(r['kwh'] for r in rows)*.177)

    def test_old_recorder_totals_are_not_counted_twice(self):
        self.path.write_text('# vibeenergy-accounted-v2\nTime Watts pkg-0\n')
        self.append(0); self.read()
        self.append(); self.read()
        self.assertEqual(self.total(),0)
