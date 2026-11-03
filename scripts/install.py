#!/usr/bin/env python3
"""Install only under XDG user directories. --prefix enables isolated staging/tests."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
ID = 'org.energytlk.monitor'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prefix', type=Path, help='Stage a relocatable test home; do not call systemd')
    parser.add_argument('--autostart', action='store_true', help='Enable collector at login')
    parser.add_argument('--no-start', action='store_true')
    args = parser.parse_args()
    if os.geteuid() == 0:
        parser.error('Install as your regular user')
    home = (args.prefix or Path.home()).resolve()
    data = home/'.local/share' if args.prefix else Path(os.environ.get('XDG_DATA_HOME', home/'.local/share'))
    config = home/'.config' if args.prefix else Path(os.environ.get('XDG_CONFIG_HOME', home/'.config'))
    lib = data/'energytlk/app'
    package = data/'plasma/plasmoids'/ID
    service = config/'systemd/user/energytlk.service'
    subprocess.run(['cmake', '-S', str(ROOT), '-B', str(ROOT/'build'), '-DCMAKE_BUILD_TYPE=Release', '-DBUILD_TESTING=OFF'], check=True)
    subprocess.run(['cmake', '--build', str(ROOT/'build'), '-j2'], check=True)
    lib.mkdir(parents=True, exist_ok=True)
    shutil.copytree(ROOT/'energytlk', lib/'energytlk', dirs_exist_ok=True, ignore=shutil.ignore_patterns('__pycache__'))
    shutil.copytree(ROOT/'plasmoid', package, dirs_exist_ok=True)
    shutil.copytree(ROOT/'build/EnergyLocal', package/'contents/ui/EnergyLocal', dirs_exist_ok=True)
    # Remove obsolete privileged-adapter setup from previous app versions.
    shutil.rmtree(lib/'powerstat-setup', ignore_errors=True)
    shutil.copy2(ROOT/'scripts/uninstall.py', lib/'uninstall.py')
    shutil.copy2(ROOT/'build/energytlk-instance', lib/'energytlk-instance')
    shutil.copy2(ROOT/'README.md', lib/'README.md')
    shutil.copy2(ROOT/'VALIDATION.md', lib/'VALIDATION.md')
    service.parent.mkdir(parents=True, exist_ok=True)
    # Quote systemd values; %% escapes specifier expansion in user-controlled paths.
    def quote(value):
        return '"'+str(value).replace('\\', '\\\\').replace('"', '\\"').replace('%', '%%')+'"'
    service.write_text('''[Unit]
Description=vibeenergy unprivileged CPU/GPU energy collector
After=graphical-session-pre.target

[Service]
Type=simple
'''+'WorkingDirectory='+str(lib).replace('%', '%%').replace('\\', r'\x5c').replace(' ', r'\x20').replace('\n', r'\n')+'\nExecStart='+quote(sys.executable)+' -m energytlk\n'+'''Restart=on-failure
RestartSec=10
TimeoutStopSec=10
UMask=0077
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=-%h/.local/share/energytlk -%h/.local/state/energytlk
RestrictAddressFamilies=AF_UNIX
LockPersonality=yes
RestrictSUIDSGID=yes

[Install]
WantedBy=default.target
''')
    # Ensure sandbox write paths exist before the service starts, including custom XDG roots.
    state = home/'.local/state' if args.prefix else Path(os.environ.get('XDG_STATE_HOME',home/'.local/state'))
    for directory in (data/'energytlk',state/'energytlk',config/'energytlk'):
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    with service.open('a') as f:
        f.write('\n[Service]\nReadWritePaths='+quote(data/'energytlk')+' '+quote(state/'energytlk')+' '+quote(home/'.vibeenergy/logs')+'\n')
        for key,value in [('XDG_DATA_HOME',data),('XDG_CONFIG_HOME',config),('XDG_STATE_HOME',state)]:
            f.write('Environment='+quote(f'{key}={value}')+'\n')
    # Migrate the previous sampling default once, preserving tariff and other settings.
    sampling_policy = config/'energytlk/one-second-default'
    settings_file = config/'energytlk/config.json'
    if not sampling_policy.exists():
        if settings_file.exists():
            settings = json.loads(settings_file.read_text())
            if settings.get('interval', 10) == 10:
                settings['interval'] = 1
            settings['retention_days'] = 1
            settings_tmp = settings_file.with_suffix('.install.tmp')
            settings_tmp.write_text(json.dumps(settings, indent=2)+'\n')
            settings_tmp.chmod(0o600)
            settings_tmp.replace(settings_file)
        sampling_policy.touch(mode=0o600)
    logs = home/'.vibeenergy/logs'
    logs.mkdir(parents=True, exist_ok=True, mode=0o700)
    for filename in ('powerstat.log', 'powerstat.log.lock', 'powerstat.log.runner.lock'):
        if not (logs/filename).exists():
            (logs/filename).touch(mode=0o600)
    # Prepare the optional system unit as the desktop user. Activation is explicit.
    (lib/'cpu-temporary').unlink(missing_ok=True)
    (lib/'vibeenergy-powerstat.service').write_text(
        '[Unit]\nDescription=Powerstat one-second recording for vibeenergy\nAfter=local-fs.target\n\n'
        '[Service]\nType=simple\nExecStart=/usr/bin/stdbuf -oL /usr/bin/powerstat -R -D -d 0 1 43200\n'
        'Restart=always\nRestartSec=1\nUMask=0077\nNoNewPrivileges=yes\n'
        'CapabilityBoundingSet=\nPrivateTmp=yes\nProtectSystem=strict\n'
        'SystemCallFilter=~socket\nSystemCallErrorNumber=EPROTONOSUPPORT\n'
        'ProtectHome=read-only\nReadWritePaths='+quote(logs)+' '+quote(data/'energytlk')+'\n'
        'StandardOutput=append:'+str(logs/'powerstat.log').replace('\\',r'\x5c').replace(' ',r'\x20').replace('%','%%')+'\nStandardError=journal\n\n[Install]\nWantedBy=multi-user.target\n')
    icons = data/'icons/hicolor/scalable/apps'
    icons.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT/'plasmoid/contents/icons/vibeenergy.svg', icons/'vibeenergy.svg')
    applications = data/'applications'
    applications.mkdir(parents=True, exist_ok=True)
    def desktop_argument(value):
        quoted = ''.join('\\'+char if char in '\\"`$' else char for char in str(value))
        return '"'+quoted.replace('\\','\\\\').replace('%','%%').replace('\n',r'\n').replace('\r',r'\r').replace('\t',r'\t')+'"'
    (applications/'vibeenergy.desktop').write_text(f"""[Desktop Entry]
