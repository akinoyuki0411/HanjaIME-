"""Execute production panel lifecycle/mode methods with small platform adapters.

These tests cover timers' state transitions, not AppKit event delivery/ordering.
The native integration suite exercises the same methods with real NSPanel.
"""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
p = argparse.ArgumentParser()
p.add_argument('--source', type=Path, required=True)
p.add_argument('--swiftc', type=Path, required=True)
a = p.parse_args()


def method(source, name):
    start = source.index('  ', source.index('func ' + name) - 10)
    # Include the declaration's access modifier without assuming its length.
    start = source.rfind('\n', 0, source.index('func ' + name)) + 1
    opening = source.index('{', start)
    end, depth = opening + 1, 1
    while depth:
        if source[end] == '{': depth += 1
        if source[end] == '}': depth -= 1
        end += 1
    return source[start:end]


panel = (a.source / 'OSXCore/HanjaIMECandidatePanel.swift').read_text()
receiver = (a.source / 'OSXCore/InputReceiver.swift').read_text()
composer = (a.source / 'OSXCore/GureumComposer.swift').read_text()
prefix = r'''
import Foundation
final class Window {
 var frame: NSRect
 var isVisible = true
 var parent: Window?
 init(_ frame: NSRect) { self.frame = frame }
 func removeChildWindow(_ child: Window) { child.parent = nil }
 func orderOut(_ sender: Any?) { isVisible = false }
}
final class PanelFixture {
 var pointerTimer: Timer?
 var positionWorkItem: DispatchWorkItem?
 var hoverWorkItem: DispatchWorkItem?
 var requestID = UUID()
 var shownDefinition: String? = "國"
 var hoveredRect: NSRect? = NSRect(x: 10, y: 10, width: 180, height: 26)
 var hoveredCandidate: Int? = 0
 var hoveredGeneration: UInt64? = 1
 var clickedDefinition = false
 var outsideSince: Date?
 var controller: NSObject? = NSObject()
 var lastCaret: NSRect? = .zero
 var anchorScreen: NSObject? = NSObject()
 var hostPID: Int? = 100
 var visibleRowCount = 4, bookButtonCount = 4
 let panel = Window(NSRect(x: 10, y: 10, width: 180, height: 134))
 let definitionPanel = Window(NSRect(x: 194, y: 10, width: 280, height: 220))
 init() { definitionPanel.parent = panel }
'''
payload = prefix + '\n'.join(method(panel, n) for n in ['hide', 'closeDefinition', 'checkPointer']) + '\n}\n'
payload += r'''
enum GureumInputSource: String {
 case han2 = "Korean"
 var keyboardIdentifier: String { "2-full" }
}
final class HanjaIMEComposer {}
final class LegacyRomanComposer {}
final class SearchComposer { func cancelSearch() {} }
final class HangulComposer { func setKeyboard(identifier: String) {} }
final class Configuration {
 static let shared = Configuration()
 var lastHangulInputMode = ""
}
final class GureumComposer {
 static var selectedModeProvider: () -> String? = { nil }
 let hanjaComposer = HanjaIMEComposer()
 var delegate: AnyObject? = HanjaIMEComposer()
 let searchComposer = SearchComposer()
 let hangulComposer = HangulComposer()
 var _inputMode = "Korean"
 var inputMode: String { _inputMode }
'''
payload += method(composer, 'synchronizeSelectedMode') + '\n}\n'
payload += r'''
final class ModeFixture {
 var explicitInputMode: String?
 var inferredInputMode: String?
 let composer = GureumComposer()
'''
payload += method(receiver, 'synchronizeMode') + '\n}\n'
payload += r'''
@main struct LifecycleTests {
 static var checks = 0
 static func expect(_ ok: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if !ok() { fatalError(message) }
 }
 static func main() {
  let now = Date(timeIntervalSince1970: 1000)
  let panel = PanelFixture()
  panel.checkPointer(NSPoint(x: 20, y: 20), now: now)
  expect(panel.outsideSince == nil, "row keeps hover open")
  panel.checkPointer(NSPoint(x: 192, y: 20), now: now)
  expect(panel.definitionPanel.isVisible, "gap grace period")
  panel.checkPointer(NSPoint(x: 200, y: 20), now: now.addingTimeInterval(0.1))
  expect(panel.outsideSince == nil && panel.definitionPanel.isVisible, "dictionary accepts pointer crossing")
  let work = DispatchWorkItem {}
  panel.hoverWorkItem = work
  let token = panel.requestID
  panel.checkPointer(NSPoint(x: 600, y: 600), now: now.addingTimeInterval(1))
  expect(work.isCancelled, "leave cancels delayed hover immediately")
  panel.checkPointer(NSPoint(x: 600, y: 600), now: now.addingTimeInterval(1.3))
  expect(!panel.definitionPanel.isVisible, "leave closes preview")
  expect(panel.requestID != token && panel.shownDefinition == nil, "stale dictionary replies invalidated")
  expect(panel.definitionPanel.parent == nil && panel.hoveredRect == nil, "child and hover state released")
  expect(panel.panel.isVisible, "leaving preview preserves candidates")
  let clicked = PanelFixture()
  clicked.clickedDefinition = true
  clicked.checkPointer(NSPoint(x: 50, y: 90), now: now)
  expect(clicked.definitionPanel.isVisible && clicked.outsideSince == nil, "book click permits pointer within candidate window")
  clicked.checkPointer(NSPoint(x: -100, y: -100), now: now)
  clicked.checkPointer(NSPoint(x: -100, y: -100), now: now.addingTimeInterval(0.3))
  expect(!clicked.definitionPanel.isVisible, "explicit preview also closes outside both windows")
  let hidden = PanelFixture()
  let timer = Timer(timeInterval: 5, repeats: true) { _ in }
  hidden.pointerTimer = timer
  hidden.hide()
  expect(!hidden.panel.isVisible && !hidden.definitionPanel.isVisible, "candidate hide closes both windows")
  expect(!timer.isValid && hidden.pointerTimer == nil, "hidden panels stop polling")
  expect(hidden.controller == nil && hidden.anchorScreen == nil && hidden.lastCaret == nil, "hide clears context and anchor")
  expect(hidden.visibleRowCount == 0 && hidden.bookButtonCount == 0, "hide clears row state")
  let mode = ModeFixture()
  mode.synchronizeMode()
  expect(mode.composer.inputMode == "Korean", "missing TIS notification retains Korean startup")
  GureumComposer.selectedModeProvider = { "English" }
  mode.synchronizeMode()
  expect(mode.composer.inputMode == "Korean", "mid-composition global source lag cannot select Latin")
  mode.explicitInputMode = "Korean"
  mode.synchronizeMode(activating: true)
  expect(mode.composer.inputMode == "Korean", "context notification wins at activation")
  mode.explicitInputMode = "English"
  mode.synchronizeMode()
  expect(mode.composer.inputMode == "Korean", "retired explicit mode cannot select Latin")
  mode.composer.delegate = LegacyRomanComposer()
  mode.synchronizeMode()
  expect(mode.composer.delegate is HanjaIMEComposer, "actual production guard repairs stale delegate")
  mode.explicitInputMode = nil
  GureumComposer.selectedModeProvider = { "Korean" }
  mode.synchronizeMode(activating: true)
  expect(mode.composer.inputMode == "Korean", "reactivation refreshes inferred context mode")
  print("PASS: \(checks) production lifecycle/mode checks with platform adapters; not AppKit")
 }
}
'''
out = ROOT / 'build/lifecycle-tests'
out.mkdir(parents=True, exist_ok=True)
source = out / 'Lifecycle.swift'
source.write_text(payload)
subprocess.run([str(a.swiftc), '-swift-version', '5', '-warnings-as-errors', str(source),
                '-parse-as-library', '-o', str(out / 'lifecycle-tests')], check=True)
subprocess.run([str(out / 'lifecycle-tests')], check=True)
