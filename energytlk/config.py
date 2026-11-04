import json
import math
import os
from pathlib import Path


def paths():
    return (Path(os.environ.get('XDG_CONFIG_HOME', Path.home()/'.config'))/'energytlk',
            Path(os.environ.get('XDG_DATA_HOME', Path.home()/'.local/share'))/'energytlk',
            Path(os.environ.get('XDG_STATE_HOME', Path.home()/'.local/state'))/'energytlk')


DEFAULTS = dict(price=0.177, currency='EUR', interval=1, retention_days=1, powerstat_log='')


def validate(data):
    result = DEFAULTS | data
    result['price'] = float(str(result['price']).replace(',', '.'))
    if not math.isfinite(result['price']) or not 0 <= result['price'] <= 10000:
        raise ValueError('Price must be between 0 and 10000 per kWh')
    result['interval'] = int(result['interval'])
    if not 1 <= result['interval'] <= 5:
        raise ValueError('Interval must be 1–5 seconds')
    result['retention_days'] = int(result['retention_days'])
    if not 1 <= result['retention_days'] <= 36500:
        raise ValueError('Retention must be 1–36500 days')
    result['retention_days'] = 1
    if not isinstance(result['currency'], str) or not result['currency'].isascii() or not result['currency'].isalpha() or len(result['currency']) != 3:
        raise ValueError('Use a three-letter currency code')
    result['currency'] = result['currency'].upper()
    if not isinstance(result['powerstat_log'], str):
        raise ValueError('Log path must be text')
    if result['powerstat_log'] and not Path(result['powerstat_log']).is_absolute():
        raise ValueError('Log path must be absolute')
    return result


def load():
    path = paths()[0]/'config.json'
    data = json.loads(path.read_text()) if path.exists() else {}
    # Accept settings saved before the maximum was reduced to five seconds.
    if 5 < int(data.get('interval', DEFAULTS['interval'])) <= 300:
        data['interval'] = 5
    return validate(data)


def atomic_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    tmp = path.with_suffix('.tmp')
    with tmp.open('w') as f:
        os.chmod(tmp, 0o600)
        json.dump(data, f, allow_nan=False)
        f.flush()
        os.fsync(f.fileno())
    tmp.replace(path)
