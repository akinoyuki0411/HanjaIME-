import Cocoa
import Carbon
import Hangul
import InputMethodKit

extension HangulComposer: HanjaIMEHangulBuffer {}

final class HanjaIMEExactDictionary {
  static let shared = HanjaIMEExactDictionary()
  private let words: HanjaTableSearchSource?
  private let wordPrefix: HGHanjaTable?
  private let characters: HanjaTableSearchSource?
  private let emoji: HanjaTableSearchSource?
  private var cache: [String: [HanjaIMECandidate]] = [:]

  init(directory: URL? = nil) {
    let bundle = Bundle(for: HGKeyboard.self)
    func path(_ name: String) -> String? {
      directory?.appendingPathComponent(name + ".txt").path
        ?? bundle.path(forResource: name, ofType: "txt", inDirectory: "hanja")
    }
    func source(_ name: String) -> HanjaTableSearchSource? {
      guard let path = path(name),
        let table = HGHanjaTable(contentOfFile: path) else { return nil }
      return HanjaTableSearchSource(table: table, method: .exact)
    }
    words = source("hanjaw")
    if let path = path("hanjaw"),
      let table = HGHanjaTable(contentOfFile: path) {
      wordPrefix = table
    } else {
      wordPrefix = nil
    }
    characters = source("hanjac")
    emoji = source("emoji_ko")
  }

  func lookup(_ reading: String) -> [HanjaIMECandidate] {
    guard HanjaIMERanking.isReading(reading) else { return [] }
    if let cached = cache[reading] { return cached }
    let token = DispatchWorkItem {}
    var found = words?.collect(reading, workItem: token) ?? []
    if reading.count == 1 { found += characters?.collect(reading, workItem: token) ?? [] }
    let result = found.map {
      let value = $0.candidate.value
      var annotation = $0.candidate.description
      if (annotation.isEmpty || annotation == reading), reading.count == value.count {
        let meanings = zip(reading, value).compactMap { syllable, glyph -> String? in
          characters?.collect(String(syllable), workItem: token).first { $0.candidate.value == String(glyph) }?.candidate.description
        }.filter { !$0.isEmpty }
        if meanings.count == value.count { annotation = meanings.joined(separator: " · ") }
      }
      return HanjaIMECandidate(value: value, annotation: annotation)
    } + (emoji?.collect(reading, workItem: token) ?? []).map {
      HanjaIMECandidate(value: $0.candidate.value, annotation: $0.candidate.description, kind: .emoji)
    }
    if cache.count >= 256 { cache.removeAll(keepingCapacity: true) }
    cache[reading] = result
    return result
  }

  func predictions(_ reading: String) -> [HanjaIMECandidate] {
    guard HanjaIMERanking.isReading(reading), reading.count <= 4 else { return [] }
    // Prefix lookup stays local and is capped before it reaches the UI.  It
    // complements the curated high-frequency list in HanjaIMERanking.
    guard let list = wordPrefix?.hanjas(byPrefixSearching: reading) else { return [] }
    // HGHanja rows borrow C storage owned by HGHanjaList. Retaining array
    // alone does not retain that owner. Copy strings before releasing list.
    return withExtendedLifetime(list) {
      list.array.lazy.filter { $0.key != reading && $0.key.hasPrefix(reading) }
        .prefix(24).map { item in
          let key = String(decoding: item.key.utf8, as: UTF8.self)
          let value = String(decoding: item.value.utf8, as: UTF8.self)
          let comment = String(decoding: item.comment.utf8, as: UTF8.self)
          return HanjaIMECandidate(value: value,
            annotation: key + " · 예측" + (comment.isEmpty ? "" : " · " + comment),
            predicted: true, frequency: 0, sourceReading: reading, sourceValue: value)
        }
    }
  }
}

final class HanjaIMEComposer: Composer {
  private static let generationKey = NSAttributedString.Key("HanjaIME.Generation")
  private static let indexKey = NSAttributedString.Key("HanjaIME.Index")
  private static let readingKey = NSAttributedString.Key("HanjaIME.Reading")
  let hangul: HangulComposer
  let session: HanjaIMESession
  var delegate: Composer! { hangul }
  var composedString: String { session.displayString }
  var originalString: String { session.reading }
  var commitString: String { session.commitString }
  var hasCandidates: Bool { !session.candidates.isEmpty }

