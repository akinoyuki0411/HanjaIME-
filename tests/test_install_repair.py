"""Linux regression tests for launcher inheritance and preserving a completed build.

Apple processes are simulated; this does not exercise macOS registration or signing.
"""
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("install_repair", ROOT / "scripts/repair_install.py")
repair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repair)

LEGACY = '''#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "Xcode를 설치하고 한 번 실행해 주세요. Python 3를 찾지 못했습니다."
  exit 1
fi
python3 "${SCRIPT_DIR}/scripts/hanjaime.py" ACTION "$@"
status=$?
if [ -t 0 ]; then
  read -r -p "Enter를 누르면 창을 닫습니다..." _ || true
fi
exit "$status"
'''


class LauncherEnvironmentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="HanjaIME launcher ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        (self.root / "bin").mkdir()
        self.trace = self.root / "trace.txt"
        self.env = dict(os.environ, PATH=str(self.root / "bin") + os.pathsep + os.environ["PATH"],
                        HANJAIME_TEST_TRACE=str(self.trace))
        self.env.pop("DEVELOPER_DIR", None)
        (self.root / "scripts/select_xcode.sh").write_text('''hanjaime_select_xcode() {
  export DEVELOPER_DIR='/Applications/Xcode 27 beta.app/Contents/Developer'
}
''')
        python_shim = self.root / "bin/python3"
        python_shim.write_text('''#!/bin/bash
if [ "${DEVELOPER_DIR:-}" != '/Applications/Xcode 27 beta.app/Contents/Developer' ]; then
  echo 'Simulated Xcode 26 default: license error' >&2
  exit 69
fi
printf '%s\\n' "$DEVELOPER_DIR" "$@" > "$HANJAIME_TEST_TRACE"
exit "${HANJAIME_TEST_EXIT:-0}"
''')
        python_shim.chmod(0o755)

    def execute(self, name, data, *args):
        path = self.root / name
        path.write_bytes(data)
        return subprocess.run(["bash", path, *args], env=self.env,
                              stdin=subprocess.DEVNULL, capture_output=True, text=True)

    def test_legacy_installer_reproduces_missing_environment_error(self):
        result = self.execute("install_hanjaime.command", LEGACY.replace("ACTION", "install").encode())
        self.assertEqual(result.returncode, 69)
        self.assertFalse(self.trace.exists())

    def test_install_and_restore_inherit_selected_xcode_before_python(self):
        for action in ("install", "restore"):
            with self.subTest(action=action):
                name = action + "_hanjaime.command"
                result = self.execute(name, (ROOT / name).read_bytes(), "path with spaces")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.trace.read_text().splitlines(), [
                    "/Applications/Xcode 27 beta.app/Contents/Developer",
                    str(self.root / "scripts/hanjaime.py"), action, "path with spaces",
                ])

    def test_failed_selection_stops_before_python(self):
        (self.root / "scripts/select_xcode.sh").write_text("hanjaime_select_xcode() { return 1; }\n")
        result = self.execute("install_hanjaime.command", (ROOT / "install_hanjaime.command").read_bytes())
        self.assertEqual(result.returncode, 1)
        self.assertFalse(self.trace.exists())

    def test_installer_failure_exit_code_is_preserved(self):
        self.env["HANJAIME_TEST_EXIT"] = "23"
        result = self.execute("install_hanjaime.command", (ROOT / "install_hanjaime.command").read_bytes())
        self.assertEqual(result.returncode, 23)


class ExistingBuildRepairTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="HanjaIME repair ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "existing Fix4 with spaces"
        self.root.mkdir()
        (self.root / "scripts").mkdir()
        for name in repair.SUPPORT_HASHES:
            shutil.copy2(ROOT / name, self.root / name)
        self.originals = {}
        for name, expected in repair.LEGACY_HASHES.items():
            data = LEGACY.replace("ACTION", name.split("_")[0]).encode()
            self.assertEqual(hashlib.sha256(data).hexdigest(), expected)
            (self.root / name).write_bytes(data)
            self.originals[name] = data
        self.dist = self.root / "dist"
        contents = self.dist / "HanjaIME.app/Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "org.hanjaime.inputmethod.HanjaIME",
            "CFBundleExecutable": "HanjaIME",
        }))
        (contents / "MacOS/HanjaIME").write_bytes(b"successful app sentinel")
        (self.dist / "build.json").write_text(json.dumps({
            "status": "macOS-build-and-integration-tests-passed",
        }))
        helper = self.dist / "register-input-source"
        helper.write_bytes(b"registration helper sentinel")
        helper.chmod(0o755)
        self.dist_before = self.snapshot_dist()

    def snapshot_dist(self):
        return {str(p.relative_to(self.dist)): (p.read_bytes(), p.stat().st_mtime_ns, p.stat().st_mode)
                for p in self.dist.rglob("*") if p.is_file()}

    def test_repair_backs_up_launchers_preserves_dist_and_repeats_safely(self):
        backup = repair.repair(self.root)
        for name, original in self.originals.items():
            self.assertEqual((backup / name).read_bytes(), original)
            self.assertEqual((self.root / name).read_bytes(), (ROOT / name).read_bytes())
        self.assertEqual(self.snapshot_dist(), self.dist_before)
        self.assertIsNone(repair.repair(self.root))
        self.assertEqual(len(list((self.root / "build").glob("installer-backup-*"))), 1)

    def test_user_edit_aborts_before_either_launcher_changes(self):
        edited = self.root / "restore_hanjaime.command"
        edited.write_bytes(edited.read_bytes() + b"\n# user edit\n")
        with self.assertRaisesRegex(RuntimeError, "덮어쓰지"):
            repair.repair(self.root)
        self.assertEqual((self.root / "install_hanjaime.command").read_bytes(), self.originals["install_hanjaime.command"])
        self.assertTrue(edited.read_bytes().endswith(b"# user edit\n"))
        self.assertEqual(self.snapshot_dist(), self.dist_before)
        self.assertFalse(list((self.root / "build").glob("installer-backup-*")))

    def test_incomplete_build_cannot_trigger_install_or_rebuild(self):
        (self.dist / "build.json").write_text('{"status": "failed"}')
        with self.assertRaisesRegex(RuntimeError, "성공 기록"):
            repair.repair(self.root)
        for name, original in self.originals.items():
            self.assertEqual((self.root / name).read_bytes(), original)

    def test_missing_helper_aborts_before_repair(self):
        (self.dist / "register-input-source").unlink()
        with self.assertRaisesRegex(RuntimeError, "등록 도구"):
            repair.repair(self.root)
        self.assertFalse((self.root / "build").exists())

    def test_second_replacement_failure_rolls_back_first(self):
        original_replace = repair.replace_file
        def fail_restore(source, target):
            if source.parent == ROOT and source.name == "restore_hanjaime.command":
                raise OSError("simulated write failure")
            return original_replace(source, target)
        with patch.object(repair, "replace_file", side_effect=fail_restore):
            with self.assertRaises(OSError):
                repair.repair(self.root)
        for name, original in self.originals.items():
            self.assertEqual((self.root / name).read_bytes(), original)
        self.assertEqual(self.snapshot_dist(), self.dist_before)

    def test_concurrent_build_lock_prevents_repair(self):
        (self.root / "build").mkdir()
        with (self.root / "build/operation.lock").open("a+") as lock:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(BlockingIOError):
                repair.repair(self.root)
        for name, original in self.originals.items():
            self.assertEqual((self.root / name).read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
