"""Installer must save post-state and fail honestly if any registration step fails."""
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
from test_input_source_migration import builder, info, source, LEGACY, CURRENT


class InstallTransactionTests(unittest.TestCase):
    def run_install(self, failure=None):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            dist, backups, reports = root/'dist', root/'Backups', root/'reports'
            for directory in (dist, backups, reports):
                directory.mkdir()
            app = dist/'HanjaIME.app'
            (app/'Contents').mkdir(parents=True)
            (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info()))
            (dist/'build.json').write_text(json.dumps({'package_fingerprint': builder.package_fingerprint()}))
            target = root/'installed/HanjaIME.app'
            target.parent.mkdir()
            manager = target/'Contents/Resources/HanjaIMEWordManager.app/Contents/MacOS/HanjaIMEWordManager'
            manager.parent.mkdir(parents=True)
            manager.write_text('manager')
            before = {'sources': [source(), source(LEGACY, name='HanjaIME English')], 'bundles': []}
            after = {'sources': [source()], 'bundles': []}
            commands = []

            def run(args, **kwargs):
                commands.append(args)
                if failure and failure in args:
                    raise RuntimeError('simulated '+failure+' error')
                return 0

            with patch.object(builder.Path, 'home', return_value=root), patch.object(builder, 'DIST', dist), patch.object(builder, 'developer_environment'), \
                 patch.object(builder, 'ensure_helper', return_value=dist/'register-input-source'), \
                 patch.object(builder, 'diagnostic_folder', return_value=reports), \
                 patch.object(builder, 'snapshot', side_effect=[before, after]) as snapshot, \
                 patch.object(builder, 'verify'), patch.object(builder, 'validate_app', return_value={'input_modes':[CURRENT]}), \
                 patch.object(builder, 'paths', return_value=(target,backups)), \
                 patch.object(builder, 'current_guard'), patch.object(builder, 'replace_app', return_value=None), \
                 patch.object(builder, 'run', run):
                if failure:
                    with self.assertRaisesRegex(RuntimeError, 'simulated'):
                        builder.install()
                else:
                    builder.install()
                self.assertEqual(snapshot.call_count, 2)
                report = json.loads((reports/'result.json').read_text())
                self.assertTrue((reports/'before-after.diff').is_file())
                self.assertEqual(report['system_settings_add_ui'], 'not-verified')
                self.assertEqual(report['installation_operation_completed'], not bool(failure))
                self.assertEqual(report['tis_registration_verified'], not bool(failure))
                if failure:
                    self.assertIn('simulated', report['operation_error'])
                return commands

    def test_cleanup_failure_still_saves_after_dump_and_failure_result(self):
        commands = self.run_install('--cleanup')
        self.assertFalse(any('--enable-korean' in cmd for cmd in commands))

    def test_registration_failure_still_saves_after_dump(self):
        self.run_install('--register')

    def test_success_requires_post_registration_checks_and_keeps_ui_pending(self):
        commands = self.run_install()
        self.assertTrue(any('--enable-korean' in cmd for cmd in commands))
        self.assertTrue(any('TextInputMenuAgent' in cmd for cmd in commands))


if __name__ == '__main__':
    unittest.main()
