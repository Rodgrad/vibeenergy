import os
import tempfile
import time
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch
from energytlk.energy import Integrator, counter_delta, day_slices
from energytlk.config import load, validate
from energytlk.database import Database
from energytlk.powerstat import PowerstatLog
from energytlk.sensors import Sensors, reading


class AccountingTests(unittest.TestCase):
    def setUp(self):
        self.math = Integrator()
        self.r = reading('cpu:0', 'CPU', 'cpu', 'test', 100)

    def add(self, wall, mono=None, boot=None):
        return self.math.add(self.r, wall, wall if mono is None else mono, wall if boot is None else boot, 10)

    def test_trapezoid(self):
        self.assertEqual(self.add(100), [])
        self.r['watts'] = 200
        self.assertAlmostEqual(sum(x[1] for x in self.add(110)), 150*10/3600)

    def test_rapl_interval_average(self):
        self.add(100)
        self.r.update(watts=200, interval_average=True)
        self.assertAlmostEqual(sum(x[1] for x in self.add(110)), 200*10/3600)

    def test_missing_does_not_mean_zero(self):
        self.add(100)
        self.r['watts'] = None
        self.assertEqual(self.add(110), [])
        self.r['watts'] = 100
        self.assertEqual(self.add(120), [])

    def test_gap(self):
        self.add(100)
        self.assertEqual(self.add(200), [])

    def test_restart(self):
        self.add(100)
        self.assertEqual(Integrator().add(self.r,110,110,110,10), [])

    def test_suspend(self):
        self.add(100)
        self.assertEqual(self.add(3710,110,3710), [])

    def test_clock_jump(self):
        self.add(100)
        self.assertEqual(self.add(500,110,110), [])

    def test_clock_backwards(self):
        self.add(100)
        self.assertEqual(self.add(50,110,110), [])

    def test_backend_change(self):
        self.add(100)
        self.r['source'] = 'other'
        self.assertEqual(self.add(110), [])

    def test_excluded_domain(self):
        self.r['account'] = False
        self.add(100)
        self.assertEqual(self.add(110), [])

    def test_nan(self):
        self.add(100)
        self.r['watts'] = float('nan')
        self.assertEqual(self.add(110), [])

    def test_counter_wrap(self):
        self.assertEqual(counter_delta(90,10,100),20)
        self.assertEqual(counter_delta(10,30,100),20)
        with self.assertRaises(ValueError):
            counter_delta(1000,10,100)

    def test_midnight_split(self):
        start = datetime(2026,11,1,23,59,55).timestamp()
        parts = list(day_slices(start,start+10,100,200))
        self.assertEqual([x[0] for x in parts], ['2026-11-01','2026-11-02'])
        self.assertAlmostEqual(parts[0][1],125*5/3600)
        self.assertAlmostEqual(sum(x[1] for x in parts),150*10/3600)

    def test_dst_calendar(self):
        old = os.environ.get('TZ')
        try:
            os.environ['TZ']='Europe/Zagreb'
            time.tzset()
            start = datetime(2026,10,25).timestamp()
            end = datetime(2026,10,26).timestamp()
            parts=list(day_slices(start,end,100,100))
            self.assertEqual(len(parts),1)
            self.assertAlmostEqual(parts[0][1],2500)
        finally:
            if old is None:
                os.environ.pop('TZ',None)
            else:
                os.environ['TZ']=old
            time.tzset()


