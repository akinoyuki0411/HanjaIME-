import copy
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'scripts'))
import input_source_migration as migration
import validate_input_modes as validator
import hanjaime as builder

BUNDLE = validator.BUNDLE_ID
CURRENT = validator.CURRENT_ID
LEGACY = BUNDLE + '.qwerty'


def info():
    return {'CFBundleIdentifier': BUNDLE, 'CFBundleExecutable': 'HanjaIME',
            'CFBundleShortVersionString': '0.8.2', 'CFBundleVersion': '14',
            'InputMethodConnectionName': 'HanjaIME_Connection',
            'TISInputSourceID': BUNDLE, 'TISIntendedLanguage': 'ko',
            'ComponentInputModeDict': {
                'tsInputModeListKey': {CURRENT: {
                    'TISInputSourceID': CURRENT, 'TISIntendedLanguage': 'ko',
                    'tsInputModeIsVisibleKey': True, 'tsInputModeDefaultStateKey': True}},
                'tsVisibleInputModeOrderedArrayKey': [CURRENT]}}


def source(source_id=CURRENT, bundle_id=BUNDLE, name=validator.DISPLAY_NAME, enabled=True):
    return dict(source_id=source_id, mode_id=source_id, bundle_id=bundle_id, name=name,
                enabled=enabled, selected=False, select_capable=True, bundle_urls=[])


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.app = Path(self.temp.name) / 'HanjaIME.app'
        self.contents = self.app / 'Contents'
        self.contents.mkdir(parents=True)
        self.write_info(info())
        for lang in ('ko', 'en'):
            path = self.contents / 'Resources' / (lang + '.lproj')
            path.mkdir(parents=True)
            (path / 'InfoPlist.strings').write_text(CURRENT + ' = "HanjaIME 두벌식";\n')

    def tearDown(self):
        self.temp.cleanup()

    def write_info(self, data):
        (self.contents / 'Info.plist').write_bytes(plistlib.dumps(data))

    def test_built_bundle_has_exactly_one_korean_mode(self):
        self.assertEqual(validator.validate_app(self.app)['input_modes'], [CURRENT])

    def test_reject_every_roman_export(self):
        for suffix in ('qwerty', 'system', 'dvorak', 'colemak'):
            with self.subTest(suffix=suffix):
                data = info()
                data['ComponentInputModeDict']['tsInputModeListKey'][BUNDLE+'.'+suffix] = {}
                self.write_info(data)
                with self.assertRaises(ValueError):
                    validator.validate_app(self.app)

    def test_reject_zero_modes(self):
        data = info()
        data['ComponentInputModeDict']['tsInputModeListKey'] = {}
        with self.assertRaises(ValueError):
            validator.validate_info(data)

    def test_reject_wrong_visible_order(self):
        data = info()
        data['ComponentInputModeDict']['tsVisibleInputModeOrderedArrayKey'].append(LEGACY)
        with self.assertRaises(ValueError):
            validator.validate_info(data)

    def test_reject_wrong_intended_language(self):
        data = info()
        data['ComponentInputModeDict']['tsInputModeListKey'][CURRENT]['TISIntendedLanguage'] = 'en'
        with self.assertRaises(ValueError):
            validator.validate_info(data)

    def test_reject_legacy_localized_names(self):
        path = self.contents / 'Resources/en.lproj/InfoPlist.strings'
        for name in ('HanjaIME English', 'HanjaIME 영문', 'Hanjimi English', 'Han 2set', 'HanjaIME 2-Set Korean'):
            with self.subTest(name=name):
                path.write_text(CURRENT + ' = "'+name+'";\n')
                with self.assertRaises(ValueError):
                    validator.validate_app(self.app)

    def test_binary_localization_is_checked(self):
        path = self.contents / 'Resources/en.lproj/InfoPlist.strings'
        path.write_bytes(plistlib.dumps({CURRENT: validator.DISPLAY_NAME}, fmt=plistlib.FMT_BINARY))
        self.assertEqual(validator.validate_app(self.app)['display_names']['en'], validator.DISPLAY_NAME)

    def test_unused_english_resource_fails_build_gate(self):
        (self.contents / 'Resources/HanjaIMEEnglish@2x.png').write_bytes(b'old resource')
        with self.assertRaises(ValueError):
            validator.validate_app(self.app)

    def test_build_merge_must_match_source(self):
        source_plist = Path(self.temp.name) / 'source.plist'
        data = info()
        data['ComponentInputModeDict']['tsInputModeListKey'][CURRENT]['tsInputModeMenuIconFileKey'] = 'different.png'
        source_plist.write_bytes(plistlib.dumps(data))
        with self.assertRaises(ValueError):
            validator.validate_app(self.app, source_plist)