  init(hangul: HangulComposer, usage: HanjaIMEUsageStore = .shared,
       dictionary: HanjaIMEExactDictionary = .shared) {
    self.hangul = hangul
    session = HanjaIMESession(hangul: hangul, usage: usage,
      predict: dictionary.predictions) {
      dictionary.lookup($0)
    }
  }

  var candidates: [NSAttributedString]? {
    guard hasCandidates else { return nil }
    return session.candidates.enumerated().map { index, candidate in
      NSAttributedString(string: Self.label(candidate, reading: session.candidateReading), attributes: [
        Self.generationKey: NSNumber(value: session.generation),
        Self.indexKey: NSNumber(value: index),
        Self.readingKey: session.candidateReading,
      ])
    }
  }

  func clear() { session.clear() }
  func clearCompositionContext() { session.clear() }
  func cancelComposition() { session.commitCurrent() }
  func dequeueCommitString() -> String { session.takeCommit() }

  private func identity(_ candidate: NSAttributedString) -> (Int, UInt64)? {
    // Some clients strip custom attributes. Match only a currently displayed row.
    if candidate.length > 0,
      candidate.attribute(Self.generationKey, at: 0, effectiveRange: nil) == nil,
      session.reading.hasSuffix(session.candidateReading),
      let index = session.candidates.firstIndex(where: {
        Self.label($0, reading: session.candidateReading) == candidate.string
      }) { return (index, session.generation) }
    guard candidate.length > 0,
      let reading = candidate.attribute(Self.readingKey, at: 0, effectiveRange: nil) as? String,
      reading == session.candidateReading,
      let generation = candidate.attribute(Self.generationKey, at: 0, effectiveRange: nil) as? NSNumber,
      let index = candidate.attribute(Self.indexKey, at: 0, effectiveRange: nil) as? NSNumber,
      generation.uint64Value == session.generation,
      session.candidates.indices.contains(index.intValue),
      candidate.string == Self.label(session.candidates[index.intValue], reading: reading)
    else { return nil }
    return (index.intValue, generation.uint64Value)
  }

  private static func label(_ candidate: HanjaIMECandidate, reading: String) -> String {
    candidate.annotation.isEmpty || candidate.annotation == reading
      ? "\(candidate.value): \(reading)" : "\(candidate.value): \(reading) · \(candidate.annotation)"
  }

  func candidateSelected(_ candidate: NSAttributedString) {
    guard let (index, generation) = identity(candidate) else { return }
    session.choose(index: index, generation: generation)
  }

  func candidateSelectionChanged(_ candidate: NSAttributedString) {
    guard let (index, generation) = identity(candidate) else { return }
    session.highlight(index: index, generation: generation)
  }

