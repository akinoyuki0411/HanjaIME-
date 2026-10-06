import SwiftUI

extension Notification.Name {
    static let atollOpenSettings = Notification.Name("Atoll.openSettings")
}

struct OpenNotchView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Use the two safe sides of the hardware cutout, instead of
            // reserving an empty notch-height row above the navigation.
            let placement = settings.navigationLayout
            HStack(spacing: 0) {
                navigationGroup(placement.tabs(left: true, visible: settings.visibleNavigationTabs), alignment: .leading)
                Color.clear.frame(width: vm.geometry.notchSize.width + 12)
                navigationGroup(placement.tabs(left: false, visible: settings.visibleNavigationTabs), alignment: .trailing)
            }.frame(height: max(26, vm.geometry.notchSize.height - 4))
            if let widget = vm.selectedWidget, vm.tab == .home {
                Button { vm.selectedWidget = nil } label: {
                    Label(HL(widget.title), systemImage: "chevron.left")
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Group {
                if vm.tab == .shelf { ShelfView() }
                else if vm.tab == .weather { WeatherWidget() }
                else if let widget = vm.selectedWidget { detail(widget) }
                else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 16) {
                            ForEach(HomeWidget.decode(settings.widgetOrder)) { widget in
                                if widget == .media {
                                    CompactMediaView().frame(width: settings.width(for: widget))
                                } else if widget == .mirror {
                                    InlineMirrorWidget().frame(width: settings.width(for: widget), height: settings.width(for: widget))
                                } else {
                                    if widget == .calendar { HomeCalendarWidget { vm.selectedWidget = .calendar } }
                                    else {
                                        Button { vm.selectedWidget = widget } label: { HomeWidgetTile(widget: widget) }.buttonStyle(.plain)
                                    }
                                }
                                if settings.widgetDividers, widget != HomeWidget.decode(settings.widgetOrder).last {
                                    Divider().frame(height: 94).overlay(Color.white.opacity(0.08))
                                }
                            }
                        }.padding(.vertical, 3)
                    }.scrollIndicators(.hidden).scrollDisabled(true)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.top, 4)
        .padding(.horizontal, 26).padding(.bottom, 24)
        .foregroundStyle(.white)
        .onAppear { if CalendarManager.shared.resetDateOnOpen { CalendarManager.shared.goToToday() } }
        .onChange(of: settings.visibleNavigationTabs) { _, _ in
            if !settings.visibleNavigationTabs.contains(vm.tab) { vm.tab = .home; vm.selectedWidget = nil }
        }
        .environment(\.locale, Locale(identifier: settings.language == "ko" ? "ko_KR" : "en_US"))
    }
    private func navigationGroup(_ tabs: [NotchTab], alignment: Alignment) -> some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < CGFloat(tabs.count * 64)
            HStack(spacing: 4) {
                ForEach(tabs) { item in tab(item, compact: compact, width: min(compact ? 36 : 96, max(18, (geometry.size.width - CGFloat(max(0, tabs.count - 1)) * 4) / CGFloat(max(1, tabs.count))))) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        }.frame(maxWidth: .infinity)
    }
    private func tab(_ tab: NotchTab, compact: Bool, width: CGFloat) -> some View {
        Button { vm.tab = tab; vm.selectedWidget = nil } label: {
            Group {
                if compact { Image(systemName: tab.systemImage) }
                else {
                    HStack(spacing: 4) {
                        Image(systemName: tab.systemImage).frame(width: 14)
                        Text(HL(tab.rawValue)).lineLimit(1).minimumScaleFactor(0.7)
                    }.padding(.horizontal, 4)
                }
            }.font(.system(size: compact ? 12 : 10, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: width, height: 28)
                .background(vm.tab == tab ? Color.white.opacity(0.16) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(HL(tab.rawValue)).accessibilityLabel(HL(tab.rawValue))
    }
    @ViewBuilder private func detail(_ widget: HomeWidget) -> some View {
        switch widget {
        case .media: MediaPlayerCard()
        case .calendar: CalendarWidgetView()
        case .timers: TimersWidgetView()
        case .notes: NotesWidgetView()
        case .todos: TodosWidgetView()
        case .mirror: MirrorView()
        case .voice: VoiceWidget()
        }
    }
}
