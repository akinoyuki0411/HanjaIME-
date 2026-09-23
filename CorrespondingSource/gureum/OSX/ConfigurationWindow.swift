// HanjaIME settings. See bundled open-source notices.
import Cocoa
import SwiftUI
import Combine
import CryptoKit
import GureumCore

func L(_ ko: String, _ en: String, _ ja: String) -> String { HanjaIMEInterface.text(ko, en, ja) }
enum HanjaIMELinks {
  static let repository = "https://github.com/akinoyuki0411/HanjaIME-"
  static func open(_ suffix: String = "") { NSWorkspace.shared.open(URL(string: repository + suffix)!) }
  static func mail() { NSWorkspace.shared.open(URL(string: "mailto:akinoyuki0122@gmail.com")!) }
  static func support() {
    let alert = NSAlert()
    alert.messageText = L("한지미 후원", "Support HanjaIME", "HanjaIMEを支援")
    alert.informativeText = L("후원 페이지를 준비 중입니다. 현재 결제는 받지 않습니다. 문의: akinoyuki0122@gmail.com", "A support page is being prepared. Payments are not accepted yet. Contact: akinoyuki0122@gmail.com", "支援ページを準備中です。現在、支払いは受け付けていません。連絡先: akinoyuki0122@gmail.com")
    alert.addButton(withTitle: "OK"); alert.runModal()
  }
}
enum HanjaIMESettingsTab: String, CaseIterable, Identifiable {
  case general, input, words, dictionary, about, licenses
  var id: String { rawValue }
  var title: String {
    switch self {
    case .general: return L("일반", "General", "一般")
    case .input: return L("입력", "Input", "入力")
    case .words: return L("개인 단어", "My Words", "ユーザー辞書")
    case .dictionary: return L("사전", "Dictionary", "辞書")
    case .about: return L("정보", "About", "情報")
    case .licenses: return L("라이선스", "Licenses", "ライセンス")
    }
  }
  var symbol: String {
    switch self {
    case .general: return "gearshape.fill"
    case .input: return "keyboard"
    case .words: return "character.book.closed.fill"
    case .dictionary: return "books.vertical.fill"
    case .about: return "ellipsis.circle.fill"
    case .licenses: return "doc.text.fill"
    }
  }
  var height: CGFloat {
    switch self { case .words: return 650; case .dictionary, .licenses: return 580; case .input: return 550; case .about: return 530; default: return 460 }
  }
}
private final class HanjaIMESettingsModel: ObservableObject {
  @Published var tab: HanjaIMESettingsTab = .general
  @Published var language = HanjaIMEInterface.language
  let configuration: Configuration
  var showChangelog: () -> Void = {}
  init(_ configuration: Configuration) { self.configuration = configuration }
  func binding(_ key: String, fallback: Bool = false) -> Binding<Bool> {
    Binding(get: { self.configuration.object(forKey: key) as? Bool ?? fallback }, set: {
      self.objectWillChange.send(); self.configuration.set($0, forKey: key)
    })
  }
}
final class HanjaIMEPreferencesWindowController: NSWindowController {
  private let model: HanjaIMESettingsModel
  private var changelog: NSWindowController?
  private var subscriptions = Set<AnyCancellable>()
  init(configuration: Configuration) {
    model = HanjaIMESettingsModel(configuration)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 490), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.title = L("한지미 설정", "HanjaIME Settings", "HanjaIME 設定")
    window.minSize = NSSize(width: 660, height: 430)
    window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false; window.center()
    super.init(window: window)
    window.contentView = NSHostingView(rootView: HanjaIMESettingsView(model: model))
    model.showChangelog = { [weak self] in self?.showChangelog() }
    model.$tab.dropFirst().sink { [weak self] tab in
      // Published emits before storing its new value. Resizing synchronously
      // can lay out the previous page and consume its pending SwiftUI update.
      DispatchQueue.main.async { self?.resize(for: tab) }
    }.store(in: &subscriptions)
    model.$language.dropFirst().sink { [weak self] language in
      HanjaIMEInterface.language = language
      self?.window?.title = L("한지미 설정", "HanjaIME Settings", "HanjaIME 設定")
      self?.changelog?.close(); self?.changelog = nil
    }.store(in: &subscriptions)
  }
  required init?(coder: NSCoder) { fatalError("Use init") }
  func select(_ tab: HanjaIMESettingsTab) { model.tab = tab }
  private func resize(for tab: HanjaIMESettingsTab) {
    guard let window else { return }
    let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
    let width: CGFloat = tab == .words ? 720 : 660
    let height = min(tab.height + 28, visible.height)
    let old = window.frame
    let x = max(visible.minX, min(old.midX - width / 2, visible.maxX - width))
    let y = max(visible.minY, min(old.maxY - height, visible.maxY - height))
    window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: window.isVisible)
  }
  override func showWindow(_ sender: Any?) {
    model.objectWillChange.send(); resize(for: model.tab)
    super.showWindow(sender); window?.makeKeyAndOrderFront(sender)
  }
  func showChangelogAfterUpdate() {
    let version = HanjaIMEUpdateService.currentVersion
    let key = "HanjaIME.LastShownChangelogVersion"
    guard HanjaIMEInterface.shouldShowChangelog(current: version, seen: model.configuration.string(forKey: key)) else { return }
    showChangelog(); model.configuration.set(version, forKey: key)
  }
  func showChangelog() {
    if changelog == nil {
      let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 760), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
      window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
      window.title = L("한지미 · 새로운 기능", "HanjaIME · What's New", "HanjaIME · 新機能")
      window.minSize = NSSize(width: 620, height: 480); window.isReleasedWhenClosed = false
      window.contentView = NSHostingView(rootView: HanjaIMEChangelogView(close: { [weak window] in window?.close() }))
      window.center(); changelog = NSWindowController(window: window)
    }
    NSApp.activate(ignoringOtherApps: true)
    changelog?.showWindow(nil); changelog?.window?.makeKeyAndOrderFront(nil)
  }
}
private struct Glass: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) { content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14)) }
    else { content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14)) }
  }
}
private struct Card<Content: View>: View {
  let title: String; let content: Content
  init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
  var body: some View {
    VStack(alignment: .leading, spacing: 13) { Text(title).font(.headline); content }
      .frame(maxWidth: .infinity, alignment: .leading).padding(16).modifier(Glass())
  }
}
private struct WordSettings: NSViewControllerRepresentable {
  func makeNSViewController(context: Context) -> HanjaIMEWordManagementViewController { HanjaIMEWordManagementViewController() }
  func updateNSViewController(_ controller: HanjaIMEWordManagementViewController, context: Context) {}
}
private struct HanjaIMESettingsView: View {
  @ObservedObject var model: HanjaIMESettingsModel
  @ObservedObject var updater = HanjaIMEUpdateService.shared
  @State private var confirmReset = false
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 2) {
        ForEach(HanjaIMESettingsTab.allCases) { tab in
          Button { model.tab = tab } label: {
            VStack(spacing: 5) {
              Image(systemName: tab.symbol).font(.system(size: 21, weight: .medium)).frame(height: 25)
              Text(tab.title).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }.foregroundColor(model.tab == tab ? .accentColor : .secondary)
              .frame(maxWidth: .infinity).frame(height: 60)
              .background(model.tab == tab ? Color.accentColor.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 12))
              .contentShape(Rectangle())
          }.buttonStyle(.plain).focusable(false).accessibilityIdentifier("settings." + tab.rawValue)
        }
      }.padding(.horizontal, 22).padding(.vertical, 10)
      Divider().opacity(0.4)
      ScrollView { VStack(alignment: .leading, spacing: 16) { page }.padding(22).frame(maxWidth: .infinity) }
    }.background(.regularMaterial)
      .alert(L("후보 선택 학습을 초기화할까요?", "Reset candidate learning?", "候補の学習をリセットしますか？"), isPresented: $confirmReset) {
        Button(L("취소", "Cancel", "キャンセル"), role: .cancel) {}
        Button(L("초기화", "Reset", "リセット"), role: .destructive) { HanjaIMEControls.resetLearning() }
      } message: { Text(L("개인 단어와 공식 구름 설정은 유지됩니다.", "Your words and Gureum settings are kept.", "ユーザー辞書とGureumの設定は保持されます。")) }
  }
  @ViewBuilder private var page: some View {
    switch model.tab {
    case .general:
      Card(L("언어", "Language", "言語")) {
        Picker(L("설정 화면 언어", "Interface language", "表示言語"), selection: $model.language) {
          Text("한국어").tag("ko"); Text("English").tag("en"); Text("日本語").tag("ja")
        }.pickerStyle(.segmented)
        Text(L("화면 언어만 바뀝니다. 입력은 한국어 두벌식으로 유지됩니다.", "Changes the interface language. Input remains Korean 2-set.", "表示言語のみ変更します。入力方式は韓国語2ボル式のままです。")).foregroundColor(.secondary)
      }
      Card(L("후보와 학습", "Candidates & learning", "候補と学習")) {
        Toggle(L("입력 중 한자 후보 자동 표시", "Show candidates while typing", "入力中に変換候補を表示"), isOn: model.binding("HanjaIME.AutoCandidates", fallback: true))
        Text(L("날씨 → 天氣 · 天気 · 🌤️", "날씨 (weather) → 天氣 · 天気 · 🌤️", "날씨（天気）→ 天氣 · 天気 · 🌤️"))
        Button(L("후보 선택 학습 초기화…", "Reset candidate learning…", "候補の学習をリセット…")) { confirmReset = true }
      }
    case .input:
      Card(L("한글 조합", "Hangul composition", "ハングルの組み立て")) {
        Toggle(L("낱자 자동 교정 (모아치기)", "Reorder Hangul jamo", "字母の順序を自動修正"), isOn: model.binding("HangulAutoReorder"))
        Toggle(L("초성 조합 중 종성 결합 허용", "Allow final-consonant combinations", "終声の結合を許可"), isOn: model.binding("HangulNonChoseongCombination"))
        Toggle(L("JDK 호환 조합", "JDK-compatible composition", "JDK互換の文字入力"), isOn: model.binding("HangulDeferredSymbolCommit"))
      }
      Card(L("키보드 안내", "Keyboard guide", "キー操作")) {
        key("Space", L("후보 선택 · 다음 후보", "Select / next candidate", "候補選択・次の候補"))
        key("Enter", L("현재 내용 확정", "Commit text", "入力を確定"))
        key("Shift + Space", L("한글 유지하고 공백", "Keep Hangul and add a space", "ハングルのまま空白を入力"))
        key("Esc", L("변환 취소", "Cancel conversion", "変換をキャンセル"))
        Text(L("한/영 전환은 macOS 입력 소스 단축키를 사용하세요. Option은 옛한글 입력에 사용합니다.", "Use the macOS input-source shortcut to switch languages. Option is used for old Hangul.", "言語切替にはmacOSの入力ソース切替キーを使います。Optionは古ハングル入力に使用します。")).foregroundColor(.secondary)
      }
    case .words:
      Text(L("개인 단어 · 이 Mac에만 저장됩니다", "My Words · stored only on this Mac", "ユーザー辞書 · このMacにのみ保存")).font(.headline)
      WordSettings().id(model.language).frame(minHeight: 460).modifier(Glass())
    case .dictionary:
      Card(L("뜻풀이 연결", "Definitions", "意味を調べる")) {
        Toggle(L("Apple 사전에 없으면 네이버 사전 연결", "Use Naver when Apple Dictionary has no result", "Apple辞書にない場合はNAVER辞書を使用"), isOn: model.binding("HanjaIME.NaverFallback", fallback: true))
        Text(L("후보의 책 버튼을 눌렀을 때 선택한 검색어만 네이버로 전송합니다. 입력 문장과 개인 단어 목록은 전송하지 않습니다.", "Only the selected term is sent to Naver when you open a definition. Your sentence and personal word list are not sent.", "意味を開くと、選択した語だけをNAVERへ送信します。入力中の文章やユーザー辞書は送信しません。"))
        Text(L("일본어 신자체는 일본어사전, 한자는 한자사전에서 찾습니다. 온라인 사전은 인터넷 연결이 필요합니다.", "Japanese forms use the Japanese dictionary; Hanja uses the Hanja dictionary. Online lookup requires an internet connection.", "日本の字体は日本語辞書、漢字は漢字辞書で検索します。オンライン検索にはインターネット接続が必要です。")).foregroundColor(.secondary)
      }
      Card(L("Apple 사전", "Apple Dictionary", "Apple辞書")) {
        Text(L("사전 앱에서 필요한 사전을 활성화하면 오프라인 뜻풀이가 늘어납니다.", "Enable dictionaries in the Dictionary app to expand offline definitions.", "辞書アプリで辞書を有効にすると、オフラインで調べられる語が増えます。"))
        Button(L("사전 앱 열기", "Open Dictionary", "辞書を開く")) { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Dictionary.app")) }
      }
    case .about:
      HStack(spacing: 16) {
        emblem.frame(width: 72, height: 72)
        VStack(alignment: .leading, spacing: 6) {
          Text(L("한지미", "HanjaIME", "HanjaIME")).font(.system(size: 26, weight: .bold))
          Text(HanjaIMEUpdateService.currentVersion).foregroundColor(.secondary)
          Button(L("변경 내역 보기", "See changelog", "変更履歴を見る")) { model.showChangelog() }.buttonStyle(.link)
        }
        Spacer()
        Button(L("새 버전 확인…", "Check for Updates…", "アップデートを確認…")) { updater.check(manual: true) }.disabled(updater.busy)
      }.padding(.bottom, 6)
      VStack(alignment: .leading, spacing: 8) {
        Toggle(L("새 버전 자동 확인", "Automatically check for updates", "アップデートを自動確認"), isOn: model.binding("HanjaIME.AutoUpdateCheck"))
        Toggle(L("업데이트 ZIP 자동 다운로드", "Automatically download update ZIPs", "更新ZIPを自動ダウンロード"), isOn: model.binding("HanjaIME.AutoUpdateDownload"))
        Text(L("다운로드 후 설치는 직접 진행합니다. 입력 중 자동 재시작하지 않습니다.", "Install downloaded updates manually. Typing is never interrupted by an automatic restart.", "ダウンロード後は手動でインストールします。入力中に自動再起動しません。")).font(.caption).foregroundColor(.secondary)
        if !updater.status.isEmpty { Text(updater.status).font(.caption).foregroundColor(.secondary).textSelection(.enabled) }
        if updater.availableVersion != nil { Button(L("업데이트 다운로드", "Download Update", "更新をダウンロード")) { updater.download() }.disabled(updater.busy) }
        if let file = updater.downloadedFile { Button(L("다운로드 파일 보기", "Show Download", "ダウンロードを表示")) { NSWorkspace.shared.activateFileViewerSelecting([file]) } }
      }
      Divider()
      VStack(spacing: 9) {
        Text("HanjaIME").font(.system(size: 36, weight: .bold, design: .rounded))
          .foregroundStyle(LinearGradient(colors: [.indigo, .purple, .blue], startPoint: .leading, endPoint: .trailing))
        Text(L("생각은 한글로, 표현은 더 넓게", "Think in Hangul. Express more.", "ハングルで考え、表現をもっと豊かに。")).font(.headline)
        Text(L("구름 · libhangul 기반의 한국어 한자 입력기", "Korean Hanja input, built on Gureum and libhangul", "Gureum・libhangulをベースにした韓国語漢字入力")).font(.caption).foregroundColor(.secondary)
      }.frame(maxWidth: .infinity).padding(.vertical, 4)
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
        link("globe", L("웹사이트", "Website", "ウェブサイト")) { HanjaIMELinks.open() }
        link("questionmark.circle", L("도움말", "Help", "ヘルプ")) { HanjaIMELinks.open("#readme") }
        link("envelope", L("이메일", "Email", "メール")) { HanjaIMELinks.mail() }
        link("ladybug", L("버그 알리기", "Report a Bug", "不具合を報告")) { HanjaIMELinks.open("/issues/new") }
        link("chevron.left.forwardslash.chevron.right", L("소스코드", "Source Code", "ソースコード")) { HanjaIMELinks.open() }
        link("heart", L("후원하기", "Support", "支援する")) { HanjaIMELinks.support() }
      }
    case .licenses:
      Card(L("오픈소스", "Open Source", "オープンソース")) {
        Text("Gureum — BSD\nlibhangul · libhangul-objc — LGPL 2.1\nMASShortcut · SwiftUp · Fuse — BSD / MIT\nUnicode CLDR — Unicode License v3\nNoto — SIL Open Font License").lineSpacing(6)
        Button(L("전체 라이선스 고지 열기…", "Open License Notices…", "ライセンス全文を開く…")) { HanjaIMEOpenSourceNotices.show() }
      }
      Card(L("사전 서비스", "Dictionary services", "辞書サービス")) {
        Text(L("Apple 사전은 설치된 사전을 사용합니다. 네이버 사전은 외부 웹페이지로 연결하며 내용을 재배포하지 않습니다. 한지미는 NAVER의 공식 제품이 아닙니다.", "Apple Dictionary uses installed dictionaries. Naver opens an external website; its content is not redistributed. HanjaIME is not an official NAVER product.", "Apple辞書はインストール済み辞書を使います。NAVERは外部サイトへ接続し、内容を再配布しません。HanjaIMEはNAVERの公式製品ではありません。"))
      }
    }
  }
  private func key(_ key: String, _ detail: String) -> some View { HStack { Text(key).font(.system(.body, design: .monospaced)).frame(width: 130, alignment: .leading); Text(detail) } }
  private func link(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Label(title, systemImage: symbol).font(.system(size: 11)).frame(maxWidth: .infinity).padding(.vertical, 7).contentShape(Rectangle()) }.buttonStyle(.bordered).clipShape(Capsule())
  }
}
private var emblem: some View {
  Text("漢").font(.system(size: 44, weight: .medium, design: .serif)).foregroundColor(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LinearGradient(colors: [.indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)).clipShape(RoundedRectangle(cornerRadius: 20))
}
private struct HanjaIMEChangelogView: View {
  let close: () -> Void
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        VStack(spacing: 12) {
          emblem.frame(width: 98, height: 98).shadow(color: .purple.opacity(0.3), radius: 25, y: 10)
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(L("한지미", "HanjaIME", "HanjaIME")).font(.system(size: 32, weight: .bold))
            Text("v" + HanjaIMEUpdateService.currentVersion).font(.title3).foregroundColor(.secondary)
          }
          Text(L("더 가까운 설정, 더 넓은 세상.", "Closer controls. A wider world.", "使いやすい設定、広がる世界。")).font(.title3)
        }.frame(maxWidth: .infinity).padding(.vertical, 12)
        feature("globe", "한국어 · English · 日本語", L("세 가지 언어", "Three languages", "3つの言語"), L("설정과 메뉴를 한국어·영어·일본어로 바꾸세요.", "Choose Korean, English or Japanese for settings and menus.", "設定とメニューを韓国語・英語・日本語に切り替え。"))
        feature("arrow.down.circle.fill", "GitHub Releases", L("업데이트를 가까이", "Updates within reach", "更新をもっと身近に"), L("새 버전 확인과 ZIP 다운로드를 설정에서. 설치는 원하는 때에 직접 진행합니다.", "Check and download releases in settings. Install when you are ready.", "設定で新しいバージョンを確認・ダウンロード。好きなときに手動でインストール。"))
        VStack(alignment: .leading, spacing: 13) {
          Text(L("새로운 기능", "Also new", "その他の新機能")).font(.headline)
          bullet("envelope", L("이메일 · 도움말 · 버그 알리기 · 소스코드", "Email, help, bug reports and source code", "メール・ヘルプ・不具合報告・ソースコード"))
          bullet("sparkles", L("업데이트 후 변경 내역을 한 번 자동 표시", "What's new appears once after an update", "更新後に変更履歴を一度だけ自動表示"))
          Text(L("수정 및 개선", "Fixes & improvements", "修正と改善")).font(.headline).padding(.top, 8)
          bullet("keyboard", L("입력 소스 전환 직후 한국어 상태 복구 보강", "Reinforced Korean context recovery after switching sources", "入力ソース切替後の韓国語状態の復旧を強化"))
          bullet("cursorarrow", L("탭 전체를 누를 수 있도록 클릭 영역 확대", "The entire tab tile is clickable", "タブ全体をクリック可能に"))
          bullet("arrow.up.left.and.arrow.down.right", L("작은 기본 창 · 긴 설정은 자동으로 확장", "Compact windows that grow for longer settings", "コンパクトなウィンドウ、長い設定は自動拡大"))
        }
        Button(L("좋아요!", "Great!", "OK!"), action: close).buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
      }.padding(.horizontal, 40).padding(.top, 48).padding(.bottom, 32)
    }.background(LinearGradient(colors: [.purple.opacity(0.23), .indigo.opacity(0.12), Color(nsColor: .windowBackgroundColor)], startPoint: .topLeading, endPoint: .bottomTrailing))
  }
  private func feature(_ symbol: String, _ sample: String, _ title: String, _ detail: String) -> some View {
    HStack(spacing: 24) {
      VStack(spacing: 16) { Image(systemName: symbol).font(.system(size: 40)); Text(sample).font(.caption).multilineTextAlignment(.center) }
        .foregroundColor(.white).frame(width: 190, height: 124)
        .background(LinearGradient(colors: [.indigo.opacity(0.8), .purple.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)).clipShape(RoundedRectangle(cornerRadius: 18))
      VStack(alignment: .leading, spacing: 8) { Text(title).font(.title3.bold()); Text(detail).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true) }
    }
  }
  private func bullet(_ symbol: String, _ text: String) -> some View { Label(text, systemImage: symbol).fixedSize(horizontal: false, vertical: true) }
}
enum HanjaIMEOpenSourceNotices {
  static func show() {
    if let folder = Bundle.main.resourceURL?.appendingPathComponent("HanjaIME-Licenses"), FileManager.default.fileExists(atPath: folder.path) { NSWorkspace.shared.open(folder) }
  }
}