class DatabaseTests(unittest.TestCase):
    def test_retention_price_persistence(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'history.sqlite3'
            db=Database(path)
            r=reading('cpu:0','CPU','cpu','test',100)
            db.record(100,'session',[r],{'cpu:0':[('2000-01-01',1000,36000)]})
            self.assertEqual(db.report(.177)[0]['cost'],.177)
            self.assertEqual(db.report(.3)[0]['cost'],.3)
            db.prune(1)
            self.assertEqual(db.db.execute('SELECT count(*) FROM samples').fetchone()[0],0)
            self.assertEqual(db.db.execute('SELECT wh FROM monthly').fetchone()[0],1000)
            db.close()
            db=Database(path)
            self.assertEqual(db.report(.177)[0]['kwh'],1)
            db.close()

    def test_unknown_energy_null(self):
        with tempfile.TemporaryDirectory() as tmp:
            db=Database(Path(tmp)/'history.sqlite3')
            db.record(100,'s',[reading('a','CPU','cpu','none')],{})
            self.assertIsNone(db.db.execute('SELECT wh FROM samples').fetchone()[0])
            self.assertEqual(db.report(.177),[])
            db.close()


class ConfigTests(unittest.TestCase):
    def test_interval_limits(self):
        for interval in (1, 5):
            self.assertEqual(validate({'interval':interval})['interval'],interval)
        for interval in (0, 6, 300):
            with self.subTest(interval=interval), self.assertRaises(ValueError):
                validate({'interval':interval})

    def test_old_saved_intervals_load_at_five_seconds(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp)/'energytlk/config.json'
            config.parent.mkdir()
            with patch.dict(os.environ, {'XDG_CONFIG_HOME':tmp}):
                for interval in (6, 10, 300):
                    config.write_text('{"interval":%d}' % interval)
                    self.assertEqual(load()['interval'],5)
                config.write_text('{"interval":301}')
                with self.assertRaises(ValueError):
                    load()

    def test_comma_and_currency(self):
        self.assertEqual(validate({'price':'0,177','currency':'eur'})['price'],.177)

    def test_invalid(self):
        for values in ({'price':'NaN'},{'price':-1},{'interval':0},{'currency':'€'},{'powerstat_log':'relative'},{'retention_days':0}):
            with self.subTest(values=values), self.assertRaises(ValueError):
                validate(values)


class LogTests(unittest.TestCase):
    HEADER='Time User Nice Sys Idle IO Run Ctxt/s IRQ/s Watts\n'
    def test_timestamp_rotation_truncation(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'power.log'
            path.write_text(self.HEADER+'2026-11-02T12:00:00+01:00 2 0 1 97 0 1 100 1000 45.2\nAverage 2 0 1 97 0 1 100 1000 999\n')
            log=PowerstatLog(path)
            stamp=datetime.fromisoformat('2026-11-02T12:00:00+01:00').timestamp()
            self.assertEqual(log.read(stamp+1,25)[0],(stamp,45.2))
            self.assertIsNone(log.read(stamp+100,25)[0])
            path.rename(Path(tmp)/'old.log')
            path.write_text(self.HEADER+'2026-11-02 12:00:10+01:00 2 0 1 97 0 1 100 1000 50.0\n')
            self.assertEqual(log.read(stamp+11,25)[0],(stamp+10,50.0))
            path.write_text(self.HEADER)
            self.assertIsNone(log.read(stamp+12,25)[0])

    def test_time_only_and_footer(self):
        log=PowerstatLog('/unused')
        log.parse(self.HEADER)
        log.parse('12:00:00 2 0 1 97 0 1 100 1000 42.0\n')
        self.assertEqual(log.latest,(None,42))
        log.parse('Average 2 0 1 97 0 1 100 1000 999\n')
        self.assertEqual(log.latest,(None,42))

    def test_partial_line(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'log'
            path.write_text(self.HEADER+'2026-11-02T12:00:00Z 2 0 1 97 0 1 100 1000 4')
            log=PowerstatLog(path)
            stamp=datetime.fromisoformat('2026-11-02T12:00:00+00:00').timestamp()
            self.assertIsNone(log.read(stamp+1,25)[0])
            with path.open('a') as f:
                f.write('5.2\n')
            self.assertEqual(log.read(stamp+1,25)[0],(stamp,45.2))


class DiscoveryTests(unittest.TestCase):
    def test_packages_only_no_duplicate_symlink(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            package=root/'class/powercap/intel-rapl:0'
            core=package/'intel-rapl:0:0'
            core.mkdir(parents=True)
            for path,name in [(package,'package-0'),(core,'core')]:
                (path/'name').write_text(name)
                (path/'energy_uj').write_text('1000')
                (path/'max_energy_range_uj').write_text('100000')
            (package.parent/'alias').symlink_to(package, target_is_directory=True)
            sensors=Sensors(root)
            sensors.discover()
            self.assertEqual(len([x for x in sensors.devices if x[0]=='rapl']),1)
            sensors.close()

    def test_no_sensors(self):
        with tempfile.TemporaryDirectory() as tmp:
            sensors=Sensors(Path(tmp))
            result=sensors.sample(10)
            self.assertEqual({r['kind'] for r in result},{'cpu','gpu'})
            self.assertTrue(all(r['watts'] is None for r in result))
            sensors.close()

    def test_amd_discrete_microwatts(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            dev=root/'class/drm/card0/device'
            hwmon=dev/'hwmon/hwmon0'
            hwmon.mkdir(parents=True)
            (dev/'vendor').write_text('0x1002')
            (dev/'mem_info_vram_total').write_text(str(8*1024**3))
            (hwmon/'power1_average').write_text('45000000')
            sensors=Sensors(root)
            gpu=next(r for r in sensors.sample(10) if r['kind']=='gpu')
            self.assertEqual(gpu['watts'],45)
            sensors.close()
