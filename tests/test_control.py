import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from energytlk.control import stop_collector

ROOT = Path(__file__).resolve().parents[1]


class CollectorStopTests(unittest.TestCase):
    def test_missing_collector_is_already_stopped(self):
        with tempfile.TemporaryDirectory() as tmp:
            stop_collector(tmp)

    def test_portable_collector_stops_gracefully_without_touching_other_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            env = os.environ | {f'XDG_{key}_HOME': str(root/key.lower()) for key in ('CONFIG','DATA','STATE')}
            process = subprocess.Popen([sys.executable,'-m','energytlk','--simulate','--interval','1'],
                                       cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            state = root/'state/energytlk/demo'
            try:
                deadline=time.monotonic()+8
                while not (state/'state.json').exists() and time.monotonic()<deadline:
                    time.sleep(.05)
                self.assertTrue((state/'state.json').exists())
                # A stop directed at another state directory cannot kill this collector.
                stop_collector(root/'other')
                self.assertIsNone(process.poll())
                # Existing lock files have no PID; inode ownership still identifies them.
                stop_collector(state)
                process.communicate(timeout=5)
                self.assertEqual(process.returncode,0)
                self.assertFalse(json.loads((state/'state.json').read_text())['running'])
                self.assertTrue((root/'data/energytlk/demo/energy.sqlite3').exists())
            finally:
                if process.poll() is None:process.terminate()
                process.communicate(timeout=5)

    def test_unknown_lock_owner_is_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)
            script="import fcntl,sys,time; f=open(sys.argv[1],'w'); fcntl.flock(f,fcntl.LOCK_EX); print('ready',flush=True); time.sleep(10)"
            process=subprocess.Popen([sys.executable,'-c',script,str(path/'collector.lock')],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            try:
                self.assertEqual(process.stdout.readline().strip(),b'ready')
                with self.assertRaisesRegex(RuntimeError,'identified safely'):
                    stop_collector(path)
                self.assertIsNone(process.poll())
            finally:
                process.terminate();process.communicate(timeout=5)
