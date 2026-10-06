import AppKit
import SwiftUI

/// Only presentation commands cross this boundary, never credentials or biometrics.
@MainActor final class FaceIntegration: ObservableObject {
    static let shared = FaceIntegration()
    @Published private(set) var presenting = false
    @Published private(set) var message: String?
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var lastHeartbeat = Date.distantPast
    private var lease: String?
    private var processID: pid_t?
    var helperURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/HanjiME Face.app") }
    var available: Bool { FileManager.default.fileExists(atPath: helperURL.path) }
    private init() {
        observer = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("org.hanjaime.notch.enrollmentPresentation.v1"), object: nil, queue: .main) { [weak self] notification in
            let info = notification.userInfo
            let pid = (info?["pid"] as? NSNumber)?.int32Value
            let token = info?["lease"] as? String
            let active = info?["active"] as? Bool
            Task { @MainActor in
                guard let self, let pid, let token, let active,
                      let app = NSRunningApplication(processIdentifier: pid),
                      app.bundleIdentifier == "org.hanjaime.face",
                      app.bundleURL?.standardizedFileURL == self.helperURL.standardizedFileURL else { return }
                if active {
                    self.processID = pid; self.lease = token; self.lastHeartbeat = Date(); self.presenting = true
                } else if self.processID == pid && self.lease == token {
                    self.presenting = false; self.lease = nil
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.presenting else { return }
                if Date().timeIntervalSince(self.lastHeartbeat) > 6 || self.processID.flatMap(NSRunningApplication.init(processIdentifier:)) == nil {
                    self.presenting = false; self.lease = nil
                }
            }
        }
    }
    func stop() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "org.hanjaime.face")
        where app.bundleURL?.standardizedFileURL == helperURL.standardizedFileURL {
            app.terminate()
        }
        presenting = false
    }
    func open(_ page: String) {
        guard ["enroll", "settings", "test"].contains(page), available,
              let url = URL(string: "hanjimeface://\(page)") else {
            message = SettingsStore.shared.language == "ko" ? "얼굴인식 구성 요소를 찾지 못했습니다. 앱 설치를 확인해 주세요." : "Face recognition component is missing."
            return
        }
        message = nil
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: helperURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                if error != nil { self?.message = SettingsStore.shared.language == "ko" ? "얼굴인식 화면을 열지 못했습니다." : "Could not open face recognition." }
            }
        }
    }
}

struct FaceIntegrationSettingsView: View {
    @ObservedObject private var face = FaceIntegration.shared
    @EnvironmentObject var settings: SettingsStore
    private var korean: Bool { settings.language == "ko" }
    var body: some View {
        Form {
            Section(korean ? "얼굴인식" : "Face recognition") {
                Label(korean ? "한지미 노치에서 얼굴을 등록하고 확인합니다." : "Enroll and verify your face from HanjiME Notch.", systemImage: "faceid")
                Button(korean ? "노치에서 얼굴 등록…" : "Enroll in the notch…") { face.open("enroll") }
                Button(korean ? "얼굴 인식 시험…" : "Test face recognition…") { face.open("test") }
                Button(korean ? "얼굴인식 설정…" : "Face recognition settings…") { face.open("settings") }
                Text(korean ? "얼굴 등록 중에는 노치가 등록 화면으로 바뀌고, 닫으면 원래 노치로 돌아옵니다. 인식 시험은 비밀번호를 입력하지 않습니다." : "Enrollment temporarily replaces the notch. Recognition testing never enters a password.").font(.caption).foregroundStyle(.secondary)
            }
            Section(korean ? "현재 지원 범위" : "Current scope") {
                Text(korean ? "웹캠 기반 실험 기능입니다. Apple Pay·패스키·다른 앱의 Touch ID 승인과 FileVault 부팅 로그인은 대체하지 않습니다." : "Experimental webcam recognition; not a replacement for Apple Pay, passkeys, other apps’ Touch ID prompts or FileVault startup login.").font(.caption)
            }
            if let message = face.message { Text(message).foregroundStyle(.orange) }
        }.formStyle(.grouped)
    }
}
