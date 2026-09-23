"""Check actual Xcode source membership; developer tests only, no Mac runtime substitute."""
import os
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

try:
    from openstep_parser import OpenStepDecoder
except ImportError:
    OpenStepDecoder = None


def target_sources(repo):
    repo = Path(repo)
    with (repo / "Gureum.xcodeproj/project.pbxproj").open() as project:
        data = OpenStepDecoder.ParseFromFile(project)
    objects = data["objects"]
    paths = {}

    def visit(ref, parent):
        item = objects[ref]
        tree = item.get("sourceTree", "<group>")
        if tree not in ("<group>", "SOURCE_ROOT"):
            return
        path = (repo if tree == "SOURCE_ROOT" else parent) / item.get("path", "")
        if item["isa"] == "PBXGroup":
            for child in item.get("children", []):
                visit(child, path)
        elif item["isa"] == "PBXFileReference":
            paths[ref] = path

    visit(objects[data["rootObject"]]["mainGroup"], repo)
    targets = {}
    for target in objects.values():
        if target.get("isa") != "PBXNativeTarget":
            continue
        files = []
        for phase_ref in target.get("buildPhases", []):
            phase = objects[phase_ref]
            if phase["isa"] == "PBXSourcesBuildPhase":
                files.extend(paths[objects[ref]["fileRef"]] for ref in phase.get("files", []))
        targets[target["name"]] = files
    return targets


@unittest.skipUnless(os.environ.get("HANJAIME_UPSTREAM_REPO") and OpenStepDecoder,
                     "developer check requires HANJAIME_UPSTREAM_REPO and tests/requirements.txt")
class XcodeTargetTests(unittest.TestCase):
    def setUp(self):
        self.targets = target_sources(os.environ["HANJAIME_UPSTREAM_REPO"])

    def test_shared_configuration_dependencies_are_in_each_target(self):
        checked = set()
        for target, files in self.targets.items():
            configuration = next((p for p in files if p.name == "Configuration.swift"), None)
            if configuration is None:
                continue
            checked.add(target)
            required = set(re.findall(r"\bHanjaIME\w+\b", configuration.read_text()))
            declarations = set()
            for source in files:
                if source.suffix == ".swift":
                    declarations.update(re.findall(r"\b(?:enum|struct|class)\s+(HanjaIME\w+)",
                                                   source.read_text()))
            self.assertFalse(required - declarations,
                             f"{target}: missing shared declarations {sorted(required - declarations)}")
        self.assertEqual(checked, {"OSXCore", "Preferences"})

    def test_custom_candidate_panel_is_in_the_core_build_target(self):
        core = self.targets["OSXCore"]
        panels = [p for p in core if p.name == "HanjaIMECandidatePanel.swift"]
        self.assertEqual(len(panels), 1)
        self.assertIn("final class HanjaIMECandidatePanel", panels[0].read_text())
        self.assertNotIn(panels[0], self.targets["Preferences"])

    def test_hanjaime_preferences_and_menu_are_in_the_app_target(self):
        app = self.targets["OSX"]
        preferences = next(p for p in app if p.name == "ConfigurationWindow.swift").read_text()
        menu = next(p for p in app if p.name == "GureumMenu.swift").read_text()
        self.assertIn("class HanjaIMEPreferencesWindowController", preferences)
        self.assertIn("configuration.set", preferences)
        self.assertIn("HanjaIMEPreferencesWindowController(configuration: .shared)", menu)
        self.assertNotIn('NSStoryboard(name: "Configuration"', menu)
        self.assertIn("preferencesWindow.select(.about)", menu)

    def test_alternate_text_callback_is_production_code_not_a_mock_override(self):
        source = next(p for p in self.targets["OSXCore"] if p.name == "InputController.swift").read_text()
        production, mock = source.split("@objcMembers public class MockInputController", 1)
        self.assertIn("public override func inputText(", production)
        self.assertNotIn("override func inputText(", mock)
        self.assertIn("return receiver.input(text: string, key: key,", production)

    def test_test_host_explicitly_isolates_input_method_connection(self):
        repo = Path(os.environ["HANJAIME_UPSTREAM_REPO"])
        scheme = ET.parse(repo / "Gureum.xcodeproj/xcshareddata/xcschemes/HanjaIME.xcscheme").getroot()
        action = scheme.find("TestAction")
        self.assertEqual(action.get("shouldUseLaunchSchemeArgsEnv"), "NO")
        flag = action.find("EnvironmentVariables/EnvironmentVariable[@key='HANJAIME_TEST_SESSION']")
        self.assertIsNotNone(flag)
        self.assertEqual(flag.get("value"), "1")
        self.assertEqual(flag.get("isEnabled"), "YES")
        self.assertIsNone(scheme.find("LaunchAction/EnvironmentVariables/EnvironmentVariable[@key='HANJAIME_TEST_SESSION']"))

    def test_connection_isolation_does_not_depend_on_debug_define(self):
        source = next(p for p in self.targets["OSXCore"] if p.name == "InputMethodServer.swift").read_text()
        initializer = source.split("  convenience init() {", 1)[1].split("  init(name:", 1)[0]
        self.assertIn('environment["HANJAIME_TEST_SESSION"] == "1"', initializer)
        self.assertIn('environment["XCTestConfigurationFilePath"] != nil', initializer)
        self.assertIn('UUID().uuidString', initializer)
        self.assertNotIn('#if DEBUG', initializer)

    def test_source_paths_exist_and_are_not_duplicated(self):
        self.assertEqual(set(self.targets), {"OSX", "OSXCore", "OSXTests", "OSXTestApp", "Preferences"})
        for target, files in self.targets.items():
            self.assertEqual(len(files), len(set(files)), target)
            for source in files:
                self.assertTrue(source.is_file(), f"{target}: missing {source}")

    def test_mock_lifecycle_does_not_enter_uninitialized_imk_connection(self):
        source = next(p for p in self.targets["OSXCore"] if p.name == "InputController.swift").read_text()
        real, mock = source.split("@objcMembers public class MockInputController", 1)
        real_callback = real.split("public override func deactivateServer", 1)[1].split("\n  }", 1)[0]
        mock_callback = mock.split("public override func deactivateServer", 1)[1].split("\n    }", 1)[0]
        self.assertIn("deactivateInputContext(sender)", real_callback)
        self.assertIn("super.deactivateServer(sender)", real_callback)
        self.assertIn("deactivateInputContext(sender)", mock_callback)
        self.assertNotIn("super.deactivateServer", mock_callback)
        cleanup = real.split("func deactivateInputContext", 1)[1].split("\n  }", 1)[0]
        for required in ["self.commitComposition(sender)", "searchComposer.cancelSearch()",
                         "hanjaPanel.hide()", "activeController = nil"]:
            self.assertIn(required, cleanup)


if __name__ == "__main__":
    unittest.main()