  func input(text: String?, key: KeyCode, modifiers flags: NSEvent.ModifierFlags,
             client: IMKTextInput & IMKUnicodeTextInput) -> InputResult {
    hangul.prepareKoreanKeyboard()
    var flags = flags
    if let literal = Self.optionLiteral(key: key, modifiers: flags) {
      _ = session.handle(.literal(literal))
      return .processed
    }
    if flags.contains(.option), flags.intersection([.command, .control]).isEmpty {
      if let base = Self.keyText(key: key, modifiers: []),
        let yetKey = HanjaIMEOptionSymbols.yetKey(key: base, shift: flags.contains(.shift)) {
        let processed = session.handle(.text) {
          if self.hangul.inputYetKey(yetKey) { return true }
          // A missing/incompatible old-Hangul layout must not send an Option
          // Latin character to the host. Retry the same physical Korean key.
          HanjaIMEStorage.recordKeyboardRecovery("OptionRetry")
          self.hangul.setKeyboard(identifier: "2")
          var koreanFlags = flags
          koreanFlags.remove(.option)
          return self.hangul.input(text: base, key: key, modifiers: koreanFlags, client: client).processed
        }
        return processed ? .processed : InputResult(processed: false, action: .commit)
      }
      // Unassigned printable Option keys take the Korean physical-key path.
      if key.isKeyMappable || key == .space { flags.remove(.option) }
    }
    let modifiers = flags.intersection([.command, .control, .option])
    if !modifiers.isEmpty { session.commitCurrent(); return InputResult(processed: false, action: .commit) }
    if flags.contains(.shift), KeyCode.arrows.contains(key) || key == .pageUp || key == .pageDown {
      session.commitRaw()
      return InputResult(processed: false, action: .commit)
    }
    let automatic = Configuration.shared.object(forKey: "HanjaIME.AutoCandidates") as? Bool ?? true
    if session.automaticCandidates != automatic {
      session.automaticCandidates = automatic
      session.refresh()
    }
    // Event.characters can be empty or belong to a different underlying layout.
    // Use the same physical-key map as HangulComposer, including with Caps Lock.
    let mapped = Self.keyText(key: key, modifiers: flags)
    let action: HanjaIMEAction
    switch key {
    case .space: action = .space(preserveHangul: flags.contains(.shift))
    case .return, .ansiKeypadEnter: action = .enter
    case .escape: action = .escape
    case .delete: action = flags.contains(.function) ? .passThrough : .backspace
    case .downArrow: action = .next
    case .upArrow: action = .previous
    case .pageDown: action = .pageNext
    case .pageUp: action = .pagePrevious
    default:
      if let punctuation = Self.punctuation(key: key, shift: flags.contains(.shift)) {
        action = .literal(punctuation)
      } else if let mapped = mapped, ("1"..."9").contains(mapped), !flags.contains(.shift) {
        action = .number(Int(mapped)!)
      } else if let mapped = mapped, mapped.range(of: "^[A-Za-z]$", options: .regularExpression) != nil {
        action = .text
      } else if let mapped = mapped {
        action = .literal(mapped)
      } else {
        action = .passThrough
      }
    }
    let processed = session.handle(action) {
      self.hangul.input(text: mapped ?? text, key: key, modifiers: flags, client: client).processed
    }
    return processed ? .processed : InputResult(processed: false, action: .commit)
  }

  static func keyText(key: KeyCode, modifiers flags: NSEvent.ModifierFlags) -> String? {
    guard key.isKeyMappable else { return nil }
    return flags.contains(.shift) ? keyMapUpper[key.rawValue] : keyMapLower[key.rawValue]
  }

  static func optionLiteral(key: KeyCode, modifiers flags: NSEvent.ModifierFlags) -> String? {
    guard flags.contains(.option), flags.intersection([.command, .control]).isEmpty,
      key.isKeyMappable else { return nil }
    guard let letter = keyMapLower[key.rawValue] else { return nil }
    return HanjaIMEOptionSymbols.literal(key: letter, shift: flags.contains(.shift))
  }

  static func punctuation(key: KeyCode, shift: Bool) -> String? {
    // One table is the extension point for additional punctuation; modifiers are guarded above.
    let pairs: [KeyCode: (String, String)] = [
      .ansiComma: ("、", "〈"), .ansiPeriod: ("。", "〉"),
      .ansiLeftBracket: ("「", "『"), .ansiRightBracket: ("」", "』"),
      .ansiBackslash: ("・", "｜"), .ansiSemicolon: (";", ":"),
      .ansiQuote: ("'", "\"")
    ]
    guard let pair = pairs[key] else { return nil }
    return shift ? pair.1 : pair.0
  }
}

public enum HanjaIMEControls {
  public static func prepare() { _ = HanjaIMEExactDictionary.shared }
  public static var automaticCandidates: Bool {
    get { Configuration.shared.object(forKey: "HanjaIME.AutoCandidates") as? Bool ?? true }
    set { Configuration.shared.set(newValue, forKey: "HanjaIME.AutoCandidates") }
  }
  public static func resetLearning() { HanjaIMEUsageStore.shared.reset() }
  public static func flushLearning() { HanjaIMEUsageStore.shared.flush() }
  public static func registerWord(reading: String, value: String) -> Bool {
    HanjaIMEUsageStore.shared.register(reading: reading, value: value)
  }
  public static func removeWord(reading: String, value: String) -> Bool {
    HanjaIMEUsageStore.shared.removePersonal(reading: reading, value: value)
  }
}

private struct Entry: Comparable, Codable {
  var reading: String
  var value: String
  var category: String
  static func < (lhs: Entry, rhs: Entry) -> Bool {
    lhs.reading == rhs.reading ? lhs.value < rhs.value : lhs.reading < rhs.reading
  }
}

public final class HanjaIMEWordManagementViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  private let store: HanjaIMEUsageStore

  public convenience init() { self.init(store: .shared) }
  init(store: HanjaIMEUsageStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError("Use init") }
  private let categories: [HanjaIMECandidateCategory] = [.names, .hanja, .shinjitai, .symbols]
  private func categoryTitle(_ category: HanjaIMECandidateCategory) -> String {
    switch category {
    case .names: return HanjaIMEInterface.text("이름", "Names", "名前")
    case .hanja: return HanjaIMEInterface.text("한자", "Hanja", "漢字")
    case .shinjitai: return HanjaIMEInterface.text("신자체", "Japanese", "新字体")
    case .symbols: return HanjaIMEInterface.text("기호", "Symbols", "記号")
    default: return category.title
    }
  }
  private var editing: Entry?
  private var entries: [Entry] = []
  private let table = NSTableView()
  private let reading = NSTextField(string: "")
  private let value = NSTextField(string: "")
  private let category = NSPopUpButton()
  private let status = NSTextField(labelWithString: "")
  public override func loadView() {
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 460))
    view = content

    let scroll = NSScrollView(frame: NSRect(x: 18, y: 166, width: 644, height: 274))
    scroll.autoresizingMask = [.width, .height]
    table.addTableColumn(column(HanjaIMEInterface.text("독음", "Reading", "読み"), "reading", 175))
    table.addTableColumn(column(HanjaIMEInterface.text("변환", "Output", "変換"), "value", 175))
    table.addTableColumn(column(HanjaIMEInterface.text("분류", "Category", "分類"), "category", 150))
    table.delegate = self
    table.dataSource = self
    table.usesAlternatingRowBackgroundColors = true
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    content.addSubview(scroll)

    reading.placeholderString = HanjaIMEInterface.text("독음 (예: 가나다)", "Reading (e.g. 가나다)", "読み（例: 가나다）")
    reading.frame = NSRect(x: 18, y: 82, width: 180, height: 24)
    value.placeholderString = HanjaIMEInterface.text("변환 (예: 加那多)", "Output (e.g. 加那多)", "変換（例: 加那多）")
    value.frame = NSRect(x: 205, y: 82, width: 180, height: 24)
    category.addItems(withTitles: categories.map(categoryTitle))
    category.frame = NSRect(x: 392, y: 82, width: 95, height: 24)
    content.addSubview(reading); content.addSubview(value); content.addSubview(category)

    let add = button(HanjaIMEInterface.text("추가/수정", "Save", "保存"), #selector(saveEntry(_:)), NSRect(x: 494, y: 82, width: 108, height: 24))
    let remove = button(HanjaIMEInterface.text("선택 삭제", "Delete", "削除"), #selector(removeEntry(_:)), NSRect(x: 18, y: 46, width: 98, height: 24))
    let reset = button(HanjaIMEInterface.text("학습 초기화", "Reset learning", "学習をリセット"), #selector(resetLearning(_:)), NSRect(x: 123, y: 46, width: 98, height: 24))
    content.addSubview(add); content.addSubview(remove); content.addSubview(reset)
    content.addSubview(button(HanjaIMEInterface.text("새 항목", "New", "新規"), #selector(newEntry(_:)), NSRect(x: 228, y: 46, width: 98, height: 24)))
    content.addSubview(button(HanjaIMEInterface.text("단어 백업", "Export", "バックアップ"), #selector(exportWords(_:)), NSRect(x: 18, y: 122, width: 98, height: 24)))
    content.addSubview(button(HanjaIMEInterface.text("단어 가져오기", "Import", "読み込む"), #selector(importWords(_:)), NSRect(x: 123, y: 122, width: 115, height: 24)))
    content.addSubview(button(HanjaIMEInterface.text("입력기 진단", "Diagnostics", "診断"), #selector(diagnose(_:)), NSRect(x: 245, y: 122, width: 98, height: 24)))
    status.frame = NSRect(x: 18, y: 12, width: 644, height: 24)
    status.textColor = .secondaryLabelColor
    content.addSubview(status)
    reload()

  }

  private func column(_ title: String, _ id: String, _ width: CGFloat) -> NSTableColumn {
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
    column.title = title; column.width = width
    return column
  }

  private func button(_ title: String, _ action: Selector, _ frame: NSRect) -> NSButton {
    let button = NSButton(title: title, target: self, action: action)
    button.frame = frame
    return button
  }

  public override func viewWillAppear() { super.viewWillAppear(); reload() }

  private func reload() {
    entries = store.allPersonalWords().map {
      Entry(reading: $0.reading, value: $0.value, category: $0.category.storageValue)
    }.sorted()
    table.deselectAll(nil)
    table.reloadData()
    if let editing, let row = entries.firstIndex(of: editing) {
      table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }
  }

  public func tableViewSelectionDidChange(_ notification: Notification) {
    guard entries.indices.contains(table.selectedRow) else { return }
    let entry = entries[table.selectedRow]
    editing = entry
    reading.stringValue = entry.reading
    value.stringValue = entry.value
    category.selectItem(at: categories.firstIndex { $0.storageValue == entry.category } ?? 0)
  }

  @objc private func newEntry(_ sender: Any?) {
    editing = nil
    table.deselectAll(nil)
    reading.stringValue = ""
    value.stringValue = ""
    view.window?.makeFirstResponder(reading)
  }

  @objc private func saveEntry(_ sender: Any?) {
    let r = reading.stringValue.precomposedStringWithCanonicalMapping
    let v = value.stringValue.precomposedStringWithCanonicalMapping
    let selectedCategory = categories[max(0, category.indexOfSelectedItem)]
    guard store.register(reading: r, value: v, category: selectedCategory) else {
      status.stringValue = selectedCategory == .symbols ? HanjaIMEInterface.text("한글 독음과 기호·이모지를 입력해 주세요.", "Enter a Hangul reading and a symbol or emoji.", "ハングルの読みと記号・絵文字を入力してください。")
        : HanjaIMEInterface.text("한글 독음과 같은 글자 수의 한자를 입력해 주세요.", "Enter a Hangul reading and Hanja of the same length.", "読みと同じ文字数の漢字を入力してください。")
      return
    }
    if let old = editing, old.reading != r || old.value != v {
      _ = store.removePersonal(reading: old.reading, value: old.value)
    }
    editing = Entry(reading: r, value: v, category: selectedCategory.storageValue)
    status.stringValue = HanjaIMEInterface.text("저장됨 · 다음 입력부터 반영됩니다.", "Saved. Applied to subsequent input.", "保存しました。次の入力から反映します。")
    store.flush()
    reload()
  }

  @objc private func removeEntry(_ sender: Any?) {
    let row = table.selectedRow
    guard entries.indices.contains(row) else { status.stringValue = HanjaIMEInterface.text("삭제할 항목을 선택해 주세요.", "Select an entry to delete.", "削除する項目を選んでください。"); return }
    let entry = entries[row]
    _ = store.removePersonal(reading: entry.reading, value: entry.value)
    store.flush()
    newEntry(nil)
    status.stringValue = HanjaIMEInterface.text("삭제됨 · 다음 입력부터 반영됩니다.", "Deleted. Applied to subsequent input.", "削除しました。次の入力から反映します。")
    reload()
  }

  @objc private func resetLearning(_ sender: Any?) {
    let alert = NSAlert()
    alert.messageText = HanjaIMEInterface.text("후보 선택 학습을 초기화할까요?", "Reset candidate learning?", "候補の学習をリセットしますか？")
    alert.informativeText = HanjaIMEInterface.text("개인 단어와 공식 구름 설정은 유지됩니다.", "Your words and Gureum settings are kept.", "ユーザー辞書とGureumの設定は保持されます。")
    alert.addButton(withTitle: HanjaIMEInterface.text("초기화", "Reset", "リセット"))
    alert.addButton(withTitle: HanjaIMEInterface.text("취소", "Cancel", "キャンセル"))
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    store.reset()
    status.stringValue = HanjaIMEInterface.text("학습 우선순위를 초기화했습니다. 개인 단어는 유지됩니다.", "Learning reset. Your words are kept.", "学習をリセットしました。ユーザー辞書は保持します。")
  }

  @objc private func exportWords(_ sender: Any?) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "HanjaIME-words.json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      reload()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(entries).write(to: url, options: .atomic)
      status.stringValue = HanjaIMEInterface.text("개인 단어 백업 완료 (학습 기록 제외)", "Words exported (without learning history).", "ユーザー辞書を書き出しました（学習履歴を除く）。")
    } catch { status.stringValue = HanjaIMEInterface.text("백업 실패: ", "Export failed: ", "書き出し失敗: ") + error.localizedDescription }
  }

  @objc private func importWords(_ sender: Any?) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size <= 8_000_000 else { status.stringValue = HanjaIMEInterface.text("8 MB 이하 파일을 선택하세요.", "Select a file of 8 MB or less.", "8 MB以下のファイルを選んでください。"); return }
      let imported = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
      guard imported.count <= 128_000 else { status.stringValue = HanjaIMEInterface.text("단어 수 제한을 초과했습니다.", "Too many entries.", "単語数の制限を超えました。"); return }
      var accepted = 0
      for entry in imported {
        guard let type = categories.first(where: { $0.storageValue == entry.category }) else { continue }
        if store.register(reading: entry.reading, value: entry.value, category: type) { accepted += 1 }
      }
      store.flush()
      reload()
      status.stringValue = HanjaIMEInterface.text("가져오기 완료: ", "Imported: ", "読み込み完了: ") + String(accepted) + HanjaIMEInterface.text("개 / ", " / ", " / ") + String(imported.count) + HanjaIMEInterface.text("개 · 기존 단어 유지", " · existing words kept", " · 既存の単語は保持")
    } catch { status.stringValue = HanjaIMEInterface.text("가져오기 실패: ", "Import failed: ", "読み込み失敗: ") + error.localizedDescription }
  }

  @objc private func diagnose(_ sender: Any?) {
    // Only input-source metadata; never capture key strings or host text.
    let sources = TISCreateInputSourceList(nil, true).takeRetainedValue() as NSArray
    var lines = ["HanjaIME " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"),
      "macOS: " + ProcessInfo.processInfo.operatingSystemVersionString,
      HanjaIMEInterface.text("설정: ", "Settings: ", "設定: ") + HanjaIMEStorage.preferencesDomain,
      HanjaIMEInterface.text("학습: ", "Learning: ", "学習: ") + HanjaIMEStorage.learningDomain,
      HanjaIMEInterface.text("입력기: ", "Input method: ", "入力方式: ") + Bundle.main.bundlePath,
      HanjaIMEInterface.text("이 보고서는 등록 정보입니다. 실제 한글 입력 성공 여부를 판정하지 않습니다.", "This report contains registration metadata, not a live input test.", "このレポートは登録情報です。実際の入力の成否を判定するものではありません。")]
    for item in sources {
      let source = item as! TISInputSource
      func property(_ key: CFString) -> String {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return "" }
        return String(describing: Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue())
      }
      let id = property(kTISPropertyInputSourceID)
      let bundle = property(kTISPropertyBundleID)
      if (id + bundle).lowercased().contains("hanja") || (id + bundle).lowercased().contains("gureum") {
        lines.append([property(kTISPropertyLocalizedName), id, bundle,
          "enabled=" + property(kTISPropertyInputSourceIsEnabled),
          "selected=" + property(kTISPropertyInputSourceIsSelected)].joined(separator: " | "))
      }
    }
    if let defaults = UserDefaults(suiteName: HanjaIMEStorage.preferencesDomain) {
      for key in ["KoreanRetry", "OptionRetry", "LastRecovery"] {
        lines.append(key + ": " + String(describing: defaults.object(forKey: "HanjaIME.Diagnostics." + key) ?? 0))
      }
    }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "HanjaIME-diagnostics.txt"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
      status.stringValue = HanjaIMEInterface.text("진단 저장 완료 · 입력 내용은 수집하지 않습니다.", "Diagnostics saved. Typed text is not collected.", "診断を保存しました。入力内容は収集しません。")
    } catch { status.stringValue = HanjaIMEInterface.text("진단 저장 실패: ", "Diagnostics save failed: ", "診断の保存に失敗: ") + error.localizedDescription }
  }

  public func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
  public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard entries.indices.contains(row), let tableColumn else { return nil }
    let id = tableColumn.identifier
    let view = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
    view.identifier = id
    let label = (view.textField ?? NSTextField(labelWithString: ""))
    label.frame = NSRect(x: 4, y: 1, width: tableColumn.width - 8, height: 18)
    if label.superview == nil { view.addSubview(label); view.textField = label }
    let entry = entries[row]
    label.stringValue = id.rawValue == "reading" ? entry.reading : id.rawValue == "value" ? entry.value
      : categories.first { $0.storageValue == entry.category }.map(categoryTitle) ?? HanjaIMEInterface.text("이름", "Names", "名前")
    return view
  }
}
