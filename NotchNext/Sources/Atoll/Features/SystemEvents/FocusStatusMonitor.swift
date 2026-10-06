import Foundation
import Combine
import Intents
import AppKit

@MainActor
final class FocusStatusMonitor: ObservableObject {
    static let shared = FocusStatusMonitor()
    @Published private(set) var authorization = INFocusStatusCenter.default.authorizationStatus
    @Published private(set) var isFocused: Bool?
    @Published private(set) var modeName = ""
    @Published private(set) var modeSymbol = "moon.fill"
    @Published private(set) var modeColor = NSColor.systemPurple
    @Published private(set) var stateFileReadable = false
    @Published private(set) var readFailure = ""
    @Published private(set) var needsFilePermission = false
    let events = PassthroughSubject<Bool, Never>()
    private var timer: Timer?
    private var changes = FocusChangeTracker()
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var notifiedState: Bool?
    private var notificationDate: Date?
    private var previousMode: String?
    private var database: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB") }

    func start() {
        guard timer == nil else { return }
        for (name, enabled) in [("_NSDoNotDisturbEnabledNotification", true), ("_NSDoNotDisturbDisabledNotification", false)] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let unknown = self.isFocused == nil
                    self.notifiedState = enabled
                    self.notificationDate = Date()
                    self.refresh()
                    if unknown { self.events.send(enabled) }
                }
            })
        }
        refresh()
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func stop() {
        timer?.invalidate(); timer = nil
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
    }
    func authorize() {
        INFocusStatusCenter.default.requestAuthorization { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func refresh() {
        authorization = INFocusStatusCenter.default.authorizationStatus
        let recentNotification = notificationDate.map { Date().timeIntervalSince($0) < 2 } ?? false
        if !recentNotification { notifiedState = nil }
        var focused: Bool?
        var modeID: String?
        do {
            let data = try Data(contentsOf: database.appendingPathComponent("Assertions.json"))
            let snapshot = try FocusFileSnapshot.decode(data)
            stateFileReadable = true
            readFailure = ""; needsFilePermission = false
            focused = recentNotification ? notifiedState : snapshot.enabled
            modeID = snapshot.modeID
            if notificationDate.map({ Date().timeIntervalSince($0) >= 2 }) ?? true { notifiedState = nil }
        } catch {
            stateFileReadable = false
            let failure = error as NSError
            let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError
            needsFilePermission = failure.code == NSFileReadNoPermissionError || (underlying?.domain == NSPOSIXErrorDomain && [1,13].contains(underlying?.code ?? 0))
            readFailure = "\(failure.domain) · \(failure.code)"
            let shared = authorization == .authorized ? INFocusStatusCenter.default.focusStatus.isFocused : nil
            // A shared false does not prove that the actual system mode is off.
            focused = notifiedState ?? (shared == true ? true : nil)
        }
        if let modeID, let data = try? Data(contentsOf: database.appendingPathComponent("ModeConfigurations.json")),
           let object = try? JSONSerialization.jsonObject(with: data),
           let mode = FocusFileSnapshot.configuration(modeID: modeID, in: object) {
            modeName = mode["name"] as? String ?? HL("Focus")
            modeSymbol = mode["symbolImageName"] as? String ?? "moon.fill"
            modeColor = Self.color(mode["tintColorName"] as? String)
        } else if focused != false || modeName.isEmpty {
            modeName = HL("Focus")
            modeSymbol = "moon.fill"
            modeColor = .systemPurple
        }
        isFocused = focused
        if let change = changes.update(focused) { events.send(change) }
        else if focused == true, let previousMode, let modeID, previousMode != modeID { events.send(true) }
        if let focused, !focused { previousMode = nil }
        else if let modeID { previousMode = modeID }
    }
    private static func color(_ name: String?) -> NSColor {
        switch name {
        case "systemIndigoColor": return .systemIndigo
        case "systemBlueColor": return .systemBlue
        case "systemGreenColor": return .systemGreen
        case "systemOrangeColor": return .systemOrange
        case "systemRedColor": return .systemRed
        case "systemYellowColor": return .systemYellow
        case "systemPinkColor": return .systemPink
        case "systemTealColor": return .systemTeal
        case "systemGrayColor": return .systemGray
        case "systemBrownColor": return .systemBrown
        case "systemCyanColor": return .systemCyan
        case "systemMintColor": return .systemMint
        default: return .systemPurple
        }
    }
}
