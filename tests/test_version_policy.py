import importlib.util
from pathlib import Path
import unittest
spec = importlib.util.spec_from_file_location("next_version", Path(__file__).resolve().parents[1] / "scripts/next_version.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
class VersionPolicyTests(unittest.TestCase):
    def test_increment(self):
        self.assertEqual(module.next_version("0.9.4"), "0.9.5")
    def test_carry(self):
        self.assertEqual(module.next_version("0.0.9"), "0.1.0")
        self.assertEqual(module.next_version("0.9.9"), "0.10.0")
    def test_reject_invalid_new_release(self):
        for value in ["0.8.14", "0.9", "0.9.-1", "v0.9.4", "0.09.4"]:
            with self.assertRaises(ValueError): module.next_version(value)
