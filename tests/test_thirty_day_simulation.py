"""Thirty days of second-by-second raw logs, using only temporary storage."""
import datetime
import math
import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from energytlk.config import DEFAULTS
from energytlk.database import Database
from energytlk.plain_powerstat import PlainPowerstat


class ThirtyDaySimulationTests(unittest.TestCase):
    def test_thirty_days_of_raw_logs(self):
        settings = dict(DEFAULTS, currency='EUR', history_currencies=[])
        with tempfile.TemporaryDirectory(prefix='vibeenergy-30days-') as temp, patch('energytlk.config.load', return_value=settings):
            root = Path(temp)
            log = root / 'powerstat.log'
            log.write_text('Time Watts core pkg-0\n')
            inode = log.stat().st_ino
            db = Database(root / 'history.sqlite3')
            try:
                reader = PlainPowerstat(log, db, cleanup=True)
                start = int(datetime.datetime(2026, 4, 1).timestamp())
                end = int(datetime.datetime(2026, 5, 1).timestamp())
                # Local timestamps use the explicitly selected process timezone.
                self.assertEqual(end-start, 30*86400)
                with log.open('a') as writer:
                    writer.write('00:00:00 999 800 120\n')
                    writer.flush()
                    os.utime(log, (start, start))
                    reader.read(start, 120, .2, currency='EUR')
                    cleanups = 0
                    for batch_start in range(start, end, 60):
                        day = (batch_start-start)//86400
                        watts = 120 + day
                        price = .2 if day < 15 else .3
                        rows = [time.strftime('%H:%M:%S', time.localtime(stamp)) + f' 999 800 {watts}\n'
                                for stamp in range(batch_start+1, batch_start+61)]
                        writer.writelines(rows)
                        writer.flush()
                        now = batch_start+60
                        os.utime(log, (now, now))
                        size_before = log.stat().st_size
                        reader.read(now, 120, price, currency='EUR')
                        if log.stat().st_size < size_before:
                            cleanups += 1
                        if (now-start) % (7*86400) == 0:
                            before = db.report(99)
                            db.close()
                            db = Database(root / 'history.sqlite3')
                            reader = PlainPowerstat(log, db, cleanup=True)
                            reader.read(now, 120, price, currency='EUR')
                            self.assertEqual(db.report(99), before, 'Restart replayed energy')
                reports = db.report(99)
                self.assertEqual(len(reports), 30)
                self.assertEqual(cleanups, 30)
                self.assertEqual(log.stat().st_ino, inode)
                for day, row in enumerate(reports):
                    self.assertEqual(row['day'], (datetime.date(2026, 4, 1)+datetime.timedelta(days=day)).isoformat())
                    # The initial anchor covers day one; subsequent daily cleanups drop one polling batch.
                    seconds = 86400 if day == 0 else 86340
                    expected_kwh = (120+day)*seconds/3600000
                    self.assertTrue(math.isclose(row['kwh'], expected_kwh, rel_tol=1e-10), (day, row, expected_kwh))
                    self.assertTrue(math.isclose(row['cost'], expected_kwh*(.2 if day < 15 else .3), rel_tol=1e-10))
                    self.assertEqual(row['covered_seconds'], seconds)
                self.assertEqual(db.db.execute('PRAGMA integrity_check').fetchone()[0], 'ok')
                total = sum(r['kwh'] for r in reports)
                cost = sum(r['cost'] for r in reports)
                print(f'\n30-day simulation: {end-start+1:,} raw rows; {cleanups} daily cleanups; '
                      f'4 database reopen/replay checks; {total:.9f} kWh; EUR {cost:.9f}; '
                      f'{29*60} seconds excluded (60-second polling batches);  final raw log {log.stat().st_size} bytes', flush=True)
            finally:
                db.close()
