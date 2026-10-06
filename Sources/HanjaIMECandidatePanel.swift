import Cocoa
import WebKit
import CoreServices
import InputMethodKit

private final class HanjaIMEFloatingPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

private final class HanjaIMERowButton: NSButton {
  var candidateIndex = 0
  var generation: UInt64 = 0
  var onHover: ((HanjaIMERowButton) -> Void)?
  var onLeave: (() -> Void)?
  private var tracking: NSTrackingArea?

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                              owner: self, userInfo: nil)
    addTrackingArea(area)
    tracking = area
  }

  override func mouseEntered(with event: NSEvent) {
    super.mouseEntered(with: event)
    onHover?(self)
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    onLeave?()
  }
}

/// Public AppKit UI: a real book button per candidate and a separate definition panel.
/// Windows never become key, so clicking a book or tab keeps the host's marked text.
final class HanjaIMECandidatePanel: NSObject {
  private var naverView: HanjaIMENaverDefinitionView?
  private(set) var panel: NSPanel
  private var definitionPanel: NSPanel
  private weak var controller: InputController?
  private weak var anchorController: InputController?
  private var shownDefinition: HanjaIMEDefinitionRequest?
  private var requestID = UUID()
  private let dictionaryQueue = DispatchQueue(label: "org.hanjaime.dictionary", qos: .userInitiated)
  private var hoverWorkItem: DispatchWorkItem?
  private var definitionText: NSTextView?
  private var pointerTimer: Timer?
  private var hoveredRect: NSRect?
  private var hoveredCandidate: Int?
  private var hoveredGeneration: UInt64?
  private var clickedDefinition = false
  private var outsideSince: Date?
  var foregroundPID: () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
  private var hostPID: pid_t?
  private var anchorScreen: NSScreen?
  private var lastCaret: NSRect?
  private var lastPanelFrame: NSRect?
  private var positionWorkItem: DispatchWorkItem?
  var isDefinitionVisible: Bool { definitionPanel.isVisible }
  var definitionFrame: NSRect { definitionPanel.frame }
  var definitionLevel: NSWindow.Level { definitionPanel.level }
  private(set) var visibleRowCount = 0
  private(set) var bookButtonCount = 0
  var isVisible: Bool { panel.isVisible }

  override init() {
    panel = Self.makePanel(size: NSSize(width: 300, height: 120))
    definitionPanel = Self.makePanel(size: NSSize(width: 280, height: 220))
    super.init()
  }

  private static func makePanel(size: NSSize) -> NSPanel {
    let window = HanjaIMEFloatingPanel(contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.level = .popUpMenu
    window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
    window.hidesOnDeactivate = false
    window.isReleasedWhenClosed = false
    window.isFloatingPanel = true
    window.becomesKeyOnlyIfNeeded = true
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    return window
  }

  private static func background(size: NSSize) -> NSVisualEffectView {
    let view = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
    view.material = .popover
    view.blendingMode = .behindWindow
    view.state = .active
    view.wantsLayer = true
    view.layer?.cornerRadius = 7
    view.layer?.masksToBounds = true
    return view
  }

  static func annotation(for candidate: HanjaIMECandidate, reading: String) -> String {
    if candidate.kind == .hanja || candidate.kind == .japanese {
      return candidate.sourceReading ?? reading
    }
    return candidate.annotation.isEmpty ? (candidate.sourceReading ?? reading) : candidate.annotation
  }

  private static func label(_ text: String, frame: NSRect, size: CGFloat = 12) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.frame = frame
    label.font = .systemFont(ofSize: size)
    label.lineBreakMode = .byTruncatingTail
    label.toolTip = text
    return label
  }

  func ownsMousePoint(_ point: NSPoint) -> Bool {
    (panel.isVisible && panel.frame.contains(point))
      || (definitionPanel.isVisible && definitionPanel.frame.contains(point))
  }

  func hide(preserveAnchor: Bool = false) {
    positionWorkItem?.cancel()
    positionWorkItem = nil
    pointerTimer?.invalidate()
    pointerTimer = nil
    closeDefinition()
    panel.orderOut(nil)
    controller = nil
    if !preserveAnchor {
      lastCaret = nil
      anchorScreen = nil
      lastPanelFrame = nil
      anchorController = nil
    }
    hostPID = nil
    visibleRowCount = 0
    bookButtonCount = 0
  }