class MigrationPolicyTests(unittest.TestCase):
    def setUp(self):
        self.policy = migration.load_policy()
        self.others = [source('com.apple.keylayout.ABC', 'com.apple', 'ABC'),
                       source('com.apple.inputmethod.Korean.2SetKorean', 'com.apple.inputmethod.Korean', '두벌식'),
                       source('com.apple.inputmethod.Kotoeri.Japanese', 'com.apple.inputmethod.Kotoeri', 'あ'),
                       source('org.youknowone.inputmethod.Gureum.han2', 'org.youknowone.inputmethod.Gureum', 'Han 2set'),
                       source('user.ThirdParty.han2', 'user.ThirdParty', 'My keyboard')]

    def test_allowlist_has_exact_source_provenance(self):
        composer = (ROOT/'Sources/GureumComposer.swift').read_text()
        self.assertNotIn(CURRENT, self.policy['legacy_source_ids'])
        for identifier in self.policy['legacy_source_ids']:
            self.assertIn('"'+identifier+'"', composer)

    def test_reject_policy_that_includes_canonical_source(self):
        self.policy['legacy_source_ids'].append(CURRENT)
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)/'policy.json'
            path.write_text(json.dumps(self.policy))
            with self.assertRaises(ValueError):
                migration.load_policy(path)

    def test_canonical_id_never_disabled_even_with_old_name(self):
        self.assertFalse(migration.is_legacy(source(name='Han 2set'), self.policy))
        row = source()
        row['mode_id'] = LEGACY
        self.assertFalse(migration.is_legacy(row, self.policy))

    def test_foreign_sources_and_names_never_identify_cleanup_target(self):
        for row in self.others + [source('unknown.Hanjimi.han2', 'unknown.Hanjimi', 'Hanjimi English')]:
            self.assertFalse(migration.is_legacy(row, self.policy))
        row = source(LEGACY, 'org.youknowone.inputmethod.Gureum')
        self.assertFalse(migration.is_legacy(row, self.policy))

    def test_mock_tis_cleanup_preserves_other_sources_and_current_korean(self):
        before = [source(LEGACY, name='HanjaIME English'), source(BUNDLE+'.system', name='Han 2set'), source(), *self.others]
        kept = [s for s in before if not migration.is_legacy(s, self.policy)]
        self.assertEqual(kept, before[2:])

    def test_only_exact_preference_fields_are_matched(self):
        self.assertTrue(migration.preference_is_legacy({'Bundle ID': BUNDLE, 'Input Mode': LEGACY}, self.policy))
        self.assertFalse(migration.preference_is_legacy({'Bundle ID': 'com.apple', 'Input Mode': LEGACY}, self.policy))
        self.assertFalse(migration.preference_is_legacy({'KeyboardLayout Name': 'Han 2set'}, self.policy))
        self.assertFalse(migration.preference_is_legacy({'Input Mode': CURRENT, 'InputSourceID': LEGACY}, self.policy))

    def test_disabled_legacy_is_not_misreported_as_removed_from_add_list(self):
        before = {'sources': [source(), source(LEGACY)]}
        after = {'sources': [source(), source(LEGACY, enabled=False)]}
        result = migration.registration_result(before, after, self.policy)
        self.assertFalse(result['tis_registration_verified'])
        self.assertEqual(result['legacy_still_enabled'], [])
        self.assertEqual(len(result['legacy_still_available']), 1)

    def test_clean_tis_still_does_not_claim_real_ui_or_input_test(self):
        state = {'sources': [source(), self.others[0]]}
        result = migration.registration_result(state, state, self.policy)
        self.assertTrue(result['tis_registration_verified'])
        self.assertEqual(result['system_settings_add_ui'], 'not-verified')
        self.assertEqual(result['actual_application_input'], 'not-verified')

    def test_other_source_loss_fails_verification(self):
        before = {'sources': [source(), self.others[0]]}
        after = {'sources': [source()]}
        self.assertFalse(migration.registration_result(before, after, self.policy)['other_enabled_sources_preserved'])

    def test_gureum_coexists_enabled_or_disabled(self):
        for enabled in (True, False):
            row = dict(self.others[3], enabled=enabled)
            state = {'sources': [source(), *self.others[:3], row]}
            result = migration.registration_result(state, state, self.policy)
            self.assertTrue(result['tis_registration_verified'])
            self.assertEqual(result['unresolved_old_display_names'], [])
            self.assertEqual(result['independent_gureum_sources'], [row])
            self.assertFalse(migration.is_legacy(row, self.policy))

    def test_gureum_loss_still_fails(self):
        before = {'sources': [source(), self.others[3]]}
        after = {'sources': [source()]}
        result = migration.registration_result(before, after, self.policy)
        self.assertFalse(result['tis_registration_verified'])
        self.assertFalse(result['other_enabled_sources_preserved'])

    def test_old_hanjaime_and_ambiguous_names_still_fail(self):
        for row in [source(name='Han 2set'), source(LEGACY, name='HanjaIME English'),
                    source('unknown.Hanjimi.han2', 'unknown.Hanjimi', 'Hanjimi English'),
                    source(LEGACY, 'org.youknowone.inputmethod.Gureum', 'Han 2set')]:
            state = {'sources': [source(), row]}
            result = migration.registration_result(state, state, self.policy)
            self.assertFalse(result['tis_registration_verified'])
            self.assertIn(row, result['unresolved_old_display_names'])

    def test_missing_bundle_is_not_claimed_as_proven_cache_cause(self):
        row = source(name='Han 2set')
        report = migration.identity_report({'sources': [row], 'bundles': []})[0]
        self.assertIn('not yet proven', report['evidence'])
        self.assertTrue(report['canonical_id_protected'])


class BundleRetirementTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.installed = self.root/'Input Methods'
        self.installed.mkdir()
        self.project = self.root/'project'
        self.backups = self.root/'Backups'
        self.current = self.installed/'HanjaIME.app'
        self.new = self.project/'dist/HanjaIME.app'
        self.old = self.installed/'Hanjimi.app'
        self.make_app(self.old)

    def tearDown(self):
        self.temp.cleanup()

    def make_app(self, path, bundle=BUNDLE):
        (path/'Contents').mkdir(parents=True)
        data = info()
        data.update(CFBundleIdentifier=bundle, CFBundleShortVersionString='0.8.1', CFBundleVersion='13')
        (path/'Contents/Info.plist').write_bytes(plistlib.dumps(data))
        (path/'sentinel').write_text('original code')

    def record(self, path):
        return migration.bundle_record(path, [self.installed], self.project, self.backups)

    def plan(self, *records):
        return migration.retirement_plan({'bundles': list(records)}, self.current, info(), self.new)

    def test_bundle_name_does_not_decide_lineage(self):
        self.assertEqual(self.plan(self.record(self.old))[0]['action'], 'archive-and-unregister-exact-bundle')
        official = self.installed/'Gureum.app'
        self.make_app(official, 'org.youknowone.inputmethod.Gureum')
        self.assertEqual(self.plan(self.record(official)), [])

    def test_canonical_target_and_new_build_excluded(self):
        self.make_app(self.current)
        self.make_app(self.new)
        self.assertEqual(self.plan(self.record(self.current), self.record(self.new)), [])

    def test_project_and_build_copies_not_installed_or_removed(self):
        test = self.project/'build/old/HanjaIME.app'
        self.make_app(test)
        record = self.record(test)
        self.assertEqual(record['classification'], 'build-or-source-copy')
        self.assertEqual(self.plan(record), [])

    def test_newer_duplicate_and_permission_failure_are_reported(self):
        record = self.record(self.old)
        record['version'] = '99.0'
        self.assertEqual(self.plan(record)[0]['action'], 'blocked-newer-version')
        record['version'] = '0.8.1'
        record['writable'] = False
        self.assertEqual(self.plan(record)[0]['action'], 'blocked-filesystem-permission')

    def test_unknown_version_never_guessed(self):
        record = self.record(self.old)
        record['version'] = None
        self.assertEqual(self.plan(record)[0]['action'], 'blocked-unverifiable-version')

    def test_symlink_never_retired(self):
        alias = self.installed/'Hanja-alias.app'
        alias.symlink_to(self.old)
        self.assertEqual(self.plan(self.record(alias)), [])

    @staticmethod
    def fake_ditto(args, **kwargs):
        if str(args[0]) == '/usr/bin/ditto':
            original, target = Path(args[-2]), Path(args[-1])
            with zipfile.ZipFile(target, 'w') as archive:
                for path in original.rglob('*'):
                    if path.is_file():
                        archive.write(path, path.relative_to(original.parent))
        return (0, "") if kwargs.get("capture_status") else 0

    def test_archive_keeps_original_bytes_and_removes_discoverable_app(self):
        archive = self.backups/'old.zip'
        migration.archive_bundle(self.old, archive, self.fake_ditto, remove=True)
        self.assertFalse(self.old.exists())
        with zipfile.ZipFile(archive) as z:
            self.assertEqual(z.read('Hanjimi.app/sentinel'), b'original code')

    def test_failed_archive_never_deletes_original(self):
        def bad_archive(args):
            Path(args[-1]).write_bytes(b'truncated')
        with self.assertRaises(zipfile.BadZipFile):
            migration.archive_bundle(self.old, self.backups/'bad.zip', bad_archive, remove=True)
        self.assertEqual((self.old/'sentinel').read_text(), 'original code')

    def test_unrelated_app_never_archived(self):
        other = self.installed/'Other.app'
        self.make_app(other, 'user.other')
        with self.assertRaises(RuntimeError):
            migration.archive_bundle(other, self.backups/'other.zip', self.fake_ditto, remove=True)
        self.assertTrue(other.exists())