// Downloads are checked against GitHub's digest and never executed automatically.
final class HanjaIMEUpdateService: ObservableObject {
  static let shared = HanjaIMEUpdateService()
  static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.9.4" }
  struct Asset: Decodable { let name: String; let browser_download_url: String; let size: Int; let digest: String? }
  struct Release: Decodable { let tag_name: String; let draft: Bool; let prerelease: Bool; let assets: [Asset] }
  @Published var busy = false
  @Published var status = ""
  @Published var availableVersion: String?
  @Published var downloadedFile: URL?
  private var asset: Asset?
  private var timer: Timer?
  private let session: URLSession
  init(session: URLSession = .shared) { self.session = session }
  func start() {
    checkIfEnabled()
    timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.checkIfEnabled() }
  }
  private func checkIfEnabled() {
    let config = Configuration.shared
    guard config.bool(forKey: "HanjaIME.AutoUpdateCheck"), Date().timeIntervalSince1970 - config.double(forKey: "HanjaIME.LastUpdateCheck") > 86400 else { return }
    check(manual: false)
  }
  func check(manual: Bool) {
    guard !busy else { return }
    busy = true; status = L("새 버전 확인 중…", "Checking for updates…", "更新を確認中…")
    var request = URLRequest(url: URL(string: "https://api.github.com/repos/akinoyuki0411/HanjaIME-/releases/latest")!)
    request.timeoutInterval = 20; request.setValue("HanjaIME", forHTTPHeaderField: "User-Agent")
    session.dataTask(with: request) { data, response, error in
      DispatchQueue.main.async {
        self.busy = false
        guard error == nil, let http = response as? HTTPURLResponse else {
          self.status = L("연결할 수 없습니다. 잠시 후 다시 시도하세요.", "Cannot connect. Please try again later.", "接続できません。しばらくしてから再試行してください。"); return
        }
        if http.statusCode == 404 {
          self.status = L("아직 공개된 릴리스가 없습니다.", "No public release is available yet.", "公開リリースはまだありません。")
          self.asset = nil; self.availableVersion = nil
          Configuration.shared.set(Date().timeIntervalSince1970, forKey: "HanjaIME.LastUpdateCheck")
          return
        }
        guard http.statusCode == 200, let data, data.count < 2_000_000,
          let release = try? JSONDecoder().decode(Release.self, from: data), !release.draft, !release.prerelease,
          HanjaIMEInterface.versionComponents(release.tag_name) != nil else {
          self.status = L("업데이트 정보를 확인하지 못했습니다.", "Could not read release information.", "更新情報を読み取れませんでした。"); return
        }
        Configuration.shared.set(Date().timeIntervalSince1970, forKey: "HanjaIME.LastUpdateCheck")
        self.asset = nil; self.availableVersion = nil
        guard HanjaIMEInterface.isNewer(release.tag_name, than: Self.currentVersion) else {
          self.status = L("최신 버전입니다.", "You're up to date.", "最新バージョンです。"); return
        }
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        self.asset = Self.selectAsset(release)
        self.availableVersion = self.asset == nil ? nil : version
        self.status = L("새 버전: ", "New version: ", "新バージョン: ") + version
        guard self.asset != nil else {
          self.status += L(" · 검증 가능한 ZIP이 없습니다. GitHub Releases를 확인하세요.", " · No verifiable ZIP is attached. See GitHub Releases.", " · 検証可能なZIPがありません。GitHub Releasesをご確認ください。"); return
        }
        if Configuration.shared.bool(forKey: "HanjaIME.AutoUpdateDownload") { self.download() }
      }
    }.resume()
  }
  static func selectAsset(_ release: Release) -> Asset? {
    guard !release.draft, !release.prerelease, HanjaIMEInterface.versionComponents(release.tag_name) != nil else { return nil }
    let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
    return release.assets.first { item in
      item.name.hasPrefix("HanjaIME_v" + version + "_") && item.name.hasSuffix(".zip") && !item.name.contains("/") && !item.name.contains("\\") &&
      item.size > 0 && item.size < 200_000_000 && validDownloadURL(item.browser_download_url) &&
      item.digest?.range(of: "^sha256:[a-fA-F0-9]{64}$", options: .regularExpression) != nil
    }
  }
  static func validDownloadURL(_ raw: String) -> Bool {
    guard let url = URL(string: raw), url.scheme == "https", url.host == "github.com", url.user == nil, url.password == nil, url.port == nil else { return false }
    return url.path.hasPrefix("/akinoyuki0411/HanjaIME-/releases/download/")
  }
  static func verified(_ data: Data, asset: Asset) -> Bool {
    guard data.count == asset.size else { return false }
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return "sha256:" + hash == asset.digest?.lowercased()
  }
  func download() {
    guard !busy, let asset, let url = URL(string: asset.browser_download_url) else { return }
    busy = true; status = L("다운로드 중…", "Downloading…", "ダウンロード中…")
    var request = URLRequest(url: url); request.timeoutInterval = 120
    session.downloadTask(with: request) { temporary, response, error in
      var result: URL?
      if error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let temporary {
        do {
          let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize
          guard size == asset.size else { throw CocoaError(.fileReadCorruptFile) }
          let data = try Data(contentsOf: temporary, options: .mappedIfSafe)
          guard Self.verified(data, asset: asset) else { throw CocoaError(.fileReadCorruptFile) }
          let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("HanjaIME/Updates")
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          let destination = folder.appendingPathComponent(asset.name)
          try data.write(to: destination, options: .atomic); result = destination
        } catch { result = nil }
      }
      let file = result
      DispatchQueue.main.async {
        self.busy = false; self.downloadedFile = file
        self.status = file == nil
          ? L("다운로드 또는 무결성 확인에 실패했습니다. 다시 시도하세요.", "Download or integrity check failed. Please try again.", "ダウンロードまたは整合性確認に失敗しました。再試行してください。")
          : L("다운로드 완료 · ZIP을 풀고 repair_and_install.command를 실행하세요.", "Downloaded · extract the ZIP and run repair_and_install.command.", "完了 · ZIPを展開し repair_and_install.command を実行してください。")
      }
    }.resume()
  }
}
