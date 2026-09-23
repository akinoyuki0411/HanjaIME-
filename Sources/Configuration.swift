//
//  Configuration.swift
//  Gureum
//
//  Created by Jeong YunWon on 2018. 4. 19..
//  Copyright © 2018 youknowone.org. All rights reserved.
//

import AppKit
import Foundation

public enum HanjaIMEInterface {
  public static let languageKey = "HanjaIME.InterfaceLanguage"
  public static var language: String {
    get { Configuration.shared.string(forKey: languageKey) ?? "ko" }
    set {
      Configuration.shared.set(["ko", "en", "ja"].contains(newValue) ? newValue : "ko", forKey: languageKey)
      NotificationCenter.default.post(name: Notification.Name("HanjaIME.LanguageChanged"), object: nil)
    }
  }
  public static func text(_ ko: String, _ en: String, _ ja: String) -> String {
    switch language { case "en": return en; case "ja": return ja; default: return ko }
  }
  public static func versionComponents(_ value: String) -> [Int]? {
    let raw = value.hasPrefix("v") ? String(value.dropFirst()) : value
    let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }
    var result: [Int] = []
    for part in parts {
      guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
        let number = Int(part), number >= 0 else { return nil }
      result.append(number)
    }
    return result
  }
  public static func isNewer(_ candidate: String, than current: String) -> Bool {
    guard let a = versionComponents(candidate), let b = versionComponents(current) else { return false }
    return b.lexicographicallyPrecedes(a)
  }
  public static func shouldShowChangelog(current: String, seen: String?) -> Bool {
    guard versionComponents(current) != nil else { return false }
    guard let seen else { return true }
    return isNewer(current, than: seen)
  }
}

/// 환경 설정 이름을 정의한 열거형.
enum ConfigurationName {
  /// 마지막 한글 입력 모드.
  public static let lastHangulInputMode = "LastHangulInputMode"
  /// 마지막 로마자 입력 모드.
  public static let lastRomanInputMode = "LastRomanInputMode"

  /// 입력기 바꾸기 단축키.
  public static let inputModeExchangeKey = "InputModeExchangeKey"
  /// 한자 및 이모지 검색 단축키.
  public static let inputModeSearchKey = "InputModeHanjaKey"
  /// 로마자로 바꾸기 단축키.
  public static let inputModeEnglishKey = "InputModeEnglishKey"
  /// 한글로 바꾸기 단축키.
  public static let inputModeKoreanKey = "InputModeKoreanKey"
  /// 옵션 키 동작.
  public static let optionKeyBehavior = "OptionKeyBehavior"
  /// 기본 키보드 레이아웃.
  public static let overridingKeyboardName = "OverridingKeyboardName"

  /// Esc 키로 로마자 자판으로 전환 (vi 모드).
  public static let romanModeByEscapeKey = "ExchangeToRomanModeByEscapeKey"
  /// 한글 입력기일 때 역따옴표(`)로 원화 기호(₩) 입력.
  public static let hangulWonCurrencySymbolForBackQuote = "HangulWonCurrencySymbolForBackQuote"
  /// 완성되지 않은 낱자 자동 교정 (모아치기).
  public static let hangulAutoReorder = "HangulAutoReorder"
  /// 두벌식 초성 조합 중에도 종성 결합 허용 (MS윈도 호환).
  public static let hangulNonChoseongCombination = "HangulNonChoseongCombination"
  /// 모든 글자를 조합 중인 글자로 취급 (JDK 호환).
  public static let hangulDeferredSymbolCommit = "HangulDeferredSymbolCommit"
  /// 세벌식 정석 강요.
  public static let hangulForceStrictCombinationRule = "HangulForceStrictCombinationRule"
  /// 우측 키로 언어 전환
  public static let rightToggleKey = "RightToggleKey"

  /// 업데이트 알림 받기
  public static let updateNotification = "UpdateNotification"
  /// 실험버전 업데이트 알림 받기
  public static let updateNotificationExperimental = "UpdateNotificationExperimental"
}

// MARK: - Configuration 클래스

public enum UpdateMode {
  case stable
  case experimental
}

/// 입력기의 환경 설정을 담당하는 오브젝트.
public class Configuration: UserDefaults {
  public static let sharedSuiteName = HanjaIMEStorage.preferencesDomain
  public static var shared = Configuration()

  var enableCapslockToToggleInputMode: Bool = false

  public typealias Shortcut = (KeyCode, NSEvent.ModifierFlags)

  class func convertShortcutToConfiguration(_ shortcut: Shortcut?) -> [String: Any] {
    guard let shortcut = shortcut else {
      return [:]
    }
    return ["modifier": shortcut.1.rawValue, "keyCode": shortcut.0.rawValue]
  }