  private func closeDefinition() {
    naverView?.stop()
    naverView = nil
    hoverWorkItem?.cancel()
    hoverWorkItem = nil
    requestID = UUID()
    shownDefinition = nil
    hoveredRect = nil
    hoveredCandidate = nil
    hoveredGeneration = nil
    clickedDefinition = false
    outsideSince = nil
    if definitionPanel.parent != nil { panel.removeChildWindow(definitionPanel) }
    definitionPanel.orderOut(nil)
  }

  // A short grace interval permits crossing the four-point gap to the definition.
  // Polling is local to visible panels and requires no global keyboard/mouse tap.
  func checkPointer(_ point: NSPoint, now: Date = Date()) {
    let insideRow = clickedDefinition ? panel.frame.contains(point) : hoveredRect?.contains(point) == true
    if insideRow || (definitionPanel.isVisible && definitionPanel.frame.contains(point)) {
      outsideSince = nil
    } else {
      hoverWorkItem?.cancel()
      if outsideSince == nil { outsideSince = now }
      if let outsideSince, now.timeIntervalSince(outsideSince) >= 0.18 { closeDefinition() }
    }
  }

  private func watchHostAndPointer() {
    hostPID = foregroundPID()
    guard pointerTimer == nil else { return }
    let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
      guard let self else { return }
      if self.hostPID != self.foregroundPID()
        || self.controller !== InputMethodServer.shared.activeController {
        self.hide()
      } else {
        // Remote web views may take much longer than the initial 200ms retry
        // budget. Keep geometry recovery alive for this active composition.
        if let controller = self.controller,
          let composer = controller.receiver.composer.delegate as? HanjaIMEComposer,
          composer.session.wantsCandidatePanel,
          self.position(relativeTo: controller.receiver.inputClient) {
          self.panel.orderFrontRegardless()
        }
        self.checkPointer(NSEvent.mouseLocation)
      }
    }
    pointerTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func update(controller: InputController, composer: HanjaIMEComposer) {
    positionWorkItem?.cancel()
    let session = composer.session
    guard session.wantsCandidatePanel else { hide(preserveAnchor: true); return }
    if anchorController !== controller {
      lastCaret = nil; anchorScreen = nil; lastPanelFrame = nil
    }
    anchorController = controller
    self.controller = controller
    closeDefinition()
    watchHostAndPointer()
    let rowsPerPage = 9
    let start = (session.selectedIndex / rowsPerPage) * rowsPerPage
    let end = min(start + rowsPerPage, session.candidates.count)
    visibleRowCount = max(0, end - start)
    bookButtonCount = 0
    // Filtering/page changes do not resize the same conversion session.
    let layoutRows = min(rowsPerPage, session.unfilteredCandidateCount)
    let showTabs = session.unfilteredCandidateCount >= 5
    let rowHeight: CGFloat = 26
    let headerHeight: CGFloat = session.unfilteredCandidateCount > rowsPerPage ? 20 : 0
    let tabHeight: CGFloat = 24
    let textWidth = session.layoutCandidates.map {
      ($0.value as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14)]).width
    }.max() ?? 90
    let size = HanjaIMEPanelLayout.size(rows: layoutRows, textWidth: textWidth + 16,
                                       paged: headerHeight > 0)
    let content = Self.background(size: size)
    let heading = Self.label(session.reading, frame: NSRect(x: 7, y: size.height - 18, width: size.width - 104, height: 16), size: 10)
    heading.textColor = .secondaryLabelColor
    if headerHeight > 0 { content.addSubview(heading) }
    let count = Self.label("\(session.candidates.count)개", frame: NSRect(x: size.width - 92, y: size.height - 18, width: 39, height: 16), size: 10)
    count.alignment = .right
    if headerHeight > 0 { content.addSubview(count) }
    for (offset, title) in ["‹", "›"].enumerated() {
      let button = NSButton(title: title, target: self, action: #selector(page(_:)))
      button.frame = NSRect(x: size.width - 48 + CGFloat(offset) * 23, y: size.height - 20, width: 22, height: 19)
      button.isBordered = false
      button.tag = offset
      button.isEnabled = session.candidates.count > rowsPerPage
      button.toolTip = offset == 0 ? "이전 후보 페이지" : "다음 후보 페이지"
      if headerHeight > 0 { content.addSubview(button) }
    }
    if start < end {
      for index in start..<end {
        let candidate = session.candidates[index]
        let y = size.height - headerHeight - CGFloat(index - start + 1) * rowHeight
        let row = NSView(frame: NSRect(x: 3, y: y - 3, width: size.width - 6, height: rowHeight - 1))
        row.wantsLayer = true
        row.layer?.cornerRadius = 5
        let selected = index == session.selectedIndex
        row.layer?.backgroundColor = selected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        let button = HanjaIMERowButton(title: "\(index % rowsPerPage + 1)  \(candidate.value)", target: self, action: #selector(choose(_:)))
        button.candidateIndex = index
        button.generation = session.generation
        button.frame = NSRect(x: 3, y: 2, width: size.width - 38, height: 22)
        button.font = .systemFont(ofSize: 14)
        button.alignment = .left
        button.isBordered = false
        button.cell?.lineBreakMode = .byTruncatingTail
        button.contentTintColor = selected ? .white : .labelColor
        let titleWidth = (button.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14)]).width
        if button.frame.width - titleWidth > 32 {
          let title = NSMutableAttributedString(string: button.title, attributes: [
            .font: NSFont.systemFont(ofSize: 14), .foregroundColor: selected ? NSColor.white : NSColor.labelColor])
          title.append(NSAttributedString(string: "  " + Self.annotation(for: candidate, reading: session.candidateReading),
            attributes: [.font: NSFont.systemFont(ofSize: 10),
                         .foregroundColor: selected ? NSColor.white : NSColor.secondaryLabelColor]))
          button.attributedTitle = title
        }
        button.toolTip = "\(candidate.value) 확정"
        button.onHover = { [weak self] rowButton in self?.hoverDefinition(rowButton) }
        button.onLeave = { [weak self] in self?.checkPointer(NSEvent.mouseLocation) }
        row.addSubview(button)
        let annotation = Self.label(Self.annotation(for: candidate, reading: session.candidateReading),
          frame: NSRect(x: 27, y: 1, width: 215, height: 12), size: 10)
        annotation.textColor = selected ? .white : .secondaryLabelColor
        button.toolTip = annotation.stringValue
        if candidate.kind == .hanja || candidate.kind == .japanese {
          let book = HanjaIMERowButton(image: NSImage(systemSymbolName: "book", accessibilityDescription: "뜻풀이")!,
            target: self, action: #selector(define(_:)))
          book.candidateIndex = index
          book.generation = session.generation
          book.frame = NSRect(x: size.width - 32, y: 2, width: 23, height: 21)
          book.isBordered = false
          book.contentTintColor = selected ? .white : .labelColor
          book.toolTip = "\(candidate.sourceValue ?? candidate.value) — 뜻풀이"
          book.onHover = { [weak self] button in self?.hoverDefinition(button) }
          book.onLeave = { [weak self] in self?.checkPointer(NSEvent.mouseLocation) }
          row.addSubview(book)
          bookButtonCount += 1
        }
        content.addSubview(row)
      }
    } else {
      let empty = Self.label(session.category == .names ? "등록된 이름·단어 후보가 없습니다." : "이 분류에 해당하는 후보가 없습니다.",
        frame: NSRect(x: 7, y: tabHeight + 4, width: size.width - 14, height: 20), size: 11)
      empty.textColor = .secondaryLabelColor
      content.addSubview(empty)
    }
    if showTabs {
      let tabs = NSSegmentedControl(labels: HanjaIMECandidateCategory.allCases.map(\.title),
        trackingMode: .selectOne, target: self, action: #selector(categoryChanged(_:)))
      tabs.controlSize = .mini
      tabs.font = .systemFont(ofSize: 10)
      tabs.frame = NSRect(x: 4, y: 3, width: size.width - 8, height: 20)
      for index in 0..<HanjaIMECandidateCategory.allCases.count { tabs.setWidth((size.width - 10) / 5, forSegment: index) }
      tabs.selectedSegment = session.category.rawValue
      tabs.toolTip = "표준 · 한자 · 이름 · 신자체 · 기호"
      content.addSubview(tabs)
    } else {
      let categories = NSPopUpButton(frame: NSRect(x: 4, y: 2, width: size.width - 8, height: 22), pullsDown: false)
      categories.controlSize = .small
      categories.font = .systemFont(ofSize: 11)
      categories.addItems(withTitles: HanjaIMECandidateCategory.allCases.map(\.title))
      categories.selectItem(at: session.category.rawValue)
      categories.target = self
      categories.action = #selector(compactCategoryChanged(_:))
      categories.toolTip = "후보 분류"
      content.addSubview(categories)
    }
    panel.contentView = content
    panel.setContentSize(size)
    if position(relativeTo: controller.receiver.inputClient) { panel.orderFrontRegardless() }
    else { panel.orderOut(nil) }
    schedulePositionRefresh(controller: controller, composer: composer)
  }

  private func position(relativeTo client: IMKTextInput & IMKUnicodeTextInput) -> Bool {
    let level = HanjaIMEPanelLayout.windowLevel(host: Int(client.windowLevel()),
      normal: NSWindow.Level.popUpMenu.rawValue, ceiling: NSWindow.Level.screenSaver.rawValue - 1)
    panel.level = NSWindow.Level(rawValue: level)
    definitionPanel.level = panel.level
    let selected = client.selectedRange(), marked = client.markedRange()
    let indices = HanjaIMEPanelLayout.characterIndices(selected: selected, marked: marked)
    let screens = NSScreen.screens.map(\.frame)
    var found: NSRect?
    // Both APIs return screen coordinates and take DOCUMENT character indices.
    // IMK remote proxies need not conform to NSTextInputClient, so also query IMK.
    if let textClient = client as? NSTextInputClient {
      for index in indices where index != NSNotFound {
        let rect = textClient.firstRect(forCharacterRange: NSRange(location: index, length: 0), actualRange: nil)
        if HanjaIMEPanelLayout.validCaret(rect, screens: screens) { found = rect; break }
      }
    }
    if found == nil {
      for index in indices {
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: index, lineHeightRectangle: &rect)
        if HanjaIMEPanelLayout.validCaret(rect, screens: screens) { found = rect; break }
      }
    }
    if let found { lastCaret = found }
    // Never anchor to the pointer: it may be over a different field or display.
    // A browser can report zero geometry until its first marked-text update settles.
    guard let anchor = lastCaret,
      let screen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -2, dy: -2).contains(anchor.origin) }) else {
      if let frame = lastPanelFrame,
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) {
        anchorScreen = screen
        panel.setFrame(HanjaIMEPanelLayout.candidate(previous: frame, size: panel.frame.size,
          visible: screen.visibleFrame.insetBy(dx: 2, dy: 2)), display: true)
        lastPanelFrame = panel.frame
        return true
      }
      return false
    }
    anchorScreen = screen
    let visible = screen.visibleFrame.insetBy(dx: 2, dy: 2)
    panel.setFrame(HanjaIMEPanelLayout.candidate(caret: anchor, size: panel.frame.size, visible: visible), display: true)
    lastPanelFrame = panel.frame
    positionDefinition(on: visible)
    return true
  }

  private func schedulePositionRefresh(controller: InputController, composer: HanjaIMEComposer, attempts: Int = 8) {
    let generation = composer.session.generation
    let item = DispatchWorkItem { [weak self, weak controller, weak composer] in
      guard let self, let controller, let composer,
        self.controller === controller, InputMethodServer.shared.activeController === controller,
        composer.session.generation == generation, composer.session.wantsCandidatePanel else { return }
      if self.position(relativeTo: controller.receiver.inputClient) {
        self.panel.orderFrontRegardless()
      } else if attempts > 1 {
        self.schedulePositionRefresh(controller: controller, composer: composer, attempts: attempts - 1)
      }
    }
    positionWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.025, execute: item)
  }

  private func positionDefinition(on visible: NSRect? = nil) {
    guard let area = visible ?? anchorScreen?.visibleFrame.insetBy(dx: 2, dy: 2) else { return }
    definitionPanel.setFrame(HanjaIMEPanelLayout.definition(candidate: panel.frame,
      size: NSSize(width: 280, height: 220), visible: area), display: true)
  }

  private func current(_ button: HanjaIMERowButton) -> (InputController, HanjaIMEComposer)? {
    guard let controller = controller, InputMethodServer.shared.activeController === controller,
      let composer = controller.receiver.composer.delegate as? HanjaIMEComposer,
      composer.session.generation == button.generation,
      composer.session.candidates.indices.contains(button.candidateIndex) else { return nil }
    return (controller, composer)
  }

  @objc private func choose(_ sender: HanjaIMERowButton) {
    guard let (controller, composer) = current(sender) else { return }
    _ = composer.session.choose(index: sender.candidateIndex, generation: sender.generation)
    controller.receiver.inputting = true
    _ = controller.receiver.commitCompositionEvent(controller.receiver.inputClient)
    controller.receiver.inputting = false
    controller.updateComposition()
    InputMethodServer.shared.showOrHideCandidates(controller: controller)
  }

  @objc private func define(_ sender: HanjaIMERowButton) {
    guard let (controller, composer) = current(sender) else { return }
    composer.session.highlight(index: sender.candidateIndex, generation: sender.generation)
    let candidate = composer.session.candidates[sender.candidateIndex]
    controller.updateComposition()
    update(controller: controller, composer: composer)
    clickedDefinition = true
    showDefinition(for: candidate, reading: composer.session.reading)
  }

  private func hoverDefinition(_ sender: HanjaIMERowButton) {
    if hoveredCandidate == sender.candidateIndex && hoveredGeneration == sender.generation { return }
    closeDefinition()
    hoveredCandidate = sender.candidateIndex
    hoveredGeneration = sender.generation
    if let row = sender.superview, let window = row.window {
      hoveredRect = window.convertToScreen(row.convert(row.bounds, to: nil))
    }
    let hoverToken = requestID
    let item = DispatchWorkItem { [weak self, weak sender] in
      guard let self, let sender, self.requestID == hoverToken, self.current(sender) != nil else { return }
      self.previewDefinition(index: sender.candidateIndex, generation: sender.generation)
    }
    hoverWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
  }

  func previewDefinition(index: Int, generation: UInt64) {
    guard let controller, InputMethodServer.shared.activeController === controller,
      let composer = controller.receiver.composer.delegate as? HanjaIMEComposer,
      composer.session.generation == generation, composer.session.candidates.indices.contains(index) else { return }
    let candidate = composer.session.candidates[index]
    guard candidate.kind == .hanja || candidate.kind == .japanese else { return }
    clickedDefinition = false
    showDefinition(for: candidate, reading: composer.session.reading)
  }

  @objc private func compactCategoryChanged(_ sender: NSPopUpButton) {
    guard let controller, let category = HanjaIMECandidateCategory(rawValue: sender.indexOfSelectedItem),
      let composer = controller.receiver.composer.delegate as? HanjaIMEComposer else { return }
    composer.session.setCategory(category)
    controller.updateComposition()
    update(controller: controller, composer: composer)
  }

  @objc private func categoryChanged(_ sender: NSSegmentedControl) {
    guard let controller = controller, let category = HanjaIMECandidateCategory(rawValue: sender.selectedSegment),
      let composer = controller.receiver.composer.delegate as? HanjaIMEComposer else { return }
    composer.session.setCategory(category)
    controller.updateComposition()
    update(controller: controller, composer: composer)
  }

  @objc private func page(_ sender: NSButton) {
    guard let controller = controller,
      let composer = controller.receiver.composer.delegate as? HanjaIMEComposer else { return }
    _ = composer.session.handle(sender.tag == 0 ? .pagePrevious : .pageNext)
    controller.updateComposition()
    update(controller: controller, composer: composer)
  }

  private func showDefinition(for candidate: HanjaIMECandidate, reading: String) {
    let request = HanjaIMEDefinitionRequest(candidate: candidate, reading: reading)
    if shownDefinition == request && definitionPanel.isVisible { positionDefinition(); return }
    naverView?.stop()
    naverView = nil
    shownDefinition = request
    let token = UUID()
    requestID = token
    positionDefinition()
    let size = definitionPanel.frame.size
    guard size.height >= 80 else { closeDefinition(); return }
    let content = Self.background(size: size)
    let priority = HanjaIMEDictionaryPriority.current
    if priority == .naverFirst {
      showNaverDefinition(request)
      return
    }
    let dictionaryLabel = request.prefersJapaneseDictionary ? "일본어 사전 우선" : "한국어 사전 우선"
    let title = Self.label(request.term + "  [" + request.reading + "] · " + dictionaryLabel,
      frame: NSRect(x: 10, y: size.height - 30, width: size.width - 20, height: 22), size: 13)
    content.addSubview(title)
    let scroll = NSScrollView(frame: NSRect(x: 10, y: 10, width: size.width - 20, height: size.height - 46))
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    let text = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
    text.isEditable = false
    text.isSelectable = true
    text.drawsBackground = false
    text.isVerticallyResizable = true
    text.isHorizontallyResizable = false
    text.autoresizingMask = [.width]
    text.textContainer?.widthTracksTextView = true
    text.textContainerInset = NSSize(width: 2, height: 4)
    text.font = .systemFont(ofSize: 12)
    text.textColor = .labelColor
    text.string = "Apple 사전에서 찾는 중…"
    scroll.documentView = text
    content.addSubview(scroll)
    definitionText = text
    definitionPanel.contentView = content
    if definitionPanel.parent == nil { panel.addChildWindow(definitionPanel, ordered: .above) }
    definitionPanel.orderFrontRegardless()
    dictionaryQueue.async { [weak self] in
      var result: String?
      var matched = request.term
      // The public API uses the user's enabled dictionaries, not a language ID.
      // Prefer the Korean reading or Japanese form without private DCS symbols.
      let terms = request.prefersJapaneseDictionary
        ? [request.term, request.reading] : [request.reading, request.term]
      for term in terms {
        if let copied = DCSCopyTextDefinition(nil, term as CFString, CFRange(location: 0, length: term.utf16.count)) {
          let definition = copied.takeRetainedValue() as String
          if !definition.isEmpty { result = definition; matched = term; break }
        }
      }
      let body: String
      if let result = result {
        body = "Apple 사전 (\(dictionaryLabel)) · \(matched)\n\n\(result)"
      } else {
        body = "활성화된 Apple 사전에서 뜻풀이를 찾지 못했습니다.\nMac의 사전 앱 설정에서 사용할 사전을 선택해 주세요."
          + (request.annotation.isEmpty ? "" : "\n\n입력기 사전 주석\n" + request.annotation)
      }
      DispatchQueue.main.async { [weak self] in
        guard let self = self, self.requestID == token, self.shownDefinition == request,
          self.panel.isVisible, self.definitionPanel.isVisible else { return }
        self.definitionText?.string = body
        if result == nil, priority.usesNaver,
          Configuration.shared.object(forKey: "HanjaIME.NaverFallback") as? Bool ?? true {
          self.showNaverDefinition(request)
        }
      }
    }
  }
  private func showNaverDefinition(_ request: HanjaIMEDefinitionRequest) {
    guard let url = HanjaIMEDictionaryLink.naver(request) else { return }
    let web = HanjaIMENaverDefinitionView(url: url)
    naverView = web
    positionDefinition()
    web.frame = NSRect(origin: .zero, size: definitionPanel.frame.size)
    web.autoresizingMask = [.width, .height]
    definitionPanel.contentView = web
    if definitionPanel.parent == nil { panel.addChildWindow(definitionPanel, ordered: .above) }
    definitionPanel.orderFrontRegardless()
    web.start()
  }

}

