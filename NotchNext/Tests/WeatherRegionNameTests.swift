@main struct WeatherRegionNameTests {
    static func main() {
        let bucheon = WeatherRegionNames(administrative: "경기도", subAdministrative: "부천시", locality: "부천시 소사구", subLocality: "소사본동")
        precondition(bucheon.name(level: "city", fallback: "현재 위치") == "부천시")
        precondition(bucheon.name(level: "district", fallback: "현재 위치") == "소사구")
        precondition(bucheon.name(level: "neighborhood", fallback: "현재 위치") == "소사본동")
        let seoul = WeatherRegionNames(administrative: "서울특별시", subAdministrative: nil, locality: "영등포구", subLocality: "여의동")
        precondition(seoul.name(level: "city", fallback: "현재 위치") == "서울특별시")
        precondition(seoul.name(level: "district", fallback: "현재 위치") == "영등포구")
        precondition(seoul.name(level: "neighborhood", fallback: "현재 위치") == "여의동")
        let coarse = WeatherRegionNames(administrative: "경기도", subAdministrative: nil, locality: "부천시", subLocality: nil)
        precondition(coarse.name(level: "neighborhood", fallback: "현재 위치") == "부천시")
        let unknown = WeatherRegionNames(administrative: nil, subAdministrative: nil, locality: nil, subLocality: nil)
        precondition(unknown.name(level: "neighborhood", fallback: "현재 위치") == "현재 위치")
        print("8 region detail and fallback checks passed")
    }
}
