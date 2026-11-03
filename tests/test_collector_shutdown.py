"""Regression for overlapping service-stop and parent-death termination signals."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CollectorShutdownTests(unittest.TestCase):
    def test_termination_does_not_reenter_an_event_lock(self):
        # The old handler called Event.set(). Force another termination signal
        # while its condition is locked to reproduce the shutdown deadlock.
        script='''import os,runpy,signal,sys,threading
original=threading.Event.set
def overlapping_stop(event):
    with event._cond:
        os.kill(os.getpid(),signal.SIGTERM)
    original(event)
threading.Event.set=overlapping_stop
sys.argv=['energytlk','--simulate','--interval','300']
runpy.run_module('energytlk',run_name='__main__')
'''
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            env=dict(os.environ)
            env.pop('APPIMAGE',None);env.pop('APPDIR',None)
            env.update({f'XDG_{key}_HOME':str(root/key.lower()) for key in ('CONFIG','DATA','STATE')})
            process=subprocess.Popen([sys.executable,'-c',script],cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            snapshot=root/'state/energytlk/demo/state.json'
            try:
                deadline=time.monotonic()+8
                while not snapshot.exists() and time.monotonic()<deadline:time.sleep(.02)
                self.assertTrue(snapshot.exists(),'Collector failed to start')
                start=time.monotonic()
                process.send_signal(signal.SIGTERM)
                _,error=process.communicate(timeout=3)
                self.assertEqual(process.returncode,0,error)
                self.assertLess(time.monotonic()-start,2)
                self.assertFalse(json.loads(snapshot.read_text())['running'])
                self.assertTrue((root/'data/energytlk/demo/energy.sqlite3').exists())
            finally:
                if process.poll() is None:process.kill()
                process.communicate(timeout=3)
