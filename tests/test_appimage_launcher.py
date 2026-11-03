"""Exercise startup supervision without Qt, Docker, or changing user services."""
import os
from pathlib import Path
import subprocess
import signal
import tempfile
import time
import unittest

LAUNCHER = Path(__file__).resolve().parents[1] / "packaging/appimage/AppRun"


class AppImageLauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "app"
        self.bin = self.app / "usr/bin"
        self.bin.mkdir(parents=True)
        copy = self.app / "AppRun"
        copy.write_text(LAUNCHER.read_text())
        copy.chmod(0o755)
        self.write_program("energytlk-instance", 'export VIBEENERGY_INSTANCE_OWNER=1\nexec "$@"\n')
        self.state = self.root / "state"
        self.state.mkdir()
        self.write_program("python3", 'exit "${TEST_PREPARE_EXIT:-0}"\n')
        self.write_program("energytlk-splash", '''
mkdir "$TEST_STATE/splash-lock" 2>/dev/null || exit 0
cleanup() { rmdir "$TEST_STATE/splash-lock"; }
trap cleanup EXIT
trap 'exit 0' TERM INT
printf '%s\\n' "$$" >> "$TEST_STATE/splash-pids"
: > "$VIBEENERGY_SPLASH_SHOWN"
if [ "${TEST_SPLASH_BLOCKED:-0}" = 1 ]; then
    while :; do sleep 0.01; done
fi
while [ ! -f "$VIBEENERGY_SPLASH_READY" ]; do sleep 0.01; done
sleep 0.03
''')
        self.write_program("plasmawindowed", '''
case "$TEST_WINDOW" in
    forward) exit 0 ;;
    fail) exit 7 ;;
    ready)
        : > "$VIBEENERGY_SPLASH_READY"
        count=0
        while [ ! -f "$VIBEENERGY_SPLASH_CLOSED" ] && [ "$count" -lt 350 ]; do
            sleep 0.01
            count=$((count + 1))
        done
        test -f "$VIBEENERGY_SPLASH_CLOSED" || exit 9
        sleep 0.15
        ;;
esac
''')

    def write_program(self, name, script):
        path = self.bin / name
        path.write_text("#!/bin/sh\nset -eu\n" + script)
        path.chmod(0o755)

    def environment(self, mode):
        env = os.environ.copy()
        # Ensure a developer's currently-running AppImage cannot affect this test.
        for name in ("LD_PRELOAD", "PYTHONHOME", "PYTHONPATH"):
            env.pop(name, None)
        env.update(APPDIR=str(self.app), TMPDIR=str(self.root),
                   TEST_STATE=str(self.state), TEST_WINDOW=mode)
        return env

    def assert_clean(self):
        self.assertFalse(list(self.root.glob("vibeenergy-splash.*")))
        self.assertFalse((self.state / "splash-lock").exists())
        pids = self.state / "splash-pids"
        if pids.exists():
            for value in pids.read_text().splitlines():
                with self.assertRaises(ProcessLookupError):
                    os.kill(int(value), 0)

    def launch(self, mode):
        return subprocess.run(["sh", str(LAUNCHER)], env=self.environment(mode),
                              capture_output=True, timeout=4)

    def test_forwarded_launch_stops_splash_without_ready_signal(self):
        started = time.monotonic()
        result = self.launch("forward")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertLess(time.monotonic() - started, 2)
        self.assert_clean()

    def test_window_failure_stops_splash_and_preserves_exit_code(self):
        result = self.launch("fail")
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assert_clean()

    def test_regular_window_receives_closed_acknowledgment(self):
        result = self.launch("ready")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_clean()

    def test_simultaneous_launches_leave_no_splash_or_startup_files(self):
        processes = [subprocess.Popen(["sh", str(LAUNCHER)],
                     env=self.environment("ready"), stdout=subprocess.PIPE,
                     stderr=subprocess.PIPE) for _ in range(4)]
        try:
            for process in processes:
                _, stderr = process.communicate(timeout=4)
                self.assertEqual(process.returncode, 0, stderr)
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                    process.communicate()
        self.assert_clean()

    def test_blocked_splash_is_stopped_when_window_is_ready(self):
        env = self.environment("ready")
        env["TEST_SPLASH_BLOCKED"] = "1"
        result = subprocess.run(["sh", str(LAUNCHER)], env=env,
                                capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_clean()

    def test_ending_splash_also_ends_window(self):
        env=self.environment("ready")
        env['TEST_SPLASH_BLOCKED']='1'
        process=subprocess.Popen(["sh",str(LAUNCHER)],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        try:
            deadline=time.monotonic()+2
            pid_file=self.state/'splash-pids'
            while not pid_file.exists() and time.monotonic()<deadline:time.sleep(.01)
            self.assertTrue(pid_file.exists())
            os.kill(int(pid_file.read_text().splitlines()[0]),signal.SIGKILL)
            _,err=process.communicate(timeout=4)
            self.assertEqual(process.returncode,137,err)
            self.assertFalse(list(self.root.glob('vibeenergy-splash.*')))
        finally:
            if process.poll() is None:process.kill()
            process.communicate(timeout=4)

    def test_preparation_failure_cleans_up_splash(self):
        env = self.environment("ready")
        env["TEST_PREPARE_EXIT"] = "8"
        result = subprocess.run(["sh", str(LAUNCHER)], env=env,
                                capture_output=True, timeout=4)
        self.assertEqual(result.returncode, 8, result.stderr)
        self.assert_clean()


if __name__ == "__main__":
    unittest.main()
