import AVFoundation
import SwiftUI

/// Settings pane for the mirror: default camera and mirroring toggle.
/// The integrator adds this as a tab/section of the settings window.
struct MirrorSettingsView: View {
    @ObservedObject private var manager = MirrorManager.shared

    var body: some View {
        Form {
            Section(HL("Mirror")) {
                Picker(HL("Default camera"), selection: $manager.selectedCameraID) {
                    Text(HL("Automatic")).tag("")
                    ForEach(manager.devices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID)
                    }
                    // Keep a stale (disconnected) selection representable so the
                    // picker doesn't silently reset the persisted value.
                    if !manager.selectedCameraID.isEmpty,
                       !manager.devices.contains(where: { $0.uniqueID == manager.selectedCameraID }) {
                        Text(HL("Last selected camera (disconnected)"))
                            .tag(manager.selectedCameraID)
                    }
                }
                Toggle(HL("Flip preview horizontally (mirror)"), isOn: $manager.isMirrored)
            }
            if manager.authStatus == .denied || manager.authStatus == .restricted {
                Section {
                    LabeledContent(HL("Camera access")) {
                        Button(HL("Open System Settings")) {
                            MirrorManager.openCameraPrivacySettings()
                        }
                    }
                    Text(HL("Camera access is currently disabled for Atoll, so the mirror can't show a preview."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            manager.refreshAuthStatus()
            manager.refreshDevices()
        }
    }
}
