@main struct WeatherCoordinateTests {
    static func main() {
        let accepted = WeatherCoordinatePolicy.rounded(latitude: 37.5665, longitude: 126.978, accuracy: 1200, age: 12)!
        precondition(accepted.0 == 37.6 && accepted.1 == 127.0)
        let southern = WeatherCoordinatePolicy.rounded(latitude: -33.8688, longitude: 151.2093, accuracy: 50, age: 0)!
        precondition(southern.0 == -33.9 && southern.1 == 151.2)
        for values in [(Double.nan, 0.0, 0.0, 0.0), (91.0, 0.0, 0.0, 0.0), (0.0, 181.0, 0.0, 0.0), (0.0, 0.0, -1.0, 0.0), (0.0, 0.0, 10001.0, 0.0), (0.0, 0.0, 10.0, 300.0)] {
            precondition(WeatherCoordinatePolicy.rounded(latitude: values.0, longitude: values.1, accuracy: values.2, age: values.3) == nil)
        }
        print("8 synthetic location privacy/validity checks passed; no real location accessed")
    }
}
