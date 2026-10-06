import SwiftUI
import Combine

enum NotchState: Equatable {
    case closed
    case open
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var state: NotchState = .closed
    @Published var tab: NotchTab = .home { didSet {
        settings.lastTabRaw = tab.rawValue
        if oldValue != tab { tabTransitionUntil = Date().addingTimeInterval(0.75); closeTask?.cancel() }
    } }
    private var tabTransitionUntil = Date.distantPast
    @Published var selectedWidget: HomeWidget?
    @Published var geometry: NotchGeometry
    @Published var isHoveringClosedNotch = false
    @Published var isHoveringArtwork = false
    @Published var weatherPreviewAvailable = false
    var isShowingWeatherPeek: Bool { isHoveringClosedNotch && settings.openOnHover && weatherPreviewAvailable && !isHoveringArtwork }
    /// Set while a drag-and-drop is hovering anywhere near the notch; forces the shelf open.
    @Published var isDropTargeted = false
    /// Pin/lock: while true the open notch never auto-closes.
    @Published var isPinned = false

    let settings: SettingsStore

    /// Size of the expanded notch content (user-adjustable).
    var openSize: CGSize {
        let desired = tab == .weather ? min(680, max(400, settings.weatherWidth)) : tab == .shelf ? min(1100, max(480, settings.shelfWidth)) : max(480, settings.openWidth, settings.homeContentWidth)
        let available = max(480, geometry.screenFrame.width - 48)
        return CGSize(width: min(desired, available), height: tab == .weather ? min(340, max(210, settings.weatherHeight)) : tab == .shelf ? min(max(220, settings.shelfHeight), min(560, max(220, geometry.screenFrame.height - 80))) : max(300, settings.openHeight))
    }
    /// Measured widths of the live-activity "wings" flanking the closed notch.
    /// Updated by ClosedNotchView via preference keys.
    @Published var leftWingWidth: CGFloat = 0
    @Published var rightWingWidth: CGFloat = 0

    var closedSize: CGSize {
        CGSize(width: geometry.notchSize.width + max(leftWingWidth, rightWingWidth) * 2,
               height: geometry.notchSize.height)
    }

    /// Solid closed body, including the very top screen edge. CGRect.contains
    /// excludes its maximum edge, so the hit check explicitly includes it.
    var closedClickFrame: CGRect {
        let hover = isHoveringClosedNotch && settings.openOnHover
        let width = closedSize.width + (hover ? 18 : 0)
        let height = geometry.notchSize.height + (hover ? 5 : 0) + (isHoveringArtwork ? 38 : isShowingWeatherPeek ? 25 : 0)
        let center = geometry.screenFrame.midX
        return CGRect(x: center - width / 2, y: geometry.screenFrame.maxY - height, width: width, height: height)
    }
    func acceptsClosedClick(at point: CGPoint) -> Bool {
        guard state == .closed else { return false }
        let frame = closedClickFrame
        return point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
    }

    private var closeTask: Task<Void, Never>?

    var pointerIsInsideOpenNotch: (() -> Bool)?

    var onStateChange: ((NotchState) -> Void)?

    init(geometry: NotchGeometry, settings: SettingsStore) {
        self.geometry = geometry
        self.settings = settings
        self.tab = settings.startingTab
    }

    static let openAnimation = Animation.spring(response: 0.38, dampingFraction: 0.8)
    static let closeAnimation = Animation.spring(response: 0.32, dampingFraction: 0.9)

    func open(tab: NotchTab? = nil) {
        closeTask?.cancel()
        isHoveringArtwork = false
        if let tab { self.tab = tab; selectedWidget = nil }
        else if state == .closed {
            let previous = self.tab
            self.tab = settings.startingTab
            if settings.defaultTabRaw != StartupDestination.previous.rawValue || self.tab != previous { selectedWidget = nil }
        }
        guard state != .open else { return }
        withAnimation(Self.openAnimation) { state = .open }
        onStateChange?(.open)
    }

    func close(after delay: TimeInterval = 0) {
        isHoveringClosedNotch = false
        isHoveringArtwork = false
        closeTask?.cancel()
        guard state != .closed else { return }
        closeTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard let self, !Task.isCancelled else { return }
            self.isPinned = false
            withAnimation(Self.closeAnimation) { self.state = .closed }
            self.onStateChange?(.closed)
        }
    }

    func toggle() {
        state == .open ? close() : open()
    }

    var displayedOpenSize: CGSize {
        CGSize(width: openSize.width, height: tab == .home && selectedWidget == nil ? max(30, geometry.notchSize.height) + 162 : openSize.height)
    }

    func hoverChanged(_ hovering: Bool) {
        if !hovering { isHoveringArtwork = false }
        guard isHoveringClosedNotch != hovering else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            isHoveringClosedNotch = hovering
        }
        let peek = SneakPeekCoordinator.shared
        if hovering, settings.openOnHover, !peek.visible, !peek.isInteracting, settings.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    func openFromClick() {
        guard state == .closed else { return }
        if settings.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        open()
    }

    /// Called when the pointer leaves the open notch entirely.
    func mouseExitedOpenNotch() {
        guard state == .open, !isDropTargeted, !isPinned else { return }
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            let delay = max(0.25, self?.tabTransitionUntil.timeIntervalSinceNow ?? 0.25)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled, self.state == .open,
                  !self.isDropTargeted, !self.isPinned,
                  self.pointerIsInsideOpenNotch?() != true else { return }
            self.close()
        }
    }

    func cancelPendingClose() {
        closeTask?.cancel()
    }
}
