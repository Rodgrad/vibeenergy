import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from energytlk.sensors import Sensors, nvidia_smi_binary


class NvidiaSetupTests(unittest.TestCase):
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
