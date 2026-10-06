import Foundation

enum WeatherCoordinatePolicy {
    static func rounded(latitude: Double, longitude: Double, accuracy: Double, age: Double) -> (Double, Double)? {
        guard latitude.isFinite, longitude.isFinite, accuracy.isFinite, age.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              (0...10000).contains(accuracy), (0..<300).contains(age) else { return nil }
        return ((latitude * 10).rounded() / 10, (longitude * 10).rounded() / 10)
    }
}

struct WeatherForecast: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
        let time: String
        let is_day: Int?
    }
    struct Hourly: Decodable {
        let time: [String]
        let temperature_2m: [Double?]
        let weather_code: [Int?]?
        let is_day: [Int?]?
    }
    struct Daily: Decodable {
        let time: [String]
        let temperature_2m_max: [Double?]
        let temperature_2m_min: [Double?]
        let weather_code: [Int?]?
    }
    struct Entry: Identifiable {
        let id: String
        let temperature: Double
        let low: Double?
        let condition: WeatherCondition
    }
    let current: Current
    let hourly: Hourly
    let daily: Daily
    var condition: WeatherCondition { .init(code: current.weather_code, isDay: current.is_day != 0) }
    var hours: [Entry] {
        let currentHour = String(current.time.prefix(13)) + ":00"
        return Array(hourly.time.enumerated().compactMap { index, time -> Entry? in
            guard time >= currentHour, index < hourly.temperature_2m.count, let temperature = hourly.temperature_2m[index] else { return nil }
            let code = hourly.weather_code.flatMap { index < $0.count ? $0[index] : nil }
            let day = hourly.is_day.flatMap { index < $0.count ? $0[index] : nil }
            return Entry(id: time, temperature: temperature, low: nil, condition: .init(code: code ?? -1, isDay: day != 0))
        }.prefix(12))
    }
    var days: [Entry] {
        Array(daily.time.enumerated().compactMap { index, time -> Entry? in
            guard index < daily.temperature_2m_max.count, index < daily.temperature_2m_min.count,
                  let high = daily.temperature_2m_max[index], let low = daily.temperature_2m_min[index] else { return nil }
            let code = daily.weather_code.flatMap { index < $0.count ? $0[index] : nil }
            return Entry(id: time, temperature: high, low: low, condition: .init(code: code ?? -1, isDay: true))
        }.prefix(7))
    }
    var today: Entry? { days.first { $0.id == String(current.time.prefix(10)) } }
    static func dayLabel(_ value: String, current: String, korean: Bool) -> String {
        if value == String(current.prefix(10)) { return korean ? "오늘" : "Today" }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: value) else { return value }
        parser.locale = Locale(identifier: korean ? "ko_KR" : "en_US")
        parser.dateFormat = "EEE"
        return parser.string(from: date)
    }
}

struct WeatherCondition {
    let code: Int
    let isDay: Bool
    var symbol: String {
        switch code {
        case 0, 1: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "questionmark.circle"
        }
    }
    func title(korean: Bool) -> String {
        let names: (String, String)
        switch code {
        case 0: names = ("맑음", "Clear")
        case 1: names = ("대체로 맑음", "Mostly clear")
        case 2: names = ("구름 조금", "Partly cloudy")
        case 3: names = ("흐림", "Cloudy")
        case 45,48: names = ("안개", "Fog")
        case 51,53,55: names = ("이슬비", "Drizzle")
        case 56,57,66,67: names = ("어는 비", "Freezing rain")
        case 61,63,65: names = ("비", "Rain")
        case 80,81,82: names = ("소나기", "Showers")
        case 71,73,75,77,85,86: names = ("눈", "Snow")
        case 95,96,99: names = ("뇌우", "Thunderstorms")
        default: names = ("날씨 정보 없음", "Conditions unavailable")
        }
        return korean ? names.0 : names.1
    }
}

struct WeatherLocation: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?
    var detail: String { [admin1, country].compactMap { $0 }.filter { $0 != name }.joined(separator: ", ") }
    static func searchName(_ input: String) -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases = ["서울": "Seoul", "서울특별시": "Seoul", "부산": "Busan", "부산광역시": "Busan", "대구": "Daegu", "대구광역시": "Daegu", "인천": "Incheon", "인천광역시": "Incheon", "광주": "Gwangju", "광주광역시": "Gwangju", "대전": "Daejeon", "대전광역시": "Daejeon", "울산": "Ulsan", "울산광역시": "Ulsan", "세종": "Sejong", "세종특별자치시": "Sejong", "제주": "Jeju", "제주시": "Jeju", "수원": "Suwon", "수원시": "Suwon"]
        return aliases[name] ?? name
    }
    struct Results: Decodable { let results: [WeatherLocation]? }
}
