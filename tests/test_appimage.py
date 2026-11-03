"""Portable-launch regressions; no real user files or services are modified."""
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch

PREPARE = Path(__file__).resolve().parents[1]/'packaging/appimage/prepare.py'


class PortableCollectorTests(unittest.TestCase):
    def prepare(self, home, fallback=False):
        image = home/'Vibe Energy%test.AppImage'
        mounted=home/'mounted'
        mounted.mkdir(parents=True,exist_ok=True)
        (mounted/'vibeenergy.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"/>')
        environment = {
            'APPDIR': str(home/'mounted'), 'APPIMAGE': str(image),
            'XDG_CONFIG_HOME': str(home/'config'),
            'XDG_DATA_HOME': str(home/'data'), 'XDG_STATE_HOME': str(home/'state'),
            'LD_LIBRARY_PATH': '/bundled/libs', 'PYTHONHOME': '/bundled/python',
        }
        with patch.dict(os.environ, environment, clear=True), patch('pathlib.Path.home', return_value=home), patch('os.geteuid', return_value=1000), patch('subprocess.run') as run, patch('subprocess.Popen') as popen:
            if fallback:
                run.side_effect = OSError('No user bus')
            result = runpy.run_path(str(PREPARE))
            if 'output' in result:
                result['output'].close()
            return image, run, popen

    def test_service_uses_extract_and_run_with_security_enabled(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            image, run, popen = self.prepare(home)
            unit = (home/'config/systemd/user/energytlk.service').read_text()
            self.assertIn('--appimage-extract-and-run --collector', unit)
            self.assertIn('NoNewPrivileges=yes', unit)
            self.assertIn('Vibe Energy%%test.AppImage', unit)
            self.assertTrue((home/'.vibeenergy/logs/powerstat.log').is_file())
            self.assertNotIn('LD_LIBRARY_PATH', run.call_args.kwargs['env'])
            popen.assert_not_called()

    def test_no_user_bus_fallback_also_avoids_fuse(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            image, run, popen = self.prepare(home, fallback=True)
            self.assertEqual(popen.call_args.args[0], [str(image), '--appimage-extract-and-run', '--collector'])
            self.assertTrue(popen.call_args.kwargs['start_new_session'])
            self.assertNotIn('PYTHONHOME', popen.call_args.kwargs['env'])
