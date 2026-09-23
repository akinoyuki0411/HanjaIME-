//
//  InputReceiver.swift
//  OSX
//
//  Created by Jeong YunWon on 21/10/2018.
//  Copyright © 2018 youknowone.org. All rights reserved.
//

import Foundation
import InputMethodKit

let debugInputReceiver = false

public class InputReceiver: InputTextDelegate {
  var inputClient: IMKTextInput & IMKUnicodeTextInput
  var composer = GureumComposer()
  weak var controller: InputController!
  var inputting: Bool = false
  var hasSelectionRange: Bool = false
  // A mode notification belongs to this input context. TIS can still report
  // the previous global (ABC) source while a browser swaps its field proxy.
  private var explicitInputMode: String?
  private var inferredInputMode: String?

  // Activation can arrive without a mode tag after ABC or a host context swap.
  // Rebind the underlying keyboard after IMK's own activation, even if the
  // composer already says Korean. Do not reset an unfinished valid syllable.
  func activateKoreanContext(_ sender: IMKTextInput & IMKUnicodeTextInput) {
    bindClient(sender)
    explicitInputMode = GureumInputSource.han2.rawValue
    synchronizeMode(activating: true)
    composer.hanjaComposer.hangul.prepareKoreanKeyboard()
    sender.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
  }

  func synchronizeMode(activating: Bool = false) {
    if activating { inferredInputMode = nil }
    if inferredInputMode == nil {
      inferredInputMode = GureumComposer.selectedModeProvider() ?? composer.inputMode
    }
    composer.synchronizeSelectedMode(explicitInputMode ?? inferredInputMode)
  }

  init(
    server: IMKServer, delegate: Any!, client: IMKTextInput & IMKUnicodeTextInput,
    controller: InputController
  ) {
    dlog(
      debugInputReceiver,
      "**** NEW INPUT CONTROLLER INIT **** WITH SERVER: %@ / DELEGATE: %@ / CLIENT: %@", server,
      (delegate as? NSObject) ?? "(nil)", (client as? NSObject) ?? "(nil)")
    inputClient = client
    self.controller = controller
  }

  // MARK: - IMKServerInputTextData

  func input2(
    text string: String?, keyCode: KeyCode, modifiers flags: NSEvent.ModifierFlags,
    client sender: IMKTextInput & IMKUnicodeTextInput
  ) -> InputResult {
    composer.synchronizeSelectedMode(nil)
    // 특정 애플리케이션에서 커맨드/옵션/컨트롤 키 입력을 선점하지 못하는 문제를 회피한다
    if flags.contains(.command) || flags.contains(.control) {
      dlog(
        debugInputReceiver, "-- InputReceiver -inputText: Command/Control key input / returned NO"
      )
      return InputResult(processed: false, action: .commit)
    }

    if string == nil, keyCode.isKeyMappable, !flags.contains(.option),
      !(composer.delegate is HanjaIMEComposer && HanjaIMEComposer.keyText(key: keyCode, modifiers: flags) != nil),
      ![.space, .return, .delete, .tab].contains(keyCode) {
      return InputResult(processed: false, action: .commit)
    }

    let result = composer.input(text: string, key: keyCode, modifiers: flags, client: sender)

    return result
  }

  // MARK: InputTextDelegate 프로토콜 구현

  func bindClient(_ sender: IMKTextInput & IMKUnicodeTextInput) {
    guard ObjectIdentifier(inputClient as AnyObject) != ObjectIdentifier(sender as AnyObject) else { return }
    let wasInputting = inputting
    inputting = false
    commitCompositionEvent(inputClient)
    inputting = wasInputting
    composer.clear()
    InputMethodServer.shared.hanjaPanel.hide()
    inputClient = sender
  }

  // IMKServerInput 프로토콜에 대한 공용 핸들러
  func input(
    text string: String?,
    key keyCode: KeyCode,
    modifiers flags: NSEvent.ModifierFlags,
    client sender: IMKTextInput & IMKUnicodeTextInput
  ) -> InputResult {
    composer.synchronizeSelectedMode(nil)
    bindClient(sender)
    synchronizeMode()
    let selected = sender.selectedRange()
    let marked = sender.markedRange()
    if selected.location != marked.location {
      //            dlog(debugLogging, "MISMATCHING: \(selected) \(marked)")
      //            cancelComposition()
      //            sender.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: selected.location, length: 0))
      //
      //            // commitComposition(sender)
      //            marked = selected
    }

    // 입력기용 특수 커맨드 처리
    if let command = composer.filterCommand(keyCode: keyCode, modifiers: flags, client: sender) {
      let result = input(event: command, client: sender)
      if result.processed {
        return result
      }
    }

    dlog(
      debugLogging, "LOGGING::KEY::(%@)(%ld)(%lu)",
      string?.replacingOccurrences(of: "\n", with: "\\n") ?? "(nil)", keyCode.rawValue,
      flags.rawValue)

    let hadComposedString = !_internalComposedString.isEmpty
    let result = input2(text: string, keyCode: keyCode, modifiers: flags, client: sender)

    inputting = true
    defer {
      InputMethodServer.shared.showOrHideCandidates(controller: controller)
      inputting = false
    }

    if result.action != .none {
      if composer.delegate is HanjaIMEComposer { cancelCompositionEvent() }
      else { cancelComposition() }
    }

    let commited = commitCompositionEvent(sender)  // 조합 된 문자 반영
    if result.action == .commit {
      return result
    }
    let hasComposedString = !_internalComposedString.isEmpty
    let selectionRange = controller.selectionRange()
    hasSelectionRange = selectionRange.location != NSNotFound && selectionRange.length > 0
    if commited || controller.selectionRange().length > 0 || hadComposedString || hasComposedString
    {
      updateComposition()  // 조합 중인 문자 반영
    }

    dlog(debugInputReceiver, "*** End of Input handling ***")
    return result
  }

