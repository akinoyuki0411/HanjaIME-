import SwiftUI
import Combine
import ServiceManagement

/// Central user settings, persisted via UserDefaults.
/// Feature modules should keep feature-specific keys here grouped under a MARK,
/// or use their own @AppStorage keys in their own views.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @AppStorage("hanjime.language") var language = "ko" { willSet { objectWillChange.send() } }

    @AppStorage("layout.widgetWidths") var widgetWidths = "{}" { willSet { objectWillChange.send() } }
    func width(for widget: HomeWidget) -> Double {
        let values = (try? JSONDecoder().decode([String: Double].self, from: Data(widgetWidths.utf8))) ?? [:]
        return widget.clampedWidth(values[widget.rawValue] ?? widget.defaultWidth)
    }
    var homeContentWidth: Double {
        let widgets = HomeWidget.decode(widgetOrder)
        // 26 pt outer gutters; each divider has a 16 pt gap on either side.
        return widgets.reduce(52.0) { $0 + width(for: $1) } + Double(max(0, widgets.count - 1)) * (widgetDividers ? 33 : 16)
    }
    func setWidth(_ value: Double, for widget: HomeWidget) {
        var values = (try? JSONDecoder().decode([String: Double].self, from: Data(widgetWidths.utf8))) ?? [:]
        values[widget.rawValue] = widget.clampedWidth(value)
        if let data = try? JSONEncoder().encode(values), let raw = String(data: data, encoding: .utf8) { widgetWidths = raw }
    }

    // MARK: General
    @AppStorage("openOnHover") var openOnHover = true { willSet { objectWillChange.send() } }
    @AppStorage("hoverDelay") var hoverDelay = 0.1 { willSet { objectWillChange.send() } }
    @AppStorage("showOnAllDisplays") var showOnAllDisplays = true { willSet { objectWillChange.send() } }
    @AppStorage("fakeNotchOnExternalDisplays") var fakeNotchOnExternalDisplays = true { willSet { objectWillChange.send() } }
    @AppStorage("hapticFeedback") var hapticFeedback = true { willSet { objectWillChange.send() } }

    // MARK: Appearance
    @AppStorage("notchExtraWidth") var notchExtraWidth = 0.0 { willSet { objectWillChange.send() } }
    @AppStorage("openCornerRadius") var openCornerRadius = 24.0 { willSet { objectWillChange.send() } }
    @AppStorage("showBorderGlow") var showBorderGlow = false { willSet { objectWillChange.send() } }
    /// "black" | "gradient" | "artwork"
    @AppStorage("appearance.backgroundStyle") var backgroundStyle = "black" { willSet { objectWillChange.send() } }
    @AppStorage("appearance.gradientStartHex") var gradientStartHex = "#101018" { willSet { objectWillChange.send() } }
    @AppStorage("appearance.gradientEndHex") var gradientEndHex = "#000000" { willSet { objectWillChange.send() } }
    @AppStorage("appearance.accentHex") var accentHex = "#FF8A3D" { willSet { objectWillChange.send() } }
    @AppStorage("appearance.openWidth") var openWidth = 640.0 { willSet { objectWillChange.send() } }
    @AppStorage("appearance.openHeight") var openHeight = 400.0 { willSet { objectWillChange.send() } }

    @AppStorage("layout.widgetOrder") var widgetOrder = "media,calendar,mirror" { willSet { objectWillChange.send() } }
    @AppStorage("layout.shelfAirDropTrailing") var shelfAirDropTrailing = false { willSet { objectWillChange.send() } }
    @AppStorage("layout.shelfWidth") var shelfWidth = 640.0 { willSet { objectWillChange.send() } }
    @AppStorage("layout.shelfHeight") var shelfHeight = 320.0 { willSet { objectWillChange.send() } }
    @AppStorage("layout.airDropWidth") var airDropWidth = 92.0 { willSet { objectWillChange.send() } }
    @AppStorage("layout.navigationPlacement") var navigationPlacement = "split" { willSet { objectWillChange.send() } }
    @AppStorage("layout.widgetDividers") var widgetDividers = true { willSet { objectWillChange.send() } }
    @AppStorage("layout.navigationLayout") var navigationLayoutRaw = "" { willSet { objectWillChange.send() } }
    @AppStorage("layout.lastTab") var lastTabRaw = "Home"
    @AppStorage("weather.width") var weatherWidth = 440.0 { willSet { objectWillChange.send() } }
    @AppStorage("weather.height") var weatherHeight = 210.0 { willSet { objectWillChange.send() } }
    @AppStorage("weather.duringMusic") var weatherDuringMusic = false { willSet { objectWillChange.send() } }
    @AppStorage("weather.liveActivity") var weatherLiveActivity = true { willSet { objectWillChange.send() } }
    var navigationLayout: NavigationLayout {
        get { NavigationLayout.decode(navigationLayoutRaw, legacy: navigationPlacement) }
        set { navigationLayoutRaw = newValue.encoded }
    }
    var visibleNavigationTabs: [NotchTab] {
        NotchTab.allCases.filter { $0 == .home || visibleTabsCSV.split(separator: ",").contains(Substring($0.rawValue)) }
    }
    func setTabVisible(_ tab: NotchTab, visible: Bool) {
        guard tab != .home else { return }
        var tabs = visibleNavigationTabs
        tabs.removeAll { $0 == tab }
        if visible { tabs.append(tab) }
        visibleTabsCSV = tabs.map(\.rawValue).joined(separator: ",")
        if visible && tab == .weather { Task { await WeatherStore.shared.refresh() } }
    }
    var startingTab: NotchTab { (StartupDestination(rawValue: defaultTabRaw) ?? .home).resolved(last: lastTabRaw, visible: visibleNavigationTabs) }
    func migrateWeatherTab() {
        guard !UserDefaults.standard.bool(forKey: "layout.weatherTabMigrated") else { return }
        if !visibleTabsCSV.split(separator: ",").contains("Weather") { visibleTabsCSV += ",Weather" }
        widgetOrder = HomeWidget.decode(widgetOrder).filter { $0.rawValue != "weather" }.map(\.rawValue).joined(separator: ",")
        UserDefaults.standard.set(true, forKey: "layout.weatherTabMigrated")
    }
    // MARK: Layout
    /// Comma-separated raw values of visible tabs (Home is always shown).
    @AppStorage("layout.visibleTabs") var visibleTabsCSV = "Home,Shelf" { willSet { objectWillChange.send() } }
    @AppStorage("layout.defaultTab") var defaultTabRaw = "Home" { willSet { objectWillChange.send() } }
    /// "mediaCalendar" | "mediaOnly" | "calendarOnly"
    @AppStorage("layout.homeLayout") var homeLayout = "mediaCalendar" { willSet { objectWillChange.send() } }

    var accentColor: Color { Color(hex: accentHex) }

    // MARK: Media colors
    @AppStorage("media.favoriteHex") var favoriteHex = "#A8A8AD" { willSet { objectWillChange.send() } }
    @AppStorage("media.progressHex") var progressHex = "#A8A8AD" { willSet { objectWillChange.send() } }

    // MARK: Live activities
    @AppStorage("mediaLiveActivity") var mediaLiveActivity = true { willSet { objectWillChange.send() } }
    @AppStorage("timerLiveActivity") var timerLiveActivity = true { willSet { objectWillChange.send() } }
    @AppStorage("batteryLiveActivity") var batteryLiveActivity = true { willSet { objectWillChange.send() } }
    @AppStorage("agentsLiveActivity") var agentsLiveActivity = false { willSet { objectWillChange.send() } }
    @AppStorage("calendarLiveActivity") var calendarLiveActivity = true { willSet { objectWillChange.send() } }
    @AppStorage("todosLiveActivity") var todosLiveActivity = true { willSet { objectWillChange.send() } }

    // MARK: HUD replacement
    @AppStorage("replaceSystemHUD") var replaceSystemHUD = false { willSet { objectWillChange.send() } }

    // MARK: Weather
    @AppStorage("weatherEnabled") var weatherEnabled = true { willSet { objectWillChange.send() } }
    @AppStorage("weatherUseCelsius") var weatherUseCelsius = false { willSet { objectWillChange.send() } }
    @AppStorage("weatherManualLocation") var weatherManualLocation = "" { willSet { objectWillChange.send() } }

    // MARK: Agent sessions
    @AppStorage("agentsNotifyOnAttention") var agentsNotifyOnAttention = true { willSet { objectWillChange.send() } }
    @AppStorage("agentsNotifyOnCompletion") var agentsNotifyOnCompletion = true { willSet { objectWillChange.send() } }
    @AppStorage("agentsIdleCutoffMinutes") var agentsIdleCutoffMinutes = 30.0 { willSet { objectWillChange.send() } }

    // MARK: Launch at login
    @AppStorage("showMenuBarIcon") var showMenuBarIcon = true { willSet { objectWillChange.send() } }
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Atoll: launch-at-login toggle failed: \(error)")
            }
        }
    }
}
