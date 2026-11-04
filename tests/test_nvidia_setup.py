import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
from energytlk.sensors import Nvidia, Sensors, nvidia_smi_binary


class NvidiaSetupTests(unittest.TestCase):
    def test_interval_change_restarts_stream_without_failure_backoff(self):
        stream = Nvidia()
        pipes = [os.pipe(), os.pipe()]
        processes = [Mock(stdout=os.fdopen(read, 'rb', buffering=0)) for read, _ in pipes]
        for process in processes:
            process.poll.return_value = None
        try:
            with patch('energytlk.sensors.time.monotonic', return_value=100), patch('energytlk.sensors.nvidia_smi_binary', return_value='/usr/bin/nvidia-smi'), patch('energytlk.sensors.subprocess.Popen', side_effect=processes) as start:
                stream.poll(1)
                os.write(pipes[0][1], b'00000000:01:00.0, Test GPU, 42\n')
                self.assertEqual(stream.poll(1)['0000:01:00.0'][1], 42)
                stream.poll(3)
                self.assertEqual(start.call_count, 2)
                self.assertIn('--loop-ms=3000', start.call_args.args[0])
                processes[0].terminate.assert_called_once()
                os.write(pipes[1][1], b'00000000:01:00.0, Test GPU, 45\n')
                self.assertEqual(stream.poll(3)['0000:01:00.0'][1], 45)
        finally:
            stream.close()
            stream.selector.close()
            for process in processes:
                process.stdout.close()
            for _, write in pipes:
                os.close(write)

    def test_stalled_stream_keeps_failure_backoff(self):
        stream = Nvidia()
        read, write = os.pipe()
        process = Mock(stdout=os.fdopen(read, 'rb', buffering=0))
        process.poll.return_value = None
        stream.process = process
        stream.interval = 1
        stream.started = 1
        stream.selector.register(process.stdout, 1)
        try:
            with patch('energytlk.sensors.time.monotonic', return_value=100), patch('energytlk.sensors.subprocess.Popen') as start:
                stream.poll(3)
                start.assert_not_called()
                self.assertEqual(stream.retry, 130)
        finally:
            stream.close()
            stream.selector.close()
            os.close(write)

    def test_missing_utility(self):
        with patch('energytlk.sensors.shutil.which', return_value=None):
            self.assertIsNone(nvidia_smi_binary())

    def test_appimage_launcher_does_not_count_as_installed_utility(self):
        with tempfile.TemporaryDirectory() as directory:
            launcher=str(Path(directory)/'usr/bin/nvidia-smi')
            with patch.dict(os.environ, {'APPDIR':directory}), patch('energytlk.sensors.shutil.which', return_value=launcher), patch('energytlk.sensors.os.access', return_value=False):
                self.assertIsNone(nvidia_smi_binary())

    def test_appimage_launcher_used_when_host_utility_exists(self):
        with tempfile.TemporaryDirectory() as directory:
            launcher=str(Path(directory)/'usr/bin/nvidia-smi')
            with patch.dict(os.environ, {'APPDIR':directory}), patch('energytlk.sensors.shutil.which', return_value=launcher), patch('energytlk.sensors.os.access', return_value=True):
                self.assertEqual(nvidia_smi_binary(),launcher)

    def test_detected_nvidia_card_reports_missing_utility(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);device=root/'class/drm/card0/device'
            device.mkdir(parents=True);(device/'vendor').write_text('0x10de')
            sensors=Sensors(root)
            try:
                with patch('energytlk.sensors.shutil.which', return_value=None), patch('energytlk.sensors.subprocess.Popen') as start:
                    readings=sensors.sample(1)
                gpu=next(r for r in readings if r['kind']=='gpu')
                self.assertEqual(gpu['source'],'nvidia-smi (board power)')
                self.assertEqual(gpu['error'],'nvidia-smi is not installed')
                self.assertIsNone(gpu['watts'])
                start.assert_not_called()
            finally:
                sensors.close()
