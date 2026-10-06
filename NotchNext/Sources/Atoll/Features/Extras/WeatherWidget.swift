import SwiftUI

@MainActor final class WeatherStore: ObservableObject {
    static let shared = WeatherStore()
    @Published var forecast: WeatherForecast?
    @Published var city = ""
    @Published var error = ""
    @Published var loading = false
    @AppStorage("weather.city") var query = "Seoul"
    @AppStorage("weather.celsius") var celsius = true
    @AppStorage("weather.useCurrentLocation") var useCurrentLocation = false
    @AppStorage("weather.location") private var selectedLocationData = ""
    @Published var locations: [WeatherLocation] = []
    @Published var searching = false
    @Published var searchError = ""
    private var searchRequest = UUID()
    var selectedLocation: WeatherLocation? {
        guard let data = selectedLocationData.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WeatherLocation.self, from: data)
    }
    func searchLocations() async {
        let token = UUID(); searchRequest = token
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { locations = []; return }
        searching = true; searchError = ""
        defer { if searchRequest == token { searching = false } }
        do {
            var url = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
            url.queryItems = [.init(name: "name", value: WeatherLocation.searchName(name)), .init(name: "count", value: "10"), .init(name: "language", value: SettingsStore.shared.language)]
            let (data, response) = try await URLSession.shared.data(from: url.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CocoaError(.fileReadUnknown) }
            let results = try JSONDecoder().decode(WeatherLocation.Results.self, from: data).results ?? []
            guard searchRequest == token else { return }
            locations = results
            if results.isEmpty { searchError = SettingsStore.shared.language == "ko" ? "지역을 찾지 못했습니다. 영문 도시 이름으로도 검색해 보세요." : "No locations found. Try another city name." }
        } catch {
            guard searchRequest == token else { return }
            searchError = SettingsStore.shared.language == "ko" ? "지역 검색에 실패했습니다. 연결을 확인해 주세요." : "Location search failed. Check your connection."
        }
    }
    func selectLocation(_ location: WeatherLocation) async {
        useCurrentLocation = false
        WeatherCurrentLocation.shared.setEnabled(false)
        if let data = try? JSONEncoder().encode(location), let value = String(data: data, encoding: .utf8) { selectedLocationData = value }
        query = location.name; locations = []; searchError = ""
        forecast = nil; city = location.name
        await refresh()
    }
    private var request = UUID()
    private var timer: Timer?
    func start() {
        guard timer == nil else { return }
        WeatherCurrentLocation.shared.changed = { [weak self] in Task { @MainActor in await self?.refresh() } }
        WeatherCurrentLocation.shared.nameChanged = { [weak self] name in if self?.useCurrentLocation == true { self?.city = name } }
        WeatherCurrentLocation.shared.setEnabled(useCurrentLocation)
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in Task { @MainActor in await self?.refresh() } }
    }
    func stop() { timer?.invalidate(); timer = nil; WeatherCurrentLocation.shared.setEnabled(false) }
    func setCurrentLocation(_ enabled: Bool) {
        useCurrentLocation = enabled; request = UUID(); forecast = nil
        WeatherCurrentLocation.shared.setEnabled(enabled)
        Task { await refresh() }
    }
    var symbol: String { forecast?.condition.symbol ?? "cloud.sun" }

    func refresh() async {
        guard SettingsStore.shared.visibleNavigationTabs.contains(.weather) || SettingsStore.shared.weatherLiveActivity else { return }
        let token = UUID(); request = token
        let cityQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cityQuery.isEmpty else { return }
        loading = true; error = ""
        defer { if request == token { loading = false } }
        do {
            let location: WeatherLocation
            if useCurrentLocation {
                guard let current = WeatherCurrentLocation.shared.location else {
                    forecast = nil; city = ""; error = WeatherCurrentLocation.shared.message
                    return
                }
                location = current
            }
            else if let saved = selectedLocation { location = saved }
            else {
                var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
                components.queryItems = [.init(name: "name", value: WeatherLocation.searchName(cityQuery)), .init(name: "count", value: "1"), .init(name: "language", value: SettingsStore.shared.language)]
                let (data, response) = try await URLSession.shared.data(from: components.url!)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let first = try JSONDecoder().decode(WeatherLocation.Results.self, from: data).results?.first else { throw CocoaError(.fileReadUnknown) }
                location = first
            }
            let latitude = location.latitude, longitude = location.longitude
            var weather = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            weather.queryItems = [.init(name: "latitude", value: String(latitude)), .init(name: "longitude", value: String(longitude)),
                .init(name: "current", value: "temperature_2m,weather_code,is_day"), .init(name: "hourly", value: "temperature_2m,weather_code,is_day"),
                .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code"), .init(name: "timezone", value: "auto"),
                .init(name: "temperature_unit", value: celsius ? "celsius" : "fahrenheit"), .init(name: "forecast_days", value: "7")]
            let (data, response) = try await URLSession.shared.data(from: weather.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CocoaError(.fileReadUnknown) }
            let decoded = try JSONDecoder().decode(WeatherForecast.self, from: data)
            guard request == token else { return }
            forecast = decoded; city = useCurrentLocation ? WeatherCurrentLocation.shared.location?.name ?? location.name : location.name
        } catch {
            guard request == token else { return }
            self.error = HL("Weather unavailable. Check the city and connection.")
        }
    }
}
struct WeatherWidget: View {
    @ObservedObject private var store = WeatherStore.shared
    @EnvironmentObject private var settings: SettingsStore
    @AppStorage("weather.dailyForecast") private var daily = false
    @AppStorage("weather.coloredCard") private var colored = true
    private var korean: Bool { settings.language == "ko" }
    var body: some View {
        VStack(spacing: 8) {
            if let forecast = store.forecast {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.city).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text("\(Int(forecast.current.temperature_2m.rounded()))°")
                            .font(.system(size: 34, weight: .light, design: .rounded)).monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Image(systemName: forecast.condition.symbol).symbolRenderingMode(.multicolor)
                            .font(.system(size: 22)).accessibilityHidden(true)
                        Text(forecast.condition.title(korean: korean)).font(.system(size: 12, weight: .medium))
                        if let today = forecast.today, let low = today.low {
                            Text(korean ? "최고 \(Int(today.temperature.rounded()))° · 최저 \(Int(low.rounded()))°" : "H:\(Int(today.temperature.rounded()))°  L:\(Int(low.rounded()))°")
                                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
                GeometryReader { geometry in
                    let entries = Array((daily ? forecast.days.filter { $0.id > String(forecast.current.time.prefix(10)) } : forecast.hours).prefix(5))
                    let cellWidth = max(58, (geometry.size.width - 24) / 5)
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(entries) { entry in
                                VStack(spacing: 7) {
                                    Text(daily ? WeatherForecast.dayLabel(entry.id, current: forecast.current.time, korean: korean) : String(entry.id.suffix(5)))
                                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                                    Image(systemName: entry.condition.symbol).symbolRenderingMode(.multicolor)
                                        .font(.system(size: 20)).frame(height: 23).accessibilityLabel(entry.condition.title(korean: korean))
                                    HStack(spacing: 4) {
                                        Text("\(Int(entry.temperature.rounded()))°").fontWeight(.semibold)
                                        
                                    }.font(.system(size: 11)).monospacedDigit()
                                }.frame(width: cellWidth).accessibilityElement(children: .combine)
                            }
                        }
                    }.scrollIndicators(.hidden).id(daily)
                }.frame(height: 64)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cloud.sun").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text(store.loading ? (korean ? "날씨 불러오는 중…" : "Loading weather…") : HL("Choose a city in Weather settings, then refresh."))
                        .font(.caption).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, minHeight: 120)
            }
            if !store.error.isEmpty { Text(store.error).font(.caption2).foregroundStyle(.orange).lineLimit(2) }
        }.padding(.horizontal, 4).padding(.top, 0).foregroundStyle(.white).buttonStyle(.plain)
            .task { if store.forecast == nil { await store.refresh() } }
    }
    private func forecastButton(_ title: String, daily value: Bool) -> some View {
        Button { daily = value } label: {
            Text(title).font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(daily == value ? 1 : 0.5))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.white.opacity(daily == value ? 0.13 : 0), in: Capsule())
        }.accessibilityAddTraits(daily == value ? .isSelected : [])
    }
}

