import Foundation
@main struct Tests {
    static func main() throws {
        precondition(WeatherLocation.searchName(" 부산 ") == "Busan")
        precondition(WeatherLocation.searchName("서울특별시") == "Seoul")
        precondition(WeatherLocation.searchName("Tokyo") == "Tokyo")
        let regionData = #"{"results":[{"id":1838524,"name":"부산광역시","latitude":35.1,"longitude":129.0,"country":"대한민국"}]}"#.data(using: .utf8)!
        let region = try JSONDecoder().decode(WeatherLocation.Results.self, from: regionData).results!.first!
        precondition(region.detail == "대한민국")
        let restored = try JSONDecoder().decode(WeatherLocation.self, from: JSONEncoder().encode(region))
        precondition(restored == region)
        let data = #"{"current":{"temperature_2m":12.5,"weather_code":2,"is_day":0,"time":"2026-10-03T23:15"},"hourly":{"time":["2026-10-03T22:00","2026-10-03T23:00","2026-10-04T00:00","2026-10-04T01:00"],"temperature_2m":[14,13,null,11],"weather_code":[0,2,3,61],"is_day":[0,0,0,0]},"daily":{"time":["2026-10-03","2026-10-04","2026-10-05"],"temperature_2m_max":[18,17,null],"temperature_2m_min":[8,7,9],"weather_code":[2,61,3]}}"#.data(using: .utf8)!
        let forecast = try JSONDecoder().decode(WeatherForecast.self, from: data)
        precondition(forecast.hours.map(\.id) == ["2026-10-03T23:00", "2026-10-04T01:00"], "Past hours and missing temperatures must be excluded")
        precondition(forecast.hours.map { $0.condition.code } == [2,61], "Missing temperatures must not shift the condition icons")
        precondition(forecast.hours.first?.condition.symbol == "cloud.moon.fill")
        precondition(forecast.today?.temperature == 18 && forecast.today?.low == 8)
        precondition(forecast.days.count == 2)
        precondition(WeatherForecast.dayLabel("2026-10-03", current: forecast.current.time, korean: true) == "오늘")
        precondition(WeatherForecast.dayLabel("2026-10-04", current: forecast.current.time, korean: true) == "일")
        precondition(WeatherForecast.dayLabel("2026-10-04", current: forecast.current.time, korean: false) == "Sun")
        precondition(WeatherCondition(code: 999, isDay: true).symbol == "questionmark.circle")
        precondition(WeatherCondition(code: 3, isDay: true).symbol == "cloud.fill")
        precondition(WeatherCondition(code: 0, isDay: false).symbol == "moon.stars.fill")
        precondition(WeatherCondition(code: 75, isDay: true).symbol == "cloud.snow.fill")
        precondition(WeatherCondition(code: 95, isDay: true).title(korean: true) == "뇌우")
        let sparse = #"{"current":{"temperature_2m":-4,"weather_code":0,"time":"2026-10-03T04:00"},"hourly":{"time":["2026-10-03T04:00","2026-10-03T05:00"],"temperature_2m":[-4]},"daily":{"time":[],"temperature_2m_max":[],"temperature_2m_min":[]}}"#.data(using: .utf8)!
        let short = try JSONDecoder().decode(WeatherForecast.self, from: sparse)
        precondition(short.hours.count == 1 && short.days.isEmpty && short.today == nil)
        precondition(short.hours[0].condition.symbol == "questionmark.circle", "Do not invent conditions for missing data")
        precondition(ShelfSizing.resizedAirDrop(origin: 120, translation: 20, scale: 0.5, trailing: false) == 160)
        precondition(ShelfSizing.resizedAirDrop(origin: 120, translation: -20, scale: 0.5, trailing: true) == 160)
        precondition(ShelfSizing.resizedAirDrop(origin: 120, translation: 20, scale: 0.5, trailing: true) == 80)
        precondition(ShelfSizing.resizedAirDrop(origin: 120, translation: -1000, scale: 0.5, trailing: false) == 72)
        precondition(ShelfSizing.resizedAirDrop(origin: 120, translation: 1000, scale: 0.5, trailing: false) == 240)
        precondition(ShelfSizing.resizedAirDrop(origin: 120, translation: 20, scale: 0, trailing: false) == 120)
        precondition(ShelfSizing.airDrop(.nan) == 92)
        precondition(ShelfSizing.airDrop(180) == 180)
        print("28 weather, location and AirDrop sizing assertions passed")
        if CommandLine.arguments.count > 1 {
            let live = try JSONDecoder().decode(WeatherForecast.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            precondition(live.hours.count == 12 && live.days.count == 7 && live.today != nil)
            precondition(live.hours.allSatisfy { $0.condition.code != -1 })
            precondition(live.days.allSatisfy { $0.condition.code != -1 })
            print("Live forecast decoded: 12 hourly icons, 7 daily icons and today high/low")
        }
    }
}
