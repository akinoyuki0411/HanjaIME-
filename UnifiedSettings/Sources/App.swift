import SwiftUI
import AppKit
import Carbon

enum Component: String, CaseIterable, Identifiable {
    case notch, ime, japanese
    var id: String { rawValue }
    var title: String { switch self { case .notch: return "한지미 노치"; case .ime: return "한지미 입력기"; case .japanese: return "HanjaIME 日本語" } }
    var filename: String { switch self { case .notch: return "HanjiME Notch.app"; case .ime: return "HanjaIME.app"; case .japanese: return "HanjaIME 日本語.app" } }
    var bundleID: String { switch self { case .notch: return "org.hanjaime.notch.next"; case .ime: return "org.hanjaime.inputmethod.HanjaIME"; case .japanese: return "org.hanjaime.inputmethod.Japanese" } }
    var destination: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(self == .notch ? "Applications/\(filename)" : "Library/Input Methods/\(filename)")
    }
    var installedURL: URL? {
        let candidates = [destination, URL(fileURLWithPath: self == .notch ? "/Applications/\(filename)" : "/Library/Input Methods/\(filename)")]
        return candidates.first { Bundle(url: $0)?.bundleIdentifier == bundleID }
    }
}

@MainActor final class SettingsModel: ObservableObject {
    @Published var installed: [Component: URL] = [:]
    @Published var busy: Component?
    @Published var message = "설치된 앱의 설정을 열거나, 필요한 앱을 설치하세요."
    func refresh() { installed = Dictionary(uniqueKeysWithValues: Component.allCases.compactMap { c in c.installedURL.map { (c, $0) } }) }
    func open(_ component: Component) {
        guard let url = component.installedURL else { refresh(); return }
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--settings"]
        config.createsNewApplicationInstance = component != .notch
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            Task { @MainActor in
                if let error { self.message = "설정을 열지 못했습니다: \(error.localizedDescription)" }
                else if component == .notch { DistributedNotificationCenter.default().postNotificationName(Notification.Name("org.hanjaime.notch.openSettings"), object: nil, userInfo: nil, deliverImmediately: true) }
            }
        }
    }
    func install(_ component: Component) {
        guard busy == nil else { return }
        busy = component; message = "\(component.title) 설치 중…"
        Task {
            do {
                try await Task.detached { try Self.installPayload(component) }.value
                message = component != .notch ? "입력기를 설치했습니다. 시스템 설정 → 키보드 → 입력 소스에서 한지미를 추가하세요. 목록에 없으면 로그아웃 후 다시 로그인해 주세요." : "노치를 설치했습니다. ‘설정 열기’로 시작할 수 있습니다."
            } catch { message = "설치하지 못했습니다: \(error.localizedDescription)" }
            busy = nil; refresh()
        }
    }
    nonisolated static func installPayload(_ component: Component, fixtureDirectory: URL? = nil) throws {
        let fm = FileManager.default
        guard let resources = Bundle.main.resourceURL else { throw NSError(domain: "Install", code: 1, userInfo: [NSLocalizedDescriptionKey: "설치 파일이 없습니다."]) }
        let payload = resources.appendingPathComponent("Payloads/\(component.filename)")
        guard Bundle(url: payload)?.bundleIdentifier == component.bundleID else { throw NSError(domain: "Install", code: 2, userInfo: [NSLocalizedDescriptionKey: "설치 파일을 확인할 수 없습니다."]) }
        let verify = Process(); verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verify.arguments = ["--verify", "--deep", "--strict", payload.path]
        verify.standardOutput = FileHandle.nullDevice; verify.standardError = FileHandle.nullDevice
        try verify.run(); verify.waitUntilExit()
        guard verify.terminationStatus == 0 else { throw NSError(domain: "Install", code: 3, userInfo: [NSLocalizedDescriptionKey: "설치 파일 서명 검증에 실패했습니다."]) }
        let destination = fixtureDirectory?.appendingPathComponent(component.filename) ?? component.destination
        guard (fixtureDirectory != nil || component.installedURL == nil), !fm.fileExists(atPath: destination.path) else { throw NSError(domain: "Install", code: 4, userInfo: [NSLocalizedDescriptionKey: "같은 위치에 앱이 이미 있습니다. 기존 앱은 덮어쓰지 않습니다."]) }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".hanjimi-install-\(UUID().uuidString).app")
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: payload, to: staging)
        try fm.moveItem(at: staging, to: destination)
        if component != .notch && fixtureDirectory == nil {
            let result = TISRegisterInputSource(destination as CFURL)
            if result != noErr { throw NSError(domain: "Install", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "앱은 복사됐지만 입력기 등록을 완료하지 못했습니다. 로그아웃 후 다시 로그인해 주세요."]) }
        }
    }
}

#if !INSTALL_TEST
@main struct UnifiedSettingsApp: App {
    @StateObject private var model = SettingsModel()
    var body: some Scene {
        WindowGroup("한지미 통합 설정") {
            VStack(alignment: .leading, spacing: 22) {
                Label("한지미 통합 설정", systemImage: "gearshape.2.fill").font(.largeTitle.bold())
                Text("노치와 입력기를 한곳에서 관리합니다.").foregroundStyle(.secondary)
                ForEach(Component.allCases) { component in
                    HStack(spacing: 16) {
                        Image(systemName: component == .notch ? "rectangle.topthird.inset.filled" : "keyboard").font(.system(size: 30)).frame(width: 48)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(component.title).font(.headline)
                            Text(model.installed[component] == nil ? "설치되지 않음" : "설치됨 · \(Bundle(url: model.installed[component]!)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")").foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.installed[component] != nil { Button("설정 열기") { model.open(component) } }
                        else { Button(model.busy == component ? "설치 중…" : "설치") { model.install(component) }.disabled(model.busy != nil) }
                    }.padding(20).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                }
                Text(model.message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("설치 상태 새로고침") { model.refresh() }
                    Button("키보드 설정") { if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") { NSWorkspace.shared.open(url) } }
                }
                Text("설치 파일이 포함되어 있어 별도 다운로드가 필요 없습니다. 현재 개발 시험판이며 Apple 공증 배포판은 아닙니다.").font(.caption).foregroundStyle(.secondary)
            }.padding(30).frame(width: 620)
                .onAppear { model.refresh() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
        }.windowResizability(.contentSize)
    }
}
#endif