  class func convertConfigurationToShortcut(_ configuration: [String: Any]) -> Shortcut? {
    guard let modifierNumber = configuration["modifier"] as? NSNumber,
      let modifier = UInt(exactly: modifierNumber),
      let keyCodeNumber = configuration["keyCode"] as? NSNumber,
      let keyCodeRawValue = Int(exactly: keyCodeNumber),
      let keyCode = KeyCode(rawValue: keyCodeRawValue)
    else {
      return nil
    }
    return (keyCode, NSEvent.ModifierFlags(rawValue: modifier))
  }

  override init?(suiteName: String?) {
    // UserDefaults rejects an explicit suite equal to the current app's bundle ID.
    super.init(suiteName: suiteName == Bundle.main.bundleIdentifier ? nil : suiteName)

    if suiteName == Configuration.sharedSuiteName {
      let keys: Set<String> = [
        ConfigurationName.lastHangulInputMode, ConfigurationName.lastRomanInputMode,
        ConfigurationName.inputModeExchangeKey, ConfigurationName.inputModeSearchKey,
        ConfigurationName.inputModeEnglishKey, ConfigurationName.inputModeKoreanKey,
        ConfigurationName.optionKeyBehavior, ConfigurationName.overridingKeyboardName,
        ConfigurationName.romanModeByEscapeKey, ConfigurationName.hangulWonCurrencySymbolForBackQuote,
        ConfigurationName.hangulAutoReorder, ConfigurationName.hangulNonChoseongCombination,
        ConfigurationName.hangulDeferredSymbolCommit, ConfigurationName.hangulForceStrictCombinationRule,
        ConfigurationName.rightToggleKey, ConfigurationName.updateNotification,
        ConfigurationName.updateNotificationExperimental, "HanjaIME.AutoCandidates",
      ]
      HanjaIMEStorage.migrateLegacyValues(
        persistentDomain(forName: HanjaIMEStorage.bundleIdentifier) ?? [:],
        to: self, domain: Configuration.sharedSuiteName, keys: keys)
    }

    register(defaults: [
      ConfigurationName.lastHangulInputMode: "org.hanjaime.inputmethod.HanjaIME.han2",
      ConfigurationName.lastRomanInputMode: "org.hanjaime.inputmethod.HanjaIME.qwerty",

      ConfigurationName.inputModeSearchKey: Configuration.convertShortcutToConfiguration(
        (.return, .option)),
      ConfigurationName.optionKeyBehavior: 1,
      ConfigurationName.overridingKeyboardName: "com.apple.keylayout.ABC",

      ConfigurationName.romanModeByEscapeKey: false,
      ConfigurationName.hangulWonCurrencySymbolForBackQuote: true,
      ConfigurationName.hangulAutoReorder: false,
      ConfigurationName.hangulNonChoseongCombination: false,
      ConfigurationName.hangulDeferredSymbolCommit: false,
      ConfigurationName.hangulForceStrictCombinationRule: false,
      ConfigurationName.rightToggleKey: 0,

      ConfigurationName.updateNotification: false,
      ConfigurationName.updateNotificationExperimental: false,
    ])
  }

  convenience init() {
    self.init(suiteName: Configuration.sharedSuiteName)!
  }

  public func persistentDomain() -> [String: Any] {
    return persistentDomain(forName: Configuration.sharedSuiteName) ?? [:]
  }

  // TODO: code generation

  /// 마지막 한글 입력 모드.
  public var lastHangulInputMode: String {
    get {
      string(forKey: ConfigurationName.lastHangulInputMode) ?? "org.hanjaime.inputmethod.HanjaIME.han2"
    }
    set {
      set(newValue, forKey: ConfigurationName.lastHangulInputMode)
    }
  }

  /// 마지막 로마자 입력 모드.
  public var lastRomanInputMode: String {
    get {
      string(forKey: ConfigurationName.lastRomanInputMode) ?? "org.hanjaime.inputmethod.HanjaIME.qwerty"
    }
    set {
      set(newValue, forKey: ConfigurationName.lastRomanInputMode)
    }
  }

  /// 옵션 키 동작.
  public var optionKeyBehavior: Int {
    get {
      integer(forKey: ConfigurationName.optionKeyBehavior)
    }
    set {
      set(newValue, forKey: ConfigurationName.optionKeyBehavior)
    }
  }

  /// 기본 키보드 레이아웃.
  public var overridingKeyboardName: String {
    get {
      string(forKey: ConfigurationName.overridingKeyboardName) ?? "com.apple.keylayout.ABC"
    }
    set {
      set(newValue, forKey: ConfigurationName.overridingKeyboardName)
    }
  }

