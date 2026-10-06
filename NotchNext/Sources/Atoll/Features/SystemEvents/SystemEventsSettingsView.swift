import SwiftUI

/// Settings pane for battery + Bluetooth live activities.
/// The integrator adds this as a tab/section of the settings window.
@MainActor
struct SystemEventsSettingsView: View {
    // "batteryLiveActivity" is the shared master toggle also exposed by
    // SettingsStore / LiveActivitySettingsView — same UserDefaults key on purpose.
    @AppStorage("batteryLiveActivity") private var batteryLiveActivity = true
    @AppStorage("systemEvents.showBatteryPercentAlways") private var showPercentAlways = false
    @AppStorage("systemEvents.lowBatteryAlerts") private var lowBatteryAlerts = true
    @AppStorage("systemEvents.bluetoothLiveActivity") private var bluetoothLiveActivity = true

    @AppStorage("audio.cycleShortcut") private var audioShortcut = false
    @AppStorage("systemEvents.focusChanges") private var focusChanges = true
    @ObservedObject private var focus = FocusStatusMonitor.shared
    @ObservedObject private var battery = BatteryMonitor.shared
    @ObservedObject private var bluetooth = BluetoothMonitor.shared

    private var settingsText: String { "실제 집중 모드 확인과 모드별 색상을 사용하려면 한지미 노치의 전체 디스크 접근이 필요합니다. 상태 파일 접근이 현재 차단되어 있습니다." }

    var body: some View {
        Form {
            Section(HL("Audio output")) { AudioOutputPicker(); Toggle(HL("Cycle outputs with ⌃⌥⌘O"), isOn: $audioShortcut) }
            Section(HL("Focus")) {
                Toggle(HL("Show Focus changes in the notch"), isOn: $focusChanges)
                if focus.stateFileReadable || focus.authorization == .authorized {
                    Text(focus.isFocused.map { $0 ? HL("Focus is on") : HL("Focus is off") } ?? HL("Focus status unavailable"))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button(HL("Allow Focus status access")) { focus.authorize() }
                }
                if !focus.stateFileReadable {
                    Text(focus.needsFilePermission ? settingsText : HL("Focus state file could not be decoded. Retry after changing Focus.")).font(.caption).foregroundStyle(.orange)
                    Text(focus.readFailure).font(.caption2).foregroundStyle(.secondary)
                    if focus.needsFilePermission { Button(HL("Open Privacy Settings…")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
                    } }
                }
                Text(HL("Focus sharing alone may not expose every mode. Full Disk Access allows reading the actual mode, icon, and color."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(HL("Battery live activity"), isOn: $batteryLiveActivity)
                Toggle(HL("Always show percentage"), isOn: $showPercentAlways)
                Toggle(HL("Low battery alerts"), isOn: $lowBatteryAlerts)
                    .disabled(!batteryLiveActivity)
            } header: {
                Text(HL("Battery"))
            } footer: {
                Text(HL("Shows charging, unplugged, fully charged and low battery (20% / 10%) events beside the notch. Low Power Mode changes are shown too."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(HL("Bluetooth live activity"), isOn: $bluetoothLiveActivity)
                if bluetooth.permissionDenied {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(HL("Bluetooth access is disabled for Atoll, so device events can't be detected."))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Button(HL("Open Privacy Settings…")) {
                                BluetoothMonitor.openBluetoothPrivacySettings()
                            }
                            .font(.system(size: 12))
                        }
                    }
                    .padding(.vertical, 2)
                } else if !bluetooth.connectedDeviceNames.isEmpty {
                    LabeledContent(HL("Connected now")) {
                        Text(bluetooth.connectedDeviceNames.joined(separator: ", "))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } header: {
                Text(HL("Bluetooth"))
            } footer: {
                Text(HL("Shows device connect and disconnect events beside the notch."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Picks up a permission change made while the pane was closed.
            bluetooth.retryAfterPermissionChange()
        }
    }
}
