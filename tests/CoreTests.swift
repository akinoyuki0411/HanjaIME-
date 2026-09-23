import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import CHangul

final class RealHangulBuffer: HanjaIMEHangulBuffer {
  let context = hangul_ic_new("2")!
  var queued = ""
  static func string(_ pointer: UnsafePointer<ucschar>?) -> String {
    guard let pointer = pointer else { return "" }
    var result = ""
    for index in 0..<64 {
      let value = pointer[index]
      if value == 0 { break }
      if let scalar = UnicodeScalar(value) { result.unicodeScalars.append(scalar) }
    }
    return result
  }
  var composedString: String { Self.string(hangul_ic_get_preedit_string(context)) }
  func feed(_ key: Character) -> Bool {
    let result = hangul_ic_process(context, Int32(key.asciiValue!))
    queued += Self.string(hangul_ic_get_commit_string(context))
    return result
  }
  func backspace() -> Bool { hangul_ic_backspace(context) }
  func dequeueCommitString() -> String { let result = queued; queued = ""; return result }
  func cancelComposition() { queued += Self.string(hangul_ic_flush(context)) }
  func clearCompositionContext() { hangul_ic_reset(context); queued = "" }
  deinit { hangul_ic_delete(context) }
}

final class RealDictionary {
  let word: OpaquePointer
  let characters: OpaquePointer
  let emoji: OpaquePointer
  init(path: String) {
    word = hanja_table_load(path)!
    let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
    characters = hanja_table_load(directory.appendingPathComponent("hanjac.txt").path)!
    emoji = hanja_table_load(directory.appendingPathComponent("emoji_ko.txt").path)!
  }
  func lookup(_ reading: String) -> [HanjaIMECandidate] {
    collect(word, reading, kind: .hanja)
      + (reading.count == 1 ? collect(characters, reading, kind: .hanja) : [])
      + collect(emoji, reading, kind: .emoji)
  }
  func collect(_ table: OpaquePointer, _ reading: String, kind: HanjaIMECandidate.Kind) -> [HanjaIMECandidate] {
    guard let list = hanja_table_match_exact(table, reading) else { return [] }
    defer { hanja_list_delete(list) }
    return (0..<hanja_list_get_size(list)).map { index in
      HanjaIMECandidate(value: String(cString: hanja_list_get_nth_value(list, UInt32(index))),
                       annotation: String(cString: hanja_list_get_nth_comment(list, UInt32(index))), kind: kind)
    }
  }
  deinit { hanja_table_delete(word); hanja_table_delete(characters); hanja_table_delete(emoji) }
}

