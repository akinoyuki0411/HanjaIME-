import Foundation

struct WeatherRegionNames {
    let city: String?
    let district: String?
    let neighborhood: String?
    init(administrative: String?, subAdministrative: String?, locality: String?, subLocality: String?) {
        let fields = [administrative, subAdministrative, locality, subLocality].compactMap { $0 }.filter { !$0.isEmpty }
        let tokens = fields.flatMap { $0.split(separator: " ").map(String.init) }
        city = tokens.first { $0.hasSuffix("시") } ?? locality ?? administrative
        district = tokens.first { $0.hasSuffix("구") || $0.hasSuffix("군") } ?? subAdministrative
        neighborhood = tokens.first { $0.hasSuffix("동") || $0.hasSuffix("읍") || $0.hasSuffix("면") || $0.hasSuffix("리") } ?? subLocality
    }
    func name(level: String, fallback: String) -> String {
        switch level {
        case "neighborhood": return neighborhood ?? district ?? city ?? fallback
        case "district": return district ?? city ?? fallback
        default: return city ?? fallback
        }
    }
}