class BuildGateTests(unittest.TestCase):
    def test_helper_recompiled_if_source_changes(self):
        with tempfile.TemporaryDirectory() as temp:
            dist = Path(temp)
            (dist/'register-input-source').write_text('obsolete helper')
            (dist/'register-input-source.sha256').write_text('old hash')
            def fake_compile(args, **kwargs):
                Path(args[-1]).write_text('new helper')
            with patch.object(builder, 'DIST', dist), patch.object(builder, 'run', fake_compile):
                helper = builder.ensure_helper()
                self.assertEqual(helper.read_text(), 'new helper')
                with patch.object(builder, 'run') as run:
                    builder.ensure_helper()
                    run.assert_not_called()

    def test_compile_failure_preserves_previous_helper(self):
        with tempfile.TemporaryDirectory() as temp:
            dist = Path(temp)
            (dist/'register-input-source').write_text('previous')
            with patch.object(builder, 'DIST', dist), patch.object(builder, 'run', side_effect=RuntimeError('compile error')):
                with self.assertRaises(RuntimeError):
                    builder.ensure_helper()
            self.assertEqual((dist/'register-input-source').read_text(), 'previous')

    def test_registration_failure_is_fatal_not_install_success(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            app, target, backups = root/'source.app', root/'HanjaIME.app', root/'Backups'
            (app/'Contents').mkdir(parents=True)
            (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info()))
            backups.mkdir()
            def run(args, **kwargs):
                if args[0] == '/usr/bin/ditto':
                    shutil.copytree(args[1], args[2])
                if '--register' in args:
                    raise RuntimeError('TIS registration failure')
                return 0
            with patch.object(builder, 'run', run), patch.object(builder, 'verify', builder.bundle_info):
                with self.assertRaisesRegex(RuntimeError, 'TIS registration failure'):
                    builder.replace_app(app, target, backups)


if __name__ == '__main__':
    unittest.main()
