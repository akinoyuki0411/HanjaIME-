"""Execute the actual Swift migration predicates with TIS record adapters."""
import argparse
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--swiftc', type=Path, required=True)
args = parser.parse_args()
helper = (ROOT / 'scripts/register_input_source.swift').read_text()
policy = helper[helper.index('struct Policy:'):helper.index('func selectABCIfNeeded')]
fixture = '''
import Foundation
let bundleID = "org.hanjaime.inputmethod.HanjaIME"
let korean2SetID = bundleID + ".han2"
let kTISPropertyInputSourceID = "source_id", kTISPropertyInputModeID = "mode_id", kTISPropertyBundleID = "bundle_id"
struct TISInputSource { let values: [String: String] }
func property(_ source: TISInputSource, _ key: String) -> String? { source.values[key] }
''' + policy + r'''
@main struct Tests {
 static var checks = 0
 static func expect(_ ok: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if !ok() { fatalError(message) }
 }
 static func main() throws {
  let policy = try Policy(path: CommandLine.arguments[1])
  expect(!policy.legacy_source_ids.contains(korean2SetID), "canonical source protected")
  for id in policy.legacy_source_ids {
   let row = TISInputSource(values: ["bundle_id": bundleID, "source_id": id, "mode_id": id])
   expect(policy.matches(row), "exact observed legacy ID recognized")
   expect(!policy.matches(TISInputSource(values: ["bundle_id": "org.youknowone.inputmethod.Gureum", "source_id": id])), "Gureum never matched")
   expect(!policy.matches(TISInputSource(values: ["bundle_id": bundleID, "source_id": korean2SetID, "mode_id": id])), "canonical ID always protected")
   expect(policy.matchesPreference(["Bundle ID": bundleID, "Input Mode": id]), "exact legacy preference")
   expect(!policy.matchesPreference(["Bundle ID": "com.apple.inputmethod.Korean", "Input Mode": id]), "foreign preferences protected")
   expect(!policy.matchesPreference(["Input Mode": korean2SetID, "InputSourceID": id]), "canonical preference protected")
  }
  for id in [korean2SetID, "com.apple.keylayout.ABC", "com.apple.inputmethod.Korean.2SetKorean", "com.apple.inputmethod.Kotoeri.Japanese", "unknown.Hanjimi.han2"] {
   expect(!policy.matchesPreference(id), "other scalar source preserved")
   expect(!policy.matchesPreference(["Input Mode": id]), "other dictionary source preserved")
  }
  let enabled: [[String: String]] = [
   ["Bundle ID": bundleID, "Input Mode": bundleID + ".qwerty"],
   ["Bundle ID": bundleID, "Input Mode": korean2SetID],
   ["Bundle ID": "com.apple.inputmethod.Korean", "Input Mode": "com.apple.inputmethod.Korean.2SetKorean"],
   ["InputSourceKind": "Keyboard Layout", "KeyboardLayout Name": "ABC"]]
  let kept = enabled.filter { !policy.matchesPreference($0) }
  expect(kept == Array(enabled.dropFirst()), "remove only legacy entry, preserve order and metadata")
  print("PASS: \(checks) production Swift migration-policy checks; TIS adapters only")
 }
}
'''
out = ROOT / 'build/migration-policy-tests'
out.mkdir(parents=True, exist_ok=True)
source = out / 'PolicyTests.swift'
source.write_text(fixture)
subprocess.run([str(args.swiftc), '-swift-version', '5', '-warnings-as-errors', '-parse-as-library', str(source), '-o', str(out/'policy-tests')], check=True)
subprocess.run([str(out/'policy-tests'), str(ROOT/'scripts/legacy_input_sources.json')], check=True)
