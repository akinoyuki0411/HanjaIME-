import SwiftUI

/// The camera lives in its home circle and is released when the circle disappears.
struct InlineMirrorWidget: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject private var manager = MirrorManager.shared
    @State private var active = false
    var body: some View {
        Button {
            if active && (manager.authStatus == .denied || manager.authStatus == .restricted) {
                MirrorManager.openCameraPrivacySettings()
            } else { active.toggle() }
        } label: {
            ZStack {
                Circle().fill(Color.white.opacity(0.10))
                if active {
                    LiveMirrorCircle()
                } else {
                    VStack(spacing: 7) {
                        Image(systemName: "web.camera").font(.system(size: 26))
                        Text(HL("Mirror")).font(.system(size: 12, weight: .medium))
                    }
                }
            }.clipShape(Circle()).contentShape(Circle())
        }.buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(settings.language == "ko" ? (active ? "거울 끄기" : "거울 켜기") : (active ? "Turn mirror off" : "Turn mirror on"))
            .help(settings.language == "ko" ? "누르면 이 원에서 거울을 켜거나 끕니다" : "Click to turn the mirror on or off in this circle")
    }
}

private struct LiveMirrorCircle: View {
    @ObservedObject private var manager = MirrorManager.shared
    var body: some View {
        ZStack {
            if manager.authStatus == .authorized && !manager.devices.isEmpty {
                MirrorCameraPreview(session: manager.session, isMirrored: manager.isMirrored, configurationVersion: manager.configurationVersion)
                    .allowsHitTesting(false)
                if !manager.isSessionRunning { ProgressView().controlSize(.small) }
            } else if manager.authStatus == .notDetermined {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "video.slash").font(.title2)
                    .help(HL("Camera access needed"))
            }
        }.onAppear { manager.previewDidAppear() }
            .onDisappear { manager.previewDidDisappear() }
    }
}
