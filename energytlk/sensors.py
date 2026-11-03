import csv
import math
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import time
from .energy import counter_delta


def number(path):
    value = float(path.read_text().strip())
    if not math.isfinite(value) or value < 0:
        raise ValueError('Invalid nonnegative sensor value')
    return value


def vendor(path):
    try:
        return (path/'vendor').read_text().strip()
    except OSError:
        return ''


def nvidia_smi_binary():
    binary = shutil.which('nvidia-smi')
    appdir = os.environ.get('APPDIR')
    if binary and appdir and Path(binary).resolve() == (Path(appdir)/'usr/bin/nvidia-smi').resolve():
        # The AppImage ships a host-tool launcher, not NVIDIA's actual utility.
        if not os.access('/usr/bin/nvidia-smi', os.X_OK):
            return None
    return binary


def reading(key, name, kind, source, watts=None, error='', **extra):
    return dict(id=key, name=name, kind=kind, source=source, watts=watts,
                quality='measured' if watts is not None else 'unavailable', error=error,
                account=True, **extra)


class Nvidia:
    """One persistent CSV stream for all NVIDIA boards, with bounded retry and stale detection."""
    def __init__(self):
        self.process = None
        self.selector = selectors.DefaultSelector()
        self.values = {}
        self.buffer = b''
        self.retry = 0
        self.error = 'Waiting for NVIDIA driver'
        self.interval = None
        self.started = 0

    def close(self):
        if self.process:
            self.selector.unregister(self.process.stdout)
            self.process.terminate()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
            self.process.stdout.close()
            self.process = None
        self.values.clear()
        self.buffer = b''

    def poll(self, interval):
        now = time.monotonic()
        if self.process and self.process.poll() is not None:
            try:
                output = self.process.stdout.read() or b''
                if output:
                    self.error = output.decode(errors='replace').strip()[:400]
            except OSError:
                pass
        if self.process and (self.process.poll() is not None or self.interval != interval or
                             now-max([t for _, _, t in self.values.values()] or [self.started]) > max(30, interval*3)):
            self.close()
            self.retry = now+30
        if self.process is None and now >= self.retry:
            binary = nvidia_smi_binary()
            self.retry = now+60
            if not binary:
                self.error = 'nvidia-smi is not installed'
            else:
                try:
                    self.process = subprocess.Popen([binary, '--query-gpu=pci.bus_id,name,power.draw',
                        '--format=csv,noheader,nounits', f'--loop-ms={interval*1000}'],
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                    os.set_blocking(self.process.stdout.fileno(), False)
                    self.selector.register(self.process.stdout, selectors.EVENT_READ)
                    self.interval, self.started = interval, now
                except OSError as exc:
                    self.error = str(exc)
        if self.process:
            for key, _ in self.selector.select(timeout=0):
                chunk = os.read(key.fileobj.fileno(), 65536)
                self.buffer = (self.buffer+chunk)[-131072:]
                lines = self.buffer.split(b'\n')
                self.buffer = lines.pop()
                for line in lines:
                    text = line.decode(errors='replace').strip()
                    try:
                        bus, name, value = next(csv.reader([text], skipinitialspace=True))
                        bus = bus.lower()
                        if not ':' in bus:
                            raise ValueError('Not a GPU row')
                        try:
                            watts = float(value)
                            if not math.isfinite(watts) or not 0 <= watts <= 10000:
                                watts = None
                        except ValueError:
                            watts = None
                        self.values[bus[-12:]] = (name, watts, now)
                    except (ValueError, StopIteration):
                        if text:
                            self.error = text[:400]
        return {bus: (name, watts) for bus, (name, watts, stamp) in self.values.items()
                if now-stamp <= max(3, interval*1.8)}


class Sensors:
    def __init__(self, root=Path('/sys')):
        self.root = root
        self.counters = {}
        self.nvidia = Nvidia()
        self.devices = []
        self.next_discovery = 0

    def discover(self):
        devices = []
        seen = set()
        for path in sorted(set((self.root/'class/powercap').glob('*/energy_uj')) | set((self.root/'class/powercap').glob('**/energy_uj'))):
            real = path.resolve()
            if real in seen:
                continue
            seen.add(real)
            try:
                name = (path.parent/'name').read_text().strip()
            except OSError:
                continue
            # Only top-level package counters, never cores/uncore/DRAM duplicates.
            if name.startswith('package-'):
                devices.append(('rapl', path, name))
        for card in sorted((self.root/'class/drm').glob('card[0-9]*')):
            if not card.name[4:].isdigit() or not (card/'device').exists():
                continue
            devices.append(('gpu', card/'device', card.name))
        self.devices = devices
        self.next_discovery = time.monotonic()+60

    def sample(self, interval):
        if time.monotonic() >= self.next_discovery:
            self.discover()
        nv = self.nvidia.poll(interval) if any(vendor(p) == '0x10de'
                  for kind, p, _ in self.devices if kind == 'gpu') else {}
        result = []
        for backend, path, name in self.devices:
            if backend == 'rapl':
                key = 'cpu:'+path.parent.name
                item = reading(key, 'CPU '+name+' (package, includes integrated graphics)', 'cpu', str(path))
                try:
                    value = number(path)
                    maximum = number(path.parent/'max_energy_range_uj')
                    now = time.monotonic()
                    old = self.counters.get(key)
                    self.counters[key] = (value, now)
                    if old and 0 < now-old[1] <= interval*2.5:
                        watts = counter_delta(old[0], value, maximum)/1e6/(now-old[1])
                        if watts > 10000:
                            raise ValueError('Counter reset or implausible power')
                        item.update(watts=watts, quality='measured', interval_average=True)
                    else:
                        item['error'] = 'Waiting for next energy counter sample'
                except (OSError, ValueError) as exc:
                    self.counters.pop(key, None)
                    item['error'] = 'Unavailable: permission denied' if isinstance(exc, PermissionError) else str(exc)
                result.append(item)
            else:
                bus = path.resolve().name.lower()[-12:]
                key = 'gpu:'+bus
                item = reading(key, 'GPU '+bus, 'gpu', 'DRM/hwmon')
                try:
                    vendor_id = (path/'vendor').read_text().strip()
                    if vendor_id == '0x10de':
                        item['source'] = 'nvidia-smi (board power)'
                        if bus in nv:
                            item['name'], item['watts'] = nv[bus]
                            item['quality'] = 'measured' if item['watts'] is not None else 'unavailable'
                            item['error'] = '' if item['watts'] is not None else 'Driver reports no power sensor'
                        else:
                            item['error'] = self.nvidia.error
                    else:
                        # Intel GPUs and AMD APUs conservatively excluded: package/SoC overlap.
                        integrated = vendor_id == '0x8086' or (vendor_id == '0x1002' and not (path/'mem_info_vram_total').exists())
                        if vendor_id == '0x1002' and (path/'mem_info_vram_total').exists():
                            integrated = number(path/'mem_info_vram_total') < 1024**3
                        if integrated:
                            item.update(account=False, error='Integrated/possibly shared SoC domain: excluded to prevent double counting')
                        else:
                            candidates = sorted(path.glob('hwmon/hwmon*/power1_average')) or sorted(path.glob('hwmon/hwmon*/power1_input'))
                            if not candidates:
                                item['error'] = 'No supported DRM power sensor exposed'
                            else:
                                watts = number(candidates[0])/1e6
                                if not math.isfinite(watts) or not 0 <= watts <= 10000:
                                    raise ValueError('Invalid hwmon power')
                                item.update(watts=watts, quality='measured', source=str(candidates[0]))
                except (OSError, ValueError) as exc:
                    item['error'] = 'Unavailable: permission denied' if isinstance(exc, PermissionError) else str(exc)
                result.append(item)
        if not any(x['kind'] == 'cpu' for x in result):
            result.append(reading('cpu:unavailable', 'CPU package', 'cpu', 'discovery', error='No supported package energy counter exposed'))
        if not any(x['kind'] == 'gpu' for x in result):
            result.append(reading('gpu:unavailable', 'GPU', 'gpu', 'discovery', error='No DRM GPU detected'))
        return result

    def close(self):
        self.nvidia.close()
        self.nvidia.selector.close()