  /// 입력기 바꾸기 단축키.
  public var inputModeExchangeKey: Shortcut? {
    get {
      shortcut(forKey: ConfigurationName.inputModeExchangeKey)
    }
    set {
      setShortcut(newValue, forKey: ConfigurationName.inputModeExchangeKey)
    }
  }

  /// 한자 및 이모지 검색 단축키.
  public var inputModeSearchKey: Shortcut? {
    get {
      shortcut(forKey: ConfigurationName.inputModeSearchKey)
    }
    set {
      setShortcut(newValue, forKey: ConfigurationName.inputModeSearchKey)
    }
  }

  /// 로마자로 바꾸기 단축키.
  public var inputModeEnglishKey: Shortcut? {
    get {
      shortcut(forKey: ConfigurationName.inputModeEnglishKey)
    }
    set {
      setShortcut(newValue, forKey: ConfigurationName.inputModeEnglishKey)
    }
  }

  /// 한글로 바꾸기 단축키.
  public var inputModeKoreanKey: Shortcut? {
    get {
      shortcut(forKey: ConfigurationName.inputModeKoreanKey)
    }
    set {
      setShortcut(newValue, forKey: ConfigurationName.inputModeKoreanKey)
    }
  }

  /// Esc 키로 로마자 자판으로 전환 (vi 모드).
  public var romanModeByEscapeKey: Bool {
    get {
      bool(forKey: ConfigurationName.romanModeByEscapeKey)
    }
    set {
      set(newValue, forKey: ConfigurationName.romanModeByEscapeKey)
    }
  }

  /// 한글 입력기일 때 역따옴표(`)로 원화 기호(₩) 입력.
  public var hangulWonCurrencySymbolForBackQuote: Bool {
    get {
      bool(forKey: ConfigurationName.hangulWonCurrencySymbolForBackQuote)
    }
    set {
      set(newValue, forKey: ConfigurationName.hangulWonCurrencySymbolForBackQuote)
    }
  }

  /// 완성되지 않은 낱자 자동 교정 (모아치기).
  public var hangulAutoReorder: Bool {
    get {
      bool(forKey: ConfigurationName.hangulAutoReorder)
    }
    set {
      set(newValue, forKey: ConfigurationName.hangulAutoReorder)
    }
  }

  /// 두벌식 초성 조합 중에도 종성 결합 허용 (MS윈도 호환).
  public var hangulNonChoseongCombination: Bool {
    get {
      bool(forKey: ConfigurationName.hangulNonChoseongCombination)
    }
    set {
      set(newValue, forKey: ConfigurationName.hangulNonChoseongCombination)
    }
  }

  /// 모든 글자를 조합중인 글자로 취급 (JDK 호환).
  public var hangulDeferredSymbolCommit: Bool {
    get {
      bool(forKey: ConfigurationName.hangulDeferredSymbolCommit)
    }
    set {
      set(newValue, forKey: ConfigurationName.hangulDeferredSymbolCommit)
    }
  }

  /// 세벌식 정석 강요.
  public var hangulForceStrictCombinationRule: Bool {
    get {
      bool(forKey: ConfigurationName.hangulForceStrictCombinationRule)
    }
    set {
      set(newValue, forKey: ConfigurationName.hangulForceStrictCombinationRule)
    }
  }

  /// 우측 키로 언어 전환
  public var rightToggleKey: Int {
    get {
      integer(forKey: ConfigurationName.rightToggleKey)
    }
    set {
      set(newValue, forKey: ConfigurationName.rightToggleKey)
    }
  }

  /// 업데이트 알림 받기
  public var updateNotification: Bool {
    get {
      bool(forKey: ConfigurationName.updateNotification)
    }
    set {
      set(newValue, forKey: ConfigurationName.updateNotification)
    }
  }

  /// 실험버전 업데이트 알림 받기
  public var updateNotificationExperimental: Bool {
    get {
      if Bundle.main.isExperimental {
        return true
      } else {
        return bool(forKey: ConfigurationName.updateNotificationExperimental)
      }
    }
    set {
      assert(!Bundle.main.isExperimental)
      set(newValue, forKey: ConfigurationName.updateNotificationExperimental)
    }
  }

  public var updateMode: UpdateMode? {
    switch (updateNotification, updateNotificationExperimental) {
    case (false, _):
      return nil
    case (true, false):
      return .stable
    case (true, true):
      return .experimental
    }
  }
}

extension Configuration {
  fileprivate func shortcut(forKey key: String) -> Shortcut? {
    guard let value = dictionary(forKey: key) else { return nil }
    return Configuration.convertConfigurationToShortcut(value)
  }

  fileprivate func setShortcut(_ newValue: Shortcut?, forKey key: String) {
    set(Configuration.convertShortcutToConfiguration(newValue), forKey: key)
  }
}
