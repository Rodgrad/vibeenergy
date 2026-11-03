import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from energytlk.config import DEFAULTS
from energytlk.database import Database
from energytlk.sensors import reading


class CurrencyHistoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)/'history.sqlite3'
        self.settings = DEFAULTS.copy()
        self.patch = patch('energytlk.config.load', side_effect=lambda: self.settings.copy())
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def record(self, db, currency, wh=1000, price=.2):
        db.record(100, 's', [reading('cpu:0', 'CPU', 'cpu', 'test', 100)],
                  {'cpu:0': [('2026-11-03', wh, 3600)]}, price=price, currency=currency)

    def test_same_day_switch_and_resume_keep_cost_and_energy_separate(self):
        db = Database(self.path)
        self.record(db, 'EUR')
        self.record(db, 'USD', price=.5)
        self.record(db, 'EUR', price=.3)
        rows = {r['currency']: r for r in db.report(99)}
        self.assertEqual(rows['EUR']['kwh'], 2)
        self.assertAlmostEqual(rows['EUR']['cost'], .5)
        self.assertEqual(rows['USD']['kwh'], 1)
        self.assertAlmostEqual(rows['USD']['cost'], .5)
        self.assertEqual(db.branches(), ['EUR', 'USD'])
        db.prune(1)
        db.close()
        self.settings['currency'] = 'USD'
        db = Database(self.path)
        self.assertEqual({r['currency']: r for r in db.report(99)}, rows)
        self.assertEqual(db.db.execute('SELECT sum(wh) FROM monthly').fetchone()[0], 3000)
        db.close()

    def test_cpu_recorder_and_importer_share_currency_branches(self):
        db = Database(self.path)
        db.record_powerstat([('2026-11-03', 1000, 3600)], .2, 'EUR')
        db.commit_powerstat('log', {'offset': 100}, [('2026-11-03', 1000, 3600)], .4, 'USD')
        rows = {r['currency']: r for r in db.report(99)}
        self.assertEqual(rows['EUR']['cost'], .2)
        self.assertEqual(rows['USD']['cost'], .4)
        self.assertEqual(db.powerstat_cursor('log'), {'offset': 100})
        db.close()

    def test_legacy_migration_preserves_original_currency_while_stopped(self):
        old = sqlite3.connect(self.path)
        old.executescript('''
            CREATE TABLE daily(day TEXT,device TEXT,kind TEXT,quality TEXT,wh REAL,covered REAL,
                PRIMARY KEY(day,device,quality));
            CREATE TABLE daily_cost(day TEXT,device TEXT,quality TEXT,cost REAL,
                PRIMARY KEY(day,device,quality));
            INSERT INTO daily VALUES('2025-01-01','cpu','cpu','measured',1000,3600);
            INSERT INTO daily VALUES('2025-01-02','cpu','cpu','measured',2000,7200);
            INSERT INTO daily_cost VALUES('2025-01-01','cpu','measured',.123);
            PRAGMA user_version=2;
        ''')
        old.close()
        self.settings.update(currency='USD', price=.8, history_currency='EUR', history_price=.2,
                             history_currencies=['EUR', 'USD'])
        db = Database(self.path)
        rows = db.report(99)
        self.assertEqual([r['currency'] for r in rows], ['EUR', 'EUR'])
        self.assertEqual([r['cost'] for r in rows], [.123, .4])
        self.assertEqual(db.branches(), ['EUR', 'USD'])
        self.assertEqual(db.db.execute('PRAGMA user_version').fetchone()[0], 3)
        db.close()
        db = Database(self.path)
        self.assertEqual(db.report(99), rows)
        db.close()

    def test_failed_commit_does_not_create_partial_branch(self):
        db = Database(self.path)
        db.db.execute("CREATE TRIGGER fail_cost BEFORE INSERT ON daily_cost BEGIN SELECT RAISE(ABORT, 'full'); END")
        with self.assertRaises(sqlite3.IntegrityError):
            self.record(db, 'USD')
        self.assertEqual(db.branches(), [])
        self.assertEqual(db.report(1), [])
        db.close()