  func input(event: InputEvent, client sender: IMKTextInput & IMKUnicodeTextInput) -> InputResult {
    switch event {
    case .changeLayout(let layout, let processed):
      let wasHanjaIME = composer.delegate is HanjaIMEComposer
      let innerLayout =
        layout == .toggleByCapsLock || layout == .toggleByRightKey ? .toggle : layout
      let result = composer.changeLayout(innerLayout, client: sender)
      if case .layout(let mode) = result.action { explicitInputMode = mode }
      // 합성 후보가 있다면 보여준다
      InputMethodServer.shared.showOrHideCandidates(controller: controller)

      inputting = true

      if result.action != .none {
        if wasHanjaIME { cancelCompositionEvent() }
        else { cancelComposition() }
        if result.action != .cancel {
          commitCompositionEvent(sender)
          if case .layout(let mode) = result.action, layout != .toggleByCapsLock {
            (sender as IMKTextInput).selectMode(mode)
          }
        } else {
          updateComposition()  // 조합 중인 문자 반영
        }
      }

      if composer.delegate is HanjaIMEComposer { updateComposition() }
      inputting = false

      return processed ? .processed : .notProcessed
    }
  }
}

extension InputReceiver {  // IMKServerInput
  // Committing a Composition
  // 조합을 중단하고 현재까지 조합된 글자를 커밋한다.
  func commitComposition(_ sender: IMKTextInput & IMKUnicodeTextInput) {
    dlog(debugLogging, "LOGGING::EVENT::COMMIT-INTERNAL")
    commitCompositionEvent(sender)
  }

  func updateComposition() {
    dlog(debugLogging, "LOGGING::EVENT::UPDATE-INTERNAL")
    controller.updateComposition()
  }

  func cancelComposition() {
    dlog(debugLogging, "LOGGING::EVENT::CANCEL-INTERNAL")
    controller.cancelComposition()
  }

  // Committing a Composition
  // 조합을 중단하고 현재까지 조합된 글자를 커밋한다.
  @discardableResult
  func commitCompositionEvent(_ sender: IMKTextInput & IMKUnicodeTextInput) -> Bool {
    composer.synchronizeSelectedMode(nil)
    dlog(debugLogging, "LOGGING::EVENT::COMMIT")
    if !inputting {
      // 입력기 외부에서 들어오는 커밋 요청에 대해서는 편집 중인 글자도 커밋한다.
      dlog(
        debugInputController, "-- CANCEL composition because of external commit request from %@",
        sender as! NSObject)
      dlog(debugLogging, "LOGGING::EVENT::CANCEL-INTERNAL")
      cancelCompositionEvent()
    }
    // 왠지는 모르겠지만 프로그램마다 동작이 달라서 조합을 반드시 마쳐주어야 한다
    // 터미널과 같이 조합중에 리턴키 먹는 프로그램은 조합 중인 문자가 없고 보통은 있다
    let commitString = composer.dequeueCommitString()

    // 커밋할 문자가 없으면 중단
    if commitString.isEmpty {
      return false
    }

    dlog(
      debugInputReceiver, "** InputController -commitComposition: with sender: %@ / strings: %@",
      sender as! NSObject, commitString)
    // Replace the entire marked range, never just its selected final syllable.
    var range = sender.markedRange()
    dlog(debugLogging, "LOGGING::COMMIT::%lu:%lu:%@", range.location, range.length, commitString)
    // NSLog("range1 \(range)")글
    if range.length == 0 {
      range = NSRange(location: NSNotFound, length: 0)
    }
    // NSLog("commit \(commitString) to \(range)")
    sender.insertText(commitString, replacementRange: range)

    InputMethodServer.shared.showOrHideCandidates(controller: controller)

    return true
  }

  func updateCompositionEvent() {
    dlog(debugLogging, "LOGGING::EVENT::UPDATE")
    dlog(debugInputController, "** InputController -updateComposition")
  }

