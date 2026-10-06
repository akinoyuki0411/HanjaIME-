import Foundation

enum NotchTab: String, CaseIterable, Identifiable, Codable {
    case home = "Home", shelf = "Shelf", weather = "Weather"
    var id: String { rawValue }
    var systemImage: String {
        switch self { case .home: return "house.fill"; case .shelf: return "tray.fill"; case .weather: return "cloud.sun.fill" }
    }
}
struct NavigationLayout: Codable, Equatable {
    var order: [NotchTab]
    var left: [NotchTab]
    static func decode(_ raw: String, legacy: String) -> Self {
        if let data = raw.data(using: .utf8), let value = try? JSONDecoder().decode(Self.self, from: data),
           Set(value.order) == Set(NotchTab.allCases), value.order.count == NotchTab.allCases.count,
           Set(value.left).isSubset(of: Set(NotchTab.allCases)), Set(value.left).count == value.left.count { return value }
        let placement = NavigationPlacement(rawValue: legacy) ?? .split
        let oldOrder = (placement.leftTabs + placement.rightTabs).compactMap(NotchTab.init(rawValue:))
        let oldLeft = placement.leftTabs.compactMap(NotchTab.init(rawValue:))
        return .init(order: oldOrder + [.weather], left: oldLeft + (placement == .left || placement == .leftReversed ? [.weather] : []))
    }
    var encoded: String { (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
    func tabs(left side: Bool, visible: [NotchTab]) -> [NotchTab] { order.filter { visible.contains($0) && left.contains($0) == side } }
}
enum StartupDestination: String, CaseIterable, Identifiable {
    case home = "Home", previous = "Previous", shelf = "Shelf", weather = "Weather"
    var id: String { rawValue }
    func resolved(last: String, visible: [NotchTab]) -> NotchTab {
        let tab = NotchTab(rawValue: self == .previous ? last : rawValue) ?? .home
        return visible.contains(tab) ? tab : .home
    }
}
