import Foundation

/// Shared limits and drag conversion for both preview and actual shelf.
enum ShelfSizing {
    static let airDropRange = 72.0...240.0
    static func airDrop(_ value: Double) -> Double {
        min(airDropRange.upperBound, max(airDropRange.lowerBound, value.isFinite ? value : 92))
    }
    static func resizedAirDrop(origin: Double, translation: Double, scale: Double, trailing: Bool) -> Double {
        guard translation.isFinite, scale.isFinite, scale > 0 else { return airDrop(origin) }
        return airDrop((origin + translation / scale * (trailing ? -1 : 1)).rounded())
    }
}