  /// Selection is relative to marked text and uses UTF-16, including emoji.
  @discardableResult
  func updateHanjaIMEComposition() -> Bool {
    guard let automatic = composer.delegate as? HanjaIMEComposer else { return false }
    let text = automatic.composedString
    let marked = inputClient.markedRange()
    if text.isEmpty && (marked.location == NSNotFound || marked.length == 0) { return true }
    let attributed = NSAttributedString(string: text, attributes: [
      .underlineStyle: automatic.session.selectionEngaged
        ? NSUnderlineStyle.thick.rawValue : NSUnderlineStyle.single.rawValue,
    ])
    inputClient.setMarkedText(attributed,
      selectionRange: NSRange(location: text.utf16.count, length: 0), replacementRange: marked)
    return true
  }

  func cancelCompositionEvent() {
    dlog(debugLogging, "LOGGING::EVENT::CANCEL")
    composer.cancelComposition()
  }

  var _internalComposedString: String {
    return composer.composedString
  }

  // Getting Input Strings and Candidates
  // 현재 입력 중인 글자를 반환한다. -updateComposition: 이 사용
  func composedString(_: IMKTextInput & IMKUnicodeTextInput) -> String {
    let string = _internalComposedString
    dlog(debugLogging, "LOGGING::CHECK::COMPOSEDSTRING::(%@)", string)
    dlog(debugInputController, "** InputController -composedString: with return: '%@'", string)
    return string
  }

  func originalString(_: IMKTextInput & IMKUnicodeTextInput) -> NSAttributedString {
    dlog(debugInputController, "** InputController -originalString:")
    let s = NSAttributedString(string: composer.originalString)
    dlog(debugLogging, "LOGGING::CHECK::ORIGINALSTRING::%@", s.string)
    return s
  }

  func candidates(_: IMKTextInput & IMKUnicodeTextInput) -> [Any]! {
    dlog(debugLogging, "LOGGING::CHECK::CANDIDATES")
    return composer.candidates
  }

  func candidateSelected(_ candidateString: NSAttributedString) {
    dlog(debugLogging, "LOGGING::CHECK::CANDIDATESELECTED::%@", candidateString)
    inputting = true
    composer.candidateSelected(candidateString)
    commitCompositionEvent(inputClient)
    inputting = false
  }

  func candidateSelectionChanged(_ candidateString: NSAttributedString) {
    // HanjaIME owns keyboard preview; native update callbacks must not select row zero.
    // Mouse clicks still commit through candidateSelected.
    if composer.delegate is HanjaIMEComposer { return }
    guard !InputMethodServer.shared.updatingCandidates else { return }
    dlog(debugLogging, "LOGGING::CHECK::CANDIDATESELECTIONCHANGED::%@", candidateString)
    composer.candidateSelectionChanged(candidateString)
    updateComposition()
  }
}

extension InputReceiver {  // IMKStateSetting
  //! @brief  마우스 이벤트를 잡을 수 있게 한다.
  func recognizedEvents(_: IMKTextInput & IMKUnicodeTextInput) -> NSEvent.EventTypeMask {
    dlog(debugLogging, "LOGGING::CHECK::RECOGNIZEDEVENTS")
    // NSFlagsChangeMask는 -handleEvent: 에서만 동작
    return NSEvent.EventTypeMask(
      arrayLiteral: .keyDown, .flagsChanged, .leftMouseUp, .rightMouseUp, .leftMouseDown,
      .rightMouseDown, .leftMouseDragged, .rightMouseDragged, .appKitDefined, .applicationDefined,
      .systemDefined)
  }

  //! @brief 자판 전환을 감지한다.
  func setValue(_ value: Any, forTag tag: Int, client sender: IMKTextInput & IMKUnicodeTextInput) {
    InputMethodServer.shared.io?.capsLockDate = nil
    dlog(debugLogging, "LOGGING::EVENT::CHANGE-%lu-%@", tag, value as? String ?? "(nonstring)")
    dlog(
      debugInputController,
      "** InputController -setValue:forTag:client: with value: %@ / tag: %lx / client: %@",
      value as? String ?? "(nonstring)", tag, String(describing: controller.client as AnyObject))
    switch tag {
    case kTextServiceInputModePropertyTag:
      guard let value = value as? String else {
        NSLog("Failed to change keyboard layout")
        assertionFailure()
        break
      }
      // Legacy notifications cannot commit a partial syllable or select Latin.
      // Repair a stale delegate even when TIS still reports the previous source.
      composer.synchronizeSelectedMode(value)
      guard value == GureumInputSource.han2.rawValue else { return }
      explicitInputMode = value
      // Only the canonical mode can alter the host keyboard context. A stale
      // Roman notification must not reconfigure a browser's active text service.
      sender.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
    default:
      dlog(true, "**** UNKNOWN TAG %ld !!! ****", tag)
    }
  }
}
