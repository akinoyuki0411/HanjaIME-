import Cocoa
import Foundation
import GureumCore
import Hangul

class GureumAppDelegate: NSObject, NSApplicationDelegate, GureumApplicationDelegate {
  @IBOutlet var menu: NSMenu!

  func applicationDidFinishLaunching(_: Notification) {
    if !CommandLine.arguments.contains("--settings") { _ = InputMethodServer.shared }
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
    addItem(L("한지미 정보", "About HanjaIME", "HanjaIMEについて"), "showStandardAboutPanel:", to: menu)
    addItem(L("환경설정…", "Settings…", "設定…"), "showPreferencesWindow:", to: menu)
    addItem(L("새 버전 확인…", "Check for Updates…", "アップデートを確認…"), "checkRecentVersion:", to: menu)
    addItem(L("변경 내역 보기…", "What's New…", "変更履歴…"), "showHanjaIMEChangelog:", to: menu)
    menu.addItem(.separator())

    let web = NSMenu(title: L("웹과 문의", "Web & Contact", "Webと連絡"))
    addItem(L("웹사이트…", "Website…", "ウェブサイト…"), "openWebsite:", to: web)
    addItem(L("도움말…", "Help…", "ヘルプ…"), "openWebsiteHelp:", to: web)
    addItem(L("버그 알리기…", "Report a Bug…", "不具合を報告…"), "openWebsiteIssues:", to: web)
    addItem(L("소스코드…", "Source Code…", "ソースコード…"), "openWebsiteSource:", to: web)
    addItem(L("이메일…", "Email…", "メール…"), "openHanjaIMEEmail:", to: web)
    addItem(L("후원하기…", "Support…", "支援する…"), "openWebsiteDonation:", to: web)
    addSubmenu(web, title: L("웹사이트와 문의", "Website & Contact", "ウェブサイトと連絡"), to: menu)

    let tools = NSMenu(title: L("한지미 도구", "HanjaIME Tools", "HanjaIMEツール"))
    addItem(L("자동 후보 켜기/끄기", "Toggle Automatic Candidates", "自動候補を切り替え"), "toggleAutomaticHanja:", to: tools)
    addItem(L("오픈소스 고지…", "Open-source Notices…", "オープンソース表記…"), "showOpenSourceNotices:", to: tools)
    addSubmenu(tools, title: L("도구", "Tools", "ツール"), to: menu)
    // Standard system input switching works without asking for input monitoring at launch.
  }

  private func addItem(_ title: String, _ action: String, to menu: NSMenu) {
    menu.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: ""))
  }

  private func addSubmenu(_ submenu: NSMenu, title: String, to menu: NSMenu) {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.submenu = submenu
    menu.addItem(item)
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    preferencesWindow.showWindow(nil)
    sender.activate(ignoringOtherApps: true)
    return true
  }
  func applicationWillTerminate(_: Notification) { HanjaIMEControls.flushLearning() }
}
