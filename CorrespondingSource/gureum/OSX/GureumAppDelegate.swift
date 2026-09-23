import Cocoa
import Foundation
import GureumCore
import Hangul

class GureumAppDelegate: NSObject, NSApplicationDelegate, GureumApplicationDelegate {
  @IBOutlet var menu: NSMenu!

  func applicationDidFinishLaunching(_: Notification) {
    _ = InputMethodServer.shared
    // Use macOS input-source switching instead of Gureum's global Caps Lock monitor.
    HanjaIMEControls.prepare()
    rebuildMenu()
    NotificationCenter.default.addObserver(self, selector: #selector(rebuildMenu), name: Notification.Name("HanjaIME.LanguageChanged"), object: nil)
    if ProcessInfo.processInfo.environment["HANJAIME_TEST_SESSION"] != "1",
      ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
      HanjaIMEUpdateService.shared.start()
      DispatchQueue.main.async { preferencesWindow.showChangelogAfterUpdate() }
    }
    if CommandLine.arguments.contains("--settings") {
      preferencesWindow.showWindow(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  @objc private func rebuildMenu() {
    if menu == nil { menu = NSMenu(title: "HanjaIME") }
    menu.removeAllItems()
    for (title, action) in [
      (L("한지미 정보", "About HanjaIME", "HanjaIMEについて"), "showStandardAboutPanel:"),
      (L("환경설정…", "Settings…", "設定…"), "showPreferencesWindow:"),
      (L("새 버전 확인…", "Check for Updates…", "アップデートを確認…"), "checkRecentVersion:"),
      (L("변경 내역 보기…", "What's New…", "変更履歴…"), "showHanjaIMEChangelog:"),
      (L("웹사이트…", "Website…", "ウェブサイト…"), "openWebsite:"),
      (L("도움말…", "Help…", "ヘルプ…"), "openWebsiteHelp:"),
      (L("버그 알리기…", "Report a Bug…", "不具合を報告…"), "openWebsiteIssues:"),
      (L("소스코드…", "Source Code…", "ソースコード…"), "openWebsiteSource:"),
      (L("이메일…", "Email…", "メール…"), "openHanjaIMEEmail:"),
      (L("후원하기…", "Support…", "支援する…"), "openWebsiteDonation:"),
      (L("자동 후보 켜기/끄기", "Toggle Automatic Candidates", "自動候補を切り替え"), "toggleAutomaticHanja:"),
      (L("오픈소스 고지…", "Open-source Notices…", "オープンソース表記…"), "showOpenSourceNotices:"),
    ] {
      menu.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: ""))
    }
    // Standard system input switching works without asking for input monitoring at launch.
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    preferencesWindow.showWindow(nil)
    sender.activate(ignoringOtherApps: true)
    return true
  }
  func applicationWillTerminate(_: Notification) { HanjaIMEControls.flushLearning() }
}
