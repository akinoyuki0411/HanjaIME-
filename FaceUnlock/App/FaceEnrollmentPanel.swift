import AppKit
import SwiftUI

// The camera stays in this process. Only a short-lived presentation lease is
// broadcast so the ordinary notch can yield its display while enrollment is open.
@MainActor final class FaceEnrollmentPanel {
    private let model: FaceService
    private var panel: NSPanel?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var heartbeat: Timer?
    private var lease = UUID().uuidString
    private var displayID: UInt32?
    init(model: FaceService) {
        self.model = model
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in self?.position() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification) { [weak self] in self?.model.closeEnrollment() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.model.closeEnrollment() }
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping @MainActor () -> Void) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { _ in Task { @MainActor in action() } }))
    }
    func present() {
        guard panel == nil else { panel?.orderFrontRegardless(); return }
        lease = UUID().uuidString
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "HanjiME · 노치 얼굴 등록"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.panel = panel; position(); panel.orderFrontRegardless()
        sendLease(true)
        heartbeat = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.sendLease(true) } }
    }
    private func position() {
        guard let panel else { return }
        let screens = NSScreen.screens
        func id(_ screen: NSScreen) -> UInt32? { (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
        guard let screen = screens.first(where: { id($0) == displayID })
                ?? screens.first(where: { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil })
                ?? NSScreen.main ?? screens.first else { model.closeEnrollment(); return }
        displayID = id(screen)
        let geometry = EnrollmentPanelLayout.calculate(screen: screen.frame, safeTop: screen.safeAreaInsets.top,
                                                       left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea)
        panel.setFrame(geometry.frame, display: true)
        panel.contentView = NSHostingView(rootView:
            EnrollmentNotchReveal(model: model, size: geometry.frame.size, topPadding: geometry.topPadding)
        )
    }
    private func sendLease(_ active: Bool) {
        DistributedNotificationCenter.default().postNotificationName(Notification.Name("org.hanjaime.notch.enrollmentPresentation.v1"), object: nil,
            userInfo: ["active": active, "lease": lease, "pid": Int(ProcessInfo.processInfo.processIdentifier), "timestamp": Date().timeIntervalSince1970], deliverImmediately: true)
    }
    func dismiss() {
        heartbeat?.invalidate(); heartbeat = nil; sendLease(false)
        panel?.orderOut(nil); panel?.close(); panel = nil; displayID = nil
    }
    func shutdown() {
        dismiss()
        for (center, token) in observers { center.removeObserver(token) }; observers.removeAll()
    }
}


// Reveal inside a fixed transparent host: the top edge stays attached to the notch
// and the content is clipped instead of stretching camera pixels during expansion.
private struct EnrollmentNotchReveal: View {
    @ObservedObject var model: FaceService
    let size: CGSize
    let topPadding: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: topPadding)
            FaceEnrollmentView(model: model).opacity(expanded ? 1 : 0)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(.black)
        .mask(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: expanded ? 24 : 10, bottomTrailingRadius: expanded ? 24 : 10)
                .frame(width: expanded || reduceMotion ? size.width : min(220, size.width),
                       height: expanded || reduceMotion ? size.height : max(28, topPadding))
        }
        .opacity(reduceMotion && !expanded ? 0 : 1)
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.88)) { expanded = true }
        }
    }
}
