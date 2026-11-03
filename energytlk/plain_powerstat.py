"""Collector-owned accounting for an independently appended Powerstat log.

Only observed fresh clock-only rows receive dates. Never reconstruct an offline
multi-day history from clock times alone. Cursor and totals commit together.
"""
import hashlib
import os
from datetime import datetime, timedelta
from pathlib import Path
from .energy import day_slices
from .powerstat import PowerstatLog

MAX_RAW_BYTES = 40 * 1024 * 1024


class PlainPowerstat:
    def __init__(self, path, db, cleanup=False):
        self.path, self.db, self.cleanup = Path(path), db, cleanup
        self.key = str(self.path.resolve())
        self.state = db.powerstat_cursor(self.key) or {}

    @staticmethod
    def signature(stream, offset):
        stream.seek(max(0, offset-128))
        return hashlib.sha256(stream.read(min(offset,128))).hexdigest()

    @staticmethod
    def dated_clock(clock, now, max_age):
        hour, minute, second = map(int, clock.split(':'))
        # Use the currently observed UTC offset, including the current DST fold.
        local = datetime.fromtimestamp(now).astimezone()
        for shift in (0, -1, 1):
            candidate = (local+timedelta(days=shift)).replace(hour=hour, minute=minute, second=second, microsecond=0).timestamp()
            if -.5 <= now-candidate <= max_age:
                return candidate
        return None

    def read(self, now, max_age, price, account=True, currency=None):
        flags = os.O_RDWR if self.cleanup else os.O_RDONLY
        fd = os.open(self.path, flags | getattr(os, 'O_NOFOLLOW', 0))
        with os.fdopen(fd, 'r+b' if self.cleanup else 'rb', buffering=0) as stream:
            stat = os.fstat(stream.fileno())
            identity = [stat.st_dev, stat.st_ino]
            old = self.state
            offset = old.get('offset', 0)
            valid = (old.get('identity') == identity and offset <= stat.st_size and
                     old.get('signature') == self.signature(stream, offset))
            parser = PowerstatLog(self.path)
            if valid:
                parser.header = old.get('header')
            else:
                old, offset = {}, 0
            previous = old.get('previous')
            continuous = valid and old.get('anchored', False) and 0 <= now-old.get('seen', -1e30) <= max_age
            if not continuous or account != old.get('account', account):
                previous = None
            parts, latest = [], None
            stream.seek(0)
            externally_accounted = stream.readline().startswith(b'# vibeenergy-accounted-v2')
            stream.seek(offset)
            for _ in range(10000):
                line = stream.readline()
                if not line or not line.endswith(b'\n'):
                    break
                offset = stream.tell()
                text = line.decode('utf-8', errors='replace')
                parser.latest = None
                parser.parse(text)
                if 'Running' in text.split()[:2]:
                    previous = None
                if parser.latest is None:
                    continue
                stamp, watts = parser.latest
                dated = stamp is not None
                if stamp is None and parser.live_clock:
                    try:
                        stamp = self.dated_clock(parser.live_clock, now, max_age)
                    except ValueError:
                        stamp = None
                if stamp is None or stamp > now+.5:
                    previous = None
                    continue
                latest = [stamp, watts]
                eligible = dated or continuous
                if account and not externally_accounted and eligible and previous:
                    dt = stamp-previous[0]
                    if 0 < dt <= 2.5:
                        parts.extend(day_slices(previous[0], stamp, watts, watts))
                previous = latest if eligible else None
            reached_end = offset == os.fstat(stream.fileno()).st_size
            fresh = -.5 <= now-stat.st_mtime <= max_age
            # On a cold start, the final fresh clock row anchors subsequent appended
            # rows only; no old clock-only intervals are assigned invented dates.
            if not previous and reached_end and latest and fresh and -.5 <= now-latest[0] <= max_age:
                previous = latest
            if latest is None:
                latest = old.get('latest')
            state = dict(identity=identity, offset=offset, signature=self.signature(stream, offset),
                         header=parser.header, previous=previous, seen=now, latest=latest,
                         day=old.get('day', datetime.fromtimestamp(stat.st_mtime).date().isoformat()), account=account,
                         anchored=previous is not None)
            self.db.commit_powerstat(self.key, state, parts, price, currency)
            self.state = state
            today = datetime.fromtimestamp(now).date().isoformat()
            if (self.cleanup and not externally_accounted and reached_end and
                    (state['day'] != today or stat.st_size >= MAX_RAW_BYTES)):
                # tee writes with O_APPEND. Keep the inode open and never rename it.
                # Abort if a writer appended anything after the consumed snapshot.
                if os.fstat(stream.fileno()).st_size == offset:
                    prefix = ('# vibeenergy-collector-v3 day='+today+'\n'+
                              (' '.join(parser.header)+'\n' if parser.header else '')).encode()
                    os.ftruncate(stream.fileno(), len(prefix))
                    os.pwrite(stream.fileno(), prefix, 0)
                    os.fsync(stream.fileno())
                    state.update(offset=len(prefix), signature=self.signature(stream, len(prefix)),
                                 day=today, previous=None, anchored=False)
                    self.db.commit_powerstat(self.key, state, [], price, currency)
            if latest and fresh and -.5 <= now-latest[0] <= max_age:
                return (latest[0], latest[1]), 'CPU log accounted by collector', externally_accounted
            return None, 'Waiting for fresh CPU samples; ambiguous offline intervals are excluded', externally_accounted
