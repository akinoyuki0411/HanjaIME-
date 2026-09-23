//
//  GureumComposer.swift
//  Gureum
//
//  Created by Hyewon on 2018. 9. 7..
//  Copyright © 2018 youknowone.org. All rights reserved.
//

import Carbon
import Cocoa
import Foundation

// MARK: - GureumInputSource 열거형

/// 구름 입력기에서 사용하는 인풋 소스를 정의한 열거형.
///
/// 각 케이스의 원시 값은 그에 대응하는 input method의 번들 식별자를 나타낸다.
enum GureumInputSource: String {
  /// 로마자 시스템 자판.
  case system = "org.hanjaime.inputmethod.HanjaIME.system"
  /// 로마자 쿼티 자판.
  case qwerty = "org.hanjaime.inputmethod.HanjaIME.qwerty"
  /// 로마자 드보락 자판.
  case dvorak = "org.hanjaime.inputmethod.HanjaIME.dvorak"
  /// 로마자 콜맥 자판.
  case colemak = "org.hanjaime.inputmethod.HanjaIME.colemak"
  /// 한글 두벌식 자판.
  case han2 = "org.hanjaime.inputmethod.HanjaIME.han2"
  /// 한글 두벌식 옛글 자판.
  case han2Classic = "org.hanjaime.inputmethod.HanjaIME.han2classic"
  /// 한글 세벌식 최종 자판.
  case han3Final = "org.hanjaime.inputmethod.HanjaIME.han3final"
  /// 한글 세벌식 390 자판.
  case han390 = "org.hanjaime.inputmethod.HanjaIME.han390"
  /// 한글 세벌식 순아래 자판.
  case han3NoShift = "org.hanjaime.inputmethod.HanjaIME.han3noshift"
  /// 한글 세벌식 옛글 자판.
  case han3Classic = "org.hanjaime.inputmethod.HanjaIME.han3classic"
  /// 한글 세벌식 두벌식 배치 자판.
  case han3Layout2 = "org.hanjaime.inputmethod.HanjaIME.han3layout2"
  /// 한글 안마태 자판.
  case hanAhnmatae = "org.hanjaime.inputmethod.HanjaIME.hanahnmatae"
  /// 한글 로마자 자판.
  case hanRoman = "org.hanjaime.inputmethod.HanjaIME.hanroman"
  /// 한글 세벌식 최종 순아래 자판.
  case han3FinalNoShift = "org.hanjaime.inputmethod.HanjaIME.han3finalnoshift"
  /// 한글 세벌식 2011 자판.
  case han32011 = "org.hanjaime.inputmethod.HanjaIME.han3-2011"
  /// 한글 세벌식 2012 자판.
  case han32012 = "org.hanjaime.inputmethod.HanjaIME.han3-2012"
}

// MARK: - GureumComposer 클래스

/// 구름 입력기의 합성기 오브젝트.
///
/// 입력 모드에 따라 `libhangul`을 이용하여 문자를 합성해 준다.
final class GureumComposer: Composer {
  // MARK: 합성기 테이블

  /// 한글 합성기.
  let hangulComposer = HangulComposer(type: .han2)
  /// 한글 합성기에 의존하여 문자를 검색하고 입력하는 합성기.
  ///
  /// 한자 및 이모지  합성기
  let searchComposer = SearchComposer()
  private let usageStore: HanjaIMEUsageStore
  lazy var hanjaComposer = HanjaIMEComposer(hangul: hangulComposer, usage: usageStore)

  /// 로마자 시스템 합성기.
  let systemRomanComposer = RomanComposer(type: .system)
  /// 로마자 쿼티 합성기.
  let qwertyComposer = RomanComposer(type: .qwerty)
  /// 로마자 드보락 합성기.
  let dvorakComposer = RomanComposer(type: .dvorak)
  /// 로마자 콜맥 합성기.
  let colemakComposer = RomanComposer(type: .colemak)

  // Injectable for tests; production reads the actually selected macOS input source.
  static var selectedModeProvider: () -> String? = {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
    for key in [kTISPropertyInputModeID, kTISPropertyInputSourceID] {
      if let raw = TISGetInputSourceProperty(source, key),
        let mode = GureumInputSource(rawValue: Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String) {
        return mode.rawValue
      }
    }
    return nil
  }

  func synchronizeSelectedMode(_ selected: String?) {
    // This controller belongs only to Korean. TIS can report ABC or a retired
    // mode while a host replaces its input context; neither changes its owner.
    // Repair a stale delegate without committing a raw Roman buffer or flushing
    // the still-valid Hanja session. The ordinary path does not reset libhangul.
    if !(delegate is HanjaIMEComposer) {
      searchComposer.cancelSearch()
      delegate = hanjaComposer
    }
    if _inputMode != GureumInputSource.han2.rawValue {
      hangulComposer.setKeyboard(identifier: GureumInputSource.han2.keyboardIdentifier)
      _inputMode = GureumInputSource.han2.rawValue
      Configuration.shared.lastHangulInputMode = _inputMode
    }
  }

  private var _inputMode: String = ""
  private var _commitStrings: [String] = []

  /// 실제 사용되는 로마자 합성기.
  var romanComposer: RomanComposer

