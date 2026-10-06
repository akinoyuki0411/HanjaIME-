import Foundation

enum NavigationPlacement: String, CaseIterable, Identifiable {
    case split, splitReversed, left, leftReversed, right, rightReversed
    var id: String { rawValue }
    var leftTabs: [String] {
        switch self {
        case .split: return ["Home"]
        case .splitReversed: return ["Shelf"]
        case .left: return ["Home", "Shelf"]
        case .leftReversed: return ["Shelf", "Home"]
        case .right, .rightReversed: return []
        }
    }
    var rightTabs: [String] {
        switch self {
        case .split: return ["Shelf"]
        case .splitReversed: return ["Home"]
        case .right: return ["Home", "Shelf"]
        case .rightReversed: return ["Shelf", "Home"]
        case .left, .leftReversed: return []
        }
    }
    func title(korean: Bool) -> String {
        switch self {
        case .split: return korean ? "양쪽 · 홈 왼쪽" : "Split · Home left"
        case .splitReversed: return korean ? "양쪽 · 파일 보관함 왼쪽" : "Split · Shelf left"
        case .left: return korean ? "둘 다 왼쪽 · 홈 먼저" : "Both left · Home first"
        case .leftReversed: return korean ? "둘 다 왼쪽 · 파일 보관함 먼저" : "Both left · Shelf first"
        case .right: return korean ? "둘 다 오른쪽 · 홈 먼저" : "Both right · Home first"
        case .rightReversed: return korean ? "둘 다 오른쪽 · 파일 보관함 먼저" : "Both right · Shelf first"
        }
    }
}