Type=Application
Name=VibeEnergy
Comment=CPU and GPU energy monitoring
Exec={desktop_argument(lib/"energytlk-instance")} {desktop_argument(shutil.which("plasmawindowed") or "plasmawindowed")} -qwindowicon {desktop_argument(icons/"vibeenergy.svg")} org.energytlk.monitor
Icon=vibeenergy
Terminal=false
Categories=System;Monitor;
StartupNotify=true
StartupWMClass=vibeenergy
""")
    (applications/'org.energytlk.monitor.desktop').write_text((applications/'vibeenergy.desktop').read_text()+'NoDisplay=true\n')
    if args.prefix:
        print('Staged installation:', home)
        return
    try:
        subprocess.run(['systemctl','--user','daemon-reload'], check=True)
        if args.autostart:
            subprocess.run(['systemctl','--user','enable','energytlk.service'], check=True)
        if not args.no_start:
            subprocess.run(['systemctl','--user','restart','energytlk.service'], check=True)
    except (OSError,subprocess.CalledProcessError):
        print('Files installed, but the collector did not start. Inspect systemctl --user status energytlk.service and its journal; see README for manual fallback.',file=sys.stderr)
        sys.exit(1)
    print('Installed. Open vibeenergy from your application menu. A Plasma widget is also available.')


if __name__ == '__main__':
    main()
