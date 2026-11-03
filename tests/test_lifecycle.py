import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
from energytlk.database import Database
from energytlk.sensors import Sensors

ROOT=Path(__file__).resolve().parents[1]


class LifecycleTests(unittest.TestCase):
    def test_simulation_lock_persistence_and_clean_shutdown(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp)
            env=os.environ | dict(XDG_CONFIG_HOME=str(base/'config'),XDG_DATA_HOME=str(base/'data'),XDG_STATE_HOME=str(base/'state'))
            command=[sys.executable,'-m','energytlk','--simulate','--interval','1']
            process=subprocess.Popen(command,cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            state=base/'state/energytlk/demo/state.json'
            try:
                deadline=time.monotonic()+8
                while not state.exists() and time.monotonic()<deadline:
                    time.sleep(.05)
                self.assertTrue(state.exists())
                duplicate=subprocess.run(command+['--samples','1'],cwd=ROOT,env=env,capture_output=True,timeout=5)
                self.assertEqual(duplicate.returncode,0)
                self.assertIn(b'already running',duplicate.stderr)
                # Wait until two valid intervals are persisted.
                while time.monotonic()<deadline:
                    snapshot=json.loads(state.read_text())
                    if sum(r['covered_seconds'] for r in snapshot['daily'])>=4:
                        break
                    time.sleep(.05)
                self.assertGreater(sum(r['kwh'] for r in snapshot['daily']),0)
                self.assertTrue(snapshot['simulated'])
            finally:
                process.terminate()
                process.communicate(timeout=5)
            self.assertEqual(process.returncode,0)
            old=json.loads(state.read_text())
            self.assertFalse(old['running'])
            subprocess.run(command+['--samples','1'],cwd=ROOT,env=env,check=True,timeout=5)
            new=json.loads(state.read_text())
            self.assertEqual(old['daily'],new['daily'])
            self.assertNotEqual(old['session'],new['session'])
            self.assertFalse((base/'data/energytlk/energy.sqlite3').exists())

    def test_corrupt_database_is_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'broken.sqlite3'
            original=b'not a sqlite database'
            path.write_bytes(original)
            with self.assertRaises(sqlite3.DatabaseError):
                Database(path)
            self.assertEqual(path.read_bytes(),original)

    def test_realistic_sysfs_symlink_discovery(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            actual=root/'devices/virtual/powercap/intel-rapl/intel-rapl:0'
            actual.mkdir(parents=True)
            (actual/'name').write_text('package-0')
            (actual/'energy_uj').write_text('1000')
            (actual/'max_energy_range_uj').write_text('100000')
            cap=root/'class/powercap'
            cap.mkdir(parents=True)
            (cap/'intel-rapl:0').symlink_to(actual,target_is_directory=True)
            sensors=Sensors(root)
            try:
                sensors.discover()
                self.assertEqual(len(sensors.devices),1)
                self.assertEqual(sensors.devices[0][2],'package-0')
            finally:
                sensors.close()
