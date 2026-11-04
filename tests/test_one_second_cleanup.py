"""Measure daily cleanup accounting with one-second reads in temporary storage."""
import datetime
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from energytlk.config import DEFAULTS
from energytlk.database import Database
from energytlk.plain_powerstat import PlainPowerstat


class OneSecondCleanupTests(unittest.TestCase):
    def test_thirty_midnights_with_one_second_polling(self):
        settings = dict(DEFAULTS, currency='EUR', history_currencies=[])
        missed = []
        with tempfile.TemporaryDirectory(prefix='vibeenergy-1s-') as temp, patch('energytlk.config.load', return_value=settings):
            for day in range(30):
                with self.subTest(day=day+1):
                    root = Path(temp) / str(day)
                    root.mkdir()
                    log = root / 'powerstat.log'
                    log.write_text('Time Watts core pkg-0\n')
                    inode = log.stat().st_ino
                    db = Database(root / 'history.sqlite3')
                    try:
                        reader = PlainPowerstat(log, db, cleanup=True)
                        start = datetime.datetime(2026, 4, 1, 23, 59, 55)+datetime.timedelta(days=day)
                        before = 0
                        with log.open('a') as writer:
                            for second in range(11):
                                current = start+datetime.timedelta(seconds=second)
                                stamp = current.timestamp()
                                writer.write(current.strftime('%H:%M:%S')+' 999 800 120\n')
                                writer.flush()
                                os.utime(log, (stamp, stamp))
                                reader.read(stamp, 5, .2, currency='EUR')
                                rows = db.report(99)
                                covered = sum(r['covered_seconds'] for r in rows)
                                expected_delta = 0 if second in (0, 6) else 1
                                self.assertEqual(covered-before, expected_delta, current.isoformat())
                                if second and covered == before:
                                    missed.append(current.isoformat())
                                before = covered
                        self.assertEqual(before, 9)
                        self.assertEqual(log.stat().st_ino, inode)
                        self.assertAlmostEqual(sum(r['kwh'] for r in rows), 120*9/3600000)
                        self.assertAlmostEqual(sum(r['cost'] for r in rows), 120*9/3600000*.2)
                        self.assertEqual(db.db.execute('PRAGMA integrity_check').fetchone()[0], 'ok')
                    finally:
                        db.close()
        self.assertEqual(len(missed), 30)
        print('\n1-second polling: 30 isolated midnight windows; 330 raw samples; '
              '300 elapsed seconds; 270 accounted seconds; '
              'exactly 1 second excluded per cleanup (00:00:00 to 00:00:01).', flush=True)
