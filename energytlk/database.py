import json
import sqlite3
from datetime import date, timedelta


class Database:
    def __init__(self, path):
        from .config import load
        config = load()
        self.currency = config['currency']
        self.db = sqlite3.connect(path, timeout=10)
        try:
            if self.db.execute('PRAGMA quick_check').fetchone()[0] != 'ok':
                raise RuntimeError('Database integrity check failed; original data preserved. Restore a backup before collecting.')
            self.db.execute('PRAGMA journal_mode=WAL')
            self.db.execute('PRAGMA busy_timeout=10000')
            version = self.db.execute('PRAGMA user_version').fetchone()[0]
            if version > 3:
                raise RuntimeError('Database is newer than this collector; upgrade required')
        except Exception:
            self.db.close()
            raise
        if version < 3:
            self.db.executescript('''
                CREATE TABLE IF NOT EXISTS samples(
                    timestamp REAL, session TEXT, device TEXT, kind TEXT, watts REAL,
                    source TEXT, quality TEXT, error TEXT, flags TEXT, wh REAL);
                CREATE INDEX IF NOT EXISTS sample_time ON samples(timestamp);
                CREATE TABLE IF NOT EXISTS daily(
                    day TEXT, device TEXT, kind TEXT, quality TEXT, wh REAL NOT NULL,
                    covered REAL NOT NULL, PRIMARY KEY(day,device,quality));
                CREATE TABLE IF NOT EXISTS observation(day TEXT PRIMARY KEY, seconds REAL NOT NULL);
                CREATE VIEW IF NOT EXISTS monthly AS SELECT substr(day,1,7) AS month,
                    kind, quality, sum(wh) AS wh FROM daily GROUP BY month,kind,quality;
                CREATE TABLE IF NOT EXISTS powerstat_cursors(path TEXT PRIMARY KEY, state TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS daily_cost(
                    day TEXT, device TEXT, quality TEXT, cost REAL NOT NULL,
                    PRIMARY KEY(day,device,quality));
            ''')
        # Collector and independent CPU recorder may start simultaneously.
        with self.db:
            self.db.execute('BEGIN IMMEDIATE')
            if self.db.execute('PRAGMA user_version').fetchone()[0] < 3:
                legacy = config.get('history_currency', config['currency'])
                self.db.execute('DROP VIEW IF EXISTS monthly')
                self.db.execute('ALTER TABLE daily RENAME TO daily_legacy')
                self.db.execute('ALTER TABLE daily_cost RENAME TO daily_cost_legacy')
                self.db.execute('''CREATE TABLE daily(
                    day TEXT, device TEXT, kind TEXT, quality TEXT, wh REAL NOT NULL,
                    covered REAL NOT NULL, currency TEXT NOT NULL,
                    PRIMARY KEY(day,device,quality,currency))''')
                self.db.execute('''CREATE TABLE daily_cost(
                    day TEXT, device TEXT, quality TEXT, cost REAL NOT NULL, currency TEXT NOT NULL,
                    PRIMARY KEY(day,device,quality,currency))''')
                self.db.execute('INSERT INTO daily SELECT *, ? FROM daily_legacy', (legacy,))
                self.db.execute('''INSERT INTO daily_cost
                    SELECT d.day,d.device,d.quality,COALESCE(c.cost,d.wh/1000*?),?
                    FROM daily_legacy d LEFT JOIN daily_cost_legacy c USING(day,device,quality)''',
                    (config.get('history_price', config['price']), legacy))
                self.db.execute('DROP TABLE daily_legacy')
                self.db.execute('DROP TABLE daily_cost_legacy')
                self.db.execute('''CREATE VIEW monthly AS SELECT substr(day,1,7) AS month,
                    kind,quality,currency,sum(wh) AS wh FROM daily GROUP BY month,kind,quality,currency''')
                self.db.execute('CREATE TABLE currency_branches(currency TEXT PRIMARY KEY)')
                self.db.execute('INSERT OR IGNORE INTO currency_branches SELECT DISTINCT currency FROM daily')
                self.db.execute('PRAGMA user_version=3')
            for currency in config.get('history_currencies', []):
                self._branch(currency)

    def branches(self):
        return [r[0] for r in self.db.execute('SELECT currency FROM currency_branches ORDER BY currency')]

    def _branch(self, currency):
        self.db.execute('INSERT OR IGNORE INTO currency_branches VALUES(?)', (currency,))

    def record(self, wall, session, readings, segments, observed=(), price=None, currency=None):
        currency = currency or self.currency
        with self.db:
            self._branch(currency)
            for r in readings:
                parts = segments.get(r['id'], [])
                self.db.execute('INSERT INTO samples VALUES(?,?,?,?,?,?,?,?,?,?)',
                    (wall, session, r['id'], r['kind'], r['watts'], r['source'], r['quality'],
                     r['error'], json.dumps({'account': r.get('account', True), 'interval_average': r.get('interval_average', False), 'energy_eligible': r.get('energy_eligible', True)}),
                     sum(x[1] for x in parts) if parts else None))
                for day, wh, seconds in parts:
                    if price is not None:
                        self._record_cost(day, r['id'], r['quality'], wh, price, currency)
                    self.db.execute('''INSERT INTO daily VALUES(?,?,?,?,?,?,?)
                        ON CONFLICT(day,device,quality,currency) DO UPDATE SET wh=wh+excluded.wh, covered=covered+excluded.covered''',
                        (day, r['id'], r['kind'], r['quality'], wh, seconds, currency))
            for day, _, seconds in observed:
                self.db.execute('''INSERT INTO observation VALUES(?,?) ON CONFLICT(day)
                    DO UPDATE SET seconds=seconds+excluded.seconds''', (day, seconds))

    def _record_cost(self, day, device, quality, wh, price, currency):
        existing = self.db.execute('SELECT wh FROM daily WHERE day=? AND device=? AND quality=? AND currency=?',
                                   (day, device, quality, currency)).fetchone()
        # Older summaries have no historical tariff; preserve their current valuation once.
        baseline = existing[0]/1000*price if existing else 0
        self.db.execute('''INSERT INTO daily_cost VALUES(?,?,?,?,?)
            ON CONFLICT(day,device,quality,currency) DO UPDATE SET cost=cost+?''',
            (day, device, quality, baseline+wh/1000*price, currency, wh/1000*price))

    def _powerstat_parts(self, parts, price, currency):
        self._branch(currency)
        for day, wh, seconds in parts:
            self._record_cost(day, 'cpu:powerstat', 'imported from log', wh, price, currency)
            self.db.execute('''INSERT INTO daily VALUES(?,?,?,?,?,?,?)
                ON CONFLICT(day,device,quality,currency) DO UPDATE SET wh=wh+excluded.wh, covered=covered+excluded.covered''',
                (day, 'cpu:powerstat', 'cpu', 'imported from log', wh, seconds, currency))

    def record_powerstat(self, parts, price, currency=None):
        with self.db:
            self._powerstat_parts(parts, price, currency or self.currency)

    def powerstat_cursor(self, key):
        row = self.db.execute('SELECT state FROM powerstat_cursors WHERE path=?', (key,)).fetchone()
        return json.loads(row[0]) if row else None

    def commit_powerstat(self, key, state, parts, price, currency=None):
        with self.db:
            self._powerstat_parts(parts, price, currency or self.currency)
            self.db.execute('''INSERT INTO powerstat_cursors VALUES(?,?)
                ON CONFLICT(path) DO UPDATE SET state=excluded.state''', (key, json.dumps(state)))

    def report(self, price):
        return [dict(day=d, device=device, kind=kind, quality=quality, kwh=wh/1000,
                     cost=stored_cost if stored_cost is not None else wh/1000*price, covered_seconds=seconds, currency=currency)
                for d, device, kind, quality, wh, seconds, currency, stored_cost in self.db.execute('SELECT d.*, c.cost FROM daily d LEFT JOIN daily_cost c USING(day,device,quality,currency) ORDER BY day,currency')]

    def last_valid(self):
        return dict(self.db.execute('SELECT device, max(timestamp) FROM samples WHERE watts IS NOT NULL GROUP BY device'))

    def observations(self):
        return dict(self.db.execute('SELECT * FROM observation'))

    def prune(self, days):
        cutoff = date.today().isoformat()
        with self.db:
            # Permanent daily summaries and monthly view retain all usage totals.
            self.db.execute("DELETE FROM samples WHERE timestamp < strftime('%s',?, 'utc')", (cutoff,))
        self.db.execute('PRAGMA wal_checkpoint(PASSIVE)')
        pages = self.db.execute('PRAGMA page_count').fetchone()[0]
        free = self.db.execute('PRAGMA freelist_count').fetchone()[0]
        if free > 1024 and free > pages/2:
            # Reclaim an old installation's multi-day raw sample allocation.
            self.db.execute('VACUUM')

    def close(self):
        self.db.execute('PRAGMA wal_checkpoint(TRUNCATE)')
        self.db.close()
