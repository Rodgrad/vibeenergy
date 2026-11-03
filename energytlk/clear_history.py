"""Confirmed reset of VibeEnergy recordings; configuration is preserved."""
from contextlib import ExitStack
import fcntl
import os
from pathlib import Path
import sqlite3
import stat
import subprocess
import sys
import time
from .config import paths, load, atomic_json
from .control import main as stop_recording, stop_collector


def active(state):
    try:
        with (state/'collector.lock').open('r+') as lock:
            try:
                fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
                return False
            except BlockingIOError:
                return True
    except FileNotFoundError:
        return False


def clear_recordings(data, state, home, config):
    """Called only after both app collectors have stopped."""
    targets = set()
    for directory in (home/'.vibeenergy/logs', state, state/'demo'):
        if directory.is_dir():
            targets.update(directory.glob('*.log'))
            targets.update(p for p in directory.glob('*.log.*') if not p.name.endswith('.lock'))
    if config.get('powerstat_log'):
        targets.add(Path(config['powerstat_log']))
    with ExitStack() as stack:
        logs=[]
        # Preflight every file before deleting history; never follow log symlinks.
        for path in sorted(targets):
            if not path.exists() and not path.is_symlink():continue
            fd=os.open(path,os.O_WRONLY|os.O_NONBLOCK|os.O_NOFOLLOW)
            stack.callback(os.close,fd)
            info=os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_uid!=os.getuid():
                raise RuntimeError('Cannot clear a log that is not a regular file owned by you: '+str(path))
            logs.append(fd)
        databases=[]
        for directory in (data,data/'demo'):
            path=directory/'energy.sqlite3'
            if path.exists():
                if path.is_symlink():raise RuntimeError('Refusing to clear a database symlink.')
                db=sqlite3.connect(path,timeout=10)
                stack.callback(db.close)
                if db.execute('PRAGMA quick_check').fetchone()[0]!='ok':raise RuntimeError('Database integrity check failed; history preserved.')
                db.execute('BEGIN IMMEDIATE')
                stack.callback(db.rollback)
                tables={r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                for table in ('samples','daily','daily_cost','observation','powerstat_cursors','currency_branches'):
                    if table in tables:db.execute('DELETE FROM '+table)
                databases.append(db)
        for db in databases:db.commit()
        # Preserve open writer inodes, rather than unlinking log files.
        for fd in logs:os.ftruncate(fd,0)
        for db in databases:
            db.execute('PRAGMA wal_checkpoint(TRUNCATE)')
            db.execute('VACUUM')
    for directory in (state,state/'demo'):
        snapshot=directory/'state.json'
        if snapshot.exists():
            atomic_json(snapshot,dict(running=False,config=config,daily=[],currencies=[],devices=[],observation={},history_generation=str(time.time_ns())))


def restart(simulated, env):
    host=dict(env)
    for key in ('LD_LIBRARY_PATH','LD_PRELOAD','PYTHONHOME','PYTHONPATH','QT_PLUGIN_PATH','QML_IMPORT_PATH','QML2_IMPORT_PATH'):host.pop(key,None)
    if host.get('VIBEENERGY_HOST_PATH'):host['PATH']=host['VIBEENERGY_HOST_PATH']
    if not simulated:
        try:
            result=subprocess.run(['/usr/bin/systemctl','--user','start','energytlk.service'],env=host,capture_output=True,timeout=10)
            if result.returncode==0:return
        except (OSError,subprocess.SubprocessError):pass
    args=['--simulate'] if simulated else []
    if env.get('APPIMAGE'):
        command=[env['APPIMAGE'],'--appimage-extract-and-run','--collector']+args
        child_env=host
        child_env.pop('APPDIR',None)
    else:
        command=[sys.executable,'-m','energytlk']+args
        child_env=env
    subprocess.Popen(command,env=child_env,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)


def main():
    _,data,state=paths()
    state.mkdir(parents=True,exist_ok=True)
    with (state/'clear-history.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        was_active=[active(state),active(state/'demo')]
        error=None
        try:
            if stop_recording()!=0:raise RuntimeError('Could not stop the collector; history was not cleared.')
            stop_collector(state/'demo')
            clear_recordings(data,state,Path.home(),load())
        except Exception as exc:
            error=exc
        finally:
            for simulated,running in enumerate(was_active):
                if running:
                    try:
                        restart(bool(simulated),dict(os.environ))
                        deadline=time.monotonic()+8
                        directory=state/'demo' if simulated else state
                        while not active(directory) and time.monotonic()<deadline:time.sleep(.05)
                        if not active(directory):raise RuntimeError('Recording could not restart. Reopen VibeEnergy to start it.')
                    except Exception as exc:error=exc if error is None else RuntimeError(str(error)+' '+str(exc))
        if error:
            print(str(error),file=sys.stderr)
            return 1
    print('All recorded history and logs cleared. Settings preserved.')
    return 0


if __name__=='__main__':sys.exit(main())
