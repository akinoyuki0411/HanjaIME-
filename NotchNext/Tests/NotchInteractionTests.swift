import SwiftUI

@MainActor final class SettingsStore {
    var defaultTabRaw = "Home"
    var lastTabRaw = "Home"
    var visibleNavigationTabs = NotchTab.allCases
    var startingTab: NotchTab { (StartupDestination(rawValue: defaultTabRaw) ?? .home).resolved(last: lastTabRaw, visible: visibleNavigationTabs) }
    var shelfWidth = 640.0
    var shelfHeight = 320.0
    var openWidth = 640.0
    var openHeight = 400.0
    var homeContentWidth = 623.0
    var weatherWidth = 440.0
    var weatherHeight = 210.0
    var openOnHover = true
    var hapticFeedback = false
}
struct NotchGeometry {
    var screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    var notchSize = CGSize(width: 180, height: 32)
}
@MainActor final class SneakPeekCoordinator {
    static let shared = SneakPeekCoordinator()
    var visible = false
    var isInteracting = false
}
@main struct InteractionTests {
    @MainActor static func main() async {
        let vm = NotchViewModel(geometry: NotchGeometry(), settings: SettingsStore())
        vm.leftWingWidth = 40; vm.rightWingWidth = 90
        precondition(vm.closedSize.width == vm.geometry.notchSize.width + 180)
        precondition(vm.closedClickFrame.midX == vm.geometry.screenFrame.midX)
        vm.leftWingWidth = 90; vm.rightWingWidth = 40
        precondition(vm.closedClickFrame.midX == vm.geometry.screenFrame.midX)
        vm.leftWingWidth = 0; vm.rightWingWidth = 0
        vm.hoverChanged(true)
        try? await Task.sleep(nanoseconds: 650_000_000)
        precondition(vm.state == .closed && vm.isHoveringClosedNotch, "Hover must never fully open")
        vm.hoverChanged(false)
        precondition(!vm.isHoveringClosedNotch)
        vm.openFromClick()
        precondition(vm.state == .open)
        precondition(vm.displayedOpenSize.height == 194)
        vm.selectedWidget = .timers
        precondition(vm.displayedOpenSize.height == 400)
        vm.mouseExitedOpenNotch()
        try? await Task.sleep(nanoseconds: 350_000_000)
        precondition(vm.state == .closed)
        vm.open()
        vm.isPinned = true
        vm.mouseExitedOpenNotch()
        try? await Task.sleep(nanoseconds: 350_000_000)
        precondition(vm.state == .open)
        precondition(HomeWidget.decode("media,notes,media,invalid") == [.media, .notes])
        precondition(HomeWidget.moving(.mirror, before: .media, in: [.media, .calendar, .mirror]) == [.mirror, .media, .calendar])
        precondition(HomeWidget.moving(.notes, before: .media, in: [.media, .calendar]) == [.media, .calendar])
        precondition(HomeWidget.media.clampedWidth(1) == 240)
        precondition(HomeWidget.media.clampedWidth(1000) == 420)
        precondition(HomeWidget.mirror.clampedWidth(.nan) == 100)
        precondition(HomeWidget.calendar.clampedWidth(180) == 180)
        vm.isHoveringArtwork = true
        vm.hoverChanged(false)
        precondition(!vm.isHoveringArtwork)
        vm.isPinned = false
        vm.pointerIsInsideOpenNotch = { true }
        vm.mouseExitedOpenNotch()
        try? await Task.sleep(nanoseconds: 350_000_000)
        precondition(vm.state == .open, "A transition hover-exit must not close under the pointer")
        vm.pointerIsInsideOpenNotch = { false }
        vm.mouseExitedOpenNotch()
        vm.cancelPendingClose()
        try? await Task.sleep(nanoseconds: 350_000_000)
        precondition(vm.state == .open, "Re-entering must cancel the delayed close")
        vm.close()
        try? await Task.sleep(nanoseconds: 20_000_000)
        precondition(vm.acceptsClosedClick(at: CGPoint(x: 720, y: 900)), "The topmost screen edge must open")
        precondition(!vm.acceptsClosedClick(at: CGPoint(x: 100, y: 900)), "Do not capture other menu-bar buttons")
        precondition(!vm.acceptsClosedClick(at: CGPoint(x: 720, y: 800)), "Do not capture the desktop")
        vm.openFromClick()
        precondition(!vm.acceptsClosedClick(at: CGPoint(x: 720, y: 900)), "Expanded widgets must keep their own clicks")
        vm.settings.homeContentWidth = 900
        precondition(vm.openSize.width == 900, "Widget resizing must expand the home")
        vm.settings.homeContentWidth = 2000
        precondition(vm.openSize.width == 1392, "Do not expand past the screen")
        precondition(HomeWidget.movingToPosition(of: .mirror, source: .media, in: [.media, .calendar, .mirror]) == [.calendar, .mirror, .media])
        precondition(HomeWidget.movingToPosition(of: .media, source: .mirror, in: [.media, .calendar, .mirror]) == [.mirror, .media, .calendar])
        precondition(HomeWidget.movingToPosition(of: .calendar, source: .media, in: [.media, .calendar, .mirror]) == [.calendar, .media, .mirror])
        vm.tab = .shelf
        vm.settings.shelfWidth = 850
        vm.settings.shelfHeight = 450
        precondition(vm.openSize == CGSize(width: 850, height: 450))
        vm.settings.shelfWidth = 2000
        vm.settings.shelfHeight = 900
        precondition(vm.openSize == CGSize(width: 1100, height: 560))
        vm.settings.shelfWidth = 10
        vm.settings.shelfHeight = 10
        precondition(vm.openSize == CGSize(width: 480, height: 220))
        vm.tab = .weather
        vm.settings.openWidth = 1000
        precondition(vm.openSize == CGSize(width: 440, height: 210), "Weather should stay compact even with a wide home")
        vm.settings.openWidth = 300
        precondition(vm.openSize == CGSize(width: 440, height: 210))
        vm.settings.weatherWidth = 1000; vm.settings.weatherHeight = 500
        precondition(vm.openSize == CGSize(width: 680, height: 340))
        vm.settings.weatherWidth = 100; vm.settings.weatherHeight = 100
        precondition(vm.openSize == CGSize(width: 400, height: 210))
        vm.settings.weatherWidth = 520; vm.settings.weatherHeight = 260
        precondition(vm.openSize == CGSize(width: 520, height: 260))
        vm.settings.weatherWidth = 440; vm.settings.weatherHeight = 210
        for destination in StartupDestination.allCases {
            vm.settings.defaultTabRaw = destination.rawValue
            vm.tab = .weather
            vm.close()
            try? await Task.sleep(nanoseconds: 20_000_000)
            vm.open()
            precondition(vm.tab == destination.resolved(last: "Weather", visible: NotchTab.allCases))
            vm.close()
            try? await Task.sleep(nanoseconds: 20_000_000)
            vm.open(tab: .shelf)
            precondition(vm.tab == .shelf, "An explicit file drop overrides the startup preference")
        }
        vm.settings.defaultTabRaw = "Weather"
        vm.settings.visibleNavigationTabs = [.home]
        vm.close()
        try? await Task.sleep(nanoseconds: 20_000_000)
        vm.open()
        precondition(vm.tab == .home, "A hidden startup tab falls back to Home")
        vm.close()
        try? await Task.sleep(nanoseconds: 20_000_000)
        vm.weatherPreviewAvailable = true
        vm.hoverChanged(true)
        precondition(vm.isShowingWeatherPeek)
        precondition(vm.closedClickFrame.height == vm.geometry.notchSize.height + 30)
        vm.isHoveringArtwork = true
        precondition(!vm.isShowingWeatherPeek, "Album hover should keep its music information")
        vm.isHoveringArtwork = false
        vm.settings.openOnHover = false
        precondition(!vm.isShowingWeatherPeek)
        vm.settings.openOnHover = true
        vm.weatherPreviewAvailable = false
        precondition(!vm.isShowingWeatherPeek, "Disabled or unavailable weather must not leave a blank peek")
        vm.open(tab: .home)
        vm.open(tab: .weather)
        vm.mouseExitedOpenNotch()
        try? await Task.sleep(nanoseconds: 300_000_000)
        precondition(vm.state == .open, "Tab resize must not close before the pointer can follow")
        try? await Task.sleep(nanoseconds: 600_000_000)
        precondition(vm.state == .closed, "Leaving after the resize grace period still closes")
        print("53 notch interaction and layout assertions passed")
    }
}
