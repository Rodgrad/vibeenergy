"""Prepare writable user files and the collector when launching the portable app."""
from pathlib import Path
import os
import shutil
import subprocess
import sys

if os.geteuid() == 0:
    sys.exit('Run VibeEnergy as your normal user, without sudo.')
appdir = Path(os.environ['APPDIR'])
image = Path(os.environ.get('APPIMAGE', appdir/'AppRun')).resolve()
home = Path.home()
data = Path(os.environ.get('XDG_DATA_HOME', home/'.local/share'))
config = Path(os.environ.get('XDG_CONFIG_HOME', home/'.config'))
state = Path(os.environ.get('XDG_STATE_HOME', home/'.local/state'))
def desktop_argument(value):
    # Quote an Exec argument, then apply desktop-entry string escaping.
    quoted = ''.join('\\' + char if char in '\\"`$' else char for char in str(value))
    escaped = quoted.replace('\\', '\\\\').replace('\n', r'\n').replace('\r', r'\r').replace('\t', r'\t')
    return '"' + escaped.replace('%', '%%') + '"'

icons = data/'icons/hicolor/scalable/apps'
icons.mkdir(parents=True, exist_ok=True)
shutil.copy2(appdir/'vibeenergy.svg', icons/'vibeenergy.svg')
applications = data/'applications'
applications.mkdir(parents=True, exist_ok=True)
(applications/'vibeenergy.desktop').write_text(
    '[Desktop Entry]\nType=Application\nName=VibeEnergy\n'
    'Comment=CPU and GPU energy and electricity cost monitor\n'
    'Exec='+desktop_argument(image)+'\nIcon=vibeenergy\nTerminal=false\n'
    'Categories=System;Monitor;\nStartupNotify=true\nStartupWMClass=vibeenergy\n')

(applications/'org.energytlk.monitor.desktop').write_text((applications/'vibeenergy.desktop').read_text()+'NoDisplay=true\n')

logs = home/'.vibeenergy/logs'
for folder in (logs, data/'energytlk/app', config/'energytlk', state/'energytlk', config/'systemd/user'):
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
for name in ('powerstat.log', 'powerstat.log.lock', 'powerstat.log.runner.lock'):
    path = logs/name
    if not path.exists():
        path.touch(mode=0o600)

def quote(value):
    return '"'+str(value).replace('\\', '\\\\').replace('"', '\\"').replace('%', '%%')+'"'

service = config/'systemd/user/energytlk.service'
unit = ('[Unit]\nDescription=VibeEnergy portable unprivileged collector\n'
        '[Service]\nType=simple\nExecStart='+quote(image)+' --appimage-extract-and-run --collector\n'
        'Restart=on-failure\nRestartSec=10\nUMask=0077\nNoNewPrivileges=yes\n'
        '[Install]\nWantedBy=default.target\n')
for key in ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_STATE_HOME'):
    if key in os.environ:
        unit+='\n[Service]\nEnvironment='+quote(key+'='+os.environ[key])+'\n'
changed = not service.exists() or service.read_text()!=unit
if changed:
    service.write_text(unit)
# Prepare the optional Powerstat unit; only the user's explicit terminal command activates it.
powerstat = ('[Unit]\nDescription=Powerstat CPU measurements for VibeEnergy\nAfter=local-fs.target\n'
             '[Service]\nType=simple\nExecStart=/usr/bin/stdbuf -oL /usr/bin/powerstat -R -D -d 0 1 43200\n'
             'StandardOutput=append:'+str(logs/'powerstat.log').replace('%', '%%')+'\n'
             'StandardError=journal\nRestart=always\nRestartSec=1\nUMask=0077\n'
             'NoNewPrivileges=yes\nCapabilityBoundingSet=\nPrivateTmp=yes\nPrivateDevices=yes\n'
             'ProtectSystem=strict\nProtectHome=read-only\nSystemCallArchitectures=native\n'
             'SystemCallFilter=~socket\nSystemCallErrorNumber=EPROTONOSUPPORT\n'
             '[Install]\nWantedBy=multi-user.target\n')
(data/'energytlk/app/vibeenergy-powerstat.service').write_text(powerstat)
host_env = dict(os.environ)
for key in ('LD_LIBRARY_PATH', 'PYTHONHOME', 'PYTHONPATH', 'QT_PLUGIN_PATH', 'QML_IMPORT_PATH', 'QML2_IMPORT_PATH'):
    host_env.pop(key, None)
try:
    if changed:
        subprocess.run(['/usr/bin/systemctl','--user','daemon-reload'], env=host_env, check=True, timeout=15)
    subprocess.run(['/usr/bin/systemctl','--user','restart' if changed else 'start','energytlk.service'], env=host_env, check=True, timeout=20)
except (OSError, subprocess.SubprocessError):
    # A separate AppImage invocation retains its own runtime mount after the window closes.
    output = (state/'energytlk/portable-collector.log').open('a')
    subprocess.Popen([str(image),'--appimage-extract-and-run','--collector'], env=host_env, stdin=subprocess.DEVNULL,
                     stdout=output, stderr=output, start_new_session=True)
