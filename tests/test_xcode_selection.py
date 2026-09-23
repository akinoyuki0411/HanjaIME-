"""Exercise the shell selector; substitute only Apple's unavailable plist reader."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class XcodeSelectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def app(self, name, version):
        app = self.root / name
        developer = app / "Contents/Developer"
        binary = developer / "usr/bin/xcodebuild"
        binary.parent.mkdir(parents=True)
        binary.write_text("#!/bin/bash\nexit 0\n")
        binary.chmod(0o755)
        (developer / "test-version").write_text(version)
        return developer

    def choose(self, *candidates):
        script = '''set -uo pipefail
source "$1"
shift
hanjaime_xcode_version() { cat "$1/test-version"; }
hanjaime_choose_xcode27 "$@" || exit 1
printf '%s' "$DEVELOPER_DIR"
'''
        env = os.environ.copy()
        env.pop("DEVELOPER_DIR", None)
        return subprocess.run(["bash", "-c", script, "selector-test",
                               str(ROOT / "scripts/select_xcode.sh"),
                               *map(str, candidates)], env=env, text=True,
                              capture_output=True)

    def test_old_selected_xcode_is_skipped_for_beta_with_spaces(self):
        old = self.app("Xcode.app", "26.6")
        beta = self.app("Xcode 27 beta.app", "27.0")
        result = self.choose(old, beta)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, str(beta))
        self.assertTrue((old / "usr/bin/xcodebuild").exists())

    def test_only_old_xcode_explains_required_download(self):
        result = self.choose(self.app("Xcode.app", "26.6"))
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("Xcode 27", result.stderr)
        self.assertIn("developer.apple.com/download/", result.stderr)

    def test_app_path_is_accepted_as_explicit_developer_directory(self):
        developer = self.app("Xcode-beta.app", "27.0")
        result = self.choose(developer.parent.parent)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, str(developer))

    def test_missing_and_malformed_candidates_are_skipped(self):
        damaged = self.app("Broken.app", "unknown")
        beta = self.app("Xcode-beta.app", "27.0")
        result = self.choose(self.root / "missing", damaged, beta)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, str(beta))

    def test_existing_compatible_selection_keeps_priority(self):
        selected = self.app("Xcode-selected.app", "27.0")
        other = self.app("Xcode-beta.app", "27.0")
        result = self.choose(selected, other)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, str(selected))


if __name__ == "__main__":
    unittest.main()
