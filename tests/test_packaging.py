import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("hanjaime_build", ROOT / "scripts/hanjaime.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class SettingsLaunchTests(unittest.TestCase):
    def test_settings_launcher_uses_installed_ime_without_developer_tools(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            installed = root / "Library/Input Methods/HanjaIME.app"
            installed.mkdir(parents=True)
            with patch.object(Path, "home", return_value=root), patch.object(build, "mac_required"), \
                 patch.object(build, "developer_environment") as developer, patch.object(build, "run") as run:
                build.settings()
                run.assert_called_once_with(["/usr/bin/open", "-a", installed, "--args", "--settings"])
                developer.assert_not_called()


class SigningMetadataTests(unittest.TestCase):
    def test_signing_removes_only_forbidden_finder_attributes(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "HanjaIME.app"
            app.mkdir()
            link = app / "external"
            link.symlink_to(Path(directory))
            license_file = app / "LICENSE"
            license_file.write_text("license")
            license_file.chmod(0o444)
            with patch.object(build, "run") as run:
                build.sign(app)
            self.assertEqual(license_file.stat().st_mode & 0o777, 0o444)
            self.assertEqual([call.args[0] for call in run.call_args_list[:2]], [
                ["/usr/bin/xattr", "-drs", "com.apple.FinderInfo", app],
                ["/usr/bin/xattr", "-drs", "com.apple.ResourceFork", app]])



class VersionValidationTests(unittest.TestCase):
    def test_stale_app_version_rejected_before_signing_check(self):
        with patch.object(build, "bundle_info", return_value={"CFBundleShortVersionString": "0.8.6"}), \
             patch.object(build, "run") as run:
            with self.assertRaisesRegex(RuntimeError, "버전"):
                build.verify(Path("HanjaIME.app"), expected_version=build.VERSION)
            run.assert_not_called()


class InstallerSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.backups = self.root / "Backups"
        self.backups.mkdir()
        self.target = self.root / "Input Methods/HanjaIME.app"
        self.target.parent.mkdir()
        self.official = self.root / "Input Methods/Gureum.app"
        self.make_app(self.official, "official", "org.youknowone.inputmethod.Gureum")
        self.make_app(self.target, "old")
        self.source = self.root / "dist/HanjaIME.app"
        self.make_app(self.source, "new")

    def tearDown(self):
        self.assertEqual((self.official / "sentinel").read_text(), "official")
        self.temp.cleanup()

    @staticmethod
    def make_app(app, sentinel, bundle_id=build.BUNDLE_ID):
        (app / "Contents").mkdir(parents=True)
        (app / "sentinel").write_text(sentinel)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": bundle_id, "CFBundleExecutable": "HanjaIME",
            "InputMethodConnectionName": "HanjaIME_Connection",
        }))

    @staticmethod
    def fake_run(args, **kwargs):
        if args[0] == "/usr/bin/ditto":
            shutil.copytree(args[1], args[2])
        return 0

    def test_wrong_bundle_never_replaced(self):
        plist = self.target / "Contents/Info.plist"
        info = plistlib.loads(plist.read_bytes())
        info["CFBundleIdentifier"] = "unrelated.user.app"
        plist.write_bytes(plistlib.dumps(info))
        with patch.object(build, "verify", build.bundle_info):
            with self.assertRaises(RuntimeError):
                build.replace_app(self.source, self.target, self.backups)
        self.assertEqual((self.target / "sentinel").read_text(), "old")

    def test_symlink_never_replaced(self):
        alias = self.target.parent / "alias.app"
        alias.symlink_to(self.official, target_is_directory=True)
        with self.assertRaises(RuntimeError):
            build.bundle_info(alias)

    def test_success_preserves_previous_app(self):
        with patch.object(build, "verify", build.bundle_info), patch.object(build, "run", self.fake_run):
            build.replace_app(self.source, self.target, self.backups)
        self.assertEqual((self.target / "sentinel").read_text(), "new")
        old = list(self.backups.glob("*/HanjaIME.app/sentinel"))
        self.assertEqual(len(old), 1)
        self.assertEqual(old[0].read_text(), "old")

    def test_failed_copy_preserves_target(self):
        with patch.object(build, "verify", build.bundle_info), patch.object(build, "run", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                build.replace_app(self.source, self.target, self.backups)
        self.assertEqual((self.target / "sentinel").read_text(), "old")

    def test_failed_final_move_rolls_back(self):
        rename = Path.rename
        def fail_new(source, target):
            if source.parent.name.startswith(".HanjaIME-stage-"):
                raise OSError("simulated final rename failure")
            return rename(source, target)
        with patch.object(build, "verify", build.bundle_info), patch.object(build, "run", self.fake_run), patch.object(Path, "rename", fail_new):
            with self.assertRaises(OSError):
                build.replace_app(self.source, self.target, self.backups)
        self.assertEqual((self.target / "sentinel").read_text(), "old")


@unittest.skipUnless(os.environ.get("HANJAIME_UPSTREAM_REPO"), "set HANJAIME_UPSTREAM_REPO to the pinned Gureum clone")
class PatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp.name) / "source with spaces"
        subprocess.run(["git", "clone", "--quiet", "--shared", "--no-checkout",
                        os.environ["HANJAIME_UPSTREAM_REPO"], self.repo], check=True)
        subprocess.run(["git", "checkout", "--quiet", "--detach", build.PIN], cwd=self.repo, check=True)

    def tearDown(self):
        self.temp.cleanup()

    def apply(self, *args):
        return subprocess.run(["python3", ROOT / "apply_hanjaime_patch.py", self.repo, *args],
                              capture_output=True, text=True)

    def test_check_has_no_side_effects(self):
        self.assertEqual(self.apply("--check").returncode, 0)
        self.assertFalse((self.repo / ".hanjaime-backups").exists())
        self.assertEqual(subprocess.check_output(["git", "status", "--porcelain"], cwd=self.repo), b"")

    def test_clean_patch_contains_xcode_icons_and_asset_catalog_files(self):
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        project = (self.repo / "Gureum.xcodeproj/project.pbxproj").read_text()
        icons = set(re.findall(r'path = "?(Icons/[^";]+)', project))
        self.assertNotIn("Icons/HanjaIMEEnglish.png", icons)
        self.assertIn("Icons/HanjaIME.png", icons)
        self.assertNotIn("Icons/HanjaIMEEnglish@2x.png", icons)
        self.assertIn("Icons/HanjaIME@2x.png", icons)
        for relative in sorted(icons):
            icon = self.repo / "OSX" / relative
            self.assertTrue(icon.is_file(), f"Missing Xcode icon: {relative}")
            self.assertTrue(icon.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"), relative)
        for catalog in (self.repo / "OSX/Assets.xcassets").rglob("Contents.json"):
            for item in json.loads(catalog.read_text()).get("images", []):
                if item.get("filename"):
                    asset = catalog.parent / item["filename"]
                    self.assertTrue(asset.is_file(), f"Missing catalog image: {asset}")


    def test_korean_only_input_source_registration(self):
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        info = plistlib.loads((self.repo / "OSX/Info.plist").read_bytes())
        modes = info["ComponentInputModeDict"]["tsInputModeListKey"]
        self.assertEqual(set(modes), {"org.hanjaime.inputmethod.HanjaIME.han2"})
        self.assertEqual(
            info["ComponentInputModeDict"]["tsVisibleInputModeOrderedArrayKey"],
            ["org.hanjaime.inputmethod.HanjaIME.han2"],
        )
        self.assertNotIn("org.hanjaime.inputmethod.HanjaIME.qwerty", modes)

    def test_apply_twice_and_backup(self):
        original = (self.repo / "OSXCore/GureumComposer.swift").read_bytes()
        first = self.apply()
        self.assertEqual(first.returncode, 0, first.stderr)
        second = self.apply()
        self.assertEqual(second.returncode, 0, second.stderr)
        copies = list((self.repo / ".hanjaime-backups").glob("*/OSXCore/GureumComposer.swift"))
        self.assertEqual(len(copies), 1)
        self.assertEqual(copies[0].read_bytes(), original)

    def test_user_edit_aborts_before_any_write(self):
        target = self.repo / "OSXCore/GureumComposer.swift"
        target.write_text(target.read_text() + "\n// user edit\n")
        before = (self.repo / "OSXCore/InputReceiver.swift").read_bytes()
        result = self.apply()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("nothing written", result.stderr)
        self.assertEqual((self.repo / "OSXCore/InputReceiver.swift").read_bytes(), before)
        self.assertTrue(target.read_text().endswith("// user edit\n"))

    def test_mixed_patch_aborts(self):
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        subprocess.run(["git", "checkout", build.PIN, "--", "OSXCore/InputReceiver.swift"], cwd=self.repo, check=True)
        before = (self.repo / "OSXCore/GureumComposer.swift").read_bytes()
        self.assertNotEqual(self.apply().returncode, 0)
        self.assertEqual((self.repo / "OSXCore/GureumComposer.swift").read_bytes(), before)


class ScriptTests(unittest.TestCase):
    def test_shell_syntax_and_no_global_security_or_gureum_writes(self):
        for script in [*ROOT.glob("*.command"), *ROOT.glob("scripts/*.sh")]:
            subprocess.run(["bash", "-n", script], check=True)
        source = (ROOT / "scripts/hanjaime.py").read_text()
        self.assertNotIn("spctl", source)
        self.assertNotIn('"sudo"', source)
        self.assertNotIn('"/Library/Input Methods/Gureum.app"', source)

    def test_patch_and_editable_sources_match(self):
        import hashlib
        manifest = json.loads((ROOT / "patches/manifest.json").read_text())
        by_path = {i["path"]: i["after"] for i in manifest["files"]}
        for source in (ROOT / "Sources").glob("*.swift"):
            folder = "OSX/" if source.name in ("ConfigurationWindow.swift", "GureumMenu.swift", "GureumAppDelegate.swift") else "OSXCore/"
            self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), by_path[folder + source.name], source.name)
        self.assertEqual(hashlib.sha256((ROOT / "tests/HanjaIMEIntegrationTests.swift").read_bytes()).hexdigest(),
                         by_path["GureumTests/HanjaIMEIntegrationTests.swift"])


    def test_korean_only_runtime_guards_and_legacy_cleanup(self):
        composer = (ROOT / "Sources/GureumComposer.swift").read_text()
        self.assertIn("guard newValue == GureumInputSource.han2.rawValue else", composer)
        self.assertIn("English is the system ABC input source", composer)
        helper = (ROOT / "scripts/register_input_source.swift").read_text()
        self.assertIn("TISDisableInputSource", helper)
        self.assertIn('bundleID + ".han2"', helper)

    def test_personal_words_are_integrated_without_standalone_manager(self):
        text = (ROOT / "scripts/hanjaime.py").read_text()
        self.assertFalse((ROOT / "Manager").exists())
        self.assertTrue((ROOT / "open_hanjaime_settings.command").is_file())
        self.assertNotIn("build_word_manager", text)
        self.assertNotIn("embed_word_manager", text)
        self.assertIn("cleanup_legacy_manager_shortcuts(target)", text)


    def test_candidate_hover_uses_the_appkit_tracking_option(self):
        panel = (ROOT / "Sources/HanjaIMECandidatePanel.swift").read_text()
        self.assertIn(".mouseEnteredAndExited", panel)
        self.assertNotIn(".mouseEntered,", panel)


if __name__ == "__main__":
    unittest.main()
