import SwiftUI

/// Settings pane for the system-HUD replacement. Add as a tab/section in the
/// settings window.
struct HUDSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var interceptor = MediaKeyInterceptor.shared
    @ObservedObject private var brightnessManager = HUDBrightnessManager.shared
    @ObservedObject private var keyboard = KeyboardBrightnessManager.shared
    private var korean: Bool { settings.language == "ko" }
    @AppStorage(SneakPeekCoordinator.showOnExternalChangeKey) private var showOnExternalChange = true

    var body: some View {
        Form {
            Section {
                Toggle(HL("Replace system HUD"), isOn: replaceSystemHUDBinding)
                Text(HL("Volume, brightness and mute changes appear inside the notch instead of the system bezel. Media keys are intercepted while this is on; turning it off restores the standard macOS HUD immediately."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if settings.replaceSystemHUD {
                    accessibilityStatusRow
                    Text(interceptor.isTapActive
                         ? (korean ? "대체 작동 중 · 음량 및 밝기 키를 노치에서 처리합니다." : "Replacement active · volume and brightness keys are handled by the notch.")
                         : (korean ? "대체 대기 중 · 현재는 macOS 기본 표시가 나옵니다. 아래 권한을 허용해 주세요." : "Replacement pending · macOS still handles these keys. Grant access below."))
                        .font(.caption).foregroundStyle(interceptor.isTapActive ? Color.green : Color.orange)
                    if interceptor.axStatus && interceptor.tapCreationFailed {
                        statusRow(
                            symbol: "exclamationmark.triangle.fill",
                            color: .orange,
                            text: HL("Could not install the media-key event tap. Try toggling the setting off and on, or relaunch Atoll.")
                        )
                    }
                }
            } header: {
                Text(HL("System HUD"))
            }

            Section {
                Toggle(HL("Show HUD when volume changes externally"), isOn: $showOnExternalChange)
                Text(HL("Also shows the notch HUD when volume or mute is changed by another app, AirPods, an external keyboard, or the menu-bar slider."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } header: {
                Text(HL("External changes"))
            }

            Section(korean ? "밝기 조절" : "Brightness controls") {
                if brightnessManager.isAvailable {
                    HStack {
                        Label(korean ? "화면 밝기" : "Display brightness", systemImage: "sun.max.fill")
                        Slider(value: Binding(get: { Double(brightnessManager.brightness) }, set: { value in
                            if brightnessManager.setBrightness(Float(value)) {
                                SneakPeekCoordinator.shared.show(type: .brightness, value: Float(value))
                            }
                        }), in: 0...1).accessibilityLabel(korean ? "화면 밝기" : "Display brightness")
                        Text("\(Int(brightnessManager.brightness * 100))%")
                    }
                }
                if keyboard.isAvailable {
                    Text(keyboard.shortcutsAvailable
                         ? (korean ? "키보드 밝기 단축키: ⌃⌥⌘↑ 밝게 · ⌃⌥⌘↓ 어둡게" : "Keyboard shortcuts: ⌃⌥⌘↑ brighter · ⌃⌥⌘↓ dimmer")
                         : (korean ? "키보드 밝기 단축키를 등록하지 못했습니다. 다른 앱과의 충돌을 확인해 주세요." : "Keyboard shortcuts unavailable. Check for conflicts with another app."))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Label(korean ? "키보드 밝기" : "Keyboard brightness", systemImage: "keyboard.fill")
                        Slider(value: Binding(get: { Double(keyboard.brightness) }, set: { value in
                            if let actual = keyboard.setBrightness(Float(value)) {
                                SneakPeekCoordinator.shared.show(type: .keyboardBrightness, value: actual)
                            }
                        }), in: 0...1).accessibilityLabel(korean ? "키보드 밝기" : "Keyboard brightness")
                        Text("\(Int(keyboard.brightness * 100))%")
                    }
                    Text(korean ? "자동 밝기와 유휴 시 꺼짐 설정은 유지합니다. 노치를 우클릭해 키보드 밝기를 바로 조절할 수도 있습니다." : "Keeps automatic brightness and idle dimming. Right-click the notch for quick keyboard controls.").font(.caption).foregroundStyle(.secondary)
                    if keyboard.writeFailed {
                        Text(korean ? "현재 macOS 또는 주변 밝기 조건에서 변경이 적용되지 않았습니다." : "The change was not applied by macOS or current lighting conditions.").font(.caption).foregroundStyle(.orange)
                    }
                } else {
                    Text(korean ? "이 기기에서 조절 가능한 키보드 백라이트를 찾지 못했습니다." : "No controllable keyboard backlight found.").font(.caption)
                }
                Text(korean ? "밝기 제어는 비공개 macOS 기능을 사용하므로 OS 업데이트 후 지원 여부가 달라질 수 있습니다." : "Brightness controls use private macOS interfaces and may change after OS updates.").font(.caption).foregroundStyle(.secondary)
            }
            if !brightnessManager.isAvailable {
                Section {
                    statusRow(
                        symbol: "sun.max.trianglebadge.exclamationmark",
                        color: .secondary,
                        text: HL("Display brightness control is unavailable on this Mac; brightness keys are passed through to the system.")
                    )
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            brightnessManager.refresh()
            keyboard.refresh()
            interceptor.refreshPermissionStatus()
        }
    }

    // MARK: - Bindings

    private var replaceSystemHUDBinding: Binding<Bool> {
        Binding(
            get: { settings.replaceSystemHUD },
            set: { enabled in
                settings.replaceSystemHUD = enabled
                if enabled && !interceptor.axStatus {
                    interceptor.requestPermission()
                } else {
                    interceptor.refreshPermissionStatus()
                }
            }
        )
    }

    // MARK: - Rows

    @ViewBuilder
    private var accessibilityStatusRow: some View {
        if interceptor.axStatus {
            statusRow(
                symbol: "checkmark.circle.fill",
                color: .green,
                text: HL("Accessibility access granted")
            )
        } else {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(HL("Accessibility access is required to intercept media keys"))
                    .font(.system(size: 12))
                Spacer()
                Button(HL("Grant Access…")) {
                    interceptor.requestPermission()
                }
                Button(HL("Open System Settings")) {
                    openAccessibilitySettings()
                }
            }
        }
    }

    private func statusRow(symbol: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
