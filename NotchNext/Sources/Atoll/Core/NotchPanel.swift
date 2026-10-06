import AppKit
import Combine
import SwiftUI

/// Borderless, non-activating panel that floats over the notch on every space,
/// including over fullscreen apps. The window frame is always the full open
/// size, pinned top-center; all open/close morphing happens inside SwiftUI.
/// Transparent regions pass clicks through (NSHostingView hit-testing).
final class NotchPanel: NSPanel {
    var handlePrimaryMouseDown: ((NSEvent) -> Bool)?
    private var menuTracking = false
    private var menuObservers: [NSObjectProtocol] = []
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        menuObservers.append(NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            self?.menuTracking = true
        })
        menuObservers.append(NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { self?.menuTracking = false }
        })
    }
    deinit { menuObservers.forEach { NotificationCenter.default.removeObserver($0) } }
    override func sendEvent(_ event: NSEvent) {
        if !menuTracking, event.type == .leftMouseDown, handlePrimaryMouseDown?(event) == true { return }
        super.sendEvent(event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Never clamp to the visible frame — the whole point is to sit over the
    /// menu bar / notch area.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class NotchController: NSObject {
    let panel: NotchPanel
    let viewModel: NotchViewModel
    private let screen: NSScreen
    private var clickOutsideMonitor: Any?
    private var settingsCancellable: AnyCancellable?

    /// Margin around the open content so shadows aren't clipped.
    private let framePadding: CGFloat = 60

    init(screen: NSScreen, settings: SettingsStore) {
        self.screen = screen
        let geometry = NotchGeometry.forScreen(screen)
        self.viewModel = NotchViewModel(geometry: geometry, settings: settings)

        panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.title = "한지미 노치"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        // Set AFTER isFloatingPanel — the isFloatingPanel setter resets level to .floating.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)

        let hosting = NotchHostingView(
            rootView: NotchRootView()
                .environmentObject(viewModel)
                .environmentObject(settings)
        )
        hosting.wantsLayer = true
        panel.contentView = hosting
        panel.handlePrimaryMouseDown = { [weak self] event in
            guard let self, self.viewModel.state == .closed else { return false }
            let model = self.viewModel
            let point = self.panel.convertPoint(toScreen: event.locationInWindow)
            guard model.acceptsClosedClick(at: point) else { return false }
            model.openFromClick()
            return true
        }
        viewModel.pointerIsInsideOpenNotch = { [weak self] in
            guard let self else { return false }
            let model = self.viewModel
            let size = model.displayedOpenSize
            let frame = CGRect(x: model.geometry.screenFrame.midX - size.width / 2,
                               y: model.geometry.screenFrame.maxY - size.height,
                               width: size.width, height: size.height)
            return frame.contains(NSEvent.mouseLocation)
        }

        applyFrame()
        panel.orderFrontRegardless()

        // The open size is user-adjustable — keep the window frame in sync.
        // objectWillChange fires in willSet, so hop a runloop before reading.
        settingsCancellable = settings.objectWillChange
            .merge(with: viewModel.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let size = self.viewModel.openSize
                if size != self.lastAppliedOpenSize {
                    self.applyFrame()
                }
            }

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let isPrimary = event.type == .leftMouseDown
            Task { @MainActor [weak self] in
                guard let self else { return }
                let point = NSEvent.mouseLocation
                // At the menu-bar edge macOS can route the click to another
                // process. The existing mouse monitor recovers only our narrow
                // closed-notch region; adjacent menu-bar controls are untouched.
                if isPrimary, self.viewModel.acceptsClosedClick(at: point) {
                    self.viewModel.openFromClick()
                    return
                }
                guard self.viewModel.state == .open, !self.viewModel.isPinned else { return }
                if self.viewModel.pointerIsInsideOpenNotch?() != true {
                    self.viewModel.close()
                }
            }
        }
    }

    deinit {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func setFacePresentation(_ active: Bool) {
        if active { viewModel.close(); panel.orderOut(nil) }
        else { panel.orderFrontRegardless() }
    }

    func refreshGeometry() {
        viewModel.geometry = NotchGeometry.forScreen(screen)
        applyFrame()
    }

    func tearDown() {
        panel.orderOut(nil)
    }

    private var lastAppliedOpenSize: CGSize = .zero

    private func applyFrame() {
        let geometry = viewModel.geometry
        let openSize = viewModel.openSize
        lastAppliedOpenSize = openSize
        let size = CGSize(
            width: min(geometry.screenFrame.width, max(1100, openSize.width, viewModel.closedSize.width) + framePadding * 2),
            height: max(560, openSize.height) + framePadding
        )
        let frame = CGRect(
            x: geometry.screenFrame.midX - size.width / 2,
            y: geometry.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
    }
}