  init(usage: HanjaIMEUsageStore = .shared) {
    usageStore = usage
    romanComposer = systemRomanComposer
    // This fork is deliberately Korean-only at the TIS level. English input is
    // handled by macOS ABC, never by a second HanjaIME mode.
    inputMode = GureumInputSource.han2.rawValue
  }

  // MARK: Composer 프로토콜 구현

  var delegate: Composer!

  var commitString: String {
    return _commitStrings.joined() + delegate.commitString
  }

  func clear() {
    hangulComposer.clear()
    romanComposer.clear()
    searchComposer.clear()
    hanjaComposer.clear()
    _commitStrings.removeAll()
    synchronizeSelectedMode(nil)
  }

  func dequeueCommitString() -> String {
    let r = commitString
    delegate.dequeueCommitString()
    _commitStrings.removeAll()
    return r
  }

  func input(
    text string: String?, key keyCode: KeyCode, modifiers flags: NSEvent.ModifierFlags,
    client sender: IMKTextInput & IMKUnicodeTextInput
  ) -> InputResult {
    synchronizeSelectedMode(nil)
    // All physical keys, including Option Yetgeul, use the same Korean path.
    // Command/Control handling remains in InputReceiver/HanjaIMEComposer.
    return hanjaComposer.input(text: string, key: keyCode, modifiers: flags, client: sender)
  }
}

extension GureumComposer {
  var inputMode: String {
    get {
      return _inputMode
    }
    set {
      // Validate before ANY commit/reset. Retired notifications are not a
      // language switch and must not split an in-progress Korean syllable.
      guard newValue == GureumInputSource.han2.rawValue else {
        synchronizeSelectedMode(nil)
        return
      }
      synchronizeSelectedMode(newValue)
    }
  }

  func cancelAndCommit() {
    delegate.cancelComposition()
    enqueueCommitString(delegate.dequeueCommitString())
  }

  func changeLayout(_ layout: ChangeLayout, client sender: Any) -> InputResult {
    synchronizeSelectedMode(nil)
    if layout == .toggle {
      // Language switching now belongs to macOS (HanjaIME <-> ABC).
      // Do not create an internal Roman state.
      return .notProcessed
    }

    switch layout {
    case .hangul:
      return InputResult(processed: true, action: .layout(inputMode))
    case .roman:
      // English is the system ABC input source, not a HanjaIME sub-mode.
      return .notProcessed
    case .search:
      hanjaComposer.session.requestConversion()
      return .processed
    default:
      return .notProcessed
    }
  }

  func filterCommand(
    keyCode: KeyCode,
    modifiers flags: NSEvent.ModifierFlags,
    client _: Any
  ) -> InputEvent? {
    synchronizeSelectedMode(nil)
    let configuration = Configuration.shared
    let inputModifier =
      flags
      .intersection(.deviceIndependentFlagsMask)
      .intersection(NSEvent.ModifierFlags(rawValue: ~NSEvent.ModifierFlags.capsLock.rawValue))

    // Option letters are Yetgeul keys even if old settings assign them to Roman mode.
    if delegate is HanjaIMEComposer, flags.contains(.option),
      flags.intersection([.command, .control]).isEmpty, keyCode.isKeyMappable { return nil }
    if delegate is HanjaIMEComposer, keyCode == .escape,
      flags.intersection([.command, .control, .option]).isEmpty { return nil }

    // Handle SpecialKeyCode first
    let inputKey = (keyCode, inputModifier)
    // HanjaIME no longer owns Korean/English switching. Let macOS switch
    // between this Korean source and ABC instead of entering RomanComposer.
    if let shortcutKey = configuration.inputModeSearchKey, shortcutKey == inputKey {
      return .changeLayout(.search, true)
    }

    // The legacy vi shortcut used to enter HanjaIME's private Roman mode.
    // That mode no longer exists; Escape remains available to the Korean composer.

    return nil
  }

  private func enqueueCommitString(_ string: String) {
    _commitStrings.append(string)
  }

  func romanComposer(by romanComposerType: RomanComposer.ComposerType) -> RomanComposer {
    switch romanComposerType {
    case .system:
      return systemRomanComposer
    case .qwerty:
      return qwertyComposer
    case .dvorak:
      return dvorakComposer
    case .colemak:
      return colemakComposer
    }
  }
}

// MARK: - GureumInputSource 열거형 확장

extension GureumInputSource {
  /// 키보드 식별자.
  var keyboardIdentifier: String {
    switch self {
    case .system:
      return "system"
    case .qwerty:
      return "qwerty"
    case .dvorak:
      return "dvorak"
    case .colemak:
      return "colemak"
    case .han2:
      return "2-full"
    case .han2Classic:
      return "2y-full"
    case .han3Final:
      return "3f"
    case .han390:
      return "39"
    case .han3NoShift:
      return "3s"
    case .han3Classic:
      return "3y"
    case .han3Layout2:
      return "32"
    case .hanAhnmatae:
      return "ahn"
    case .hanRoman:
      return "ro"
    case .han3FinalNoShift:
      return "3gs"
    case .han32011:
      return "3-2011"
    case .han32012:
      return "3-2012"
    }
  }
}
