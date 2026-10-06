import SwiftUI
import Combine

/// The collapsed notch sliver: live-activity wings either side of the physical
/// notch cutout. Wing content is measured via preference keys and fed back to
/// the view model so the black shape grows to fit.
struct ClosedNotchView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var settings: SettingsStore

    @ObservedObject private var peek = SneakPeekCoordinator.shared
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var battery = BatteryMonitor.shared
    @ObservedObject private var timers = TimerManager.shared
    @ObservedObject private var weather = WeatherStore.shared

    /// Transient battery/bluetooth event live activity.
    @State private var transientEvent: TransientEvent?
    @State private var transientHideTask: Task<Void, Never>?

    enum TransientEvent: Equatable {
        case battery
        case message(String, String)
        case bluetooth(BluetoothEvent)

        static func == (lhs: TransientEvent, rhs: TransientEvent) -> Bool {
            switch (lhs, rhs) {
            case (.battery, .battery): return true
            case let (.message(a, x), .message(b, y)): return a == b && x == y
            case let (.bluetooth(a), .bluetooth(b)):
                return a.deviceName == b.deviceName && a.connected == b.connected
            default: return false
            }
        }
    }

    private var weatherVisible: Bool {
        settings.weatherLiveActivity && weather.forecast != nil && (settings.weatherDuringMusic || music.playback?.isPlaying != true)
    }
    private var canPeekWeather: Bool { weatherVisible && !peek.visible && transientEvent == nil }
    private var weatherSummary: String {
        guard let forecast = weather.forecast else { return "" }
        let korean = settings.language == "ko"
        var summary = weather.city + " · " + forecast.condition.title(korean: korean)
        if let today = forecast.today, let low = today.low {
            summary += korean ? " · 최고 \(Int(today.temperature.rounded()))° 최저 \(Int(low.rounded()))°" : " · H:\(Int(today.temperature.rounded()))° L:\(Int(low.rounded()))°"
        }
        return summary
    }

    var body: some View {
        VStack(spacing: 0) {
        HStack(spacing: 0) {
            leftWing
                .frame(height: vm.geometry.notchSize.height)
                .fixedSize()
                .background(WingWidthReader(side: .left))
                .frame(width: max(vm.leftWingWidth, vm.rightWingWidth), alignment: .leading)
            Color.clear
                .frame(width: vm.geometry.notchSize.width, height: vm.geometry.notchSize.height)
            rightWing
                .frame(height: vm.geometry.notchSize.height)
                .fixedSize()
                .background(WingWidthReader(side: .right))
                .frame(width: max(vm.leftWingWidth, vm.rightWingWidth), alignment: .trailing)
        }
        if vm.isShowingWeatherPeek {
            Text(weatherSummary).font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.65)).lineLimit(1).minimumScaleFactor(0.75)
                .frame(width: max(100, vm.closedSize.width - 20), height: 25, alignment: .top)
                .transition(.opacity).allowsHitTesting(false)
        } else if vm.isHoveringArtwork, let playback = music.playback, playback.hasContent {
            VStack(spacing: 2) {
                Text(playback.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                Text(playback.artist).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            }.lineLimit(1).frame(width: max(100, vm.closedSize.width - 28))
                .padding(.bottom, 7).padding(.top, 2)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
        }
        .onAppear { vm.weatherPreviewAvailable = canPeekWeather }
        .onChange(of: canPeekWeather) { _, available in vm.weatherPreviewAvailable = available }
        .onDisappear { vm.weatherPreviewAvailable = false }
        .onPreferenceChange(WingWidthPreferenceKey.self) { widths in
            withAnimation(.easeInOut(duration: 0.24)) {
                vm.leftWingWidth = widths[.left] ?? 0
                vm.rightWingWidth = widths[.right] ?? 0
            }
        }
        .onReceive(CodeActivityStore.shared.messages) { event in
            showTransient(.message(event.title + " · " + HL(event.phase.capitalized) + (event.progress.map { " \(Int($0 * 100))%" } ?? ""), event.phase == "completed" ? "checkmark.circle" : "hammer"))
        }
        .onReceive(TimerManager.shared.activityMessages) { text in
            showTransient(.message(text, "target"))
        }
        .onReceive(BatteryMonitor.shared.events) { _ in
            showTransient(.battery)
        }
        .onReceive(BluetoothMonitor.shared.events) { event in
            showTransient(.bluetooth(event))
        }
    }

    // MARK: Wing content

    @ViewBuilder
    private var leftWing: some View {
        if peek.visible {
            HUDWingLeftView()
                .frame(width: 96)
                .padding(.leading, 8)
        } else if case .message(let text, _) = transientEvent {
            Text(text).font(.system(size: 11, weight: .medium))
                .lineLimit(1).frame(maxWidth: 180).padding(.horizontal, 10)
        } else if case .battery = transientEvent, settings.batteryLiveActivity {
            Text(battery.eventStatusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(batteryEventColor)
                .lineLimit(1)
                .padding(.leading, 10)
                .padding(.trailing, 4)
        } else {
            HStack(spacing: 5) {
                if settings.mediaLiveActivity && FocusActivityPolicy.allows("Music") { MediaClosedWingLeft() }
                if weatherVisible {
                    Image(systemName: weather.symbol).symbolRenderingMode(.multicolor)
                        .font(.system(size: 15)).frame(width: 23)
                        .scaleEffect(vm.isHoveringClosedNotch && settings.openOnHover ? 1.08 : 1)
                        .accessibilityLabel(HL("Weather"))
                }
            }.padding(.leading, 7).padding(.trailing, 3)
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        if peek.visible {
            HUDWingRightView()
                .frame(width: 96)
                .padding(.trailing, 8)
        } else if let event = transientEvent {
            switch event {
            case .message(_, let symbol):
                Image(systemName: symbol).foregroundStyle(.white).padding(.horizontal, 12)
            case .battery:
                if settings.batteryLiveActivity {
                    BatteryWingView(variant: .event)
                        .padding(.horizontal, 8)
                }
            case .bluetooth(let btEvent):
                BluetoothEventWingView(event: btEvent)
                    .padding(.horizontal, 8)
            }
        } else {
            HStack(spacing: 7) {
                if settings.mediaLiveActivity && FocusActivityPolicy.allows("Music") {
                    MediaClosedWingRight()
                }
                if settings.timerLiveActivity {
                    TimerClosedWing()
                }
                if settings.calendarLiveActivity && FocusActivityPolicy.allows("Calendar") {
                    CalendarNextEventWing()
                }
                if weatherVisible, let forecast = weather.forecast {
                    Text("\(Int(forecast.current.temperature_2m.rounded()))°").monospacedDigit()
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                        .accessibilityLabel(HL("Weather") + " " + weather.city + " \(Int(forecast.current.temperature_2m.rounded()))°")
                }
                if settings.todosLiveActivity {
                    TodoCountWing()
                }
            }
            .padding(.leading, 3)
            .padding(.trailing, hasAnyRightContent ? 8 : 0)
        }
    }

    private var hasAnyRightContent: Bool {
        (settings.mediaLiveActivity && music.playback != nil) ||
        (settings.weatherLiveActivity && weather.forecast != nil && (settings.weatherDuringMusic || music.playback?.isPlaying != true))
    }

    private var batteryEventColor: Color {
        if case .lowBattery = battery.lastEvent { return .red }
        return battery.isCharging || battery.isCharged ? .green : .white
    }

    private func showTransient(_ event: TransientEvent) {
        transientHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.24)) {
            transientEvent = event
        }
        transientHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.24)) {
                transientEvent = nil
            }
        }
    }
}

// MARK: - Wing width measurement

enum WingSide: Hashable {
    case left, right
}

struct WingWidthPreferenceKey: PreferenceKey {
    static var defaultValue: [WingSide: CGFloat] = [:]
    static func reduce(value: inout [WingSide: CGFloat], nextValue: () -> [WingSide: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: max)
    }
}

private struct WingWidthReader: View {
    let side: WingSide

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: WingWidthPreferenceKey.self, value: [side: proxy.size.width])
        }
    }
}
