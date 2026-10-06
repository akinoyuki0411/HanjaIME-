import Foundation
import CoreGraphics
struct EnrollmentPanelLayout {
    let frame: CGRect
    let topPadding: CGFloat
    static func calculate(screen: CGRect, safeTop: CGFloat, left: CGRect?, right: CGRect?) -> Self {
        let physical = safeTop > 0 && left != nil && right != nil && right!.minX > left!.maxX
        let center = physical ? (left!.maxX + right!.minX) / 2 : screen.midX
        let topPadding = physical ? safeTop : 12
        let width = min(340, screen.width - 24)
        let height = min(408 + topPadding, screen.height - 24)
        let x = min(max(center - width / 2, screen.minX + 12), screen.maxX - width - 12)
        return Self(frame: CGRect(x: x, y: screen.maxY - height - (physical ? 0 : 8), width: width, height: height), topPadding: topPadding)
    }
}