/// Static atmospheric artwork keeps the forecast calm and costs no animation timer.
struct WeatherCardBackground: View {
    let condition: WeatherCondition?
    private var night: Bool { condition?.isDay == false }
    private var code: Int { condition?.code ?? 3 }
    private var colors: [Color] {
        if night { return [Color(red: 0.16, green: 0.17, blue: 0.36), Color(red: 0.025, green: 0.035, blue: 0.10)] }
        switch code {
        case 0...1: return [Color(red: 0.20, green: 0.47, blue: 0.91), Color(red: 0.07, green: 0.22, blue: 0.56)]
        case 2: return [Color(red: 0.20, green: 0.40, blue: 0.73), Color(red: 0.08, green: 0.20, blue: 0.38)]
        case 71...77,85,86: return [Color(red: 0.34, green: 0.43, blue: 0.49), Color(red: 0.13, green: 0.22, blue: 0.29)]
        case 95...99: return [Color(red: 0.27, green: 0.22, blue: 0.36), Color(red: 0.07, green: 0.08, blue: 0.15)]
        default: return [Color(red: 0.055, green: 0.09, blue: 0.15), Color(red: 0.10, green: 0.15, blue: 0.23)]
        }
    }
    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color.white.opacity(night ? 0.06 : 0.13), .clear], center: .topTrailing, startRadius: 0, endRadius: 220)
            Canvas { context, size in
                if night && code <= 2 {
                    for index in 0..<18 {
                        let x = Double((index * 71 + 19) % 100) / 100 * size.width
                        let y = Double((index * 43 + 7) % 100) / 100 * size.height * 0.65
                        let radius = index % 3 == 0 ? 1.2 : 0.7
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)), with: .color(.white.opacity(0.16)))
                    }
                } else if [51,53,55,61,63,65,80,81,82,95,96,99].contains(code) {
                    for index in 0..<16 {
                        let x = Double((index * 67 + 11) % 100) / 100 * size.width
                        let y = Double((index * 37 + 13) % 100) / 100 * size.height
                        var line = Path(); line.move(to: CGPoint(x: x, y: y)); line.addLine(to: CGPoint(x: x - 3, y: y + 12))
                        context.stroke(line, with: .color(.white.opacity(0.055)), lineWidth: 1)
                    }
                }
            }.allowsHitTesting(false)
        }
    }
}
struct WeatherSettingsView: View {
    @ObservedObject private var store = WeatherStore.shared
    @ObservedObject private var currentLocation = WeatherCurrentLocation.shared
    @EnvironmentObject private var settings: SettingsStore
    @AppStorage("weather.coloredCard") private var colored = true
    @AppStorage("weather.dailyForecast") private var daily = false
    var body: some View {
        Form {
            Section(settings.language == "ko" ? "날씨 창 크기" : "Weather size") {
                LabeledContent(settings.language == "ko" ? "너비" : "Width", value: "\(Int(settings.weatherWidth)) pt")
                Slider(value: $settings.weatherWidth, in: 400...680)
                LabeledContent(settings.language == "ko" ? "높이" : "Height", value: "\(Int(settings.weatherHeight)) pt")
                Slider(value: $settings.weatherHeight, in: 210...340)
                Button(settings.language == "ko" ? "기본 크기로" : "Reset size") { settings.weatherWidth = 440; settings.weatherHeight = 210 }
            }
            Section(HL("Weather")) {
                Toggle(settings.language == "ko" ? "현재 위치에 날씨 자동 동기화" : "Sync weather with current location", isOn: Binding(get: { store.useCurrentLocation }, set: { store.setCurrentLocation($0) }))
                Text(settings.language == "ko" ? "켜면 macOS 위치 권한을 요청합니다. 예보 조회에는 소수점 한 자리로 반올림한 좌표만 Open-Meteo로 보냅니다. 위치는 저장하지 않으며, 끄면 선택했던 도시로 돌아갑니다." : "Requests macOS location access. Sends only coordinates rounded to one decimal place to Open-Meteo for forecasts. Locations are not saved. Turning this off restores your selected city.").font(.caption).foregroundStyle(.secondary)
                if store.useCurrentLocation { Text(currentLocation.message).font(.caption) }
                Toggle(settings.language == "ko" ? "현재 위치의 지역 이름 표시" : "Show current region name", isOn: Binding(get: { currentLocation.regionNamesEnabled }, set: { currentLocation.setRegionNames($0) }))
                Text(settings.language == "ko" ? "지역 이름을 켜면 현재 좌표를 Apple 지역 조회 서비스에 전달합니다. 좌표·주소는 저장하지 않습니다. 상세 지역이 없으면 확인 가능한 상위 지역을 표시합니다." : "Sends current coordinates to Apple to resolve region names. Coordinates and addresses are not saved. Falls back to a broader region when detail is unavailable.").font(.caption).foregroundStyle(.secondary)
                Picker(settings.language == "ko" ? "지역 이름 상세 수준" : "Region detail", selection: Binding(get: { currentLocation.detailLevel }, set: { currentLocation.setDetailLevel($0) })) {
                    Text(settings.language == "ko" ? "시·도 / 시 — 부천시" : "City / region").tag("city")
                    Text(settings.language == "ko" ? "구·군 — 영등포구" : "District / county").tag("district")
                    Text(settings.language == "ko" ? "동·읍·면 — 소사본동" : "Neighborhood").tag("neighborhood")
                }.disabled(!currentLocation.regionNamesEnabled)
                Toggle(settings.language == "ko" ? "날씨 탭 표시" : "Show Weather tab", isOn: Binding(get: { settings.visibleNavigationTabs.contains(.weather) }, set: { settings.setTabVisible(.weather, visible: $0) }))
                HStack {
                    TextField(settings.language == "ko" ? "지역 검색" : "Search locations", text: $store.query)
                        .onSubmit { Task { await store.searchLocations() } }
                    Button(settings.language == "ko" ? "검색" : "Search") { Task { await store.searchLocations() } }.disabled(store.searching)
                }
                if store.searching { ProgressView().controlSize(.small) }
                ForEach(store.locations) { location in
                    Button { Task { await store.selectLocation(location) } } label: {
                        HStack {
                            VStack(alignment: .leading) { Text(location.name); Text(location.detail).font(.caption).foregroundStyle(.secondary) }
                            Spacer(); Image(systemName: "plus.circle")
                        }
                    }.buttonStyle(.plain).accessibilityLabel("\(location.name), \(location.detail)")
                }
                if !store.searchError.isEmpty { Text(store.searchError).font(.caption).foregroundStyle(.orange) }
                if let selected = store.selectedLocation {
                    LabeledContent(settings.language == "ko" ? "선택한 지역" : "Selected location", value: "\(selected.name) · \(selected.detail)")
                }
                Picker(settings.language == "ko" ? "예보" : "Forecast", selection: $daily) {
                    Text(HL("Hourly")).tag(false); Text(HL("Daily")).tag(true)
                }.pickerStyle(.segmented)
                Toggle(HL("Celsius"), isOn: $store.celsius)
                VStack(alignment: .leading, spacing: 10) {
                    Text(settings.language == "ko" ? "펼친 날씨 테마" : "Expanded weather style").font(.headline)
                    HStack(spacing: 10) {
                        themeChoice(false, title: settings.language == "ko" ? "어둡게" : "Dark")
                        themeChoice(true, title: settings.language == "ko" ? "날씨 색상" : "Colored")
                    }
                }.padding(.vertical, 4)
                Text(settings.language == "ko" ? "맑음·흐림·비·눈·밤에 맞춰 카드의 색상이 달라집니다." : "The card adapts to clear, cloudy, rainy, snowy and night conditions.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(settings.language == "ko" ? "접힌 노치에 날씨 표시" : "Show weather in the closed notch", isOn: $settings.weatherLiveActivity)
                Toggle(settings.language == "ko" ? "음악 재생 중에도 날씨 표시" : "Show weather while music is playing", isOn: $settings.weatherDuringMusic)
                Text(settings.language == "ko" ? "아이콘과 온도를 표시하고, 마우스를 올리면 도시·최고/최저 기온을 보여줍니다." : "Shows the icon and temperature; hover for the city and high/low.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(HL("Refresh weather")) { Task { await store.refresh() } }.disabled(store.loading)
                if !store.city.isEmpty { Text(store.city) }
                if !store.error.isEmpty { Text(store.error).foregroundStyle(.orange) }
                Text(settings.language == "ko" ? "지역 검색과 날씨 예보는 Open-Meteo를 사용합니다." : "City searches and forecasts use Open-Meteo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
            .onChange(of: settings.weatherLiveActivity) { _, enabled in if enabled { Task { await store.refresh() } } }
            .onChange(of: store.celsius) { _, _ in Task { await store.refresh() } }
    }
    private func themeChoice(_ value: Bool, title: String) -> some View {
        Button { colored = value } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(settings.language == "ko" ? "날씨" : "Weather").font(.system(size: 9, weight: .medium))
                        Text("22°").font(.system(size: 23, weight: .light))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Image(systemName: "sun.max.fill").symbolRenderingMode(.multicolor).font(.system(size: 19))
                        Text(settings.language == "ko" ? "최고 22° · 최저 11°" : "H:22° L:11°").font(.system(size: 8))
                    }
                }.padding(12).foregroundStyle(.white)
                    .background {
                        if value { WeatherCardBackground(condition: .init(code: 0, isDay: true)) }
                        else { Color.black }
                    }.clipShape(RoundedRectangle(cornerRadius: 12))
                HStack {
                    Text(title).font(.caption.weight(.medium))
                    Spacer()
                    Image(systemName: colored == value ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(colored == value ? Color.accentColor : .secondary)
                }
            }.padding(8).frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(colored == value ? Color.accentColor : .clear, lineWidth: 1.5))
        }.buttonStyle(.plain).accessibilityLabel(title)
            .accessibilityAddTraits(colored == value ? .isSelected : [])
    }

}
