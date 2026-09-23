// Public TIS diagnostics and strictly scoped migration. No private unregister API.
import Foundation
import Carbon
import AppKit

let bundleID = "org.hanjaime.inputmethod.HanjaIME"
let korean2SetID = bundleID + ".han2"
let arguments = CommandLine.arguments
let preferenceDomain = "com.apple.HIToolbox" as CFString
let preferenceKeys = ["AppleEnabledInputSources", "AppleSelectedInputSources",
  "AppleCurrentKeyboardLayoutInputSourceID", "AppleInputSourceHistory", "AppleInputSourceUpdateTime"]

func property(_ source: TISInputSource, _ key: CFString) -> String? {
  guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
  return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
}
func flag(_ source: TISInputSource, _ key: CFString) -> Bool {
  guard let raw = TISGetInputSourceProperty(source, key) else { return false }
  return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue())
}
func sources() -> [TISInputSource] {
  TISCreateInputSourceList(nil, true).takeRetainedValue() as NSArray as! [TISInputSource]
}
func jsonValue(_ value: Any) -> Any {
  if let date = value as? Date { return ISO8601DateFormatter().string(from: date) }
  if let data = value as? Data { return ["base64": data.base64EncodedString()] }
  if let dict = value as? [String: Any] { return dict.mapValues(jsonValue) }
  if let array = value as? [Any] { return array.map(jsonValue) }
  return value
}
func emit(_ object: Any) throws {
  let data = try JSONSerialization.data(withJSONObject: jsonValue(object), options: [.prettyPrinted, .sortedKeys])
  FileHandle.standardOutput.write(data)
  FileHandle.standardOutput.write(Data([10]))
}
func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}
func row(_ source: TISInputSource) -> [String: Any] {
  let bundle = property(source, kTISPropertyBundleID) ?? ""
  // TIS has no public bundle URL property. LS returns *possible* locations,
  // including missing/duplicate bundles; do not mislabel one as an exact URL.
  let urls = bundle.isEmpty ? [] :
    (LSCopyApplicationURLsForBundleIdentifier(bundle as CFString, nil)?.takeRetainedValue() as? [URL] ?? [])
  return ["name": property(source, kTISPropertyLocalizedName) ?? "",
    "bundle_id": bundle,
    "source_id": property(source, kTISPropertyInputSourceID) ?? "",
    "mode_id": property(source, kTISPropertyInputModeID) ?? "",
    "enabled": flag(source, kTISPropertyInputSourceIsEnabled),
    "selected": flag(source, kTISPropertyInputSourceIsSelected),
    "select_capable": flag(source, kTISPropertyInputSourceIsSelectCapable),
    "enable_capable": flag(source, kTISPropertyInputSourceIsEnableCapable),
    "bundle_url_resolution": "LaunchServices candidates; not a TIS URL property",
    "bundle_urls": urls.map { ["path": $0.path, "exists": FileManager.default.fileExists(atPath: $0.path)] }]
}
func preferenceSnapshot() -> [String: Any] {
  var result: [String: Any] = [:]
  for (name, host) in [("any_host", kCFPreferencesAnyHost), ("current_host", kCFPreferencesCurrentHost)] {
    var values: [String: Any] = [:]
    for key in preferenceKeys {
      values[key] = CFPreferencesCopyValue(key as CFString, preferenceDomain, kCFPreferencesCurrentUser, host)
        .map { jsonValue($0) } ?? NSNull()
    }
    result[name] = values
  }
  return result
}
struct Policy: Decodable {
  let bundle_id: String
  let current_source_id: String
  let legacy_source_ids: [String]
  init(path: String) throws {
    self = try JSONDecoder().decode(Self.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    guard bundle_id == bundleID, current_source_id == korean2SetID,
      !legacy_source_ids.contains(korean2SetID), !legacy_source_ids.contains(bundleID),
      !legacy_source_ids.isEmpty,
      legacy_source_ids.allSatisfy({ $0.hasPrefix(bundleID + ".") }) else {
      throw NSError(domain: "HanjaIMEMigration", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Unsafe migration policy"])
    }
  }
  func matches(_ source: TISInputSource) -> Bool {
    let id = property(source, kTISPropertyInputSourceID) ?? ""
    let mode = property(source, kTISPropertyInputModeID) ?? ""
    guard property(source, kTISPropertyBundleID) == bundleID,
      id != korean2SetID, mode != korean2SetID else { return false }
    return legacy_source_ids.contains(id) || legacy_source_ids.contains(mode)
  }
  func matchesPreference(_ item: Any) -> Bool {
    if let id = item as? String { return legacy_source_ids.contains(id) }
    guard let entry = item as? [String: Any] else { return false }
    let bundleKeys = ["Bundle ID", "BundleID", "BundleIdentifier"]
    let bundles = bundleKeys.compactMap { entry[$0] as? String }
    if bundles.contains(where: { $0 != bundleID }) { return false }
    let idKeys = ["Input Mode", "InputMode", "InputModeID", "Input Source ID", "InputSourceID", "Source ID"]
    let ids = idKeys.compactMap { entry[$0] as? String }
    if ids.contains(korean2SetID) { return false }
    return ids.contains { legacy_source_ids.contains($0) }
  }
}
func selectABCIfNeeded() -> OSStatus {
  let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
  guard property(current, kTISPropertyBundleID) == bundleID else { return noErr }
  // Select an already enabled Apple layout. Do not add/remove other sources.
  let available = sources()
  for id in ["com.apple.keylayout.ABC", "com.apple.keylayout.US"] {
    if let abc = available.first(where: {
      property($0, kTISPropertyInputSourceID) == id && flag($0, kTISPropertyInputSourceIsEnabled)
        && flag($0, kTISPropertyInputSourceIsSelectCapable)
    }) { return TISSelectInputSource(abc) }
  }
  return OSStatus(-1)
}

do {
  guard arguments.count >= 2 else { fail("Missing operation") }
  switch arguments[1] {
  case "--dump":
    try emit(["schema": 1, "captured_at": ISO8601DateFormatter().string(from: Date()),
      "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
      "sources": sources().map(row), "hitoolbox": preferenceSnapshot()])
  case "--check-current":
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    exit(property(source, kTISPropertyBundleID) == bundleID ? 3 : 0)
  case "--select-abc-if-needed":
    let status = selectABCIfNeeded()
    try emit(["action": "select-existing-ABC-if-needed", "status": status])
    if status != noErr { fail("Switch to an enabled Apple ABC/Korean source, then rerun. No input sources were removed.") }
  case "--register":
    guard arguments.count == 3 else { fail("--register APP") }
    let url = URL(fileURLWithPath: arguments[2], isDirectory: true)
    guard let app = Bundle(url: url), app.bundleIdentifier == bundleID,
      let component = app.infoDictionary?["ComponentInputModeDict"] as? [String: Any],
      let modes = component["tsInputModeListKey"] as? [String: Any],
      Set(modes.keys) == Set([korean2SetID]) else { fail("Refusing unrelated or multi-mode bundle") }
    let status = TISRegisterInputSource(url as CFURL)
    try emit(["action": "register", "app": url.path, "status": status])
    if status != noErr { exit(1) }
  case "--enable-korean":
    guard let korean = sources().first(where: {
      property($0, kTISPropertyBundleID) == bundleID && property($0, kTISPropertyInputSourceID) == korean2SetID
        && flag($0, kTISPropertyInputSourceIsSelectCapable)
    }) else { fail("Canonical Korean source absent after registration") }
    let status = TISEnableInputSource(korean)
    try emit(["action": "enable-korean", "status": status])
    if status != noErr { exit(1) }
  case "--cleanup":
    guard arguments.count == 3 else { fail("--cleanup POLICY.json") }
    let policy = try Policy(path: arguments[2])
    guard selectABCIfNeeded() == noErr else { fail("Could not select existing ABC safely") }
    var results: [[String: Any]] = []
    var failed = false
    for source in sources() where policy.matches(source) {
      var result = row(source)
      let enabled = flag(source, kTISPropertyInputSourceIsEnabled)
      let status = enabled ? TISDisableInputSource(source) : noErr
      result["disable_status"] = status
      results.append(result)
      if status != noErr { failed = true }
    }
    // TIS owns enabled sources. Only remove exact legacy references left in
    // history/selection arrays; preserve every other item, order and domain key.
    var preferencesChanged: [[String: String]] = []
    if !failed {
      for (name, host) in [("any_host", kCFPreferencesAnyHost), ("current_host", kCFPreferencesCurrentHost)] {
        for key in preferenceKeys where key != "AppleInputSourceUpdateTime" {
          guard let value = CFPreferencesCopyValue(key as CFString, preferenceDomain, kCFPreferencesCurrentUser, host) else { continue }
          if let array = value as? [Any] {
            let kept = array.filter { !policy.matchesPreference($0) }
            if kept.count != array.count {
              CFPreferencesSetValue(key as CFString, kept as CFArray, preferenceDomain, kCFPreferencesCurrentUser, host)
              preferencesChanged.append(["host": name, "key": key])
            }
          } else if policy.matchesPreference(value) {
            CFPreferencesSetValue(key as CFString, nil, preferenceDomain, kCFPreferencesCurrentUser, host)
            preferencesChanged.append(["host": name, "key": key])
          }
        }
        if !CFPreferencesSynchronize(preferenceDomain, kCFPreferencesCurrentUser, host) { failed = true }
      }
    }
    let remaining = sources().filter { policy.matches($0) && flag($0, kTISPropertyInputSourceIsEnabled) }
    try emit(["action": "targeted-cleanup", "sources": results, "preferences_changed": preferencesChanged,
      "remaining_enabled": remaining.map(row),
      "add_list_absence": "must verify separately; disable is not unregister"])
    if failed || !remaining.isEmpty { exit(1) }
  default:
    fail("Unknown operation: " + arguments[1])
  }
} catch { fail(error.localizedDescription) }
