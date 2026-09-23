import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("manager_cleanup", ROOT / "scripts/hanjaime.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)

class ManagerCleanupTests(unittest.TestCase):
    def test_removes_both_matching_links_even_after_embedded_app_removed(self):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder)
            target = home / "Library/Input Methods/HanjaIME.app"
            embedded = target / "Contents/Resources/HanjaIMEWordManager.app"
            system = home / "SystemApplications"
            links = [home / "Applications/HanjaIME Manager.app", system / "HanjaIME Manager.app"]
            for link in links:
                link.parent.mkdir(parents=True)
                link.symlink_to(embedded)
            with patch.object(Path, "home", return_value=home), patch.object(build, "SYSTEM_APPLICATIONS", system):
                self.assertEqual(len(build.cleanup_legacy_manager_shortcuts(target)), 2)
                self.assertEqual(build.cleanup_legacy_manager_shortcuts(target), [])
            self.assertTrue(all(not link.is_symlink() for link in links))

    def test_unrelated_app_and_link_are_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder)
            system = home / "SystemApplications"
            app = home / "Applications/HanjaIME Manager.app"
            app.mkdir(parents=True)
            link = system / "HanjaIME Manager.app"
            system.mkdir(); link.symlink_to(home / "unrelated.app")
            with patch.object(Path, "home", return_value=home), patch.object(build, "SYSTEM_APPLICATIONS", system):
                self.assertEqual(build.cleanup_legacy_manager_shortcuts(home / "ime.app"), [])
            self.assertTrue(app.is_dir()); self.assertTrue(link.is_symlink())
