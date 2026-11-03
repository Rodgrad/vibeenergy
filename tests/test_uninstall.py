import contextlib
import io
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from energytlk.uninstall import main


class UninstallTests(unittest.TestCase):
    def test_removes_only_app_files_and_preserves_history_settings_logs(self):
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory)
            removed=['.config/autostart/vibeenergy.desktop','.local/share/applications/org.energytlk.monitor.desktop','.local/share/icons/hicolor/scalable/apps/vibeenergy.svg','.local/share/energytlk/app/module.py','.local/share/plasma/plasmoids/org.energytlk.monitor/metadata.json','.local/share/applications/vibeenergy.desktop','.config/systemd/user/energytlk.service']
            kept=['.local/share/energytlk/energy.sqlite3','.local/state/energytlk/state.json','.config/energytlk/config.json','.vibeenergy/logs/powerstat.log','VibeEnergy.AppImage','.local/share/applications/other.desktop']
            for name in removed+kept:
                path=home/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('keep')
            with patch('os.geteuid',return_value=1000),patch('sys.argv',['uninstall','--prefix',str(home)]),patch('subprocess.run') as command,contextlib.redirect_stdout(io.StringIO()):
                main()
            command.assert_not_called()
            for name in removed:self.assertFalse((home/name).exists(),name)
            for name in kept:self.assertEqual((home/name).read_text(),'keep',name)

    def test_failed_service_stop_removes_nothing(self):
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory);service=home/'.config/systemd/user/energytlk.service'
            service.parent.mkdir(parents=True);service.write_text('unit')
            with patch('os.geteuid',return_value=1000),patch('pathlib.Path.home',return_value=home),patch.dict('os.environ',{},clear=True),patch('sys.argv',['uninstall']),patch('subprocess.run',side_effect=OSError('No bus')):
                with self.assertRaises(SystemExit):main()
            self.assertEqual(service.read_text(),'unit')

    def test_service_stop_timeout_preserves_installation_and_history(self):
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory)
            files=[home/'.config/systemd/user/energytlk.service',home/'.local/share/energytlk/energy.sqlite3']
            for path in files:
                path.parent.mkdir(parents=True,exist_ok=True);path.write_text('preserved')
            with patch('os.geteuid',return_value=1000),patch('pathlib.Path.home',return_value=home),patch.dict('os.environ',{},clear=True),patch('sys.argv',['uninstall']),patch('subprocess.run',side_effect=subprocess.TimeoutExpired('systemctl',10)) as command:
                with self.assertRaisesRegex(SystemExit,'cancelled.*timed out.*No files removed'):main()
            self.assertEqual(command.call_args.kwargs['timeout'],3)
            for path in files:self.assertEqual(path.read_text(),'preserved')

    def test_host_service_command_has_bounded_wait_and_clean_environment(self):
        from energytlk.uninstall import run_systemctl
        with patch.dict('os.environ',{'LD_LIBRARY_PATH':'bundled','PYTHONHOME':'bundled','VIBEENERGY_HOST_PATH':'/usr/bin:/bin'}),patch('subprocess.run') as command:
            run_systemctl(['daemon-reload'],timeout=5)
        self.assertEqual(command.call_args.kwargs['timeout'],5)
        environment=command.call_args.kwargs['env']
        self.assertNotIn('LD_LIBRARY_PATH',environment)
        self.assertNotIn('PYTHONHOME',environment)
        self.assertEqual(environment['PATH'],'/usr/bin:/bin')
        self.assertIn('--no-ask-password',command.call_args.args[0])

    def test_reload_timeout_is_success_after_completed_removal(self):
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory)
            launcher=home/'.local/share/applications/vibeenergy.desktop'
            history=home/'.local/share/energytlk/energy.sqlite3'
            for path in (launcher,history):
                path.parent.mkdir(parents=True,exist_ok=True);path.write_text('preserved')
            outcomes=[subprocess.CompletedProcess([],0),subprocess.CompletedProcess([],0),subprocess.TimeoutExpired('systemctl',5)]
            output=io.StringIO()
            with patch('os.geteuid',return_value=1000),patch('pathlib.Path.home',return_value=home),patch.dict('os.environ',{},clear=True),patch('sys.argv',['uninstall']),patch('subprocess.run',side_effect=outcomes) as command,contextlib.redirect_stdout(output):
                main()
            self.assertFalse(launcher.exists())
            self.assertEqual(history.read_text(),'preserved')
            self.assertIn('Uninstalled.',output.getvalue())
            self.assertIn('reload is pending',output.getvalue())
            self.assertEqual([call.kwargs['timeout'] for call in command.call_args_list],[3,5,5])

    def test_failure_after_recording_stops_restores_recording_and_autostart(self):
        from energytlk.uninstall import prepare_removal
        state={'active':True}
        def stop(_):state['active']=False
        def resume(*_):state['active']=True
        outcomes=[None,subprocess.TimeoutExpired('systemctl',5),None]
        with patch('energytlk.uninstall.active',side_effect=lambda _:state['active']),patch('energytlk.uninstall.stop_collector',side_effect=stop),patch('energytlk.uninstall.restart',side_effect=resume) as restart,patch('energytlk.uninstall.run_systemctl',side_effect=outcomes) as systemctl:
            with self.assertRaisesRegex(RuntimeError,'No files removed.*Recording resumed'):
                prepare_removal(Path('/isolated/state'),enabled=True)
        self.assertTrue(state['active'])
        restart.assert_called_once()
        self.assertEqual(systemctl.call_args_list[-1].args[0],['enable','energytlk.service'])

    def test_failure_does_not_start_previously_stopped_recording(self):
        from energytlk.uninstall import prepare_removal
        with patch('energytlk.uninstall.active',return_value=False),patch('energytlk.uninstall.run_systemctl',side_effect=OSError('No bus')),patch('energytlk.uninstall.restart') as restart:
            with self.assertRaisesRegex(RuntimeError,'No files removed'):
                prepare_removal(Path('/isolated/state'),enabled=False)
        restart.assert_not_called()

    def test_success_confirms_stop_before_disabling_and_never_restarts(self):
        from energytlk.uninstall import prepare_removal
        order=[]
        with patch('energytlk.uninstall.active',return_value=True),patch('energytlk.uninstall.stop_collector',side_effect=lambda _:order.append('stopped')),patch('energytlk.uninstall.run_systemctl',side_effect=lambda args,timeout:order.append(args)),patch('energytlk.uninstall.restart') as restart:
            prepare_removal(Path('/isolated/state'),enabled=True)
        self.assertEqual(order,[['--no-block','stop','energytlk.service'],'stopped',['disable','energytlk.service']])
        restart.assert_not_called()

    def test_real_collector_resumes_after_disable_timeout(self):
        import json
        import os
        import sys
        import time
        from energytlk.clear_history import active, restart as real_restart
        from energytlk.control import stop_collector
        from energytlk.uninstall import prepare_removal
        processes=[]
        original_popen=subprocess.Popen
        def spawn(*args,**kwargs):
            process=original_popen(*args,**kwargs);processes.append(process);return process
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            env=dict(os.environ)
            env.pop('APPIMAGE',None);env.pop('APPDIR',None)
            env.update({f'XDG_{name}_HOME':str(root/name.lower()) for name in ('STATE','DATA','CONFIG')})
            state=root/'state/energytlk/demo'
            try:
                spawn([sys.executable,'-m','energytlk','--simulate','--interval','1'],env=env,cwd=Path(__file__).resolve().parents[1],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                deadline=time.monotonic()+8
                while not (state/'state.json').exists() and time.monotonic()<deadline:time.sleep(.05)
                self.assertTrue(active(state))
                previous=json.loads((state/'state.json').read_text())['timestamp']
                outcomes=[None,subprocess.TimeoutExpired('systemctl',5),None]
                # Same recovery function, using its isolated simulation branch so
                # this integration test never contacts the real user service.
                with patch.dict('os.environ',env,clear=True),patch('energytlk.uninstall.run_systemctl',side_effect=outcomes),patch('energytlk.uninstall.restart',side_effect=lambda _,environment:real_restart(True,environment)),patch('subprocess.Popen',side_effect=spawn):
                    with self.assertRaisesRegex(RuntimeError,'Recording resumed'):
                        prepare_removal(state,enabled=True)
                deadline=time.monotonic()+8
                while time.monotonic()<deadline:
                    reading=json.loads((state/'state.json').read_text())
                    if reading['running'] and reading['timestamp']>previous:break
                    time.sleep(.05)
                self.assertTrue(active(state))
                self.assertTrue(reading['running'])
                self.assertGreater(reading['timestamp'],previous)
                self.assertTrue((root/'data/energytlk/demo/energy.sqlite3').exists())
            finally:
                stop_collector(state)
                for process in processes:
                    if process.poll() is None:process.terminate()
                    process.wait(timeout=5)

    def test_failure_requests_recovery_even_if_old_collector_is_still_stopping(self):
        from energytlk.uninstall import prepare_removal
        with patch('energytlk.uninstall.active',return_value=True),patch('energytlk.uninstall.run_systemctl',side_effect=subprocess.TimeoutExpired('systemctl',3)),patch('energytlk.uninstall.restart') as restart:
            with self.assertRaisesRegex(RuntimeError,'Recording resumed'):
                prepare_removal(Path('/isolated/state'),enabled=False)
        restart.assert_called_once()
