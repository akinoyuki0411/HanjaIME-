import SwiftUI

@MainActor final class QuickAwake: ObservableObject {
    static let shared = QuickAwake()
    @Published private(set) var active = false
    private let lock = FocusWakeLock()
    private var expiry: Timer?
    func toggle() {
        if active { stop(); return }
        lock.update(enabled: true, focusing: true, paused: false)
        active = lock.isActive
        guard active else { return }
        expiry = Timer.scheduledTimer(withTimeInterval: 3600, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }
    func stop() {
        expiry?.invalidate(); expiry = nil
        lock.update(enabled: false, focusing: false, paused: false)
        active = false
    }
}

struct QuickActionsMenu: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject private var timer = TimerManager.shared
    @ObservedObject private var audio = AmbientAudio.shared
    @ObservedObject private var awake = QuickAwake.shared
    private func text(_ ko: String, _ en: String) -> String { settings.language == "ko" ? ko : en }
    var body: some View {
        Button(text(timer.isPomodoroRunning ? "집중 세션 일시정지" : "집중 세션 시작 / 재개", "Start / pause focus session")) {
            if timer.isPomodoroRunning { timer.pausePomodoro() } else { timer.startPomodoro() }
            DispatchQueue.main.async { vm.open(tab: .home); vm.selectedWidget = .timers }
        }
        Button(text(audio.playing ? "배경 소리 끄기" : "배경 소리 켜기", audio.playing ? "Stop background audio" : "Play background audio")) {
            audio.playing ? audio.stop() : audio.start()
        }
        Button(text(awake.active ? "화면 잠자기 방지 해제" : "1시간 화면 잠자기 방지", awake.active ? "Allow display sleep" : "Keep display awake for one hour")) { awake.toggle() }
        Divider()
        Button(text("일정 보기", "Show calendar")) { DispatchQueue.main.async { vm.open(tab: .home); vm.selectedWidget = .calendar } }
        if settings.visibleNavigationTabs.contains(.weather) {
            Button(text("날씨 보기", "Show weather")) { DispatchQueue.main.async { vm.open(tab: .weather) } }
        }
        Divider()
    }
}
