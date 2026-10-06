import AppKit
import SwiftUI

/// Consume horizontal trackpad scrolling only inside the home calendar.
/// One gesture changes one day; momentum never repeats a date change.
struct CalendarSwipeCapture: NSViewRepresentable {
    let page: (Int) -> Void
    func makeNSView(context: Context) -> CaptureView { let view = CaptureView(); view.page = page; return view }
    func updateNSView(_ view: CaptureView, context: Context) { view.page = page }
    final class CaptureView: NSView {
        var page: ((Int) -> Void)?
        private var monitor: Any?
        private var accumulated: CGFloat = 0
        private var didPage = false
        private var lastEvent = Date.distantPast
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                if event.phase == .began || Date().timeIntervalSince(self.lastEvent) > 0.3 {
                    self.accumulated = 0; self.didPage = false
                }
                self.lastEvent = Date()
                guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY), abs(event.scrollingDeltaX) > 0 else { return event }
                if event.momentumPhase.isEmpty && !self.didPage {
                    self.accumulated += event.scrollingDeltaX
                    if abs(self.accumulated) >= 24 {
                        self.didPage = true
                        self.page?(self.accumulated < 0 ? 1 : -1)
                    }
                }
                return nil
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
