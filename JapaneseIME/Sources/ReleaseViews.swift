import SwiftUI
import Translation
import NaturalLanguage

struct JapaneseChangelog:View {
    var body:some View {ScrollView {VStack(alignment:.leading,spacing:24) {
        HStack(spacing:20) {Image(nsImage:NSImage(named:NSImage.applicationIconName) ?? NSImage()).resizable().frame(width:98,height:98).shadow(radius:8);VStack(alignment:.leading) {Text("HanjaIME 日本語").font(.system(size:32,weight:.bold));Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "").foregroundStyle(.secondary)}}
        Text(JL("이번 버전의 새로운 기능","What's new","今回の新機能")).font(.title2.bold())
        ForEach([JL("사전 선택: Apple 먼저 · 네이버 먼저 · Apple만","Dictionary priority: Apple first, NAVER first or Apple only","辞書選択：Apple優先・NAVER優先・Appleのみ"),JL("Apple 번역을 선택적으로 사용","Optional Apple Translation","Apple翻訳を選択可能"),JL("책 버튼에 커서를 올려 작은 뜻풀이 표시","Compact dictionary definitions on hover","本ボタンにカーソルを置いて意味を表示"),JL("설정 탭 전환 시 부드러운 크기 조절","Smooth resizing between settings pages","設定画面の滑らかなサイズ変更")],id:\.self) {text in Label(text,systemImage:"checkmark.circle.fill").padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Color.accentColor.opacity(0.08),in:RoundedRectangle(cornerRadius:14))}
        Text(JL("이전 변경: 구자체 우선 후보, 기호 탭, 작은 입력기 아이콘, 네이버 뜻풀이 캐시.","Earlier changes: old forms first, symbols, compact input icon and cached NAVER definitions.","以前の変更：旧字体優先、記号、小さな入力アイコン、NAVER意味のキャッシュ。" )).foregroundStyle(.secondary)
    }.padding(32)}}
}
@available(macOS 15.0,*)
struct JapaneseTranslatedDefinition:View {
    let text:String;let url:URL?
    @State private var translated:String?
    @State private var translationFailed=false
    private var configuration:TranslationSession.Configuration? {
        guard let source=NLLanguageRecognizer.dominantLanguage(for:text) else{return nil}
        let target=JapanesePreferences.shared.language
        guard source.rawValue != target else{return nil}
        return .init(source:Locale.Language(identifier:source.rawValue),target:Locale.Language(identifier:target))
    }
    var body:some View {VStack(alignment:.leading,spacing:6) {
        Text("Apple · "+JL("번역","Translation","翻訳")).font(.caption).foregroundStyle(.secondary)
        ScrollView {Text(translated ?? text).font(.system(size:12)).frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled)}
        if translationFailed {Text(JL("번역을 사용할 수 없어 원문을 표시합니다.","Translation unavailable; showing original.","翻訳できないため原文を表示します。")).font(.caption).foregroundStyle(.secondary)}
        if let url {Link(JL("네이버에서 자세히 보기","More on NAVER","NAVERで詳しく見る"),destination:url).font(.caption)}
    }.padding(10).frame(width:280,height:220).translationTask(configuration) {session in
        do {translated=try await session.translate(text).targetText} catch {translationFailed=true}
    }}
}
