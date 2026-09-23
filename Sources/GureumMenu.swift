//
//  GureumMenu.swift
//  OSX
//
//  Created by KMLee on 2018. 8. 24..
//  Copyright © 2018 youknowone.org. All rights reserved.
//

import Cocoa
import Foundation
import GureumCore

let preferencesWindow = HanjaIMEPreferencesWindowController(configuration: .shared)

// 왜 App delegate가 아니라 여기 붙는건지 모르겠다
extension InputController {
  @IBAction func showStandardAboutPanel(_ sender: Any) {
    NSApp.activate(ignoringOtherApps: true)
    preferencesWindow.select(.about)
    preferencesWindow.showWindow(nil)
    answers.logMenu(name: "about")
  }

  @IBAction func showPreferencesWindow(_: Any) {
    commitComposition(client())
    NSApp.activate(ignoringOtherApps: true)
    preferencesWindow.showWindow(nil)
  }

  @IBAction func checkRecentVersion(_: Any) {
    NSApp.activate(ignoringOtherApps: true)
    preferencesWindow.select(.about)
    preferencesWindow.showWindow(nil)
    HanjaIMEUpdateService.shared.check(manual: true)
  }
  @IBAction func checkExperimentalVersion(_ sender: Any) { checkRecentVersion(sender) }
  @IBAction func openWebsite(_: Any) { HanjaIMELinks.open() }
  @IBAction func openWebsiteHelp(_: Any) { HanjaIMELinks.open("#readme") }
  @IBAction func openWebsiteSource(_: Any) { HanjaIMELinks.open() }
  @IBAction func openWebsiteIssues(_: Any) { HanjaIMELinks.open("/issues/new") }
  @IBAction func openWebsiteDonation(_: Any) { HanjaIMELinks.support() }
  @IBAction func openHanjaIMEEmail(_: Any) { HanjaIMELinks.mail() }
  @IBAction func showHanjaIMEChangelog(_: Any) { preferencesWindow.showChangelog() }

}


extension InputController {
  @IBAction func openHanjaIMEWordManager(_: Any) {
    commitComposition(client())
    NSApp.activate(ignoringOtherApps: true)
    preferencesWindow.select(.words)
    preferencesWindow.showWindow(nil)
  }

  @IBAction func showOpenSourceNotices(_: Any) { HanjaIMEOpenSourceNotices.show() }

  @IBAction func editPersonalHanjaWord(_: Any) {
    commitComposition(client())
    let alert = NSAlert()
    alert.messageText = "개인 한자 단어"
    alert.informativeText = "읽기와 같은 글자 수의 한자를 입력하세요. 예: 가나다 → 加那多\n등록한 단어는 이 Mac의 후보에 우선 표시됩니다."
    let form = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 88))
    let reading = NSTextField(frame: NSRect(x: 76, y: 52, width: 258, height: 24))
    let value = NSTextField(frame: NSRect(x: 76, y: 12, width: 258, height: 24))
    for (title, field) in [("한글 읽기", reading), ("한자 표기", value)] {
      let label = NSTextField(labelWithString: title)
      label.frame = NSRect(x: 0, y: field.frame.minY + 2, width: 72, height: 20)
      form.addSubview(label)
      form.addSubview(field)
    }
    reading.placeholderString = "가나다"
    value.placeholderString = "加那多"
    reading.nextKeyView = value
    alert.accessoryView = form
    alert.addButton(withTitle: "등록")
    alert.addButton(withTitle: "취소")
    alert.addButton(withTitle: "이 단어 삭제")
    alert.window.initialFirstResponder = reading
    NSApp.activate(ignoringOtherApps: true)
    let result = alert.runModal()
    guard result != .alertSecondButtonReturn else { return }
    let key = reading.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let text = value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let deleting = result == .alertThirdButtonReturn
    let success = deleting ? HanjaIMEControls.removeWord(reading: key, value: text)
      : HanjaIMEControls.registerWord(reading: key, value: text)
    if !success {
      let message = NSAlert()
      message.messageText = deleting ? "등록된 단어를 찾지 못했어요" : "단어를 등록하지 못했어요"
      message.informativeText = deleting ? "등록할 때 쓴 읽기와 한자를 확인해 주세요."
        : "읽기는 한글, 표기는 같은 글자 수의 한자여야 합니다. 최대 64글자, 2,000개 읽기, 읽기마다 64개 표기를 저장할 수 있습니다."
      message.addButton(withTitle: "확인")
      message.runModal()
    }
  }

  @IBAction func toggleAutomaticHanja(_: Any) {
    commitComposition(client())
    HanjaIMEControls.automaticCandidates.toggle()
  }

  @IBAction func resetHanjaLearning(_: Any) {
    let alert = NSAlert()
    alert.messageText = "한자 선택 학습을 초기화할까요?"
    alert.informativeText = "이 Mac에 저장한 선택 횟수와 최근 선택 순서를 지웁니다. 개인 단어는 유지합니다."
    alert.addButton(withTitle: "초기화")
    alert.addButton(withTitle: "취소")
    if alert.runModal() == .alertFirstButtonReturn { HanjaIMEControls.resetLearning() }
  }
}
