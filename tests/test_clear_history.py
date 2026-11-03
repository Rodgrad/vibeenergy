import json
from pathlib import Path
import tempfile
import unittest
from energytlk.clear_history import clear_recordings
from energytlk.config import DEFAULTS
from energytlk.database import Database


class ClearHistoryTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.data=self.root/'data';self.state=self.root/'state';self.home=self.root/'home'
        self.logs=self.home/'.vibeenergy/logs'
        for directory in (self.data,self.state,self.logs,self.data/'demo',self.state/'demo'):directory.mkdir(parents=True,exist_ok=True)
        for directory in (self.data,self.data/'demo'):
            db=Database(directory/'energy.sqlite3')
            db.record_powerstat([('2026-11-03',1000,3600)],.2,'EUR')
            db.record_powerstat([('2026-11-03',2000,7200)],.3,'USD')
            db.close()
        for directory in (self.state,self.state/'demo'):(directory/'state.json').write_text(json.dumps({'daily':[1],'running':True}))

    def test_clears_all_currencies_demo_logs_and_snapshots_but_keeps_settings(self):
        raw=self.logs/'powerstat.log';raw.write_text('old samples')
        inode=raw.stat().st_ino
        lock=self.logs/'powerstat.log.lock';lock.write_text('keep')
        (self.state/'portable-collector.log').write_text('diagnostics')
        settings=self.root/'settings.json';settings.write_text('preserve')
        custom=self.root/'custom.log';custom.write_text('cpu data')
        clear_recordings(self.data,self.state,self.home,DEFAULTS | {'powerstat_log':str(custom)})
        for directory in (self.data,self.data/'demo'):
            db=Database(directory/'energy.sqlite3')
            self.assertEqual(db.report(1),[]);db.close()
        self.assertEqual(raw.read_text(),'');self.assertEqual(raw.stat().st_ino,inode)
        self.assertEqual(custom.read_text(),'');self.assertEqual(lock.read_text(),'keep')
        self.assertEqual(settings.read_text(),'preserve')
        for directory in (self.state,self.state/'demo'):
            state=json.loads((directory/'state.json').read_text())
            self.assertEqual(state['daily'],[]);self.assertFalse(state['running'])
            self.assertIn('history_generation',state)

    def test_log_symlink_rejected_before_history_changes(self):
        outside=self.root/'unrelated.txt';outside.write_text('preserve')
        (self.logs/'bad.log').symlink_to(outside)
        with self.assertRaises(OSError):clear_recordings(self.data,self.state,self.home,DEFAULTS)
        db=Database(self.data/'energy.sqlite3');self.assertEqual(len(db.report(1)),2);db.close()
        self.assertEqual(outside.read_text(),'preserve')

    def test_lock_files_and_unrelated_files_are_preserved(self):
        for name in ('powerstat.log.runner.lock','notes.txt'):(self.logs/name).write_text('keep')
        clear_recordings(self.data,self.state,self.home,DEFAULTS)
        self.assertEqual((self.logs/'powerstat.log.runner.lock').read_text(),'keep')
        self.assertEqual((self.logs/'notes.txt').read_text(),'keep')
