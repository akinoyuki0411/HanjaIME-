import AppKit
import SwiftUI
import Carbon

func JL(_ ko:String,_ en:String,_ ja:String)->String {
    switch JapanesePreferences.shared.language {case "en":return en;case "ja":return ja;default:return ko}
}
enum JapaneseSettingsTab:String,CaseIterable,Identifiable {
    case general,input,dictionary,about,licenses
    var id:String {rawValue}
    var title:String {switch self {case .general:return JL("일반","General","一般");case .input:return JL("입력","Input","入力");case .dictionary:return JL("사전","Dictionary","辞書");case .about:return JL("정보","About","情報");case .licenses:return JL("라이선스","Licenses","ライセンス")}}
    var symbol:String {switch self {case .general:return "gearshape.fill";case .input:return "keyboard";case .dictionary:return "books.vertical.fill";case .about:return "ellipsis.circle.fill";case .licenses:return "doc.text.fill"}}
    var height:CGFloat {switch self {case .general:return 530;case .input:return 590;case .dictionary:return 550;case .about:return 550;case .licenses:return 500}}
}
enum JapaneseDictionaryPriority:String,CaseIterable,Identifiable {
    case appleThenNaver,naverFirst,appleOnly
    var id:String {rawValue}
    var title:String {switch self {case .appleThenNaver:return JL("Apple 먼저, 없으면 네이버","Apple first, then NAVER","Apple優先、なければNAVER");case .naverFirst:return JL("네이버 먼저","NAVER first","NAVER優先");case .appleOnly:return JL("Apple 사전만","Apple only","Appleのみ")}}
}
final class JapanesePreferences:ObservableObject {
    static let shared=JapanesePreferences()
    @Published var automatic=UserDefaults.standard.object(forKey:"automatic") as? Bool ?? true {didSet {UserDefaults.standard.set(automatic,forKey:"automatic")}}
    @Published var language=UserDefaults.standard.string(forKey:"interfaceLanguage") ?? "ko" {didSet {UserDefaults.standard.set(language,forKey:"interfaceLanguage")}}
    @Published var dictionaryPriority=JapaneseDictionaryPriority(rawValue:UserDefaults.standard.string(forKey:"dictionaryPriority") ?? "naverFirst") ?? .naverFirst {didSet {UserDefaults.standard.set(dictionaryPriority.rawValue,forKey:"dictionaryPriority")}}
    @Published var appleTranslation=UserDefaults.standard.bool(forKey:"appleTranslation") {didSet {UserDefaults.standard.set(appleTranslation,forKey:"appleTranslation")}}
    @Published var tab:JapaneseSettingsTab = .general
    @Published var registrationMessage=""
    func addInputSource() {
        let registered=TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
        guard registered==noErr else {registrationMessage=JL("입력기 등록에 실패했습니다: ","Registration failed: ","登録に失敗しました: ")+String(registered);return}
        let filter=[kTISPropertyInputSourceID as String:"org.hanjaime.inputmethod.Japanese"] as CFDictionary
        let sources=TISCreateInputSourceList(filter,true).takeRetainedValue() as! [TISInputSource]
        guard !sources.isEmpty else {registrationMessage=JL("로그아웃 후 다시 로그인해 입력기를 추가해 주세요.","Sign out and back in, then add the input source.","ログアウトして再ログイン後に追加してください。");return}
        var error:OSStatus=noErr
        for source in sources {let result=TISEnableInputSource(source);if result != noErr {error=result}}
        let enabled=sources.allSatisfy {source in
            guard let value=TISGetInputSourceProperty(source,kTISPropertyInputSourceIsEnabled) else{return false}
            return Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue()==kCFBooleanTrue
        }
        if error==noErr && !enabled {
            registrationMessage=JL("등록을 요청했지만 macOS 입력 목록이 아직 갱신되지 않았습니다. 작업을 저장하고 로그아웃·로그인한 뒤 다시 추가해 주세요.","Registration requested; macOS has not refreshed the list yet. Save your work, sign out and back in, then add again.","登録を要求しました。入力一覧が更新されていません。保存後にログアウト・再ログインし、再度追加してください。")
            return
        }
        registrationMessage=error==noErr ? JL("입력 소스에 추가했습니다. 상단 입력 메뉴에서 ‘HanjaIME 日本語’를 선택하세요.","Added. Select HanjaIME 日本語 in the Input menu.","追加しました。入力メニューでHanjaIME 日本語を選んでください。") : JL("추가를 완료하지 못했습니다: ","Could not finish adding: ","追加できませんでした: ")+String(error)
    }
}
private struct JapaneseGlass:ViewModifier {
    func body(content:Content)->some View {
        if #available(macOS 26.0,*) {content.glassEffect(.regular,in:RoundedRectangle(cornerRadius:14))}
        else {content.background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:14))}
    }
}
private struct JapaneseCard<Content:View>:View {
    let title:String;let content:Content
    init(_ title:String,@ViewBuilder content:()->Content) {self.title=title;self.content=content()}
    var body:some View {VStack(alignment:.leading,spacing:13) {Text(title).font(.headline);content}.frame(maxWidth:.infinity,alignment:.leading).padding(16).modifier(JapaneseGlass())}
}
struct JapaneseSettings:View {
    @ObservedObject var preferences=JapanesePreferences.shared
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:2) {
                ForEach(JapaneseSettingsTab.allCases) {tab in
                    Button {preferences.tab=tab} label:{
                        VStack(spacing:5) {Image(systemName:tab.symbol).font(.system(size:21,weight:.medium)).frame(height:25);Text(tab.title).font(.system(size:11,weight:.medium))}
                        .foregroundColor(preferences.tab==tab ? .accentColor : .secondary).frame(maxWidth:.infinity).frame(height:60)
                        .background(preferences.tab==tab ? Color.accentColor.opacity(0.13) : .clear,in:RoundedRectangle(cornerRadius:12)).contentShape(Rectangle())
                    }.buttonStyle(.plain).focusable(false).accessibilityIdentifier("japanese.settings."+tab.rawValue)
                }
            }.padding(.horizontal,22).padding(.vertical,10)
            Divider().opacity(0.4)
            ScrollView {VStack(alignment:.leading,spacing:16) {page}.padding(22).frame(maxWidth:.infinity)}
        }.background(.regularMaterial)
        .onChange(of:preferences.tab) {_ in (NSApp.delegate as? JapaneseAppDelegate)?.resizeSettings()}
        .onChange(of:preferences.language) {_ in (NSApp.delegate as? JapaneseAppDelegate)?.resizeSettings()}
        .onAppear {(NSApp.delegate as? JapaneseAppDelegate)?.resizeSettings()}
    }
    @ViewBuilder private var page:some View {
        switch preferences.tab {
        case .general:
            JapaneseCard(JL("언어","Language","言語")) {
                Picker(JL("설정 화면 언어","Interface language","表示言語"),selection:$preferences.language) {Text("한국어").tag("ko");Text("English").tag("en");Text("日本語").tag("ja")}.pickerStyle(.segmented)
                Text(JL("화면 언어만 바뀝니다. 입력은 일본어로 유지됩니다.","Changes the interface language. Input remains Japanese.","表示言語のみ変更します。入力は日本語のままです。")).foregroundColor(.secondary)
            }
            JapaneseCard(JL("입력기 사용","Enable input method","入力方法を使う")) {
                Button(JL("키보드에 일본어 입력기 추가","Add Japanese input source","日本語入力方法を追加")) {preferences.addInputSource()}
                Text(preferences.registrationMessage.isEmpty ? JL("추가 후 상단 입력 메뉴 또는 언어 전환 키로 HanjaIME 日本語를 선택하세요.","After adding, select HanjaIME 日本語 with the Input menu or input-source switch key.","追加後、入力メニューまたは切り替えキーでHanjaIME 日本語を選んでください。") : preferences.registrationMessage).foregroundColor(.secondary)
                Button(JL("키보드 설정 열기","Open Keyboard Settings","キーボード設定を開く")) {NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)}
            }
            JapaneseCard(JL("후보","Candidates","候補")) {
                Toggle(JL("입력 중 한자 후보 자동 표시","Show candidates while typing","入力中に変換候補を表示"),isOn:$preferences.automatic)
                Text(JL("구자체를 먼저, 신자체를 뒤에 표시합니다.","Old forms appear first, followed by modern forms.","旧字体を先、新字体を後に表示します。")).foregroundColor(.secondary)
            }
        case .input:
            JapaneseCard(JL("입력 방식","Input method","入力方式")) {
                Text(JL("로마자를 히라가나로 바꿔 입력합니다. 작은 っ·ゃ·ゅ·ょ와 기본 활용형을 지원합니다.","Type romaji to enter hiragana, including small kana and basic inflections.","ローマ字からひらがなへ入力します。促音・拗音と基本的な送り仮名に対応します。"))
                Text("gakkou → がっこう → 學校 / 学校\ntenki → てんき → 天氣 / 天気\nrekishi → れきし → 歷史 / 歴史").textSelection(.enabled)
            }
            JapaneseCard(JL("키보드 조작","Keyboard controls","キー操作")) {
                key("Space",JL("변환 · 다음 후보","Convert · next candidate","変換・次の候補"));key("↑ / ↓",JL("후보 이동","Move between candidates","候補を移動"));key("Enter / 1–9",JL("후보 확정","Commit candidate","候補を確定"));key("Esc",JL("변환 취소 · 다시 누르면 조합 지우기","Cancel conversion · press again to clear","変換解除・もう一度で読みを消去"));key("F7",JL("카타카나로 확정","Commit as katakana","カタカナで確定"))
                Text(JL("ん은 n' 또는 nn으로, 작은 っ은 자음을 두 번 입력합니다.","Use n' or nn for ん; repeat a consonant for small っ.","んはn'またはnn、促音は子音を重ねて入力します。")).font(.callout).foregroundColor(.secondary)
            }
        case .dictionary:
            JapaneseCard(JL("뜻풀이 조회","Definition lookup","意味の検索")) {
                Picker(JL("사전 우선순위","Dictionary priority","辞書の優先順位"),selection:$preferences.dictionaryPriority) {ForEach(JapaneseDictionaryPriority.allCases) {Text($0.title).tag($0)}}
                Toggle(JL("Apple 번역으로 설정 언어에 맞춰 뜻풀이 번역","Translate definitions with Apple Translation","Apple翻訳で表示言語に翻訳"),isOn:$preferences.appleTranslation)
                Text(JL("번역을 끄면 원문을 바로 표시합니다. Apple 번역은 macOS 15 이상에서 지원하며 처음에는 언어 다운로드가 필요할 수 있습니다.","When off, the original appears immediately. Apple Translation requires macOS 15 or later and may need a language download.","オフでは原文をすぐ表示します。Apple翻訳にはmacOS 15以降が必要で、言語のダウンロードが必要な場合があります。")).font(.caption).foregroundColor(.secondary)
            }
            JapaneseCard(JL("일본어 사전","Japanese dictionary","日本語辞書")) {
                Text("SKK-JISYO.L").font(.headline)
                Text(JL("단어와 짧은 표현을 사전에서 찾아 변환합니다.","Dictionary conversion for words and short expressions.","単語と短い表現を辞書から検索して変換します。"))
                Text(JL("구자체 대응은 일본 문화청의 상용한자표를 기준으로 합니다. 모든 역사적 이체자를 포함하지는 않습니다.","Old forms follow the Agency for Cultural Affairs Joyo Kanji table; not every historical variant is covered.","旧字体は文化庁の常用漢字表に基づきます。全ての歴史的異体字を網羅しません。")).foregroundColor(.secondary)
            }
            JapaneseCard(JL("현재 지원 범위","Current capabilities","現在の対応範囲")) {Text(JL("긴 문장의 자동 분절과 개인 학습 사전은 아직 지원하지 않습니다. 먼저 단어 단위로 변환해 주세요.","Automatic sentence segmentation and personal learning are not supported yet. Convert words individually.","長文の自動分節と学習辞書は未対応です。単語単位で変換してください。"))}
        case .about:
            HStack(spacing:16) {
                Image(nsImage:NSImage(contentsOf:Bundle.main.resourceURL!.appendingPathComponent("AppIcon.icns")) ?? NSImage()).resizable().frame(width:72,height:72)
                VStack(alignment:.leading,spacing:6) {
                    Text(JL("한지미 일본어","HanjaIME Japanese","HanjaIME 日本語")).font(.system(size:26,weight:.bold))
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "").foregroundColor(.secondary)
                    Button(JL("변경 내역 보기","See changelog","変更履歴を見る")) {(NSApp.delegate as? JapaneseAppDelegate)?.showChangelog()}.buttonStyle(.link)
                }
                Spacer()
                Button(JL("새 버전 확인…","Check for Updates…","アップデートを確認…")) {NSWorkspace.shared.open(URL(string:"https://github.com/akinoyuki0411/HanjaIME-/releases")!)}
            }
            Text(JL("배포 페이지에서 일본어 입력기 버전을 확인할 수 있습니다. 다운로드 후 설치는 직접 진행합니다.","Check Japanese input-method releases on the download page. Install downloaded updates manually.","配布ページで日本語入力方法の版を確認できます。ダウンロード後は手動でインストールします。")).font(.caption).foregroundColor(.secondary)
            Divider()
            VStack(spacing:9) {
                Text("HanjaIME 日本語").font(.system(size:34,weight:.bold,design:.rounded)).foregroundStyle(LinearGradient(colors:[.indigo,.purple,.blue],startPoint:.leading,endPoint:.trailing))
                Text(JL("생각은 일본어로, 표현은 더 넓게","Think in Japanese. Express more.","日本語で考え、表現をもっと豊かに。")).font(.headline)
                Text(JL("SKK 기반 · 구자체 우선 일본어 입력기","SKK-based Japanese input, old forms first","SKKベース・旧字体優先の日本語入力方法")).font(.caption).foregroundColor(.secondary)
            }.frame(maxWidth:.infinity).padding(.vertical,8)
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:8) {
                aboutLink("globe",JL("웹사이트","Website","ウェブサイト"),"")
                aboutLink("questionmark.circle",JL("도움말","Help","ヘルプ"),"#readme")
                Button {NSWorkspace.shared.open(URL(string:"https://github.com/akinoyuki0411/HanjaIME-/issues")!)} label:{Label(JL("이메일","Email","メール"),systemImage:"envelope").frame(maxWidth:.infinity).padding(10)}.buttonStyle(.bordered)
                aboutLink("ladybug",JL("버그 알리기","Report a Bug","不具合を報告"),"/issues/new")
                aboutLink("chevron.left.forwardslash.chevron.right",JL("소스코드","Source Code","ソースコード"),"")
                Button {let alert=NSAlert();alert.messageText=JL("한지미 후원","Support HanjaIME","HanjaIMEを支援");alert.informativeText=JL("후원 페이지를 준비 중입니다. 현재 결제는 받지 않습니다.","A support page is being prepared. Payments are not accepted yet.","支援ページを準備中です。現在、支払いは受け付けていません。");alert.runModal()} label:{Label(JL("후원하기","Support","支援する"),systemImage:"heart").frame(maxWidth:.infinity).padding(10)}.buttonStyle(.bordered)
            }
            Text(JL("입력·변환은 Mac에서 처리합니다. 책 버튼의 뜻 조회 시 선택한 단어를 네이버에 전송합니다.","Input and conversion run locally. Dictionary lookups send the selected term to NAVER.","入力と変換はMac内で処理します。辞書検索時は選択した単語をNAVERに送信します。")).font(.caption).foregroundColor(.secondary)
        case .licenses:
            JapaneseCard(JL("오픈소스 고지","Open-source notices","オープンソース表記")) {Text("SKK-JISYO.L · GPL-2.0-or-later");Text(JL("원본 사전, 라이선스와 출처를 앱에 포함했습니다.","Original dictionary, license and sources are bundled with the app.","原辞書、ライセンスと出典を同梱しています。"));Button(JL("라이선스 전문 보기","Read full license","ライセンス全文")) {openResource("SKK-COPYING")};Button(JL("자료 출처 보기","View data sources","データの出典")) {openResource("SOURCES.txt")}}
        }
    }
    private func aboutLink(_ icon:String,_ title:String,_ suffix:String)->some View {
        Button {NSWorkspace.shared.open(URL(string:"https://github.com/akinoyuki0411/HanjaIME-"+suffix)!)} label:{Label(title,systemImage:icon).frame(maxWidth:.infinity).padding(10)}.buttonStyle(.bordered)
    }
    private func key(_ name:String,_ text:String)->some View {HStack {Text(name).font(.system(.body,design:.monospaced)).frame(width:110,alignment:.leading);Text(text);Spacer()}}
    private func openResource(_ name:String) {if let root=Bundle.main.resourceURL {NSWorkspace.shared.open(root.appendingPathComponent(name))}}
}
