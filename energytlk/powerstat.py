"""Read-only Powerstat file reader, running inside the unprivileged app."""
import math
import re
from datetime import datetime
from pathlib import Path

DEFAULT_LOG_PATH = Path.home()/'.vibeenergy/logs/powerstat.log'


def discover_log(configured='', default=None):
    """Prefer the shared Powerstat log, with legacy-folder and explicit overrides."""
    if configured:
        return configured
    path = DEFAULT_LOG_PATH if default is None else Path(default)
    try:
        directory = path.parent.resolve()
        if path.is_file() and path.stat().st_size > 0 and path.resolve().is_relative_to(directory):
            return str(path)
        candidates = [p for p in directory.glob('*.log') if p.is_file() and p.stat().st_size > 0 and p.resolve().is_relative_to(directory)]
        candidates.sort(key=lambda p: p.stat().st_mtime, reverse=True)
        return str(candidates[0]) if candidates else ''
    except OSError:
        return ''


class PowerstatLog:
    def __init__(self, path):
        self.path = Path(path)
        self.identity = None
        self.offset = 0
        self.header = None
        self.latest = None
        self.logger_session = None
        self.energy_eligible = True
        self.live_clock = None
        self.accounted = False
        self.note = 'Waiting for a complete Powerstat header and sample'

    def read(self, now, max_age):
        stat = self.path.stat()
        identity = (stat.st_dev, stat.st_ino)
        if identity != self.identity or stat.st_size < self.offset:
            self.identity, self.offset, self.header, self.latest = identity, 0, None, None
            self.logger_session = None
        with self.path.open() as f:
            self.accounted = f.readline().startswith('# vibeenergy-accounted-v2')
            if stat.st_size-self.offset > 1024*1024:
                self.offset = stat.st_size-1024*1024
                f.seek(self.offset)
                f.readline()
                self.offset = f.tell()
                self.header = None
            f.seek(self.offset)
            for _ in range(10000):
                line = f.readline()
                if not line or not line.endswith('\n'):
                    break
                self.offset = f.tell()
                self.parse(line)
        if not self.latest:
            return None, self.note
        stamp, watts = self.latest
        self.energy_eligible = stamp is not None
        if stamp is None:
            if self.live_clock is None or not 0 <= now-stat.st_mtime <= max_age:
                return None, 'Powerstat log is stale'
            local = datetime.fromtimestamp(now)
            h, m, second = map(int, self.live_clock.split(':'))
            distance = ((local.hour*3600+local.minute*60+local.second-(h*3600+m*60+second)+43200) % 86400)-43200
            if abs(distance)>max_age:
                return None, 'Powerstat sample time is stale'
            return (None, watts), 'Live CPU watts from log; CPU energy history unavailable without full dates' 
        if not 0 <= now-stamp <= max_age:
            return None, 'Powerstat log is stale or timestamp is in the future'
        return (stamp, watts), 'Imported CPU-package readings from Powerstat log'

    def parse(self, line):
        if line.startswith('# vibeenergy-accounted-v2'):
            self.accounted = True
            return
        # Read old adapter files for compatibility; no privileged Python adapter is installed.
        if line.startswith('# vibeenergy-powerstat v1 '):
            fields = dict(part.split('=', 1) for part in line.split() if '=' in part)
            if fields.get('scope') == 'cpu-package' and fields.get('interval') == '10':
                self.logger_session = fields.get('session')
            return
        tokens = line.split()
        if not tokens:
            return
        stamp = None
        prefixed = False
        try:
            if re.fullmatch(r'\d{4}-\d\d-\d\d', tokens[0]) and len(tokens)>1:
                tokens = [tokens[0]+'T'+tokens[1]]+tokens[2:]
            if re.match(r'^\d{4}-\d\d-\d\dT', tokens[0]):
                stamp = datetime.fromisoformat(tokens[0].replace('Z', '+00:00')).timestamp()
                if len(tokens)>1 and (tokens[1] == 'Time' or re.fullmatch(r'\d\d:\d\d:\d\d',tokens[1]) or not re.match(r'^[\d.-]+$',tokens[1])):
                    tokens = tokens[1:]
                    prefixed = True
            if not tokens:
                return
            if tokens[0]=='Running':
                self.latest = None
                self.logger_session = str(stamp) if stamp is not None else None
                return
            if 'Time' in tokens and 'Watts' in tokens:
                self.header = tokens
                if prefixed and self.logger_session is None:
                    self.logger_session = str(stamp)
                return
            if not self.header or any(x.lower().startswith(('average','summary','stddev','minimum','maximum')) for x in tokens):
                return
            if stamp is None and not re.fullmatch(r'\d\d:\d\d:\d\d',tokens[0]):
                return
            packages = [i for i,name in enumerate(self.header) if re.fullmatch(r'(pkg|package)-\d+',name)]
            if packages:
                if len({self.header[i] for i in packages}) != len(packages):
                    self.note = 'Duplicate CPU package columns; refusing overlapping values'
                    return
                values = [float(tokens[i]) for i in packages]
            else:
                if prefixed:
                    self.note = 'No CPU package columns. Start Powerstat with -R -D as shown in CPU setup'
                    return
                values = [float(tokens[self.header.index('Watts')])]
            if not all(math.isfinite(value) and 0<=value<=10000 for value in values):
                return
            self.latest = stamp, sum(values)
            self.live_clock = tokens[0] if stamp is None else None
        except (ValueError, IndexError):
            return
