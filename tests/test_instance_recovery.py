"""Use a private bus to verify activation while the previous window is cleaning up."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = Path(os.environ.get('ENERGYTLK_TEST_LAUNCHER', ROOT/'build/energytlk-instance'))


@unittest.skipUnless(LAUNCHER.is_file() and shutil.which('dbus-daemon'), 'Build the native launcher and install dbus-daemon')
class InstanceRecoveryTests(unittest.TestCase):
    def test_reopen_during_cleanup_starts_a_new_window_automatically(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            config=root/'bus.conf'
            config.write_text('<busconfig><type>session</type><listen>unix:path='+str(root/'bus')+'</listen><auth>EXTERNAL</auth><policy context="default"><allow send_destination="*"/><allow receive_sender="*"/><allow own="*"/></policy></busconfig>')
            bus=subprocess.Popen(['dbus-daemon','--nofork','--config-file='+str(config),'--print-address'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            primary=None
            log=(root/'launcher.log').open('w')
            try:
                address=bus.stdout.readline().strip()
                self.assertTrue(address,'Private D-Bus failed to start')
                command=root/'AppRun'
                command.write_text('#!/bin/sh\ntrap \'sleep 1\' EXIT\ntrap \'exit 0\' TERM\nsleep 60 &\nchild=$!\necho "$child" > "$TEST_ROOT/gui"\necho spawn >> "$TEST_ROOT/windows"\nwait "$child"\n')
                command.chmod(0o755)
                env=os.environ|dict(DBUS_SESSION_BUS_ADDRESS=address,XDG_STATE_HOME=str(root/'state'),TEST_ROOT=str(root))
                primary=subprocess.Popen([str(LAUNCHER),str(command)],env=env,stdout=log,stderr=log)
                deadline=time.monotonic()+5
                while not (root/'gui').exists() and time.monotonic()<deadline:time.sleep(.02)
                self.assertTrue((root/'gui').exists(),'Initial window did not start')
                os.kill(int((root/'gui').read_text()),signal.SIGKILL)
                # The child shell remains alive for its EXIT cleanup while the GUI is gone.
                time.sleep(.1)
                secondary=subprocess.run([str(LAUNCHER),str(command)],env=env,stdout=log,stderr=log,timeout=3)
                self.assertEqual(secondary.returncode,0)
                deadline=time.monotonic()+7
                while len((root/'windows').read_text().splitlines())<2 and time.monotonic()<deadline:time.sleep(.02)
                self.assertEqual(len((root/'windows').read_text().splitlines()),2,'Reopen was acknowledged but no replacement window started')
                self.assertIsNone(primary.poll())
                # A terminating launcher refuses activation. The new launch must
                # wait for ownership rather than returning without a window.
                primary.terminate()
                time.sleep(.1)
                replacement=subprocess.Popen([str(LAUNCHER),str(command)],env=env,stdout=log,stderr=log)
                try:
                    primary.wait(timeout=8)
                finally:
                    primary=replacement
                deadline=time.monotonic()+8
                while len((root/'windows').read_text().splitlines())<3 and time.monotonic()<deadline:time.sleep(.02)
                self.assertEqual(len((root/'windows').read_text().splitlines()),3,'Reopen during launcher termination lost the new request')
                self.assertIsNone(primary.poll())
            finally:
                if primary and primary.poll() is None:
                    primary.terminate()
                    try:primary.wait(timeout=8)
                    except subprocess.TimeoutExpired:primary.kill();primary.wait(timeout=3)
                log.close()
                bus.terminate()
                bus.communicate(timeout=3)
