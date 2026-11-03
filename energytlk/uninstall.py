#!/usr/bin/env python3
"""Remove user integration, restoring recording if preparation fails."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from .control import stop_collector
from .clear_history import active, restart


def run_systemctl(arguments, timeout):
    env = dict(os.environ)
    for key in ('LD_LIBRARY_PATH', 'LD_PRELOAD', 'PYTHONHOME', 'PYTHONPATH',
                'QT_PLUGIN_PATH', 'QML_IMPORT_PATH', 'QML2_IMPORT_PATH'):
        env.pop(key, None)
    if env.get('VIBEENERGY_HOST_PATH'):
        env['PATH'] = env['VIBEENERGY_HOST_PATH']
    return subprocess.run(['systemctl', '--user', '--no-ask-password', *arguments],
                          env=env, check=True, capture_output=True, text=True, timeout=timeout)


def prepare_removal(state, enabled):
    was_running = active(state)
    try:
        # Request shutdown without waiting for systemd's potentially long stop job.
        run_systemctl(['--no-block', 'stop', 'energytlk.service'], timeout=3)
        # Confirm the actual lock owner has exited, including portable collectors.
        stop_collector(state)
        run_systemctl(['disable', 'energytlk.service'], timeout=5)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        recovery = ''
        if enabled:
            try:
                run_systemctl(['enable', 'energytlk.service'], timeout=5)
            except (OSError, subprocess.SubprocessError):
                recovery += ' Recording autostart could not be restored.'
        if was_running:
            try:
                # A stop job may still be pending even while the old lock is held.
                # Always request start, so systemd also resolves that pending stop.
                restart(False, dict(os.environ))
                deadline = time.monotonic()+8
                while not active(state) and time.monotonic()<deadline:
                    time.sleep(.05)
                if not active(state):
                    raise RuntimeError('The collector did not restart.')
                recovery += ' Recording resumed.'
            except (OSError, RuntimeError, subprocess.SubprocessError) as restart_error:
                recovery += ' Recording could not resume: '+str(restart_error)
        if isinstance(error, subprocess.TimeoutExpired):
            reason = 'The service manager timed out.'
        else:
            reason = 'Could not finish stopping or disabling recording.'
        raise RuntimeError('Uninstall cancelled. '+reason+' No files removed.'+recovery) from error


def main():
    parser = argparse.ArgumentParser(description='Remove VibeEnergy; history is preserved by default')
    parser.add_argument('--delete-data', action='store_true', help='Explicitly delete energy history, demo data, and settings')
    parser.add_argument('--prefix', type=Path, help='Remove an isolated staged installation')
    args = parser.parse_args()
    if os.geteuid() == 0:
        parser.error('Run as your regular user')
    home = (args.prefix or Path.home()).resolve()
    data = home/'.local/share' if args.prefix else Path(os.environ.get('XDG_DATA_HOME',home/'.local/share'))
    config = home/'.config' if args.prefix else Path(os.environ.get('XDG_CONFIG_HOME',home/'.config'))
    state = home/'.local/state' if args.prefix else Path(os.environ.get('XDG_STATE_HOME',home/'.local/state'))
    if not args.prefix:
        enabled = (config/'systemd/user/default.target.wants/energytlk.service').is_symlink()
        try:
            prepare_removal(state/'energytlk', enabled)
        except RuntimeError as error:
            sys.exit(str(error))
    shutil.rmtree(data/'plasma/plasmoids/org.energytlk.monitor',ignore_errors=True)
    shutil.rmtree(data/'energytlk/app',ignore_errors=True)
    (config/'systemd/user/energytlk.service').unlink(missing_ok=True)
    (config/'autostart/vibeenergy.desktop').unlink(missing_ok=True)
    (data/'applications/vibeenergy.desktop').unlink(missing_ok=True)
    (data/'applications/org.energytlk.monitor.desktop').unlink(missing_ok=True)
    (data/'icons/hicolor/scalable/apps/vibeenergy.svg').unlink(missing_ok=True)
    warning = ''
    if not args.prefix:
        try:
            run_systemctl(['daemon-reload'], timeout=5)
        except (OSError, subprocess.SubprocessError):
            # Removal is already complete. Do not present it as a failed operation
            # or try to restart an installation whose files have been removed.
            warning = ' Service-manager reload is pending; it will be retried when the app is opened again.'
    if args.delete_data:
        for directory in (data/'energytlk',state/'energytlk',config/'energytlk'):
            shutil.rmtree(directory,ignore_errors=True)
    print('Uninstalled. '+('Historical data explicitly deleted.' if args.delete_data else 'Historical data and settings preserved.')+warning)


if __name__ == '__main__':
    main()
