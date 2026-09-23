import Cocoa
import InputMethodKit
import XCTest
@testable import GureumCore

final class HanjaIMEIntegrationTests: XCTestCase {
  var app: ModerateApp!
  var domain: String!
  var usage: HanjaIMEUsageStore!
  var savedModeProvider: (() -> String?)!
  var savedForegroundPID: (() -> pid_t?)!

  override func setUp() {
    super.setUp()
    savedForegroundPID = InputMethodServer.shared.hanjaPanel.foregroundPID
    InputMethodServer.shared.hanjaPanel.foregroundPID = { 100 }
    savedModeProvider = GureumComposer.selectedModeProvider
    GureumComposer.selectedModeProvider = { nil }
    domain = "org.hanjaime.tests." + UUID().uuidString
    Configuration.shared = Configuration(suiteName: domain)!
    usage = HanjaIMEUsageStore(defaults: UserDefaults(suiteName: domain)!)
    Configuration.shared.set(false, forKey: "HanjaIME.NaverFallback")
    app = ModerateApp()
    app.controller.receiver.composer = GureumComposer(usage: usage)
    app.controller.receiver.composer.inputMode = GureumInputSource.han2.rawValue
  }

  override func tearDown() {
    InputMethodServer.shared.hanjaPanel.hide()
    InputMethodServer.shared.hanjaPanel.foregroundPID = savedForegroundPID
    GureumComposer.selectedModeProvider = savedModeProvider
    app.controller.receiver.composer.clear()
    app = nil
    usage.flush()
    UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain)
    super.tearDown()
  }

  func testWeatherMeaningAndJapaneseCategory() {
    app.inputKeys("skfTl")
    let session = app.controller.receiver.composer.hanjaComposer.session
    XCTAssertEqual(session.reading, "날씨")
    XCTAssertTrue(session.candidates.contains { $0.value == "天氣" })
    XCTAssertTrue(session.candidates.contains { $0.value == "天気" && $0.kind == .japanese })
    session.setCategory(.shinjitai)
    XCTAssertTrue(session.candidates.contains { $0.value == "天気" })
  }

  func testActivationAfterABCWithoutModeTagBindsKoreanKeyboard() {
    let receiver = app.controller.receiver!
    GureumComposer.selectedModeProvider = { GureumInputSource.qwerty.rawValue }
    receiver.composer.delegate = receiver.composer.systemRomanComposer
    let before = app.client.keyboardOverrideCount
    receiver.activateKoreanContext(app.client)
    XCTAssertEqual(app.client.keyboardOverrideCount, before + 1)
    app.inputKeys("dkssudgktpdy")
    XCTAssertEqual(app.client.string, "안녕하세요")
  }

  func testRepeatedActivationPreservesPartialHangulAndShortcuts() {
    app.inputKeys("dk")
    app.controller.receiver.activateKoreanContext(app.client)
    app.inputKeys("s")
    XCTAssertEqual(app.client.string, "안")
    let result = app.controller.receiver.input(text: "a", key: .ansiA, modifiers: .command, client: app.client)
    XCTAssertFalse(result.processed)
    XCTAssertFalse(app.client.string.contains("a"))
  }

  func testThreePartVersionsAndChangelogOncePerUpgrade() {
    XCTAssertTrue(HanjaIMEInterface.isNewer("v0.8.14", than: "0.8.9"))
    XCTAssertFalse(HanjaIMEInterface.isNewer("0.8.9", than: "0.8.14"))
    for malformed in ["0.8", "0.8.14.1", "0.8.14-beta", "-1.0.0", "1.x.0"] {
      XCTAssertNil(HanjaIMEInterface.versionComponents(malformed))
    }
    XCTAssertTrue(HanjaIMEInterface.shouldShowChangelog(current: "0.8.14", seen: nil))
    XCTAssertTrue(HanjaIMEInterface.shouldShowChangelog(current: "0.8.14", seen: "0.8.13"))
    XCTAssertFalse(HanjaIMEInterface.shouldShowChangelog(current: "0.8.14", seen: "0.8.14"))
    XCTAssertFalse(HanjaIMEInterface.shouldShowChangelog(current: "0.8.13", seen: "0.8.14"))
  }

  func testInterfaceLanguageDoesNotChangeKoreanInput() {
    for language in ["ko", "en", "ja"] {
      HanjaIMEInterface.language = language
      XCTAssertEqual(HanjaIMEInterface.language, language)
      app.controller.receiver.composer.clear()
      app.client.string = ""
      app.inputKeys("alrnr")
      XCTAssertEqual(app.client.string, "미국")
    }
    HanjaIMEInterface.language = "unsupported"
    XCTAssertEqual(HanjaIMEInterface.language, "ko")
  }

  func testNaverLinksEncodeOnlySelectedTermAndRestrictNavigation() throws {
    let candidate = HanjaIMECandidate(value: "天気", annotation: "날씨", kind: .japanese)
    let request = HanjaIMEDefinitionRequest(candidate: candidate, reading: "날씨 뒤의 다른 문장")
    let url = try XCTUnwrap(HanjaIMEDictionaryLink.naver(request))
    XCTAssertEqual(url.host, "ja.dict.naver.com")
    XCTAssertEqual(url.fragment?.removingPercentEncoding, "/search?query=天気")
    XCTAssertFalse(url.absoluteString.contains("%EB%92%A4"))
    let special = HanjaIMEDefinitionRequest(candidate: HanjaIMECandidate(value: "字&x=#?%", annotation: ""), reading: "자")
    let escaped = try XCTUnwrap(HanjaIMEDictionaryLink.naver(special))
    XCTAssertTrue(escaped.absoluteString.contains("%26"))
    XCTAssertTrue(HanjaIMEDictionaryLink.isAllowed(url))
    XCTAssertFalse(HanjaIMEDictionaryLink.isAllowed(URL(string: "https://dict.naver.com.attacker.invalid/")!))
    XCTAssertFalse(HanjaIMEDictionaryLink.isAllowed(URL(string: "http://dict.naver.com/")!))
    XCTAssertFalse(HanjaIMEDictionaryLink.isAllowed(URL(string: "file:///tmp/example")!))
  }

  func testIntegratedPersonalWordsSaveWithoutStandaloneApplication() throws {
    let controller = HanjaIMEWordManagementViewController(store: usage)
    let view = controller.view
    let fields = view.subviews.compactMap { $0 as? NSTextField }
    let reading = try XCTUnwrap(fields.first { $0.placeholderString?.contains("독음") == true })
    let value = try XCTUnwrap(fields.first { $0.placeholderString?.contains("변환") == true })
    reading.stringValue = "가나다"; value.stringValue = "加那多"
    let save = try XCTUnwrap(view.subviews.compactMap { $0 as? NSButton }.first { $0.title == "추가/수정" })
    save.performClick(nil)
    XCTAssertEqual(usage.personalCandidates(reading: "가나다").first?.value, "加那多")
    let reloaded = HanjaIMEUsageStore(defaults: UserDefaults(suiteName: domain)!)
    XCTAssertEqual(reloaded.personalCandidates(reading: "가나다").first?.value, "加那多")
  }

  func testCandidatePanelStopsRecoveryAfterHostSwitch() {
    app.inputKeys("durtk")
    let ui = InputMethodServer.shared.hanjaPanel
    XCTAssertTrue(ui.isVisible)
    ui.foregroundPID = { 200 }
    let deadline = Date().addingTimeInterval(2)
    while ui.isVisible && Date() < deadline {
      RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    XCTAssertFalse(ui.isVisible)
  }

  func testRelatedEmojiCountriesAndOrdinaryWords() {
    let required = ["미국": ["🇺🇸", "🗽"], "영국": ["🇬🇧", "💷", "💂", "🇮🇴", "🇦🇺", "🇳🇿"],
                    "유럽": ["🇪🇺"], "사랑": ["❤️"], "바다": ["🌊"], "강아지": ["🐶"]]
    for (reading, values) in required {
      let candidates = HanjaIMERanking.rank(HanjaIMEEmojiLexicon.candidates(for: reading), reading: reading, counts: [:])
      for value in values { XCTAssertTrue(candidates.contains { $0.value == value }, "\(reading): \(value)") }
    }
    app.inputKeys("alrnr")
    let session = app.controller.receiver.composer.hanjaComposer.session
    session.setCategory(.symbols)
    XCTAssertTrue(session.candidates.contains { $0.value == "🇺🇸" })
    XCTAssertTrue(session.candidates.contains { $0.value == "🗽" })
  }

  func testForeignNameAndNativeKoreanSemanticCandidates() {
    app.inputKeys("epsakzm")
    let session = app.controller.receiver.composer.hanjaComposer.session
    XCTAssertEqual(session.reading, "덴마크")
    for value in ["丁抹", "丹麥", "🇩🇰"] { XCTAssertTrue(session.candidates.contains { $0.value == value }) }
    XCTAssertTrue(HanjaIMERanking.semanticCandidates(for: "하늘").contains { $0.value == "天" })
    XCTAssertTrue(HanjaIMERanking.semanticCandidates(for: "바다").contains { $0.value == "海" })
  }

  func testFreshInstallHasNoPersonalDictionarySeed() {
    XCTAssertTrue(usage.personalCandidates(reading: "가나다").isEmpty)
    XCTAssertTrue(usage.register(reading: "가나다", value: "加那多"))
    usage.flush()
    let restored = HanjaIMEUsageStore(defaults: UserDefaults(suiteName: domain)!)
    XCTAssertEqual(restored.personalCandidates(reading: "가나다").first?.value, "加那多")
  }

  func testActualCKeyboardDriftIsRepairedForEveryPhysicalKey() {
    for key in "dkssudgktpdy" {
      app.controller.receiver.composer.hangulComposer.inputContext.setKeyboardWithIdentifier("ro")
      app.inputKeys(String(key))
    }
    XCTAssertEqual(app.controller.receiver.composer.hanjaComposer.session.reading, "안녕하세요")
  }

  func testCountryPersonSuffixAndInflectionCandidates() {
    app.inputKeys("dudrnrdls")
    let session = app.controller.receiver.composer.hanjaComposer.session
    XCTAssertEqual(session.reading, "영국인")
    XCTAssertTrue(session.candidates.contains { $0.value == "英國人" })
    XCTAssertTrue(session.candidates.contains { $0.value == "英國인" })
    app.inputKeys("dlfkrh")
    XCTAssertEqual(session.reading, "영국인이라고")
    XCTAssertTrue(session.candidates.contains { $0.value == "英國人이라고" })
  }

  func testProductiveSuffixesRetainExactAndParticleAlternatives() {
    let exact: (String) -> [HanjaIMECandidate] = { reading in
      switch reading {
      case "미국": return [HanjaIMECandidate(value: "美國", annotation: "아메리카합중국")]
      case "문화": return [HanjaIMECandidate(value: "文化", annotation: "문화")]
      default: return []
      }
    }
    XCTAssertEqual(HanjaIMECompound.candidates(reading: "미국인", exact: exact).first?.value, "美國人")
    XCTAssertEqual(HanjaIMECompound.candidates(reading: "문화적", exact: exact).first?.value, "文化的")
    XCTAssertTrue(HanjaIMECompound.candidates(reading: "미국은", exact: exact).isEmpty)
    XCTAssertTrue(HanjaIMECompound.candidates(reading: "가나다인", exact: exact).isEmpty)
  }

  func testCandidateAnnotationsShowMeaningAndCharacterReadings() throws {
    app.inputKeys("alrnr")
    let candidates = app.controller.receiver.composer.hanjaComposer.session.candidates
    XCTAssertEqual(candidates.first?.value, "美國")
    let america = try XCTUnwrap(candidates.first { $0.value == "美國" })
    let rice = try XCTUnwrap(candidates.first { $0.value == "米麴" })
    XCTAssertEqual(HanjaIMECandidatePanel.annotation(for: america, reading: "미국"), "아메리카합중국")
    XCTAssertTrue(rice.annotation.contains("쌀 미"))
    XCTAssertTrue(rice.annotation.contains("누룩 국"))
    let content = try XCTUnwrap(InputMethodServer.shared.hanjaPanel.panel.contentView)
    let buttons = content.subviews.flatMap { $0.subviews }.compactMap { $0 as? NSButton }
    XCTAssertTrue(buttons.contains { $0.attributedTitle.string.contains("아메리카합중국") })
  }

  func testDelayedWebViewGeometryRecoversAfterInitialRetryBudget() throws {
    let ui = InputMethodServer.shared.hanjaPanel
    app.client.useSimulatedAttributeCaret = true
    app.client.simulatedAttributeCaret = .zero
    app.inputKeys("durtk")
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    XCTAssertFalse(ui.isVisible)
    let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first).visibleFrame
    app.client.expectedAttributeIndex = try XCTUnwrap(UInt(exactly: app.client.selectedRange().location))
    app.client.simulatedAttributeCaret = NSRect(x: screen.midX, y: screen.maxY - 90, width: 1, height: 20)
    let deadline = Date().addingTimeInterval(2)
    while !ui.isVisible && Date() < deadline {
      RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    XCTAssertTrue(ui.isVisible, "Delayed web-view geometry must recover without another key event")
    XCTAssertEqual(ui.panel.frame.minX, app.client.simulatedAttributeCaret.minX)
    ui.hide()
    RunLoop.main.run(until: Date().addingTimeInterval(0.16))
    XCTAssertFalse(ui.isVisible, "Recovery must stop when the composition is hidden")
  }

  func testDefaultStorageDomainsAndBundleIDInitialization() {
    XCTAssertNotEqual(Configuration.sharedSuiteName, Bundle.main.bundleIdentifier)
    XCTAssertNotEqual(HanjaIMEUsageStore.domain, Bundle.main.bundleIdentifier)
    XCTAssertNotEqual(Configuration.sharedSuiteName, HanjaIMEUsageStore.domain)
    XCTAssertNotNil(Configuration(suiteName: Bundle.main.bundleIdentifier))
    XCTAssertEqual(app.controller.receiver.composer.inputMode, GureumInputSource.han2.rawValue)
    Configuration.shared.inputModeExchangeKey = (.space, .command)
    XCTAssertEqual(Configuration.shared.inputModeExchangeKey?.0, KeyCode.space)
    XCTAssertEqual(Configuration.shared.inputModeExchangeKey?.1, NSEvent.ModifierFlags.command)
    XCTAssertNil(Configuration.convertConfigurationToShortcut(["modifier": -1, "keyCode": 49]))
    XCTAssertNil(Configuration.convertConfigurationToShortcut(["modifier": 1.5, "keyCode": 49]))
  }

  func testFreshProcessDefaultsToKoreanAndComposesPhysicalKeys() {
    let fresh = GureumComposer(usage: usage)
    XCTAssertEqual(fresh.inputMode, GureumInputSource.han2.rawValue)
    XCTAssertTrue(fresh.delegate is HanjaIMEComposer)
    app.controller.receiver.composer = fresh
    app.inputKeys("dkssudgktpdy")
    XCTAssertEqual(app.controller.receiver.composer.composedString, "안녕하세요")
    XCTAssertNotEqual(app.controller.receiver.composer.composedString, "dkssudgktpdy")
  }

  func testPredictionStringsOutliveNativeDictionaryLists() {
    for _ in 0..<100 {
      let candidates: [HanjaIMECandidate] = autoreleasepool {
        HanjaIMEExactDictionary.shared.predictions("역사")
      }
      XCTAssertTrue(candidates.contains { $0.value == "歷史家" })
      XCTAssertTrue(candidates.allSatisfy { $0.annotation.hasPrefix("역사") })
      XCTAssertFalse(candidates.contains { $0.value == "歷史" })
    }
  }

  func testRelatedBookEmojiAreCandidatesNotDictionaryButtons() {
    app.inputKeys("cor")
    let values = app.controller.receiver.composer.hanjaComposer.session.candidates.map(\.value)
    XCTAssertTrue(values.contains("📕"))
    XCTAssertTrue(values.contains("📖"))
    XCTAssertTrue(values.contains("📗"))
    XCTAssertTrue(values.contains("📘"))
    XCTAssertTrue(values.contains("📚"))
  }

  func testSpacePreviewsThenEnterCommits() {
    for (keys, result) in [("eogksalsrnr", "大韓民國"), ("durtk", "歷史"),
                           ("wjdcl", "政治"), ("tktkd", "思想"),
                           ("dusrn", "硏究"), ("wprnr", "帝國")] {
      app.controller.receiver.composer.clear()
      app.client.string = ""
      app.inputKeys(keys)
      XCTAssertTrue(app.controller.receiver.composer.hasCandidates)
      XCTAssertTrue(app.inputText(" ", key: .space, modifiers: []))
      XCTAssertEqual(app.client.string, result)
      XCTAssertTrue(app.controller.receiver.composer.hanjaComposer.session.selectionEngaged)
      XCTAssertTrue(usage.snapshot(reading: app.controller.receiver.composer.hanjaComposer.session.reading).isEmpty)
      XCTAssertTrue(app.inputText("\r", key: .return, modifiers: []))
      XCTAssertFalse(app.client.hasMarkedText())
      XCTAssertFalse(app.inputText(" ", key: .space, modifiers: []))
      XCTAssertEqual(app.client.string, result + " ")
    }
  }

  func testNativeHangulSpace() {
    // 안녕하세요 has the requested 安寧 + 하세요 candidate. Use words
    // without dictionary candidates to exercise ordinary Hangul spacing.
    for (keys, reading) in [("rhakdnjdy", "고마워요"), ("djqtdjdy", "없어요")] {
      app.controller.receiver.composer.clear()
      app.client.string = ""
      app.inputKeys(keys)
      XCTAssertEqual(app.controller.receiver.composer.composedString, reading)
      XCTAssertFalse(app.controller.receiver.composer.hasCandidates)
      XCTAssertTrue(app.inputText(" ", key: .space, modifiers: []))
      XCTAssertEqual(app.client.string, reading + " ")
      XCTAssertTrue(app.client.hasMarkedText())
      XCTAssertTrue(app.inputText("\r", key: .return, modifiers: []))
      XCTAssertEqual(app.client.string, reading + " ")
      XCTAssertFalse(app.client.hasMarkedText())
    }
  }

  func testInflectedGreetingSpacePreviewsThenEnterCommits() {
    app.inputKeys("dkssudgktpdy")
    let session = app.controller.receiver.composer.hanjaComposer.session
    XCTAssertEqual(session.reading, "안녕하세요")
    XCTAssertTrue(app.controller.receiver.composer.hasCandidates)
    XCTAssertEqual(session.candidates.first?.value, "安寧하세요")
    XCTAssertTrue(app.inputText(" ", key: .space, modifiers: []))
    XCTAssertEqual(app.client.string, "安寧하세요")
    XCTAssertTrue(app.client.hasMarkedText())
    XCTAssertTrue(session.selectionEngaged)
    XCTAssertEqual(session.reading, "안녕하세요")
    XCTAssertTrue(usage.snapshot(reading: "안녕").isEmpty)
    XCTAssertTrue(app.inputText("\r", key: .return, modifiers: []))
    XCTAssertEqual(app.client.string, "安寧하세요")
    XCTAssertFalse(app.client.hasMarkedText())
    XCTAssertEqual(usage.snapshot(reading: "안녕")["安寧"], 1)
    XCTAssertTrue(usage.snapshot(reading: "안녕하세요").isEmpty)
    XCTAssertFalse(app.inputText(" ", key: .space, modifiers: []))
    XCTAssertEqual(app.client.string, "安寧하세요 ")
  }

  func testGreetingShiftSpacePreservesHangulBeforeAndDuringPreview() {
    for previewFirst in [false, true] {
      app.controller.receiver.composer.clear()
      app.client.string = ""
      app.inputKeys("dkssudgktpdy")
      if previewFirst {
        XCTAssertTrue(app.inputText(" ", key: .space, modifiers: []))
        XCTAssertEqual(app.client.string, "安寧하세요")
      }
      XCTAssertTrue(app.inputText(" ", key: .space, modifiers: [.shift]))
      XCTAssertEqual(app.client.string, "안녕하세요 ")
      XCTAssertTrue(app.client.hasMarkedText())
      XCTAssertTrue(app.inputText("\r", key: .return, modifiers: []))
      XCTAssertEqual(app.client.string, "안녕하세요 ")
      XCTAssertFalse(app.client.hasMarkedText())
      XCTAssertTrue(usage.snapshot(reading: "안녕").isEmpty)
    }
  }

  func testPreserveEnterEscapeAndShiftSpace() {
    for (key, flags, expected) in [(KeyCode.return, NSEvent.ModifierFlags(), "역사"),
                                   (.escape, [], "역사"), (.space, [.shift], "역사 ")] {
      app.controller.receiver.composer.clear()
      app.client.string = ""
      app.inputKeys("durtk")
      XCTAssertTrue(app.inputText("", key: key, modifiers: flags))
      XCTAssertEqual(app.client.string, expected)
    }
  }

  func testArrowThenEnterAndLearning() {
    app.inputKeys("durtk")
    app.inputText(nil, key: .downArrow, modifiers: [])
    app.inputText(nil, key: .downArrow, modifiers: [])
    app.inputText("\r", key: .return, modifiers: [])
    XCTAssertEqual(app.client.string, "役事")
    XCTAssertEqual(usage.snapshot(reading: "역사")["役事"], 1)
    app.inputKeys("durtk")
    XCTAssertEqual(app.controller.receiver.composer.hanjaComposer.session.candidates.first?.value, "役事")
  }

  func testBackspaceAndPunctuation() {
    app.inputKeys("durtkr")
    app.inputDelete()
    XCTAssertEqual(app.controller.receiver.composer.composedString, "역사")
    app.inputText(".", key: .ansiPeriod, modifiers: [])
    XCTAssertEqual(app.client.string, "역사。")
    app.inputText("[", key: .ansiLeftBracket, modifiers: [])
    app.inputText("]", key: .ansiRightBracket, modifiers: [.shift])
    XCTAssertEqual(app.client.string, "역사。「』")
  }

  func testNumericTextAndExplicitNumericSelection() {
    app.inputKeys("durtk")
    app.inputText("2", key: .ansi2, modifiers: [])
    XCTAssertEqual(app.client.string, "역사2")
    app.controller.receiver.composer.clear()
    app.client.string = ""
    app.inputKeys("durtk")
    app.inputText(nil, key: .downArrow, modifiers: [])
    app.inputText("2", key: .ansi2, modifiers: [])
    XCTAssertEqual(app.client.string, "役事")
  }

  func testInternalRomanToggleIsDisabled() {
    app.inputKeys("durtk")
    let result = app.controller.receiver.composer.changeLayout(.toggle, client: app.client)
    XCTAssertFalse(result.processed)
    XCTAssertTrue(app.controller.receiver.composer.delegate is HanjaIMEComposer)
    app.inputText("[", key: .ansiLeftBracket, modifiers: [])
    XCTAssertEqual(app.client.string, "역사「")
  }

  func testStaleCallbackAndCommandKey() {
    app.inputKeys("durtk")
    let old = app.controller.receiver.composer.candidates!.first!
    app.inputKeys("r")
    app.controller.candidateSelected(old)
    XCTAssertEqual(app.controller.receiver.composer.composedString, "역삭")
    XCTAssertTrue(usage.snapshot(reading: "역사").isEmpty)
    XCTAssertFalse(app.inputText(".", key: .ansiPeriod, modifiers: .command))
    XCTAssertEqual(app.client.string, "역삭")
  }

  func testSpaceCyclesThenEnterCommits() {
    app.inputKeys("durtk")
    app.inputText(" ", key: .space, modifiers: [])
    app.inputText(" ", key: .space, modifiers: [])
    XCTAssertEqual(app.client.string, "役事")
    XCTAssertEqual(app.controller.receiver.composer.hanjaComposer.session.reading, "역사")
    XCTAssertTrue(usage.snapshot(reading: "역사").isEmpty)
    app.inputText("\r", key: .return, modifiers: [])
    XCTAssertEqual(app.client.string, "役事")
    XCTAssertEqual(usage.snapshot(reading: "역사")["役事"], 1)
  }
  func testParticlesAndTypingAfterPreview() {
    for keys in ["sms", "dms", "dl", "rk", "dmf", "fmf", "dptj", "Rkwl"] {
      app.controller.receiver.composer.clear()
      app.client.string = ""
      app.inputKeys(keys)
      let reading = app.controller.receiver.composer.hanjaComposer.session.reading
      XCTAssertFalse(app.controller.receiver.composer.hasCandidates)
      app.inputText(" ", key: .space, modifiers: [])
      XCTAssertEqual(app.client.string, reading + " ")
    }
    app.controller.receiver.composer.clear()
    app.client.string = ""
    app.inputKeys("durtk")
    app.inputText(" ", key: .space, modifiers: [])
    app.inputKeys("fmf")
    app.inputText(" ", key: .space, modifiers: [])
    XCTAssertEqual(app.client.string, "歷史를 ")
  }
  func testOptionLiteralsFlushTheFinalSyllable() {
    for (key, flags, symbol) in [(KeyCode.ansiSemicolon, NSEvent.ModifierFlags.option, "…"),
                                (.ansiE, .option, "ㅼ"), (.ansiE, [.option, .shift], "ㅼ")] {
      app.controller.receiver.composer.clear()
      app.client.string = ""
      app.inputKeys("durtk")
      XCTAssertTrue(app.inputText(nil, key: key, modifiers: flags))
      XCTAssertEqual(app.client.string, "역사" + symbol)
      XCTAssertTrue(app.client.hasMarkedText())
      app.inputKeys("rk")
      app.inputText("\r", key: .return, modifiers: [])
      XCTAssertEqual(app.client.string, "역사" + symbol + "가")
    }
    XCTAssertNil(HanjaIMEComposer.optionLiteral(key: .ansiE, modifiers: [.option, .command]))
    XCTAssertNil(HanjaIMEComposer.optionLiteral(key: .ansiE, modifiers: [.option, .control]))
    XCTAssertNil(HanjaIMEComposer.optionLiteral(key: .ansiE, modifiers: []))
  }
  func testCaretAndEnterAtNonzeroOffset() {
    app.client.string = "앞 😀 "
    app.client.setSelectedRange(NSRange(location: app.client.string.utf16.count, length: 0))
    app.inputKeys("dkssudgktpdy")
    XCTAssertEqual(app.client.selectedRange().length, 0)
    XCTAssertEqual(app.client.selectedRange().location, app.client.string.utf16.count)
    XCTAssertTrue(app.inputText("\r", key: .return, modifiers: []))
    XCTAssertEqual(app.client.string, "앞 😀 안녕하세요")
    XCTAssertFalse(app.client.hasMarkedText())
    XCTAssertFalse(app.inputText("\n", key: .return, modifiers: []))
    XCTAssertEqual(app.client.string, "앞 😀 안녕하세요\n")
  }
  func testEmojiPreviewUsesUTF16() {
    app.inputKeys("rhdiddl")
    let composer = app.controller.receiver.composer.hanjaComposer
    let index = composer.session.candidates.firstIndex { $0.value == "🐈" }!
    composer.session.highlight(index: index, generation: composer.session.generation)
    app.controller.updateComposition()
    XCTAssertEqual(app.client.string, "🐈")
    XCTAssertEqual(app.client.selectedRange(), NSRange(location: 2, length: 0))
    app.inputText("\r", key: .return, modifiers: [])
    XCTAssertEqual(app.client.string, "🐈")
    XCTAssertFalse(app.client.hasMarkedText())
  }
  func testEscapeAndNativeHighlightCallbacks() {
    app.inputKeys("durtk")
    app.controller.candidateSelectionChanged(app.controller.receiver.composer.candidates!.first!)
    XCTAssertFalse(app.controller.receiver.composer.hanjaComposer.session.selectionEngaged)
    app.inputText(" ", key: .space, modifiers: [])
    app.inputText("", key: .escape, modifiers: [])
    XCTAssertEqual(app.client.string, "역사")
    XCTAssertEqual(app.client.selectedRange().length, 0)
    app.inputText("\r", key: .return, modifiers: [])
    XCTAssertEqual(app.client.string, "역사")
  }
  func testRealKeyEventAndPlainMouseCandidate() {
    app.inputKeys("durtk")
    for _ in 0..<2 {
      let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: [.numericPad, .function], timestamp: 0, windowNumber: 0,
        context: nil, characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}",
        isARepeat: false, keyCode: UInt16(KeyCode.downArrow.rawValue))!
      XCTAssertTrue(app.controller.handle(event, client: app.client))
    }
    XCTAssertEqual(app.client.string, "役事")
    let candidate = app.controller.receiver.composer.candidates![1]
    app.controller.candidateSelected(NSAttributedString(string: candidate.string))
    XCTAssertEqual(app.client.string, "役事")
    XCTAssertFalse(app.client.hasMarkedText())
  }
  func testExternalAndCommandCommitPreserveLastSyllable() {
    app.inputKeys("durtk")
    app.controller.commitComposition(app.client)
    XCTAssertEqual(app.client.string, "역사")
    XCTAssertFalse(app.client.hasMarkedText())
    app.controller.commitComposition(app.client)
    XCTAssertEqual(app.client.string, "역사")
    app.inputKeys("rk")
    XCTAssertFalse(app.inputText("c", key: .ansiC, modifiers: .command))
    XCTAssertEqual(app.client.string, "역사가")
  }
  func testOptionAlphabetNeverMapsToRoman() {
    for legacyBehavior in [0, 1] {
      Configuration.shared.optionKeyBehavior = legacyBehavior
      for flags: NSEvent.ModifierFlags in [.option, [.option, .shift], [.option, .capsLock]] {
        for character in "abcdefghijklmnopqrstuvwxyz" {
          app.controller.receiver.composer.clear()
          app.controller.receiver.composer.clear()
      app.client.string = ""
          let key = keyMapReversed[String(character)]!.0
          XCTAssertTrue(app.inputText("LatinFallback", key: key, modifiers: flags))
          XCTAssertFalse(app.client.string.isEmpty)
          XCTAssertNil(app.client.string.range(of: "[A-Za-z]", options: .regularExpression))
          XCTAssertEqual(app.controller.receiver.composer.inputMode, GureumInputSource.han2.rawValue)
        }
      }
    }
  }

  func testOptionYetgeulComposesAraeaSyllable() {
    app.inputKeys("r")
    XCTAssertTrue(app.inputText(nil, key: .ansiK, modifiers: .option))
    app.inputKeys("s")
    XCTAssertEqual(app.controller.receiver.composer.composedString, "ᄀᆞᆫ")
    XCTAssertTrue(app.inputText("\r", key: .return, modifiers: []))
    XCTAssertEqual(app.client.string, "ᄀᆞᆫ")
    XCTAssertFalse(app.client.hasMarkedText())
    app.inputKeys("rk")
    XCTAssertTrue(app.inputText("\r", key: .return, modifiers: []))
    XCTAssertEqual(app.client.string, "ᄀᆞᆫ가")
  }

  func testModeReconciliationAndEscapeStayKorean() {
    app.controller.receiver.composer.inputMode = GureumInputSource.qwerty.rawValue
    GureumComposer.selectedModeProvider = { GureumInputSource.han2.rawValue }
    Configuration.shared.romanModeByEscapeKey = true
    _ = app.inputText("", key: .escape, modifiers: [])
    app.inputKeys("dkssudgktpdy")
    XCTAssertEqual(app.controller.receiver.composer.composedString, "안녕하세요")
    XCTAssertTrue(app.controller.receiver.composer.delegate is HanjaIMEComposer)
  }

  func testOptionDoesNotActivateStaleRomanShortcut() {
    Configuration.shared.inputModeEnglishKey = (.ansiA, .option)
    XCTAssertTrue(app.inputText("a", key: .ansiA, modifiers: .option))
    XCTAssertTrue(app.controller.receiver.composer.delegate is HanjaIMEComposer)
    XCTAssertNil(app.client.string.range(of: "[A-Za-z]", options: .regularExpression))
    app.inputKeys("k")
    _ = app.inputText("\r", key: .return, modifiers: [])
    let saved = app.client.string
    XCTAssertFalse(app.inputText("e", key: .ansiE, modifiers: [.command, .option]))
    XCTAssertEqual(app.client.string, saved)
  }

  func testCandidateCategoriesUseDisplayedSelection() {
    app.inputKeys("cor")
    let composer = app.controller.receiver.composer.hanjaComposer
    composer.session.setCategory(.symbols)
    XCTAssertFalse(composer.session.candidates.isEmpty)
    XCTAssertTrue(composer.session.candidates.allSatisfy { $0.kind == .emoji || $0.kind == .symbol || $0.kind == .kaomoji })
    let expected = composer.session.candidates[0].value
    _ = app.inputText(" ", key: .space, modifiers: [])
    _ = app.inputText("\r", key: .return, modifiers: [])
    XCTAssertEqual(app.client.string, expected)
  }

  func testCandidatePanelHasTabsAndRealBookButtons() throws {
    app.inputKeys("dkssudgktpdy")
    let ui = InputMethodServer.shared.hanjaPanel
    XCTAssertTrue(ui.isVisible)
    XCTAssertGreaterThan(ui.bookButtonCount, 0)
    let content = try XCTUnwrap(ui.panel.contentView)
    let tabs = content.subviews.compactMap { $0 as? NSSegmentedControl }.first
    XCTAssertEqual(tabs != nil, ui.visibleRowCount >= 5)
    if let tabs {
      XCTAssertEqual(tabs.segmentCount, 5)
      XCTAssertEqual((0..<5).map { tabs.label(forSegment: $0) }, ["표준", "한자", "이름", "신자체", "기호"])
    } else {
      let categories = try XCTUnwrap(content.subviews.compactMap { $0 as? NSPopUpButton }.first)
      XCTAssertEqual(categories.itemTitles, ["표준", "한자", "이름", "신자체", "기호"])
      XCTAssertLessThan(ui.visibleRowCount, 5)
    }
    let buttons = content.subviews.flatMap { $0.subviews }.compactMap { $0 as? NSButton }
    let book = try XCTUnwrap(buttons.first { $0.image != nil && ($0.toolTip ?? "").contains("Apple 사전") })
    book.performClick(nil)
    XCTAssertTrue(app.client.hasMarkedText())
    XCTAssertEqual(app.client.string, "安寧하세요")
    XCTAssertTrue(usage.snapshot(reading: "안녕").isEmpty)
  }

  func testSentencePrefixSurvivesInlineConversionAndSymbolSelection() {
    app.inputKeys("durtk")
    app.inputText("[", key: .ansiLeftBracket, modifiers: [])
    app.inputKeys("wjdcl")
    app.inputText(" ", key: .space, modifiers: [])
    app.inputKeys("rk")
    XCTAssertEqual(app.client.string, "역사「政治가")
    XCTAssertTrue(app.client.hasMarkedText())
    app.inputText("\r", key: .return, modifiers: [])
    XCTAssertEqual(app.client.string, "역사「政治가")
    XCTAssertFalse(app.client.hasMarkedText())
  }

  func testManyCandidatesShowCategoryTabs() throws {
    app.inputKeys("wl")
    let session = app.controller.receiver.composer.hanjaComposer.session
    XCTAssertGreaterThanOrEqual(session.unfilteredCandidateCount, 5)
    let content = try XCTUnwrap(InputMethodServer.shared.hanjaPanel.panel.contentView)
    let tabs = try XCTUnwrap(content.subviews.compactMap { $0 as? NSSegmentedControl }.first)
    XCTAssertEqual(tabs.segmentCount, 5)
  }

  func testRelatedSymbolGroupsStayInTheMarkedSession() {
    app.inputKeys("durtk")
    XCTAssertTrue(app.inputText("[", key: .ansiLeftBracket, modifiers: []))
    let composer = app.controller.receiver.composer.hanjaComposer
    XCTAssertEqual(composer.session.reading, "역사「")
    XCTAssertTrue(composer.session.candidates.contains { $0.value == "『" })
    XCTAssertTrue(app.client.hasMarkedText())
  }

  func testMeaningPredictionVariantsAndNames() {
    let composer = app.controller.receiver.composer.hanjaComposer
    app.inputKeys("tkfkd")
    XCTAssertTrue(composer.session.candidates.contains { $0.value == "愛" && $0.semantic })
    app.controller.receiver.composer.clear(); app.client.string = ""
    app.inputKeys("wl")
    XCTAssertTrue(composer.session.candidates.contains { $0.value == "地圖" && $0.predicted })
    app.controller.receiver.composer.clear(); app.client.string = ""
    app.inputKeys("rnr")
    XCTAssertTrue(composer.session.candidates.contains { $0.value == "國" })
    composer.session.setCategory(.shinjitai)
    XCTAssertTrue(composer.session.candidates.contains { $0.value == "国" && $0.kind == .japanese })
    XCTAssertTrue(usage.register(reading: "김좌진", value: "金佐鎭", category: .names))
    app.controller.receiver.composer.clear(); app.client.string = ""
    app.inputKeys("rla"); app.inputKeys("whk"); app.inputKeys("wls")
    composer.session.setCategory(.names)
    XCTAssertTrue(composer.session.candidates.contains { $0.value == "金佐鎭" })
  }

  func testCompactCandidatesAlwaysAllowCategoryChanges() throws {
    XCTAssertTrue(usage.register(reading: "김좌진", value: "金佐鎭", category: .names))
    app.inputKeys("rlawhkwls")
    let ui = InputMethodServer.shared.hanjaPanel
    let composer = app.controller.receiver.composer.hanjaComposer
    XCTAssertTrue((1...4).contains(ui.visibleRowCount))
    XCTAssertLessThanOrEqual(ui.panel.frame.width, 240)
    XCTAssertEqual(ui.panel.frame.height, 30 + CGFloat(ui.visibleRowCount) * 26)
    let stableSize = ui.panel.frame.size
    for category in HanjaIMECandidateCategory.allCases {
      let menu = try XCTUnwrap(ui.panel.contentView?.subviews.compactMap { $0 as? NSPopUpButton }.first)
      XCTAssertEqual(menu.itemTitles, ["표준", "한자", "이름", "신자체", "기호"])
      menu.selectItem(at: category.rawValue)
      XCTAssertTrue(menu.sendAction(menu.action, to: menu.target))
      XCTAssertEqual(composer.session.category, category)
      XCTAssertTrue(ui.isVisible)
      XCTAssertEqual(ui.panel.frame.size, stableSize, "Filtering must not resize this session")
    }
  }

  func testDictionaryPreviewLeavesAndClosesWithCandidateWindow() {
    app.inputKeys("durtk")
    let ui = InputMethodServer.shared.hanjaPanel
    let session = app.controller.receiver.composer.hanjaComposer.session
    ui.previewDefinition(index: 0, generation: session.generation)
    XCTAssertTrue(ui.isDefinitionVisible)
    let now = Date()
    let outside = NSPoint(x: -100000, y: -100000)
    ui.checkPointer(outside, now: now)
    XCTAssertTrue(ui.isDefinitionVisible)
    ui.checkPointer(outside, now: now.addingTimeInterval(0.3))
    XCTAssertFalse(ui.isDefinitionVisible)
    ui.previewDefinition(index: 0, generation: session.generation)
    ui.checkPointer(NSPoint(x: ui.definitionFrame.midX, y: ui.definitionFrame.midY), now: now.addingTimeInterval(1))
    XCTAssertTrue(ui.isDefinitionVisible)
    ui.hide()
    XCTAssertFalse(ui.isDefinitionVisible)
    XCTAssertFalse(ui.isVisible)
    XCTAssertFalse(ui.panel.canBecomeKey)
    XCTAssertFalse(ui.panel.canBecomeMain)
  }

  func testOneThroughFourRowsHaveNoReservedSpace() throws {
    let ui = InputMethodServer.shared.hanjaPanel
    let values = ["伽倻", "可也", "假也", "家也"]
    for count in 1...4 {
      XCTAssertTrue(usage.register(reading: "갸냐", value: values[count - 1], category: .names))
      app.controller.receiver.composer.clear()
      app.client.string = ""
      app.inputKeys("risi")
      let composer = app.controller.receiver.composer.hanjaComposer
      composer.session.setCategory(.names)
      ui.update(controller: app.controller, composer: composer)
      XCTAssertEqual(ui.visibleRowCount, count)
      XCTAssertEqual(ui.bookButtonCount, count)
      XCTAssertEqual(ui.panel.frame.height, 30 + CGFloat(count) * 26)
      let menu = try XCTUnwrap(ui.panel.contentView?.subviews.compactMap { $0 as? NSPopUpButton }.first)
      XCTAssertEqual(menu.numberOfItems, 5)
    }
  }

  func testKoreanContextModeTagOverridesStaleGlobalRomanMode() {
    app.controller.receiver.setValue(GureumInputSource.han2.rawValue,
      forTag: kTextServiceInputModePropertyTag, client: app.client)
    GureumComposer.selectedModeProvider = { GureumInputSource.qwerty.rawValue }
    app.inputKeys("dkssudgktpdy")
    XCTAssertEqual(app.client.string, "안녕하세요")
    XCTAssertTrue(app.controller.receiver.composer.delegate is HanjaIMEComposer)
    // Even an explicit legacy qwerty notification must never enable Roman input.
    app.controller.receiver.setValue(GureumInputSource.qwerty.rawValue,
      forTag: kTextServiceInputModePropertyTag, client: app.client)
    XCTAssertTrue(app.controller.receiver.composer.delegate is HanjaIMEComposer)
    XCTAssertEqual(app.controller.receiver.composer.inputMode, GureumInputSource.han2.rawValue)
  }

  func testAllLegacyModeTagsPreserveAnUnfinishedKoreanSyllable() {
    for mode in [GureumInputSource.qwerty, .system, .dvorak, .colemak] {
      let receiver = app.controller.receiver!
      receiver.composer.clear()
      app.client.string = ""
      app.inputKeys("d") // initial ㅇ; committing here would corrupt 안
      receiver.setValue(mode.rawValue, forTag: kTextServiceInputModePropertyTag, client: app.client)
      receiver.composer.inputMode = mode.rawValue
      XCTAssertTrue(receiver.composer.delegate is HanjaIMEComposer)
      XCTAssertFalse(receiver.composer.delegate is RomanComposer)
      XCTAssertTrue(receiver.composer.commitString.isEmpty)
      app.inputKeys("kssudgktpdy")
      XCTAssertEqual(receiver.composer.composedString, "안녕하세요")
      XCTAssertEqual(app.client.string, "안녕하세요")
    }
  }

  func testCorruptRomanDelegateRepairsWithoutModeNotification() {
    let receiver = app.controller.receiver!
    for mode in [GureumInputSource.qwerty, .system, .dvorak, .colemak] {
      receiver.composer.clear()
      app.client.string = ""
      receiver.composer.delegate = receiver.composer.systemRomanComposer
      GureumComposer.selectedModeProvider = { mode.rawValue }
      receiver.synchronizeMode(activating: true)
      XCTAssertTrue(receiver.composer.delegate is HanjaIMEComposer)
      app.inputKeys("dkssudgktpdy")
      XCTAssertEqual(app.client.string, "안녕하세요")
      XCTAssertFalse(receiver.composer.delegate is RomanComposer)
    }
  }

  func testBothProductionEntryPointsSurviveBrowserFocusAndInvalidMarkedRanges() {
    for index in 0..<5 {
      let client = MockInputClient()
      client.string = "앞 😀 "
      client.setSelectedRange(NSRange(location: client.string.utf16.count, length: 0))
      client.returnsInvalidMarkedRange = index % 2 == 0
      for (offset, character) in "dkssudgktpdy".enumerated() {
        let (key, modifiers) = keyMapReversed[String(character)]!
        let handled: Bool
        if offset % 2 == 0 {
          // Inherited production callback, not a test-only implementation.
          handled = app.controller.inputText(nil, key: key.rawValue,
            modifiers: Int(modifiers.rawValue), client: client)
        } else {
          let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: modifiers, timestamp: Double(offset), windowNumber: 0,
            context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: UInt16(key.rawValue))!
          handled = app.controller.handle(event, client: client)
        }
        XCTAssertTrue(handled)
      }
      XCTAssertEqual(client.string, "앞 😀 안녕하세요")
      XCTAssertTrue(app.controller.receiver.composer.delegate is HanjaIMEComposer)
      XCTAssertFalse(app.controller.inputText("a", key: KeyCode.ansiA.rawValue,
        modifiers: Int(NSEvent.ModifierFlags.command.rawValue), client: client))
      XCTAssertEqual(client.string, "앞 😀 안녕하세요")
    }
  }

  func testStaleNotificationDoesNotOverrideTheClientKeyboard() {
    let client = MockInputClient()
    let receiver = app.controller.receiver!
    receiver.setValue(GureumInputSource.qwerty.rawValue,
      forTag: kTextServiceInputModePropertyTag, client: client)
    XCTAssertEqual(client.keyboardOverrideCount, 0)
    receiver.setValue(GureumInputSource.han2.rawValue,
      forTag: kTextServiceInputModePropertyTag, client: client)
    XCTAssertEqual(client.keyboardOverrideCount, 1)
  }

  func testAllTabsKeepTheStandardSessionSizeAndControlType() throws {
    app.inputKeys("dkssud")
    let ui = InputMethodServer.shared.hanjaPanel
    let composer = app.controller.receiver.composer.hanjaComposer
    XCTAssertGreaterThanOrEqual(composer.session.unfilteredCandidateCount, 5)
    let size = ui.panel.frame.size
    let anchor = ui.panel.frame.origin
    for category in HanjaIMECandidateCategory.allCases {
      let tabs = try XCTUnwrap(ui.panel.contentView?.subviews.compactMap { $0 as? NSSegmentedControl }.first)
      tabs.selectedSegment = category.rawValue
      XCTAssertTrue(tabs.sendAction(tabs.action, to: tabs.target))
      XCTAssertEqual(composer.session.category, category)
      XCTAssertEqual(ui.panel.frame.size, size)
      XCTAssertEqual(ui.panel.frame.origin, anchor)
      XCTAssertEqual(tabs.segmentCount, 5)
      XCTAssertEqual(ui.visibleRowCount, min(9, composer.session.candidates.count))
    }
  }

  func testFirstAnchorUsesAbsoluteDocumentIndexAndWaitsForGeometry() throws {
    let ui = InputMethodServer.shared.hanjaPanel
    let client = MockInputClient()
    client.string = "기존 문장과 검색어 "
    client.setSelectedRange(NSRange(location: client.string.utf16.count, length: 0))
    client.useSimulatedAttributeCaret = true
    client.simulatedAttributeCaret = .zero
    for char in "dkssud" {
      let (key, modifiers) = keyMapReversed[String(char)]!
      XCTAssertTrue(app.controller.inputText(String(char), key: key.rawValue,
        modifiers: Int(modifiers.rawValue), client: client))
    }
    XCTAssertFalse(ui.isVisible, "Do not show a first candidate at the mouse pointer")
    let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first).visibleFrame
    client.expectedAttributeIndex = try XCTUnwrap(UInt(exactly: client.selectedRange().location))
    client.simulatedAttributeCaret = NSRect(x: screen.midX, y: screen.maxY - 60, width: 1, height: 20)
    RunLoop.main.run(until: Date().addingTimeInterval(0.08))
    XCTAssertTrue(ui.isVisible, "First marked-text geometry is retried without another keystroke")
    XCTAssertEqual(client.lastAttributeIndex, client.expectedAttributeIndex)
    XCTAssertEqual(ui.panel.frame.minX, client.simulatedAttributeCaret.minX)
    XCTAssertEqual(ui.panel.frame.maxY, client.simulatedAttributeCaret.minY - 2)
    ui.hide()
    RunLoop.main.run(until: Date().addingTimeInterval(0.08))
    XCTAssertFalse(ui.isVisible, "A pending positioning callback cannot reopen a closed session")
  }

  func testSecondWordCandidatePanelReusesRecentCaretWhileGeometrySettles() throws {
    let ui = InputMethodServer.shared.hanjaPanel
    app.inputKeys("durtk")
    XCTAssertTrue(ui.isVisible)
    let firstFrame = ui.panel.frame
    XCTAssertTrue(app.inputText(" ", key: .space, modifiers: []))
    XCTAssertTrue(app.inputText("\r", key: .return, modifiers: []))
    XCTAssertFalse(ui.isVisible)

    app.client.useSimulatedAttributeCaret = true
    app.client.expectedAttributeIndex = UInt.max
    app.client.simulatedAttributeCaret = .zero
    app.inputKeys("wjdcl")
    XCTAssertTrue(ui.isVisible, "A second word must still show candidates while a browser/search field delays caret geometry")
    XCTAssertEqual(ui.panel.frame.origin, firstFrame.origin)

    let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first).visibleFrame
    app.client.expectedAttributeIndex = try XCTUnwrap(UInt(exactly: app.client.selectedRange().location))
    app.client.simulatedAttributeCaret = NSRect(x: screen.midX, y: screen.maxY - 80, width: 1, height: 20)
    RunLoop.main.run(until: Date().addingTimeInterval(0.08))
    XCTAssertTrue(ui.isVisible)
    XCTAssertEqual(ui.panel.frame.minX, app.client.simulatedAttributeCaret.minX)
  }

  func testResetAndLegacyToggleKeepActualKoreanInput() {
    let receiver = app.controller.receiver!
    receiver.composer.delegate = receiver.composer.qwertyComposer
    receiver.composer.clear()
    for layout: ChangeLayout in [.toggle, .roman] {
      _ = receiver.input(event: .changeLayout(layout, true), client: app.client)
      // InputEvent.processed is event consumption, not the resulting language.
      XCTAssertTrue(receiver.composer.delegate is HanjaIMEComposer)
      XCTAssertFalse(receiver.composer.delegate is RomanComposer)
    }
    app.inputKeys("dkssudgktpdy")
    XCTAssertEqual(app.client.string, "안녕하세요")
  }

  func testBrowserAndSearchClientChangesNeverInsertRawRomanKeys() {
    let receiver = app.controller.receiver!
    receiver.setValue(GureumInputSource.han2.rawValue, forTag: kTextServiceInputModePropertyTag, client: app.client)
    app.inputKeys("durtk")
    // These model distinct browser, Spotlight and Finder text-input proxies.
    // The real applications remain in the manual macOS matrix.
    for _ in 0..<3 {
      let next = MockInputClient()
      GureumComposer.selectedModeProvider = { GureumInputSource.qwerty.rawValue }
      for character in "dkssudgktpdy" {
        let (key, modifiers) = keyMapReversed[String(character)]!
        XCTAssertTrue(receiver.input(text: nil, key: key, modifiers: modifiers, client: next).processed)
        app.controller.updateComposition()
      }
      XCTAssertEqual(next.string, "안녕하세요")
      XCTAssertNil(next.string.range(of: "[A-Za-z]", options: .regularExpression))
    }
    XCTAssertEqual(app.client.string, "역사")
  }

  func testMissingModeNotificationKeepsKoreanAcrossGlobalSourceLag() {
    app.inputKeys("dks")
    GureumComposer.selectedModeProvider = { GureumInputSource.qwerty.rawValue }
    app.inputKeys("sudgktpdy")
    XCTAssertEqual(app.client.string, "안녕하세요")
    XCTAssertTrue(app.controller.receiver.composer.delegate is HanjaIMEComposer)
  }

  func testFloatingSearchOrderingAndCaretAnchor() throws {
    let receiver = app.controller.receiver!
    let next = MockInputClient()
    next.simulatedWindowLevel = 180
    let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first).visibleFrame
    next.simulatedCaret = NSRect(x: screen.midX, y: screen.maxY - 40, width: 1, height: 20)
    NSLog("HanjaIME floating regression: input")
    for character in "durtk" {
      let (key, modifiers) = keyMapReversed[String(character)]!
      _ = receiver.input(text: String(character), key: key, modifiers: modifiers, client: next)
      app.controller.updateComposition()
    }
    let ui = InputMethodServer.shared.hanjaPanel
    NSLog("HanjaIME floating regression: candidate geometry")
    XCTAssertEqual(ui.panel.level.rawValue, 181)
    XCTAssertEqual(ui.panel.frame.maxY, next.simulatedCaret.minY - 2)
    XCTAssertEqual(ui.panel.frame.minX, next.simulatedCaret.minX)
    let session = receiver.composer.hanjaComposer.session
    NSLog("HanjaIME floating regression: dictionary")
    ui.previewDefinition(index: 0, generation: session.generation)
    XCTAssertEqual(ui.definitionLevel, ui.panel.level)
    XCTAssertTrue(screen.contains(ui.definitionFrame))
    NSLog("HanjaIME floating regression: deactivate context")
    app.controller.deactivateServer(next)
    XCTAssertEqual(next.string, "역사")
    XCTAssertFalse(next.hasMarkedText())
    XCTAssertNil(InputMethodServer.shared.activeController)
    XCTAssertFalse(ui.isVisible)
    XCTAssertFalse(ui.isDefinitionVisible)
    NSLog("HanjaIME floating regression: complete")
  }

}
