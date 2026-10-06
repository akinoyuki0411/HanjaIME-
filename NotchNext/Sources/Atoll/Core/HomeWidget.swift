import Foundation

enum HomeWidget: String, CaseIterable, Identifiable {
    case media, calendar, timers, notes, todos, mirror, voice
    var id: String { rawValue }
    var title: String {
        switch self {
        case .media: return "Media"
        case .calendar: return "Calendar"
        case .timers: return "Timers"
        case .notes: return "Notes"
        case .todos: return "To-dos"
        case .mirror: return "Mirror"
        case .voice: return "Voice"
        }
    }
    var symbol: String {
        switch self {
        case .media: return "music.note"
        case .calendar: return "calendar"
        case .timers: return "timer"
        case .notes: return "note.text"
        case .todos: return "checklist"
        case .mirror: return "web.camera"
        case .voice: return "mic"
        }
    }
    var widthRange: ClosedRange<Double> { self == .media ? 240...420 : (self == .mirror ? 84...124 : 100...260) }
    var defaultWidth: Double { self == .media ? 280 : (self == .mirror ? 100 : 125) }
    func clampedWidth(_ value: Double) -> Double { value.isFinite ? min(widthRange.upperBound, max(widthRange.lowerBound, value)) : defaultWidth }
    static func decode(_ raw: String) -> [HomeWidget] {
        var seen = Set<HomeWidget>()
        return raw.split(separator: ",").compactMap { HomeWidget(rawValue: String($0)) }.filter { seen.insert($0).inserted }
    }
    static func movingToPosition(of target: HomeWidget, source: HomeWidget, in values: [HomeWidget]) -> [HomeWidget] {
        guard source != target, let from = values.firstIndex(of: source), let to = values.firstIndex(of: target) else { return values }
        var result = values
        result.remove(at: from)
        result.insert(source, at: to)
        return result
    }
    static func moving(_ source: HomeWidget, before target: HomeWidget, in values: [HomeWidget]) -> [HomeWidget] {
        guard source != target, values.contains(source), values.contains(target) else { return values }
        var result = values.filter { $0 != source }
        result.insert(source, at: result.firstIndex(of: target)!)
        return result
    }
}