final class HanjaIMENaverDefinitionView: NSView, WKNavigationDelegate {
    private static let cache:NSCache<NSString,NSString> = {let cache=NSCache<NSString,NSString>();cache.countLimit=64;return cache}()
    private let url:URL
    private let web:WKWebView
    private let body=NSTextView()
    private var retry:DispatchWorkItem?
    private var stopped=false
    private var extracting=false
    private var attempts=0
    init(url:URL) {
        self.url=url
        let config=WKWebViewConfiguration();config.websiteDataStore = .nonPersistent()
        web=WKWebView(frame:NSRect(x:0,y:0,width:640,height:600),configuration:config)
        super.init(frame:NSRect(x:0,y:0,width:280,height:220))
        wantsLayer=true;layer?.cornerRadius=7;layer?.masksToBounds=true;layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor
        let title=NSTextField(labelWithString:"네이버 사전 · NAVER");title.font = .systemFont(ofSize:11);title.textColor = .secondaryLabelColor
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.drawsBackground=false
        body.frame=NSRect(x:0,y:0,width:260,height:160);body.autoresizingMask=[.width];body.isEditable=false;body.isSelectable=true;body.drawsBackground=false;body.font = .systemFont(ofSize:12);body.textColor = .labelColor;body.isVerticallyResizable=true;body.isHorizontallyResizable=false;body.textContainer?.widthTracksTextView=true;body.textContainerInset=NSSize(width:2,height:3)
        body.string="뜻을 찾는 중…";scroll.documentView=body
        let open=NSButton(title:"네이버에서 자세히 보기",target:self,action:#selector(openBrowser));open.bezelStyle = .rounded;open.controlSize = .small
        for child in [title,scroll,open] {child.translatesAutoresizingMaskIntoConstraints=false;addSubview(child)}
        NSLayoutConstraint.activate([title.leadingAnchor.constraint(equalTo:leadingAnchor,constant:10),title.topAnchor.constraint(equalTo:topAnchor,constant:8),title.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-10),title.heightAnchor.constraint(equalToConstant:18),scroll.leadingAnchor.constraint(equalTo:leadingAnchor,constant:8),scroll.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-8),scroll.topAnchor.constraint(equalTo:title.bottomAnchor,constant:5),scroll.bottomAnchor.constraint(equalTo:open.topAnchor,constant:-5),open.centerXAnchor.constraint(equalTo:centerXAnchor),open.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-7)])
        web.isHidden=true;addSubview(web);web.navigationDelegate=self
    }
    required init?(coder:NSCoder) {fatalError("Use init")}
    func start() {
        if let cached=Self.cache.object(forKey:url.absoluteString as NSString) {body.string=cached as String;return}
        web.load(URLRequest(url:url,timeoutInterval:12))
        let work=DispatchWorkItem { [weak self] in self?.extract() };retry=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.5,execute:work)
    }
    func stop() {stopped=true;retry?.cancel();web.stopLoading();web.navigationDelegate=nil}
    @objc private func openBrowser() {NSWorkspace.shared.open(url)}
    private func extract() {
        guard !stopped,!extracting else{return};extracting=true;attempts += 1
        let script="""
        (() => {
          const query=new URLSearchParams(location.hash.split('?')[1]||'').get('query')||'';
          const letter=location.hostname==='hanja.dict.naver.com' && Array.from(query).length===1 ? document.querySelector('#searchPage_letter .row') : null;
          const row=letter || document.querySelector('#searchPage_entry .row') || document.querySelector('#searchPage_hanja .row') || document.querySelector('#searchPage_word .row');
          if(!row) return null;
          const clean=s=>(s||'').replace(/\\s+/g,' ').trim();
          const origin=row.querySelector('.origin .link');
          const kanji=row.querySelector('.origin ._kanji');
          const meaning=row.querySelector('.mean_list') || row.querySelector('.entry_mean');
          const source=row.querySelector('.source');
          if(!meaning || !clean(meaning.innerText)) return null;
          return [(clean(origin?.innerText)||query)+' '+clean(kanji?.innerText),clean(meaning.innerText).slice(0,600),clean(source?.innerText)].filter(Boolean).join('\\n\\n');
        })()
        """
        web.evaluateJavaScript(script) { [weak self] value,error in
            guard let self,!self.stopped else{return};self.extracting=false
            if let text=value as? String,!text.isEmpty {
                self.body.string=text;Self.cache.setObject(text as NSString,forKey:self.url.absoluteString as NSString);self.retry?.cancel();self.stopped=true;self.web.stopLoading();return
            }
            if self.attempts>=24 {self.body.string="뜻풀이를 불러오지 못했습니다. 아래 버튼으로 네이버 사전에서 확인해 주세요.";self.web.stopLoading();return}
            let work=DispatchWorkItem { [weak self] in self?.extract() };self.retry=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.5,execute:work)
        }
    }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {extract()}
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {
        guard !stopped,(error as NSError).code != NSURLErrorCancelled else{return};body.string="네이버 연결이 지연됩니다. 아래 버튼으로 직접 확인해 주세요."
    }
    func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
        guard let url=action.request.url,url.scheme=="https",let host=url.host,host=="dict.naver.com" || host.hasSuffix(".dict.naver.com") else {decisionHandler(.cancel);return};decisionHandler(.allow)
    }
}
