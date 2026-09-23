import Foundation

enum HanjaIMEStorage {
  static let bundleIdentifier = "org.hanjaime.inputmethod.HanjaIME"
  static let preferencesDomain = bundleIdentifier + ".preferences"
  static let learningDomain = bundleIdentifier + ".learning"
  private static let diagnosticLock = NSLock()

  static func recordKeyboardRecovery(_ kind: String) {
    diagnosticLock.lock()
    defer { diagnosticLock.unlock() }
    guard let defaults = UserDefaults(suiteName: preferencesDomain) else { return }
    let key = "HanjaIME.Diagnostics." + kind
    defaults.set(min(1_000_000, defaults.integer(forKey: key) + 1), forKey: key)
    defaults.set(Date().timeIntervalSince1970, forKey: "HanjaIME.Diagnostics.LastRecovery")
  }

  static let selectionCountsKey = "HanjaIME.SelectionCounts.v2"

  // Copy only HanjaIME's old values, preserving the source and any newer destination values.
  static func migrateLegacyValues(_ legacy: [String: Any], to defaults: UserDefaults,
                                  domain: String, keys: Set<String>) {
    let marker = "HanjaIME.LegacyMigration.v1." + domain
    guard !defaults.bool(forKey: marker) else { return }
    let existing = defaults.persistentDomain(forName: domain) ?? [:]
    for key in keys where existing[key] == nil {
      if let value = legacy[key] { defaults.set(value, forKey: key) }
    }
    defaults.set(true, forKey: marker)
  }

  static func learningDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: learningDomain) ?? .standard
    migrateLegacyValues(defaults.persistentDomain(forName: bundleIdentifier) ?? [:],
                        to: defaults, domain: learningDomain, keys: [selectionCountsKey])
    return defaults
  }
}

