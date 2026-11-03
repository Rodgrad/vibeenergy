"""Unprivileged stdin recorder: commit daily totals before retaining raw output."""
import argparse
import fcntl
import os
import sys
import time
from datetime import datetime
from pathlib import Path
from .config import load
from .database import Database
from .energy import day_slices
from .powerstat import PowerstatLog

MAX_RAW_BYTES = 40 * 1024 * 1024
MARKER = '# vibeenergy-accounted-v2\n'


class Recorder:
    def __init__(self, log, db, price, clock=time.time, boot=None, currency=None):
        self.log, self.db, self.price, self.clock = Path(log), db, price, clock
        self.boot = boot or (lambda: time.clock_gettime(time.CLOCK_BOOTTIME))
        self.currency = currency or (lambda: db.currency)
        self.parser = PowerstatLog(log)
        self.previous = None
        self.day = None
        self.header = None
        # Read the old day marker without relying on its filesystem modification time.
        with self.log.open() as stream:
            for _ in range(4):
                line = stream.readline()
                if line.startswith('# day='):
                    self.day = line.strip()[6:]
                    break

    def accept(self, line):
        wall, boot = self.clock(), self.boot()
        stamp = datetime.fromtimestamp(wall).astimezone()
        day = stamp.date().isoformat()
        if line.startswith('Running'):
            self.previous = None
        dated = stamp.isoformat(timespec='microseconds')+' '+line.rstrip('\n')+'\n'
        self.parser.latest = None
        self.parser.parse(dated)
        if 'Time' in line.split() and 'Watts' in line.split():
            self.header = line.rstrip('\n')
        sample = self.parser.latest
        if sample:
            old = self.previous
            self.previous = wall, boot, sample[1]
            parts = []
            if old:
                ow, ob, _ = old
                dt = wall-ow
                # RAPL reports the average over the preceding measurement interval.
                if 0 < dt <= 2.5 and abs((boot-ob)-dt) < .5:
                    parts = list(day_slices(ow, wall, sample[1], sample[1]))
            self.db.record_powerstat(parts, self.price(), self.currency())
        # This file is diagnostic only: every sample above is committed before cleanup.
        reset = self.day != day or self.log.stat().st_size + len(dated.encode()) > MAX_RAW_BYTES
        with self.log.open('w' if reset else 'a') as stream:
            if reset:
                stream.write(MARKER+'# day='+day+'\n')
                if self.header and line.rstrip('\n') != self.header:
                    stream.write(stamp.isoformat(timespec='microseconds')+' '+self.header+'\n')
            stream.write(dated)
        if self.day != day:
            self.db.prune(1)
        self.day = day


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--log', required=True)
    parser.add_argument('--data', required=True)
    parser.add_argument('--config', required=True)
    args = parser.parse_args()
    if os.geteuid() == 0:
        parser.error('Recorder must run as the desktop user')
    os.umask(0o077)
    # All directories and files are prepared by the standalone installer.
    os.environ['XDG_CONFIG_HOME'] = str(Path(args.config).parent)
    with open(args.log+'.lock', 'r+') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            parser.exit(1, 'A Powerstat recorder is already running\n')
        db = Database(Path(args.data)/'energy.sqlite3')
        cached = load()
        def price():
            nonlocal cached
            # Read the tariff and currency together for each committed measurement.
            cached = load()
            return cached['price']
        try:
            recorder = Recorder(args.log, db, price, currency=lambda: cached['currency'])
            for line in sys.stdin:
                recorder.accept(line)
        finally:
            db.close()


if __name__ == '__main__':
    main()
