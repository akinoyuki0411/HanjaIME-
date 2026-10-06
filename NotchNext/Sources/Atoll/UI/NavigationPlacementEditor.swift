import SwiftUI

struct NavigationPlacementEditor: View {
    @EnvironmentObject private var settings: SettingsStore
    private let orders: [[NotchTab]] = [[.home,.shelf,.weather],[.home,.weather,.shelf],[.shelf,.home,.weather],[.shelf,.weather,.home],[.weather,.home,.shelf],[.weather,.shelf,.home]]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(settings.language == "ko" ? "탭 순서" : "Tab order", selection: Binding(get: { settings.navigationLayout.order.map(\.rawValue).joined(separator: ",") }, set: { raw in
                var layout = settings.navigationLayout; layout.order = raw.split(separator: ",").compactMap { NotchTab(rawValue: String($0)) }; settings.navigationLayout = layout
            })) {
                ForEach(orders, id: \.self) { order in Text(order.map { HL($0.rawValue) }.joined(separator: " · ")).tag(order.map(\.rawValue).joined(separator: ",")) }
            }
            HStack {
                Button(settings.language == "ko" ? "모두 왼쪽" : "All left") { var layout = settings.navigationLayout; layout.left = NotchTab.allCases; settings.navigationLayout = layout }
                Button(settings.language == "ko" ? "모두 오른쪽" : "All right") { var layout = settings.navigationLayout; layout.left = []; settings.navigationLayout = layout }
            }
            ForEach(settings.navigationLayout.order) { tab in
                HStack {
                    Label(HL(tab.rawValue), systemImage: tab.systemImage).frame(maxWidth: .infinity, alignment: .leading)
                    Picker(HL(tab.rawValue), selection: Binding(get: { settings.navigationLayout.left.contains(tab) }, set: { left in
                        var layout = settings.navigationLayout; layout.left.removeAll { $0 == tab }; if left { layout.left.append(tab) }; settings.navigationLayout = layout
                    })) {
                        Text(settings.language == "ko" ? "왼쪽" : "Left").tag(true)
                        Text(settings.language == "ko" ? "오른쪽" : "Right").tag(false)
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 180)
                }
            }
        }.font(.system(size: 12))
    }
}
