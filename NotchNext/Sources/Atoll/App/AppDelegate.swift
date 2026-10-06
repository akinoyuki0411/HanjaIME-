import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [NotchController] = []
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var restoreSettingsAfterFace = false
    private var toggleHotKey: GlobalHotKey?
    private var audioHotKey: GlobalHotKey?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        SettingsStore.shared.migrateWeatherTab()
        rebuildControllers()
        setupStatusItem()
        SettingsStore.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.statusItem?.isVisible = SettingsStore.shared.showMenuBarIcon
            }
        }.store(in: &cancellables)
        startManagers()
        wireIntegrations()
        FaceIntegration.shared.$presenting.removeDuplicates().sink { [weak self] active in
            guard let self else { return }
            if active {
                self.restoreSettingsAfterFace = self.settingsWindow?.isVisible == true
                self.settingsWindow?.orderOut(nil)
            }
            for controller in self.controllers { controller.setFacePresentation(active) }
            if !active && self.restoreSettingsAfterFace {
                self.settingsWindow?.orderFront(nil)
                self.restoreSettingsAfterFace = false
            }
        }.store(in: &cancellables)
        // Upstream input-synthesis debug channel is disabled.
        // Login launches stay unobtrusive. Settings opens only on explicit request.
        if CommandLine.arguments.contains("--settings") { openSettings() }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(openSettings), name: Notification.Name("org.hanjaime.notch.openSettings"), object: nil)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildControllers()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .atollOpenSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openSettings()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        WeatherStore.shared.stop()
        AmbientAudio.shared.stop()
        QuickAwake.shared.stop()
        VoiceStore.shared.stop()
        FaceIntegration.shared.stop()
        ShelfStore.shared.handleAppWillTerminate()
        NotesStore.shared.flush()
        MusicManager.shared.stop()
        MirrorManager.shared.stopSession()
        MediaKeyInterceptor.shared.stop()
        FocusStatusMonitor.shared.stop()
        BatteryMonitor.shared.stop()
        BluetoothMonitor.shared.stop()
    }

    // MARK: Managers

    private func startManagers() {
        WeatherStore.shared.start()
        MusicManager.shared.start()
        CalendarManager.shared.start()
        FocusStatusMonitor.shared.start()
        BatteryMonitor.shared.start()
        _ = ShelfStore.shared
        _ = TodosStore.shared
        _ = TimerManager.shared

        HUDVolumeManager.shared.start()
        HUDBrightnessManager.shared.start()
        MediaKeyInterceptor.shared.start()
        KeyboardBrightnessManager.shared.registerShortcuts()

        CodeActivityStore.shared.start()


        // Bluetooth triggers a modal TCC prompt on first use (which blocks the
        // main thread) — never auto-start it. Start only when macOS already
        // granted access, or when the user explicitly enabled the toggle
        // (explicit = present in the persistent domain, not a registered default).
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if Self.bluetoothExplicitlyWanted {
                BluetoothMonitor.shared.start()
            }
        }
    }

    private static var bluetoothExplicitlyWanted: Bool {
        let domain = Bundle.main.bundleIdentifier.flatMap {
            UserDefaults.standard.persistentDomain(forName: $0)
        }
        guard let explicit = domain?["systemEvents.bluetoothLiveActivity"] as? Bool else {
            return false // registered default only — user never chose; avoid the TCC prompt
        }
        return explicit
    }

    private func wireIntegrations() {
        FocusStatusMonitor.shared.events.sink { focused in
            if UserDefaults.standard.object(forKey: "systemEvents.focusChanges") as? Bool ?? true {
                SneakPeekCoordinator.shared.show(type: .focus, value: focused ? 1 : 0)
            }
        }.store(in: &cancellables)
        configureAudioShortcut()
        // Drag a file toward the notch → open the shelf on the pointer's screen.
        DragDetector.shared.onDragNearNotch = { [weak self] in
            Task { @MainActor [weak self] in
                self?.controllerUnderMouse()?.viewModel.open(tab: .shelf)
            }
        }
        DragDetector.shared.start()

        // Timer completion → open the tools tab on the Timers pane.
        TimerManager.shared.onCountdownFinished = { [weak self] in
            Task { @MainActor [weak self] in
                let model = self?.primaryController()?.viewModel
                model?.open(tab: .home)
                model?.selectedWidget = .timers
            }
        }

        // Display-related settings → rebuild the notch panels. objectWillChange
        // fires in willSet, so hop a runloop before reading, and only rebuild on
        // an actual change (slider drags fire this constantly).
        // Open-size changes are handled inside each NotchController.
        var displayConfig = (SettingsStore.shared.showOnAllDisplays,
                             SettingsStore.shared.fakeNotchOnExternalDisplays)
        SettingsStore.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let current = (SettingsStore.shared.showOnAllDisplays,
                               SettingsStore.shared.fakeNotchOnExternalDisplays)
                if current != displayConfig {
                    displayConfig = current
                    self.rebuildControllers()
                }
            }
            .store(in: &cancellables)

        // Enabling the Bluetooth live activity at runtime boots the monitor
        // (start() is idempotent; the TCC prompt fires on first IOBluetooth use,
        // which is fine here because the user just flipped the toggle).
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.configureAudioShortcut()
                if Self.bluetoothExplicitlyWanted {
                    BluetoothMonitor.shared.start()
                }
            }
        }

        // ⌥⌘N toggles the nook.
        toggleHotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_N),
            modifiers: UInt32(cmdKey | optionKey)
        ) { [weak self] in
            self?.primaryController()?.viewModel.toggle()
        }
        if toggleHotKey == nil {
            NSLog("Atoll: global hotkey ⌥⌘N registration failed (conflict with another app?)")
        }
    }

    private func configureAudioShortcut() {
        guard UserDefaults.standard.bool(forKey: "audio.cycleShortcut") else { audioHotKey = nil; return }
        guard audioHotKey == nil else { return }
        audioHotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_O), modifiers: UInt32(cmdKey | optionKey | controlKey), id: 4) {
            guard UserDefaults.standard.bool(forKey: "audio.cycleShortcut") else { return }
            let devices = AudioOutputDevices.list()
            guard !devices.isEmpty else { return }
            let current = devices.firstIndex { $0.id == AudioOutputDevices.current() } ?? -1
            let next = devices[(current + 1) % devices.count]
            if AudioOutputDevices.select(next.id) { SneakPeekCoordinator.shared.show(type: .volume, value: HUDVolumeManager.shared.volume) }
        }
    }

    // MARK: Controllers

    private func rebuildControllers() {
        controllers.forEach { $0.tearDown() }
        controllers.removeAll()

        let settings = SettingsStore.shared
        var screens: [NSScreen]
        if settings.showOnAllDisplays {
            screens = NSScreen.screens
            if !settings.fakeNotchOnExternalDisplays {
                screens = screens.filter { $0.safeAreaInsets.top > 0 }
            }
        } else if let screen = NotchGeometry.preferredScreen() {
            screens = [screen]
        } else {
            screens = []
        }
        controllers = screens.map { screen in
            let controller = NotchController(screen: screen, settings: settings)
            controller.viewModel.tab = settings.startingTab
            // Each visible mirror owns a preview lease. Closing one display must
            // not stop a mirror that is still visible on another display.
            controller.setFacePresentation(FaceIntegration.shared.presenting)
            return controller
        }
    }

    private func primaryController() -> NotchController? {
        controllerUnderMouse() ?? controllers.first
    }

    private func controllerUnderMouse() -> NotchController? {
        let mouse = NSEvent.mouseLocation
        return controllers.first { $0.viewModel.geometry.screenFrame.contains(mouse) } ?? controllers.first
    }

    // MARK: Status item & settings window

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "sparkles.rectangle.stack",
            accessibilityDescription: "Atoll"
        )

        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: "노치 열기 / 닫기", action: #selector(toggleNook), keyEquivalent: "")
        menu.addItem(toggleItem)
        menu.addItem(NSMenuItem(title: "집중 세션 시작 / 일시정지", action: #selector(quickFocus), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "배경 소리 켜기 / 끄기", action: #selector(quickAudio), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "1시간 화면 잠자기 방지 / 해제", action: #selector(quickAwake), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "일정 보기", action: #selector(quickCalendar), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "날씨 보기", action: #selector(quickWeather), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "한지미 노치 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        if let quit = menu.items.last { quit.target = nil }
        item.menu = menu
        statusItem = item
        item.isVisible = SettingsStore.shared.showMenuBarIcon
    }

    @objc private func toggleNook() {
        primaryController()?.viewModel.toggle()
    }

    @objc private func quickFocus() {
        let timer = TimerManager.shared
        if timer.isPomodoroRunning { timer.pausePomodoro() } else { timer.startPomodoro() }
        primaryController()?.viewModel.open(tab: .home)
        primaryController()?.viewModel.selectedWidget = .timers
    }
    @objc private func quickAudio() { AmbientAudio.shared.playing ? AmbientAudio.shared.stop() : AmbientAudio.shared.start() }
    @objc private func quickAwake() { QuickAwake.shared.toggle() }
    @objc private func quickCalendar() {
        primaryController()?.viewModel.open(tab: .home)
        primaryController()?.viewModel.selectedWidget = .calendar
    }
    @objc private func quickWeather() {
        guard SettingsStore.shared.visibleNavigationTabs.contains(.weather) else { return }
        primaryController()?.viewModel.selectedWidget = nil
        primaryController()?.viewModel.open(tab: .weather)
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "한지미 노치 설정"
            window.contentView = NSHostingView(
                rootView: SettingsRootView().environmentObject(SettingsStore.shared)
            )
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Do not assign keyboard focus to a tab when the settings window opens.
        // User-initiated Tab navigation and editable controls retain normal focus.
        DispatchQueue.main.async { [weak self] in
            self?.settingsWindow?.makeFirstResponder(nil)
        }
    }
}