@main struct CoreTests {
  static var assertions = 0
  static func expect(_ ok: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
  }
  static func testStorageMigration() {
    expect(HanjaIMEStorage.preferencesDomain != HanjaIMEStorage.bundleIdentifier, "settings suite differs from app ID")
    expect(HanjaIMEUsageStore.domain != HanjaIMEStorage.bundleIdentifier, "learning suite differs from app ID")
    expect(HanjaIMEUsageStore.domain != HanjaIMEStorage.preferencesDomain, "learning and settings are separate")
    let domain = "org.hanjaime.tests.migration." + UUID().uuidString
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let key = HanjaIMEStorage.selectionCountsKey
    let legacy: [String: Any] = [key: ["역사": ["役事": 7]], "unrelated": "keep out"]
    HanjaIMEStorage.migrateLegacyValues(legacy, to: defaults, domain: domain, keys: [key])
    let migrated = HanjaIMEUsageStore(defaults: defaults)
    expect(migrated.snapshot(reading: "역사")["役事"] == 7, "old learning copied")
    expect(defaults.object(forKey: "unrelated") == nil, "unrelated keys not copied")
    migrated.reset(); migrated.flush()
    HanjaIMEStorage.migrateLegacyValues(legacy, to: defaults, domain: domain, keys: [key])
    expect(HanjaIMEUsageStore(defaults: defaults).snapshot(reading: "역사").isEmpty, "reset learning is not restored from old data")
    let nextDomain = domain + ".existing"
    let next = UserDefaults(suiteName: nextDomain)!
    defer { next.removePersistentDomain(forName: nextDomain) }
    next.set(["역사": ["役事": 12]], forKey: key)
    HanjaIMEStorage.migrateLegacyValues(legacy, to: next, domain: nextDomain, keys: [key])
    expect(HanjaIMEUsageStore(defaults: next).snapshot(reading: "역사")["役事"] == 12, "newer destination learning preserved")
    expect((legacy[key] as? [String: [String: Int]])?["역사"]?["役事"] == 7, "legacy values preserved")
    print("PASS: independent settings/learning domains and one-time learning migration")
  }
  static func main() {
    testStorageMigration()
    let indices = HanjaIMEPanelLayout.characterIndices(selected: NSRange(location: 104, length: 0),
      marked: NSRange(location: 102, length: 2))
    expect(indices == [104, 102, NSNotFound], "geometry uses absolute document indices, not composition offset 2")
    expect(HanjaIMEPanelLayout.characterIndices(selected: NSRange(location: NSNotFound, length: 0),
      marked: NSRange(location: NSNotFound, length: 0)) == [NSNotFound], "unavailable geometry asks for insertion location")
    let displays = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: -900, y: 0, width: 900, height: 700)]
    expect(!HanjaIMEPanelLayout.validCaret(.zero, screens: displays), "initial zero geometry rejected")
    expect(!HanjaIMEPanelLayout.validCaret(CGRect(x: 5000, y: 600, width: 1, height: 20), screens: displays), "offscreen anchor rejected")
    expect(HanjaIMEPanelLayout.validCaret(CGRect(x: -600, y: 600, width: 0, height: 20), screens: displays), "zero-width caret on left display accepted")
    for count in 1...12 {
      let size = HanjaIMEPanelLayout.size(rows: count, textWidth: 80, paged: count > 9)
      expect(size.height == 30 + CGFloat(min(9, count)) * 26 + (count > 9 ? 20 : 0), "no reserved candidate rows")
      expect(size.width == (count <= 4 ? 150 : 214), "short candidates stay compact")
    }
    for screen in [CGRect(x: 0, y: 0, width: 1440, height: 900),
                   CGRect(x: -1600, y: 120, width: 1600, height: 900)] {
      for point in [CGPoint(x: screen.minX + 1, y: screen.minY + 3),
                    CGPoint(x: screen.maxX - 1, y: screen.maxY - 20)] {
        let frame = HanjaIMEPanelLayout.candidate(caret: CGRect(origin: point, size: CGSize(width: 1, height: 18)),
          size: CGSize(width: 214, height: 284), visible: screen)
        expect(screen.contains(frame), "candidate is within current screen")
      }
      let candidate = CGRect(x: screen.minX + 100, y: screen.minY + 300, width: 180, height: 100)
      let right = HanjaIMEPanelLayout.definition(candidate: candidate, size: CGSize(width: 280, height: 220), visible: screen)
      expect(right.minX == candidate.maxX + 4 && screen.contains(right), "dictionary right first")
      let edge = CGRect(x: screen.maxX - 190, y: screen.minY + 300, width: 180, height: 100)
      let left = HanjaIMEPanelLayout.definition(candidate: edge, size: CGSize(width: 280, height: 220), visible: screen)
      expect(left.maxX == edge.minX - 4 && screen.contains(left), "dictionary left when right does not fit")
      expect(!left.intersects(edge) && !right.intersects(candidate), "dictionary does not cover candidate")
    }
    expect(HanjaIMEPanelLayout.windowLevel(host: 0, normal: 101, ceiling: 999) == 101, "normal host uses IME level")
    expect(HanjaIMEPanelLayout.windowLevel(host: 180, normal: 101, ceiling: 999) == 181, "floating search host stays below IME")
    expect(HanjaIMEPanelLayout.windowLevel(host: Int.max, normal: 101, ceiling: 999) == 999, "window level bounded without overflow")
    let dictionary = RealDictionary(path: CommandLine.arguments[1])
    let domain = "org.hanjaime.tests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let usage = HanjaIMEUsageStore(defaults: defaults)
    let hangul = RealHangulBuffer()
    let session = HanjaIMESession(hangul: hangul, usage: usage, lookup: dictionary.lookup)
    func type(_ keys: String) {
      for key in keys { expect(session.handle(.text) { hangul.feed(key) }, "handled \(key)") }
    }
    let examples = [("eogksalsrnr", "대한민국", "大韓民國"), ("durtk", "역사", "歷史"),
                    ("wjdcl", "정치", "政治"), ("tktkd", "사상", "思想"),
                    ("dusrn", "연구", "硏究"), ("wprnr", "제국", "帝國")]
    for (keys, reading, expected) in examples {
      type(keys)
      expect(session.reading == reading, "two-set \(reading)")
      expect(session.candidates.first?.value == expected, "top \(reading)")
      expect(session.handle(.space(preserveHangul: false)), "space starts conversion")
      expect(session.takeCommit().isEmpty, "Space does not commit")
      expect(session.reading == reading && session.displayString == expected, "preview preserves reading")
      expect(session.handle(.enter), "Enter commits preview")
      expect(session.takeCommit() == expected, "conversion \(reading)")
      expect(session.reading.isEmpty && session.candidates.isEmpty, "clear after conversion")
      expect(!session.handle(.space(preserveHangul: false)), "second space passes through")
    }
    print("PASS: requested conversion examples")
    for keys in ["djqtdjdy", "rhakdnjdy"] {
      type(keys)
      let reading = session.reading
      expect(session.candidates.isEmpty, "native word has no candidates: \(reading)")
      expect(session.handle(.space(preserveHangul: false)), "native word keeps a marked-text space")
      expect(session.reading == reading + " ", "native text remains in the session")
      expect(session.takeCommit().isEmpty, "Space alone does not commit")
      _ = session.handle(.enter)
      expect(session.takeCommit() == reading + " ", "native text preserved on Enter")
    }
    type("durtk")
    expect(session.handle(.space(preserveHangul: true)), "shift space")
    expect(session.reading == "역사 ", "raw space stays marked")
    _ = session.handle(.enter)
    expect(session.takeCommit() == "역사 ", "raw space on Enter")
    type("durtk")
    expect(session.handle(.enter), "first enter")
    expect(session.takeCommit() == "역사", "enter preserves unselected Hangul")
    expect(!session.handle(.enter), "second enter belongs to host")
    type("durtk")
    expect(session.handle(.escape), "escape consumes current composition")
    expect(session.takeCommit() == "역사", "escape preserves Hangul")
    type("durtk")
    expect(session.handle(.number(2)), "ordinary number")
    expect(session.takeCommit() == "역사2", "numbers do not select unsolicited candidates")
    type("durtk")
    expect(session.handle(.next), "down begins selection")
    expect(session.handle(.number(2)), "second candidate")
    expect(session.takeCommit() == "役事", "intentional numeric selection")
    usage.flush()
    expect(usage.snapshot(reading: "역사")["役事"] == 1, "selection recorded")
    usage.record(reading: "역사", value: "役事")
    let reloaded = { () -> HanjaIMEUsageStore in usage.flush(); return HanjaIMEUsageStore(defaults: defaults) }()
    expect(reloaded.snapshot(reading: "역사")["役事"] == 2, "local persistence reload")
    type("durtk")
    expect(session.candidates.first?.value == "役事", "learned ordering")
    let stale = session.generation
    type("r")
    expect(!session.choose(index: 0, generation: stale), "reject stale mouse callback")
    expect(session.handle(.backspace) { hangul.backspace() }, "jamo backspace")
    expect(session.reading == "역사", "backspace restores reading")
    session.commitRaw(); _ = session.takeCommit()
    type("djqtdjdy")
    let before = session.reading
    expect(!session.handle(.next), "arrow with no candidate goes to host")
    expect(session.takeCommit() == before, "arrow preserves raw text")
    type("gksmf")
    for _ in 0..<10 { _ = session.handle(.backspace) { hangul.backspace() } }
    expect(session.reading.isEmpty, "backspace crosses buffered syllables")
    expect(!session.handle(.backspace) { hangul.backspace() }, "empty backspace goes to host")
    type("durtk")
    expect(session.handle(.literal("。")), "punctuation")
    expect(session.reading == "역사。", "punctuation stays in conversion session")
    _ = session.handle(.enter)
    expect(session.takeCommit() == "역사。", "punctuation commits on Enter")
    type("durtk")
    expect(!session.handle(.passThrough), "shortcut/English mode boundary")
    expect(session.takeCommit() == "역사", "boundary preserves text")
    session.automaticCandidates = false
    type("wjdcl")
    expect(session.candidates.isEmpty, "Hangul-only mode")
    _ = session.handle(.space(preserveHangul: false))
    expect(session.reading == "정치 ", "Hangul-only space remains marked")
    _ = session.handle(.enter)
    expect(session.takeCommit() == "정치 ", "Hangul-only space on Enter")
    session.automaticCandidates = true
    let variants = [HanjaIMECandidate(value: "歴史", annotation: ""),
                    HanjaIMECandidate(value: "歷史", annotation: ""),
                    HanjaIMECandidate(value: "歷史", annotation: "duplicate")]
    let ranked = HanjaIMERanking.rank(variants, reading: "역사", counts: ["歴史": 999])
    expect(ranked.first?.value == "歴史" && ranked.count == 2, "explicit choices override defaults and deduplicate")
    expect(HanjaIMERanking.rank(variants, reading: "역사", counts: [:]).first?.value == "歷史", "traditional default without learning")
    expect(HanjaIMERanking.rank(variants, reading: "역사", counts: ["歷史": 2, "歴史": 2],
      recent: ["歷史": 1, "歴史": 2]).first?.value == "歴史", "recent choice breaks frequency ties")
    expect(HanjaIMERanking.rank([HanjaIMECandidate(value: "🌈", annotation: "")],
                               reading: "무지개", counts: [:]).isEmpty, "emoji cannot masquerade as Hanja")
    expect(HanjaIMERanking.rank([HanjaIMECandidate(value: "大韓民國", annotation: "", predicted: true)],
                               reading: "대한", counts: [:]).first?.value == "大韓民國", "allow offline predictive completions")
    expect(HanjaIMERanking.semanticCandidates(for: "사랑").map(\.value).starts(with: ["愛", "戀"]),
           "meaning candidates supplement phonetic reading")
    expect(HanjaIMERanking.predictedCandidates(for: "지").first?.value == "地圖",
           "frequent prefix prediction ranks before single syllables")
    expect(HanjaIMERanking.japaneseVariant(of: "國家") == "国家", "central shinjitai variant table")
    expect(HanjaIMERanking.relatedSymbols(for: "「").contains { $0.value == "『" && $0.kind == .symbol },
           "related punctuation group")
    expect(HanjaIMERanking.kaomojiCandidates(for: "웃음").contains { $0.value == "(^_^)" },
           "kaomoji are local symbol candidates")
    for keys in ["sms", "dms", "dl", "rk", "dmf", "fmf", "dml", "dp", "dhk", "rhk", "eh", "fh", "aks", "dptj", "Rkwl"] {
      type(keys)
      let raw = session.reading
      expect(session.candidates.isEmpty, "protect particle \(raw)")
      _ = session.handle(.space(preserveHangul: false))
      expect(session.reading == raw + " ", "particle stays Hangul: \(raw)")
      _ = session.handle(.enter)
      expect(session.takeCommit() == raw + " ", "particle commits on Enter: \(raw)")
    }
    usage.reset(); usage.flush()
    expect(usage.register(reading: "가나다", value: "加那多"), "register fictional fixture")
    for (keys, result) in [("durtkfmf", "歷史를"), ("dkssudgktpdy", "安寧하세요"),
                          ("dkssudgktuTdjdy", "安寧하셨어요"), ("gkrrydptjsms", "學校에서는"),
                          ("dusrngkqslek", "硏究합니다"), ("rkskek", "加那多"),
                          ("rkskekdprpeh", "加那多에게도")] {
      type(keys)
      expect(session.candidates.first?.value == result, "stem or personal candidate: \(session.reading)")
      _ = session.handle(.space(preserveHangul: false))
      expect(session.displayString == result && session.takeCommit().isEmpty, "suffix preview")
      _ = session.handle(.enter)
      expect(session.takeCommit() == result, "suffix retained on commit")
    }
    expect(usage.snapshot(reading: "안녕")["安寧"] == 2, "learn stem across two endings")
    expect(usage.snapshot(reading: "안녕하세요").isEmpty, "never store mixed text as a Hanja word")
    expect(usage.snapshot(reading: "가나다")["加那多"] == 2, "learn name across suffixes")
    type("dkssudgktpdy")
    _ = session.handle(.space(preserveHangul: false)); _ = session.handle(.escape)
    expect(session.reading == "안녕하세요", "cancel restores entire inflected reading")
    _ = session.handle(.space(preserveHangul: true))
    _ = session.handle(.enter)
    expect(session.takeCommit() == "안녕하세요 ", "preserve original inflected Hangul")
    for raw in ["하늘", "바다", "고마워요", "없어요", "안녕하세욥", "역사xyz"] {
      expect(HanjaIMEInflection.candidates(reading: raw, exact: dictionary.lookup).isEmpty, "do not guess suffix: \(raw)")
    }
    type("gks")
    expect(session.candidates.first?.value == "韓", "single-syllable Hanja is available without shortcut")
    expect(session.requestConversion(), "explicit single-syllable lookup")
    expect(session.candidates.contains { $0.value == "韓" }, "manual dictionary contains 韓")
    _ = session.handle(.escape)
    expect(session.reading == "한" && !session.selectionEngaged, "Escape restores reading")
    _ = session.handle(.enter); _ = session.takeCommit()
    type("fmf")
    expect(session.candidates.isEmpty, "particle protected automatically")
    expect(session.requestConversion() && !session.candidates.isEmpty, "manual request can convert even protected reading")
    _ = session.handle(.escape); _ = session.handle(.enter); _ = session.takeCommit()
    expect(usage.register(reading: "우리", value: "宇里"), "register personal word")
    expect(!usage.register(reading: "우리", value: "宇"), "reject unequal length")
    expect(!usage.register(reading: "우리", value: "영어"), "reject non-Hanja value")
    expect(!usage.register(reading: "hello", value: "宇里"), "reject non-Hangul reading")
    usage.flush()
    let personalReload = HanjaIMEUsageStore(defaults: defaults)
    expect(personalReload.personalCandidates(reading: "우리").first?.value == "宇里", "personal dictionary reload")
    expect(!personalReload.recency(reading: "안녕").isEmpty, "recency reload")
    type("dnflsms")
    expect(session.candidates.first?.value == "宇里는", "new personal stem with particle")
    session.commitRaw(); _ = session.takeCommit()
    usage.reset(); usage.flush()
    expect(usage.personalCandidates(reading: "우리").count == 1, "reset learning preserves personal dictionary")
    expect(usage.removePersonal(reading: "우리", value: "宇里"), "remove personal spelling")
    expect(usage.removePersonal(reading: "가나다", value: "加那多"), "default spelling can be removed")
    usage.flush()
    expect(HanjaIMEUsageStore(defaults: defaults).personalCandidates(reading: "가나다").isEmpty, "removed default never respawns")
    expect(usage.register(reading: "가나다", value: "加那多"), "restore test spelling")
    usage.reset(); usage.flush()
    type("durtk")
    _ = session.handle(.space(preserveHangul: false))
    _ = session.handle(.space(preserveHangul: false))
    expect(session.displayString == "役事" && session.takeCommit().isEmpty, "second Space cycles")
    _ = session.handle(.backspace) { hangul.backspace() }
    expect(session.reading == "역사" && !session.selectionEngaged, "Backspace cancels preview")
    _ = session.handle(.space(preserveHangul: false))
    type("fmf")
    expect(session.takeCommit().isEmpty && session.reading == "歷史를", "typing keeps preview in the same session")
    _ = session.handle(.space(preserveHangul: false))
    _ = session.handle(.enter)
    expect(session.takeCommit() == "歷史를 ", "particle after converted word")
    type("rhdiddl")
    expect(session.reading == "고양이" && session.candidates.contains { $0.value == "🐈" }, "real emoji dictionary")
    expect(session.choose(index: session.candidates.firstIndex { $0.value == "🐈" }!), "select emoji")
    expect(session.takeCommit() == "🐈", "emoji committed intact")
    usage.flush()
    expect(HanjaIMEUsageStore(defaults: defaults).snapshot(reading: "고양이")["🐈"] == 1, "emoji learning reload")
    type("cor")
    let bookEmoji = Set(session.candidates.filter { $0.kind == .emoji }.map(\.value))
    expect(["📕", "📖", "📗", "📘", "📚"].allSatisfy(bookEmoji.contains),
           "book reading exposes Japanese-IME-style related emoji candidates")
    session.commitRaw(); _ = session.takeCommit()
    let mixed = HanjaIMERanking.rank([
      HanjaIMECandidate(value: "☕", annotation: "커피", kind: .emoji),
      HanjaIMECandidate(value: "咖啡", annotation: "")], reading: "커피", counts: ["☕": 99])
    expect(mixed.first?.kind == .hanja, "Hanja stays ahead of emoji")
    let literals: [(String, Bool, UInt32)] = [
      (";", false, 0x2026), ("e", false, 0x317C), ("e", true, 0x317C),
      ("u", false, 0x118D), ("r", false, 0x115A), ("l", true, 0x1198),
      (".", false, 0x318D), (".", true, 0x119E),
    ]
    for (key, shift, scalar) in literals {
      let symbol = HanjaIMEOptionSymbols.literal(key: key, shift: shift)!
      expect(symbol.unicodeScalars.map { $0.value } == [scalar], "exact old Jamo scalar")
      type("durtk")
      _ = session.handle(.literal(symbol))
      expect(session.reading == "역사" + symbol && session.takeCommit().isEmpty, "literal preserves marked session")
      _ = session.handle(.enter)
      expect(session.takeCommit() == "역사" + symbol, "literal commits on Enter")
      type("rk"); _ = session.handle(.enter)
      expect(session.takeCommit() == "가", "next Hangul starts independently")
    }
    print("PASS: preview/cancel, particles, manual Hanja, emoji and literal regressions")
    type("dkssud")
    let allGreeting = session.layoutCandidates
    let greetingCount = session.unfilteredCandidateCount
    expect(greetingCount >= 5, "greeting has an expanded standard session")
    for category in HanjaIMECandidateCategory.allCases {
      session.setCategory(category)
      expect(session.layoutCandidates == allGreeting && session.unfilteredCandidateCount == greetingCount,
             "tab preserves layout population: \(category.title)")
      expect(session.candidates == allGreeting.filter(category.accepts), "tab filtering preserves full standard ranking")
    }
    session.commitRaw(); _ = session.takeCommit()
    _ = session.handle(.literal("「"))
    let bracketVariants = session.candidates
    session.setCategory(.hanja)
    expect(session.candidates.isEmpty && session.wantsCandidatePanel, "empty hanja tab preserves symbol session")
    session.setCategory(.symbols)
    expect(session.candidates == bracketVariants, "tab switch retains related symbols without rebuilding a Hangul query")
    session.commitRaw(); _ = session.takeCommit()
    expect(usage.register(reading: "미소", value: "(^_^)", category: .symbols), "manager can register symbol category")
    expect(usage.personalCandidates(reading: "미소").contains { $0.kind == .symbol }, "registered symbols retain metadata")
    expect(usage.register(reading: "한국", value: "韓國", category: .hanja), "register ordinary personal word")
    expect(!usage.personalCandidates(reading: "한국").contains(where: HanjaIMECandidateCategory.names.accepts), "non-name personal word is not a name")
    let otherProcess = HanjaIMEUsageStore(defaults: defaults)
    usage.record(reading: "역사", value: "歷史"); usage.flush()
    otherProcess.reset()
    expect(usage.snapshot(reading: "역사").isEmpty, "manager reset is visible to a running input method")
    usage.record(reading: "역사", value: "歷史"); usage.flush()
    expect(usage.snapshot(reading: "역사")["歷史"] == 1, "selection after external reset starts from one")
    type("cor")
    session.setCategory(.symbols)
    expect(!session.candidates.isEmpty && session.candidates.allSatisfy { $0.kind == .emoji }, "symbols tab filters real candidates")
    _ = session.handle(.space(preserveHangul: false))
    let emojiValue = session.candidates[0].value
    _ = session.handle(.enter)
    expect(session.takeCommit() == emojiValue, "filtered Space and Enter use the displayed index")
    type("rkskek")
    session.setCategory(.names)
    expect(session.candidates.first?.value == "加那多", "names tab retains personal dictionary")
    session.setCategory(.symbols)
    expect(session.candidates.isEmpty && session.wantsCandidatePanel, "empty category keeps tabs available")
    session.setCategory(.standard)
    expect(session.candidates.first?.value == "加那多", "switch back restores candidates")
    session.commitRaw(); _ = session.takeCommit()
    type("dkssudgktpdy")
    let definition = HanjaIMEDefinitionRequest(candidate: session.candidates[0], reading: session.reading)
    expect(definition.term == "安寧" && definition.reading == "안녕", "dictionary looks up the stem")
    session.commitRaw(); _ = session.takeCommit()
    for key in HanjaIMEOptionSymbols.yetKeys {
      expect(HanjaIMEOptionSymbols.yetKey(key: key, shift: false) == key.uppercased(), "2y shifted position")
    }
    let start = Date()
    for _ in 0..<200 {
      type("eogksalsrnr")
      _ = session.handle(.space(preserveHangul: false))
      _ = session.handle(.enter)
      expect(session.takeCommit() == "大韓民國", "rapid stream")
    }
    let elapsed = Date().timeIntervalSince(start)
    print("PASS: input, persistence, stale-selection, and rapid-stream checks")
    DispatchQueue.concurrentPerform(iterations: 2) { _ in
      for _ in 0..<50 { usage.record(reading: "제국", value: "諸國") }
    }
    usage.flush()
    expect(usage.snapshot(reading: "제국")["諸國"] == 100, "concurrent selection storage")
    usage.reset(); usage.flush()
    expect(HanjaIMEUsageStore(defaults: defaults).snapshot(reading: "제국").isEmpty, "reset persistence")
    print("PASS: \(assertions) assertions; production Swift core + pinned libhangul + full Gureum word dictionary")
    print(String(format: "Rapid stream: 2,200 letter keys + 200 conversions in %.3f s (core benchmark; not a UI latency measurement)", elapsed))
  }
}
