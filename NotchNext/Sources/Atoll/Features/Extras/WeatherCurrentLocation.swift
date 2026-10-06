import CoreLocation
import Combine

/// Coordinates stay in memory; forecasts use rounded coordinates only.
@MainActor final class WeatherCurrentLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherCurrentLocation()
    @Published private(set) var location: WeatherLocation?
    @Published private(set) var message = ""
    private let manager = CLLocationManager()
    private var enabled = false
    private let geocoder = CLGeocoder()
    private var latestLocation: CLLocation?
    private var namedLocation: CLLocation?
    private var names: WeatherRegionNames?
    private var lookupToken = UUID()
    private var lastLookup = Date.distantPast
    @Published private(set) var regionNamesEnabled = UserDefaults.standard.bool(forKey: "weather.regionNamesEnabled")
    @Published private(set) var detailLevel = UserDefaults.standard.string(forKey: "weather.locationDetail") ?? "district"
    var changed: (() -> Void)?
    var nameChanged: ((String) -> Void)?
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 500
    }
    func setEnabled(_ value: Bool) {
        enabled = value
        if !value {
            manager.stopUpdatingLocation(); geocoder.cancelGeocode(); lookupToken = UUID()
            location = nil; latestLocation = nil; namedLocation = nil; names = nil; message = ""; return
        }
        updateAuthorization()
    }
    func setRegionNames(_ value: Bool) {
        regionNamesEnabled = value; UserDefaults.standard.set(value, forKey: "weather.regionNamesEnabled")
        lookupToken = UUID(); geocoder.cancelGeocode(); names = nil; namedLocation = nil
        publishName()
        if value, enabled, let latestLocation { resolveName(latestLocation, force: true) }
    }
    func setDetailLevel(_ level: String) {
        guard ["city", "district", "neighborhood"].contains(level) else { return }
        detailLevel = level; UserDefaults.standard.set(level, forKey: "weather.locationDetail")
        publishName()
    }
    private func publishName() {
        guard let old = location else { return }
        let fallback = SettingsStore.shared.language == "ko" ? "현재 위치" : "Current location"
        let name = regionNamesEnabled ? names?.name(level: detailLevel, fallback: fallback) ?? fallback : fallback
        location = WeatherLocation(id: old.id, name: name, latitude: old.latitude, longitude: old.longitude, country: nil, admin1: nil)
        nameChanged?(name)
    }
    private func resolveName(_ source: CLLocation, force: Bool = false) {
        guard enabled, regionNamesEnabled, !geocoder.isGeocoding else { return }
        guard force || (Date().timeIntervalSince(lastLookup) >= 60 && (namedLocation.map { source.distance(from: $0) >= 500 } ?? true)) else { return }
        let token = UUID(); lookupToken = token; lastLookup = Date()
        geocoder.reverseGeocodeLocation(source, preferredLocale: Locale(identifier: SettingsStore.shared.language == "ko" ? "ko_KR" : "en_US")) { [weak self] placemarks, _ in
            Task { @MainActor in
                guard let self, self.enabled, self.regionNamesEnabled, self.lookupToken == token else { return }
                if let place = placemarks?.first {
                    self.names = WeatherRegionNames(administrative: place.administrativeArea, subAdministrative: place.subAdministrativeArea, locality: place.locality, subLocality: place.subLocality)
                    self.namedLocation = source
                    self.message = "현재 지역 이름에 맞춰 날씨를 표시합니다."
                } else { self.message = "지역 이름을 확인하지 못했습니다. 현재 위치 예보는 계속 표시합니다." }
                self.publishName()
            }
        }
    }
    private func updateAuthorization() {
        guard enabled else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            message = "현재 위치 확인 중…"; manager.startUpdatingLocation()
        case .notDetermined:
            message = "위치 접근 허용이 필요합니다."
            manager.requestWhenInUseAuthorization()
            manager.startUpdatingLocation()
        default:
            location = nil; message = "위치 접근이 차단되어 있습니다. 시스템 설정의 위치 서비스를 확인해 주세요."
            manager.stopUpdatingLocation(); changed?()
        }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.updateAuthorization() }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let latitude = latest.coordinate.latitude, longitude = latest.coordinate.longitude
        let accuracy = latest.horizontalAccuracy, age = abs(latest.timestamp.timeIntervalSinceNow)
        Task { @MainActor in
            guard self.enabled, let (lat, lon) = WeatherCoordinatePolicy.rounded(latitude: latitude, longitude: longitude, accuracy: accuracy, age: age) else { return }
            self.latestLocation = latest
            self.resolveName(latest)
            guard self.location?.latitude != lat || self.location?.longitude != lon else { return }
            self.location = WeatherLocation(id: -1, name: SettingsStore.shared.language == "ko" ? "현재 위치" : "Current location", latitude: lat, longitude: lon, country: nil, admin1: nil)
            self.message = "현재 위치에 맞춰 날씨를 동기화합니다."
            self.publishName()
            self.changed?()
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.enabled else { return }
            self.message = "현재 위치를 확인하지 못했습니다. 잠시 후 다시 시도해 주세요."
        }
    }
}
