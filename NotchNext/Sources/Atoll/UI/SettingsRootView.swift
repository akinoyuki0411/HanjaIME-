import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var showingChangelog=false

    enum Pane: String, CaseIterable, Identifiable {
        case general = "General"
        case appearance = "Appearance"
        case layout = "Layout"
        case liveActivities = "Live Activities"
        case media = "Media"
        case calendar = "Calendar"
        case shelf = "Shelf"
        case hud = "HUD"
        case system = "System"
        case agents = "Agents"
        case mirror = "Mirror"
        case timers = "Timers"
        case notes = "Notes"
        case todos = "To-dos"
        case face = "Face recognition"
        case weather = "Weather"
        case voice = "Voice"
        case insights = "Focus history"
        case ambient = "Focus background audio"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .general: return "gear"
            case .appearance: return "paintbrush"
            case .layout: return "rectangle.3.group"
            case .liveActivities: return "bolt.badge.clock"
            case .media: return "play.circle"
            case .calendar: return "calendar"
            case .shelf: return "tray.full"
            case .hud: return "rectangle.tophalf.inset.filled"
            case .system: return "battery.100.bolt"
            case .agents: return "sparkles.rectangle.stack"
            case .mirror: return "web.camera"
            case .timers: return "timer"
            case .notes: return "note.text"
            case .todos: return "checklist"
            case .face: return "faceid"
            case .weather: return "cloud.sun"
            case .voice: return "mic"
            case .insights: return "chart.bar"
            case .ambient: return "waveform"
            }
        }
    }

    @State private var pane: Pane = .general
    @State private var section = 0
    private let groups: [[Pane]] = [[.general, .appearance], [.liveActivities, .hud, .system, .agents], [.layout, .media, .calendar, .mirror, .timers, .notes, .todos, .weather, .voice, .insights, .ambient, .face], [.shelf]]
    private let symbols = ["gearshape.fill", "clock.fill", "rectangle.topthird.inset.filled", "tray.fill", "key.fill", "ellipsis.circle.fill"]
    private var names: [String] { settings.language == "ko" ? ["일반", "실시간 활동", "노치", "파일 보관함", "라이선스", "정보"] : ["General", "Live Activities", "Nook", "Tray", "License", "About"] }
    private var height: CGFloat {
        if section == 5 { return 440 }
        if section == 0 { return pane == .appearance ? 570 : 700 }
        if section == 2 {
            switch pane {
            case .calendar, .weather, .face: return 700
            case .layout, .media: return 650
            default: return 590
            }
        }
        return section == 3 ? 610 : 570
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ForEach(0..<names.count, id: \.self) { index in
                    Button {
                        section = index
                        if index < groups.count { pane = groups[index][0] }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: symbols[index]).font(.system(size: 26, weight: .semibold))
                            Text(names[index]).font(.system(size: 12, weight: .medium))
                        }.frame(width: 95, height: 70)
                            .foregroundStyle(section == index ? Color.accentColor : Color.secondary)
                            .background(RoundedRectangle(cornerRadius: 12).fill(section == index ? Color.primary.opacity(0.07) : .clear))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).focusable(false)
                }
            }.padding(.vertical, 12)
            Divider()
            if section == 5 { about }
            else if section == 4 { licenses }
            else if section == 2 {
                HStack(spacing: 16) {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(groups[section]) { item in
                                HStack(spacing: 4) {
                                    Button { pane = item } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: item.systemImage)
                                                .font(.system(size: 18)).frame(width: 30, height: 36)
                                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(HL(item.rawValue)).font(.system(size: 13, weight: .semibold))
                                                if let widget = HomeWidget(rawValue: item == .todos ? "todos" : item.rawValue.lowercased()) {
                                                    Text("\(Int(settings.width(for: widget))) pt")
                                                        .font(.caption).foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer(minLength: 0)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.vertical, 14).contentShape(Rectangle())
                                    }.buttonStyle(.plain).focusable(false)
                                    if let widget = HomeWidget(rawValue: item == .todos ? "todos" : item.rawValue.lowercased()) {
                                        Toggle(HL(widget.title), isOn: Binding(get: {
                                            HomeWidget.decode(settings.widgetOrder).contains(widget)
                                        }, set: { on in
                                            var value = HomeWidget.decode(settings.widgetOrder).filter { $0 != widget }
                                            if on { value.append(widget) }
                                            settings.widgetOrder = value.map(\.rawValue).joined(separator: ",")
                                        })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                                    }
                                }.padding(.horizontal, 12)
                                    .foregroundStyle(pane == item ? Color.accentColor : Color.primary)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(pane == item ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04)))
                            }
                        }.padding(10)
                    }.frame(width: 220).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
                    VStack(spacing: 12) {
                        if pane == .layout || HomeWidget(rawValue: pane == .todos ? "todos" : pane.rawValue.lowercased()) != nil { HomeLayoutEditor(selection: Binding(get: {
                            HomeWidget(rawValue: pane == .todos ? "todos" : pane.rawValue.lowercased())
                        }, set: { widget in
                            if let widget { pane = groups[2].first { $0.rawValue == widget.title } ?? .layout }
                        })) }
                        paneContent
                    }
                }.padding(20)
            } else {
                VStack(spacing: 8) {
                    if groups[section].count > 1 {
                        Picker("", selection: $pane) {
                            ForEach(groups[section]) { Text(HL($0.rawValue)).tag($0) }
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 360).padding(.top, 16)
                    }
                    if section == 3 { ShelfLayoutEditor() }
                    paneContent
                }.padding(.horizontal, 22)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .background(SettingsWindowSizer(width: section == 2 ? 900 : 760, height: height, title: names[section]))
            .id(settings.language)
    }
    private var about: some View {
        VStack(spacing: 24) {
            HStack(spacing: 18) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage()).resizable().interpolation(.high)
                    .frame(width: 82, height: 82)
                VStack(alignment: .leading, spacing: 8) {
                    Text("HanjiME Notch").font(.system(size: 30, weight: .bold))
                    Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") · \(settings.language == "ko" ? "빌드" : "Build") \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")").foregroundStyle(.secondary)
                }
                Spacer()
            }
            Button(settings.language == "ko" ? "변경 내역 보기" : "See changelog") {showingChangelog=true}.buttonStyle(.link)
                .sheet(isPresented:$showingChangelog) {
                    ScrollView {VStack(alignment:.leading,spacing:22) {
                        Text("HanjiME Notch").font(.system(size:32,weight:.bold))
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "").foregroundStyle(.secondary)
                        Text(settings.language == "ko" ? "변경 내역" : "Changelog").font(.title2.bold())
                        ForEach(settings.language == "ko" ? ["홈·파일 보관함·날씨 탭 배치와 크기 설정", "현재 위치 날씨와 지역 이름 표시", "미디어 좋아요·진행 바 색상 설정", "일정 날짜 이동과 다시 열 때 날짜 유지 옵션", "음량·밝기·집중 모드 노치 표시", "통합 설정 앱과 입력기 설치 지원"] : ["Home, Shelf and Weather layout and sizing", "Current-location weather and place names", "Media favorites and progress colors", "Calendar navigation and date retention", "Volume, brightness and Focus notch indicators", "Unified settings and input-method installation"],id:\.self) {Text($0).padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color.accentColor.opacity(0.08),in:RoundedRectangle(cornerRadius:14))}
                        Text(settings.language == "ko" ? "집중 모드의 macOS 알림 숨김은 권한과 운영체제 동작에 따라 제한될 수 있습니다." : "Hiding the macOS Focus notification depends on permissions and system behavior.").font(.caption).foregroundStyle(.secondary)
                        Button(settings.language == "ko" ? "닫기" : "Close") {showingChangelog=false}
                    }.padding(32)}.frame(width:620,height:620)
                }
            Divider()
            Text(settings.language == "ko" ? "일상에 필요한 도구를 노치 한곳에." : "Everyday tools, together in your notch.").font(.title3)
            HStack(spacing: 24) {
                Link(settings.language == "ko" ? "소스 코드" : "Source", destination: URL(string: "https://github.com/akinoyuki0411/HanjaIME-")!)
                Link(settings.language == "ko" ? "버그 알리기" : "Report a bug", destination: URL(string: "https://github.com/akinoyuki0411/HanjaIME-/issues")!)
                Link(settings.language == "ko" ? "이메일" : "Email", destination: URL(string: "https://github.com/akinoyuki0411/HanjaIME-/issues")!)
            }
            Text(settings.language == "ko" ? "이 미리보기에는 자동 업데이트가 연결되어 있지 않습니다." : "Automatic updates are not connected in this preview.").font(.caption).foregroundStyle(.secondary)
        }.padding(36).frame(maxHeight: .infinity)
    }
    private var licenses: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(settings.language == "ko" ? "오픈소스 고지" : "Open-source notices").font(.title2.bold())
                ForEach(["Atoll-MIT", "MediaRemoteAdapter-BSD-3-Clause"], id: \.self) { name in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(name).font(.headline)
                        Text(licenseText(name)).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                }
            }.padding(28)
        }
    }
    private func licenseText(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) else { return name }
        return text
    }

    @ViewBuilder
    private var paneContent: some View {
        switch pane {
        case .general: GeneralSettingsView()
        case .appearance: AppearanceSettingsView()
        case .layout: LayoutSettingsView()
        case .liveActivities: LiveActivitySettingsView()
        case .media: MediaSettingsView()
        case .calendar: CalendarSettingsView()
        case .shelf: ShelfSettingsView()
        case .hud: HUDSettingsView()
        case .system: SystemEventsSettingsView()
        case .agents: CodeActivitySettingsView()
        case .mirror: MirrorSettingsView()
        case .timers: TimersSettingsView()
        case .notes: NotesSettingsView()
        case .todos: TodosSettingsView()
        case .face: FaceIntegrationSettingsView()
        case .weather: WeatherSettingsView()
        case .voice: VoiceSettingsView()
        case .insights: FocusInsightsView()
        case .ambient: AmbientSettingsView()
        }
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section(settings.language == "ko" ? "언어" : "Language") {
                Picker(settings.language == "ko" ? "표시 언어" : "Display language", selection: $settings.language) {
                    Text("한국어").tag("ko")
                    Text("English").tag("en")
                }
            }
            Section(settings.language == "ko" ? "홈 · 파일 보관함 · 날씨 위치" : "Home / Shelf / Weather position") {
                NavigationPlacementEditor()
            }
            Section(settings.language == "ko" ? "노치를 열 때" : "When opening the notch") {
                Picker(settings.language == "ko" ? "시작 화면" : "Start screen", selection: $settings.defaultTabRaw) {
                    ForEach(StartupDestination.allCases) { option in Text(option == .previous ? (settings.language == "ko" ? "닫았던 위치부터" : "Last screen") : HL(option.rawValue)).tag(option.rawValue) }
                }
                Text(settings.language == "ko" ? "클릭으로 다시 열거나 앱을 재실행할 때 적용합니다. 파일을 끌어오면 파일 보관함이 열립니다." : "Applies when reopening or restarting. Dragging a file opens the shelf.").font(.caption).foregroundStyle(.secondary)
            }
            Section(HL("Behavior")) {
                Toggle(settings.language == "ko" ? "마우스를 올리면 살짝 펼치기" : "Gently expand on hover", isOn: $settings.openOnHover)
                Text(settings.language == "ko" ? "클릭하면 바로 열립니다." : "Click to open immediately.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(HL("Haptic feedback"), isOn: $settings.hapticFeedback)
            }
            Section(HL("Displays")) {
                Toggle(HL("Show on all displays"), isOn: $settings.showOnAllDisplays)
                Toggle(HL("Simulate notch on external displays"), isOn: $settings.fakeNotchOnExternalDisplays)
            }
            Section(HL("System")) {
                Toggle(settings.language == "ko" ? "메뉴 막대에 한지미 노치 아이콘 표시" : "Show HanjiME Notch icon in the menu bar", isOn: $settings.showMenuBarIcon)
                Text(settings.language == "ko" ? "숨겨도 노치를 우클릭하면 설정을 열 수 있습니다." : "Right-click the notch to open Settings even when the icon is hidden.").font(.caption).foregroundStyle(.secondary)
                Toggle(HL("Launch at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        settings.launchAtLogin = newValue
                    }
                LabeledContent(HL("Toggle shortcut"), value: "⌥⌘N")
                LabeledContent(HL("Version"),
                               value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label(HL("Quit Atoll"), systemImage: "power")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = settings.launchAtLogin }
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section(HL("Background")) {
                Picker(HL("Style"), selection: $settings.backgroundStyle) {
                    Text(HL("Pure black")).tag("black")
                    Text(HL("Gradient")).tag("gradient")
                    Text(HL("Tinted by artwork")).tag("artwork")
                }
                if settings.backgroundStyle == "gradient" {
                    ColorPicker(HL("Gradient top"), selection: colorBinding($settings.gradientStartHex), supportsOpacity: false)
                    ColorPicker(HL("Gradient bottom"), selection: colorBinding($settings.gradientEndHex), supportsOpacity: false)
                }
            }
            Section(HL("Accent")) {
                ColorPicker(HL("Accent color"), selection: colorBinding($settings.accentHex), supportsOpacity: false)
                Toggle(HL("Border glow"), isOn: $settings.showBorderGlow)
            }
            Section(HL("Open nook size")) {
                HStack {
                    Text(HL("Width"))
                    Slider(value: $settings.openWidth, in: 480...900, step: 20)
                    Text("\(Int(settings.openWidth)) pt").monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
                HStack {
                    Text(HL("Height"))
                    Slider(value: $settings.openHeight, in: 300...560, step: 20)
                    Text("\(Int(settings.openHeight)) pt").monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
                HStack {
                    Text(HL("Corner radius"))
                    Slider(value: $settings.openCornerRadius, in: 10...40)
                    Text("\(Int(settings.openCornerRadius))").monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct LayoutSettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    private func tabBinding(_ tab: NotchTab) -> Binding<Bool> {
        Binding(get: { settings.visibleNavigationTabs.contains(tab) },
                set: { settings.setTabVisible(tab, visible: $0) })
    }

    var body: some View {
        Form {
            Section(HL("Tabs")) {
                ForEach(NotchTab.allCases) { tab in
                    Toggle(HL(tab.rawValue), isOn: tabBinding(tab))
                        .disabled(tab == .home)
                }

            }
            Section(HL("Home tab")) {
                Text(settings.language == "ko" ? "왼쪽 스위치로 위젯을 켜고, 미리보기에서 순서와 너비를 바꾸세요." : "Enable widgets on the left, then arrange and resize them in the preview.")
            }
        }
        .formStyle(.grouped)
    }
}

struct LiveActivitySettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section(HL("Closed-notch live activities")) {
                Toggle(HL("Now playing"), isOn: $settings.mediaLiveActivity)
                Toggle(HL("Timers"), isOn: $settings.timerLiveActivity)
                Toggle(HL("Battery & charging"), isOn: $settings.batteryLiveActivity)
                Toggle(HL("Upcoming calendar event"), isOn: $settings.calendarLiveActivity)
                Toggle(HL("Open to-dos count"), isOn: $settings.todosLiveActivity)
                Toggle(HL("Weather"), isOn: $settings.weatherLiveActivity)
                    .onChange(of: settings.weatherLiveActivity) { _, enabled in if enabled { Task { await WeatherStore.shared.refresh() } } }
            }
        }
        .formStyle(.grouped)
    }
}

private struct SettingsWindowSizer: NSViewRepresentable {
    var width: CGFloat
    var height: CGFloat
    var title: String
    final class Coordinator { var requested: NSSize?; var pending: DispatchWorkItem? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.pending?.cancel()
        let work = DispatchWorkItem {
            guard let window = view.window else { return }
            window.title = title
            let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
            var size = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: width, height: height)).size
            size.width = min(size.width, visible.width)
            size.height = min(size.height, visible.height)
            guard context.coordinator.requested != size else { return }
            context.coordinator.requested = size
            guard abs(window.frame.height - size.height) > 1 || abs(window.frame.width - size.width) > 1 else { return }
            let old = window.frame
            let x = max(visible.minX, min(old.midX - size.width / 2, visible.maxX - size.width))
            let y = max(visible.minY, min(old.maxY - size.height, visible.maxY - size.height))
            window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true, animate: window.isVisible)
        }
        context.coordinator.pending = work
        DispatchQueue.main.async(execute: work)
    }
}
