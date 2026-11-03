"""Stop the current user's collector, including a portable fallback instance."""
import fcntl
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def stop_collector(state):
    lock_path = Path(state)/'collector.lock'
    try:
        lock = lock_path.open('r+')
    except FileNotFoundError:
        return
    with lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return
        except BlockingIOError:
            pass
        identity = os.fstat(lock.fileno())
        owners = []
        # Match the actual open lock inode, not an executable name alone. This
        # also handles older collectors whose lock file contains no PID.
        for process in Path('/proc').glob('[0-9]*'):
            try:
                if process.stat().st_uid != os.getuid():
                    continue
                args = (process/'cmdline').read_bytes().split(b'\0')
                if not any(args[i:i+2] in ([b'-m', b'energytlk'], [b'-m', b'energytlk.collector'])
                           for i in range(len(args)-1)):
                    continue
                for fd in (process/'fd').iterdir():
                    try:
                        opened = fd.stat()
                    except OSError:
                        continue
                    if (opened.st_dev, opened.st_ino) == (identity.st_dev, identity.st_ino):
                        owners.append(int(process.name))
                        break
            except (OSError, ValueError):
                continue
        if not owners:
            raise RuntimeError('Collector is still running, but its owner could not be identified safely.')
        for pid in owners:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        deadline = time.monotonic()+5
        while time.monotonic() < deadline:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return
            except BlockingIOError:
                time.sleep(.05)
        raise RuntimeError('Collector did not stop. VibeEnergy has been left open.')


def main():
    env = dict(os.environ)
    for key in ('LD_LIBRARY_PATH', 'LD_PRELOAD', 'PYTHONHOME', 'PYTHONPATH',
                'QT_PLUGIN_PATH', 'QML_IMPORT_PATH', 'QML2_IMPORT_PATH'):
        env.pop(key, None)
    if env.get('VIBEENERGY_HOST_PATH'):
        env['PATH'] = env['VIBEENERGY_HOST_PATH']
    try:
        subprocess.run(['/usr/bin/systemctl', '--user', 'stop', 'energytlk.service'],
                       env=env, capture_output=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        pass
    try:
        stop_collector(Path(os.environ.get('XDG_STATE_HOME', Path.home()/'.local/state'))/'energytlk')
    except (OSError, RuntimeError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
