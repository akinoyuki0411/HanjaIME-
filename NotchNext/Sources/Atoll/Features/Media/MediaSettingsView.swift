import SwiftUI

/// Settings pane for the media widget — add as a section/tab of the
/// settings window.
struct MediaSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var manager = MusicManager.shared

    var body: some View {
        Form {
            Section(HL("Now Playing")) {
                Toggle(HL("Show media controls"), isOn: $manager.mediaEnabled)

                Picker(HL("Show media from"), selection: Binding(
                    get: { manager.sourceFilter },
                    set: { manager.sourceFilter = $0 }
                )) {
                    ForEach(MediaSourceFilter.allCases) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                .disabled(!manager.mediaEnabled)

                Toggle(HL("Audio visualizer in the notch"), isOn: $manager.showVisualizer)
                    .disabled(!manager.mediaEnabled)
            }

            Section(settings.language == "ko" ? "음악 색상" : "Music colors") {
                ColorPicker(settings.language == "ko" ? "좋아요한 곡의 별" : "Favorite star", selection: colorBinding($settings.favoriteHex), supportsOpacity: false)
                ColorPicker(settings.language == "ko" ? "재생 진행 막대" : "Playback progress", selection: colorBinding($settings.progressHex), supportsOpacity: false)
                Button(settings.language == "ko" ? "기본 회색으로 되돌리기" : "Reset to gray") {
                    settings.favoriteHex = "#A8A8AD"
                    settings.progressHex = "#A8A8AD"
                }
            }

            Section(HL("Status")) {
                statusRow(
                    ok: manager.adapterResourcesAvailable,
                    okText: HL("MediaRemote adapter available"),
                    failText: HL("MediaRemote adapter not bundled — using app-specific fallback only")
                )
                if manager.usingScriptFallback {
                    statusRow(
                        ok: true,
                        okText: "Using AppleScript fallback (\(manager.playback?.appName ?? "Spotify / Apple Music"))",
                        failText: ""
                    )
                }
                if manager.automationPermissionDenied {
                    HStack {
                        statusRow(
                            ok: false,
                            okText: "",
                            failText: HL("Automation access denied for Spotify / Music")
                        )
                        Spacer()
                        Button(HL("Open Settings")) {
                            manager.openAutomationSettings()
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func statusRow(ok: Bool, okText: String, failText: String) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(ok ? Color.green.opacity(0.85) : Color.orange.opacity(0.9))
                .frame(width: 7, height: 7)
            Text(ok ? okText : failText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
