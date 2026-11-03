import datetime
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
from energytlk.powerstat import PowerstatLog, discover_log
from energytlk.sensors import reading


def sample_log(path, stamp=None, cpu=42):
    stamp = stamp or datetime.datetime.now(datetime.timezone.utc)
    prefix=stamp.isoformat()
    clock=stamp.strftime('%H:%M:%S')
    path.write_text(f'{prefix} Running for 36000 seconds\n{prefix} Time Watts core pkg-0\n{prefix} {clock} 999 10 {cpu}\n')
    return stamp


class PowerstatSetupTests(unittest.TestCase):
    def test_timestamped_linux_pipeline_output_uses_package_columns(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'powerstat.log'
            stamp=sample_log(path)
            sample,note=PowerstatLog(path).read(stamp.timestamp()+.1,25)
            self.assertEqual(sample,(stamp.timestamp(),42))

    def test_multiple_packages_exclude_core_and_dram(self):
        parser=PowerstatLog('/unused')
        stamp=datetime.datetime.now(datetime.timezone.utc).isoformat()
        parser.parse(stamp+' Time Watts core pkg-0 pkg-1 dram')
        parser.parse(stamp+' 12:00:00 999 10 40 50 5')
        self.assertEqual(parser.latest[1],90)

    def test_ambiguous_or_duplicate_package_columns_refused(self):
        stamp=datetime.datetime.now(datetime.timezone.utc).isoformat()
        for header,row in [('Time Watts core dram','12:00:00 999 10 5'),('Time Watts pkg-0 pkg-0','12:00:00 999 10 10')]:
            parser=PowerstatLog('/unused')
            parser.parse(stamp+' '+header)
            parser.parse(stamp+' '+row)
            self.assertIsNone(parser.latest)

    def test_stale_and_future_samples_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'powerstat.log'
            stamp=sample_log(path)
            self.assertIsNone(PowerstatLog(path).read(stamp.timestamp()+100,25)[0])
            self.assertIsNone(PowerstatLog(path).read(stamp.timestamp()-100,25)[0])

    def test_restart_changes_source_session(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'powerstat.log'
            stamp=sample_log(path)
            importer=PowerstatLog(path)
            importer.read(stamp.timestamp(),25)
            previous=importer.logger_session
            with path.open('a') as stream:
                stream.write((stamp+datetime.timedelta(seconds=10)).isoformat()+' Running for 36000 seconds\n')
            self.assertIsNone(importer.read(stamp.timestamp()+10,25)[0])
            self.assertNotEqual(previous,importer.logger_session)

    def test_discovery_prefers_shared_log_and_preserves_explicit_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            first=Path(tmp)/'powerstat.log'
            self.assertEqual(discover_log(default=first),'')
            sample_log(first)
            self.assertEqual(discover_log(default=first),str(first))
            second=Path(tmp)/'another.log'
            sample_log(second)
            os.utime(second,(first.stat().st_mtime+10,first.stat().st_mtime+10))
            self.assertEqual(discover_log(default=first),str(first))
            first.unlink()
            self.assertEqual(discover_log(default=first),str(second))
            self.assertEqual(discover_log('/explicit.log',default=first),'/explicit.log')

    def test_scanner_does_not_follow_links_outside_logs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            (root/'logs').mkdir()
            outside=root/'private.log'
            sample_log(outside)
            (root/'logs/link.log').symlink_to(outside)
            self.assertEqual(discover_log(default=root/'logs/powerstat.log'),'')

    def test_collector_automatically_reads_home_log_without_settings(self):
        from energytlk import collector
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp)
            logdir=base/'.vibeenergy/logs'
            logdir.mkdir(parents=True)
            path=logdir/'powerstat.log'
            sample_log(path)
            env=dict(XDG_CONFIG_HOME=str(base/'config'),XDG_DATA_HOME=str(base/'data'),XDG_STATE_HOME=str(base/'state'))
            sensors=Mock()
            sensors.sample.return_value=[reading('cpu:0','CPU','cpu','RAPL',error='Permission denied'),reading('gpu:0','GPU','gpu','test',50)]
            with patch.dict(os.environ,env),patch('energytlk.powerstat.DEFAULT_LOG_PATH',path),patch.object(collector,'Sensors',return_value=sensors),patch('sys.argv',['vibeenergy','--samples','1']),patch.object(collector.signal,'signal'):
                collector.main()
            snapshot=json.loads((base/'state/energytlk/state.json').read_text())
            cpu=next(row for row in snapshot['devices'] if row['kind']=='cpu')
            self.assertEqual(cpu['watts'],42)
            self.assertEqual(cpu['quality'],'imported from log')
            self.assertEqual(snapshot['powerstat_log'],str(path))
            self.assertFalse((base/'config/energytlk/config.json').exists())

    def test_managed_log_does_not_double_count_readable_direct_cpu(self):
        from energytlk import collector
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp)
            path=base/'powerstat.log'
            env=dict(XDG_CONFIG_HOME=str(base/'config'),XDG_DATA_HOME=str(base/'data'),XDG_STATE_HOME=str(base/'state'))
            sensors=Mock()
            def sample(_):
                stamp=sample_log(path)
                path.write_text('# vibeenergy-accounted-v2\n'+path.read_text())
                return [reading('cpu:0','CPU','cpu','RAPL',100)]
            sensors.sample.side_effect=sample
            with patch.dict(os.environ,env),patch('energytlk.powerstat.DEFAULT_LOG_PATH',path),patch.object(collector,'Sensors',return_value=sensors),patch('sys.argv',['vibeenergy','--samples','2','--interval','1']),patch.object(collector.signal,'signal'):
                collector.main()
            snapshot=json.loads((base/'state/energytlk/state.json').read_text())
            self.assertEqual(snapshot['devices'][0]['id'],'cpu:powerstat')
            self.assertTrue(snapshot['devices'][0]['accounted_from_log'])
            self.assertEqual(snapshot['daily'],[])

    def test_plain_powerstat_log_provides_live_watts_without_inventing_energy(self):
        import time
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'powerstat.log'
            path.write_text('Time Watts core pkg-0\n'+time.strftime('%H:%M:%S')+' 999 10 42\n')
            reader=PowerstatLog(path)
            self.assertEqual(reader.read(time.time(),25)[0],(None,42))
            self.assertFalse(reader.energy_eligible)
            self.assertIsNone(reader.read(time.time()+100,25)[0])

    def test_collector_anchors_plain_cpu_log_without_inventing_history(self):
        import time
        from energytlk import collector
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp)
            path=base/'powerstat.log'
            path.write_text('Time Watts core pkg-0\n'+time.strftime('%H:%M:%S')+' 999 10 42\n')
            env=dict(XDG_CONFIG_HOME=str(base/'config'),XDG_DATA_HOME=str(base/'data'),XDG_STATE_HOME=str(base/'state'))
            sensors=Mock()
            sensors.sample.return_value=[reading('cpu:0','CPU','cpu','RAPL',error='Permission denied')]
            with patch.dict(os.environ,env),patch('energytlk.powerstat.DEFAULT_LOG_PATH',path),patch.object(collector,'Sensors',return_value=sensors),patch('sys.argv',['vibeenergy','--samples','2','--interval','1']),patch.object(collector.signal,'signal'):
                collector.main()
            snapshot=json.loads((base/'state/energytlk/state.json').read_text())
            self.assertEqual(snapshot['devices'][0]['watts'],42)
            self.assertTrue(snapshot['devices'][0]['accounted_from_log'])
            self.assertEqual(snapshot['daily'],[])
