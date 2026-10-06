import Foundation
@main struct Tests {
    static func main() {
        let expected: [NavigationPlacement: ([String], [String])] = [
            .split: (["Home"], ["Shelf"]), .splitReversed: (["Shelf"], ["Home"]),
            .left: (["Home", "Shelf"], []), .leftReversed: (["Shelf", "Home"], []),
            .right: ([], ["Home", "Shelf"]), .rightReversed: ([], ["Shelf", "Home"])
        ]
        for placement in NavigationPlacement.allCases {
            let sides = expected[placement]!
            precondition(placement.leftTabs == sides.0 && placement.rightTabs == sides.1)
            precondition(Set(placement.leftTabs + placement.rightTabs) == Set(["Home", "Shelf"]))
        }
        precondition(NavigationPlacement(rawValue: "unknown") == nil)
        var count = 13
        for legacy in NavigationPlacement.allCases {
            let layout = NavigationLayout.decode("", legacy: legacy.rawValue)
            precondition(Set(layout.order) == Set(NotchTab.allCases))
            precondition(NavigationLayout.decode(layout.encoded, legacy: "invalid") == layout)
            count += 2
        }
        let orders: [[NotchTab]] = [[.home,.shelf,.weather],[.home,.weather,.shelf],[.shelf,.home,.weather],[.shelf,.weather,.home],[.weather,.home,.shelf],[.weather,.shelf,.home]]
        for order in orders {
            for mask in 0..<8 {
                let left = NotchTab.allCases.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
                let layout = NavigationLayout(order: order, left: left)
                precondition(NavigationLayout.decode(layout.encoded, legacy: "split") == layout)
                for side in [true, false] {
                    precondition(layout.tabs(left: side, visible: [.home,.shelf]) == order.filter { $0 != .weather && left.contains($0) == side })
                    count += 1
                }
                count += 1
            }
        }
        precondition(StartupDestination.previous.resolved(last: "Weather", visible: [.home,.weather]) == .weather)
        precondition(StartupDestination.weather.resolved(last: "Home", visible: [.home]) == .home)
        precondition(StartupDestination.previous.resolved(last: "invalid", visible: NotchTab.allCases) == .home)
        print("\(count + 3) navigation and startup assertions passed")
    }
}
