import AppKit
import SwiftUI
import LocalAuthentication
import AVFoundation

@MainActor final class FaceService: ObservableObject {
    @Published private(set) var cameraState = "카메라 꺼짐"
    @Published private(set) var testing = false
    @Published private(set) var lastTestResult = ""
    private var waitingForTestFrame = false
    private var testPreparationHint = "카메라 영상이 아직 도착하지 않았습니다."
    @Published var status = "실험 기능 · 자동 입력 꺼짐"
    @Published var registration = "등록 상태 확인 전"
    @Published var enabled = false
    @Published var busy = false
    @Published var enrollmentProgress = 0
    @Published var showingPreview = false
    @Published var enrollmentOpen = false
    @Published var enrollmentStep = "intro"
    @Published var pose = EnrollmentPose.all[0]
    private var guide = EnrollmentGuide()
    var enrollmentVisibility: ((Bool) -> Void)?
    @Published var password = ""
    @Published var acknowledged = false
    private let secrets = SecretStore(service: "org.hanjaime.face.private")
    private let driver = UnlockDriver()
    let camera = FaceCapture()
    private var template: FaceTemplate?
    private var samples: [[Float]] = []
    private var enrolling = false
    private var challenge: FaceChallenge?
    private var gate = UnlockAttemptGate()
    private var target: UnlockDriver.Target?
    private var timer: Timer?
    private var deadline: TimeInterval = 0
    private var desktopChecks = 0
    private var operation = UUID()
    private var authContext: LAContext?
    init() {
        refreshRegistration()
        camera.diagnostic = { [weak self] message in Task { @MainActor in
            guard let self, self.busy else { return }; self.cameraState = message
        } }
        camera.issue = { [weak self] message in Task { @MainActor in
            guard let self, self.busy else { return }
            self.status = message
            if self.testing && self.waitingForTestFrame { self.testPreparationHint = message }
        } }
        camera.receive = { [weak self] frame in Task { @MainActor in self?.receive(frame) } }
    }
    func refreshRegistration() {
        registration = "얼굴: " + (secrets.contains("face-template") ? "등록됨" : "미등록 또는 접근 불가")
            + " · 비밀번호: " + (secrets.contains("login-password") ? "저장됨" : "미등록 또는 접근 불가")
    }
    private func authorize(_ reason: String) async -> Bool {
        let context = LAContext(); authContext = context
        defer { if authContext === context { authContext = nil } }
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            status = "이 환경에서는 macOS 본인 확인을 시작할 수 없습니다."; busy = false; enrollmentStep = "failed"; return false
        }
        NSApp.activate(ignoringOtherApps: true)
        status = "macOS 본인 확인 창에서 Touch ID 또는 비밀번호로 확인해 주세요."
        do { return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) }
        catch { status = "본인 확인이 취소되었거나 실패했습니다."; busy = false; showingPreview = false; enrollmentStep = "failed"; return false }
    }
    func openEnrollment() {
        disable(); enrollmentProgress = 0; guide = EnrollmentGuide(); pose = guide.pose
        enrollmentStep = "intro"; enrollmentOpen = true; enrollmentVisibility?(true)
    }
    func closeEnrollment() { disable(); enrollmentOpen = false; enrollmentVisibility?(false) }
    func enroll() {
        disable()
        let run = operation
        busy = true; enrollmentProgress = 0; guide = EnrollmentGuide(); pose = guide.pose; enrollmentStep = "authorizing"
        Task {
            guard await authorize("한지미 얼굴 등록을 변경합니다."), operation == run else { return }
            status = "카메라 권한을 확인하고 있습니다."
            let permitted = await AVCaptureDevice.requestAccess(for: .video)
            guard operation == run else { return }
            guard permitted else { busy = false; enrollmentStep = "failed"; status = "시스템 설정에서 카메라 권한을 허용해야 합니다."; return }
            samples = []; enrolling = true; busy = true; showingPreview = true
            deadline = ProcessInfo.processInfo.systemUptime + 90
            enrollmentStep = "capture"
            status = pose.label
            startTimer(); camera.start()
        }
    }
    /// Verify an enrollment without reading a password or invoking UnlockDriver.
    func testRecognition() {
        disable()
        lastTestResult = ""
        testPreparationHint = "카메라 영상이 아직 도착하지 않았습니다."
        let run = operation
        busy = true
        Task {
            guard await authorize("등록한 얼굴의 인식 상태를 확인합니다."), operation == run else { return }
            do {
                guard let data = try secrets.read("face-template"),
                      let saved = try? JSONDecoder().decode(FaceTemplate.self, from: data), saved.valid else {
                    busy = false; status = "먼저 얼굴을 등록해 주세요."; return
                }
                guard FacePolicy.enrollmentIsConsistent(saved) else {
                    busy = false
                    lastTestResult = "기존 등록의 방향별 얼굴 특징이 서로 일치 기준을 만족하지 않습니다. 고개를 조금씩 움직여 얼굴을 다시 등록해 주세요."
                    status = lastTestResult; return
                }
                let permitted = await AVCaptureDevice.requestAccess(for: .video)
                guard operation == run else { return }
                guard permitted else { busy = false; status = "카메라 권한이 필요합니다."; return }
                template = saved; testing = true; showingPreview = true
                challenge = nil; waitingForTestFrame = true
                deadline = ProcessInfo.processInfo.systemUptime + 30
                status = "인식 시험 · 카메라 준비 중입니다. 정면을 바라봐 주세요. 비밀번호는 입력하지 않습니다."
                startTimer(); camera.start()
            } catch { busy = false; status = "등록 정보를 읽지 못했습니다. 다시 등록해 주세요." }
        }
    }
    func savePassword() {
        // Copy only for the duration of the authenticated save; never send to logs or IPC.
        let value = password; password = ""; disable()
        guard !value.isEmpty, value.utf16.count <= 256,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            status = "비밀번호 형식을 확인하세요."; return
        }
        let run = operation
        Task {
            guard await authorize("Mac 잠금 해제용 비밀번호를 이 Mac의 키체인에 저장합니다."), operation == run else { return }
            do { try secrets.save(Data(value.utf8), account: "login-password"); refreshRegistration(); status = "키체인에 저장했습니다. 비밀번호의 정확성은 아직 확인하지 않았습니다." }
            catch { status = "키체인 저장에 실패했습니다." }
        }
    }
    func enable() {
        guard acknowledged, !busy else { return }
        operation = UUID(); let run = operation
        Task {
            guard await authorize("실험용 얼굴 인증과 Mac 비밀번호 자동 입력을 켭니다."), operation == run else { return }
            do {
                guard let data = try secrets.read("face-template"),
                      let saved = try? JSONDecoder().decode(FaceTemplate.self, from: data), saved.valid,
                      secrets.contains("login-password") else {
                    status = "먼저 얼굴과 비밀번호를 등록하세요."; return
                }
                guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { status = "카메라 권한이 필요합니다."; return }
                guard driver.trusted else { driver.requestAccessibility(); status = "손쉬운 사용에서 HanjiME Face를 허용한 뒤 다시 켜세요."; return }
                template = saved; enabled = true; startTimer(); status = "대기 중 · 확인 가능한 잠금 화면에서만 시도합니다."
            } catch { status = "키체인 정보를 읽지 못했습니다." }
        }
    }
    func disable() {
        if testing { lastTestResult = "인식 시험을 중지했습니다. 비밀번호는 입력하지 않았습니다." }
        waitingForTestFrame = false
        testing = false; cameraState = "카메라 꺼짐"
        operation = UUID(); authContext?.invalidate(); authContext = nil; showingPreview = false
        enabled = false; busy = false; enrolling = false; challenge = nil; target = nil
        samples.removeAll(); template = nil; camera.stop(); timer?.invalidate(); timer = nil
        // Retain the attempt gate until an observed desktop session rearms it.
        status = "자동 입력 꺼짐"
    }
    func erase() {
        disable()
        let run = operation
        Task {
            guard await authorize("한지미에 등록한 얼굴 특징과 비밀번호를 삭제합니다."), operation == run else { return }
            do { try secrets.delete("face-template"); try secrets.delete("login-password"); status = "한지미의 얼굴 특징과 비밀번호를 삭제했습니다." }
            catch { status = "일부 키체인 항목을 삭제하지 못했습니다." }
        }
    }
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    private func tick() {
        if busy {
            if ProcessInfo.processInfo.systemUptime > deadline {
                finish(testing && waitingForTestFrame ? "인식 시험 준비 시간 초과 · " + testPreparationHint : "시간 초과 · 카메라를 중지했습니다.")
            }
            else if !enrolling, let target, !driver.sameTarget(target, requireEmpty: true) { finish("잠금 화면이 바뀌어 중지했습니다.") }
            return
        }
        guard enabled else { return }
        if driver.desktopIsActive {
            desktopChecks += 1
            if desktopChecks >= 3 { gate.unlocked(); challenge = nil; target = nil }
            return
        }
        desktopChecks = 0
        guard let verified = driver.target() else { return }
        gate.locked()
        guard !gate.attempted, challenge == nil else { return }
        target = verified; challenge = FaceChallenge(now: ProcessInfo.processInfo.systemUptime)
        busy = true; deadline = ProcessInfo.processInfo.systemUptime + 18
        status = "얼굴 확인: 정면 → 고개 돌리기 → 정면"
        camera.start()
    }
    private func receive(_ frame: FaceFrame?) {
        guard busy else { return }
        if testing && waitingForTestFrame {
            guard let frame, let template else { return }
            guard FacePolicy.matches(frame.embedding, template: template) else {
                testPreparationHint = "등록한 얼굴과 일치하지 않았습니다. 같은 조명에서 정면을 보고 다시 시험해 주세요."
                status = testPreparationHint; return
            }
            guard abs(frame.yaw) < 0.13 else {
                testPreparationHint = "등록한 얼굴은 확인됐습니다. 고개를 정면으로 돌려 주세요."
                status = testPreparationHint; return
            }
            waitingForTestFrame = false
            let now = ProcessInfo.processInfo.systemUptime
            challenge = FaceChallenge(now: now); deadline = now + 18
            status = "카메라 준비 완료 · 정면을 잠시 유지해 주세요."
        }
        if enrolling {
            guard let frame else {
                _ = guide.observe(yaw: nil, pitch: nil, now: ProcessInfo.processInfo.systemUptime)
                return
            }
            if !samples.allSatisfy({ (FacePolicy.score($0, frame.embedding) ?? -1) >= FacePolicy.threshold }) {
                // A difficult pose is a rejected frame, not a discarded enrollment.
                // The same identity threshold still gates every saved sample.
                _ = guide.observe(yaw: nil, pitch: nil, now: ProcessInfo.processInfo.systemUptime)
                status = "얼굴 특징이 선명하지 않습니다. 고개를 덜 돌리고 천천히 움직여 주세요."
                return
            }
            guard guide.observe(yaw: frame.yaw, pitch: frame.pitch, now: ProcessInfo.processInfo.systemUptime) else { status = guide.stableFrames > 0 ? "얼굴을 찾았습니다. 잠시 그대로 있어 주세요." : "얼굴 감지됨 · " + pose.label; return }
            samples.append(frame.embedding); enrollmentProgress = guide.completed; pose = guide.pose
            status = guide.finished ? "등록 정보를 저장하고 있습니다." : pose.label
            guard guide.finished else { return }
            let value = FaceTemplate(model: FaceTemplate.model, samples: samples)
            do { try secrets.save(JSONEncoder().encode(value), account: "face-template"); finish("얼굴 특징을 키체인에 등록했습니다."); enrollmentStep = "complete" }
            catch { finish("얼굴 특징 저장에 실패했습니다.") }
            return
        }
        guard var current = challenge, let template else { return }
        current.observe(matches: frame.map { FacePolicy.matches($0.embedding, template: template) } ?? false,
                        yaw: frame?.yaw, now: ProcessInfo.processInfo.systemUptime)
        challenge = current
        switch current.stage {
        case .center: status = "카메라를 정면으로 보세요."
        case .turn: status = current.direction > 0 ? "고개를 한쪽으로 천천히 돌리세요 →" : "← 고개를 반대쪽으로 천천히 돌리세요"
        case .returnToCenter: status = "다시 정면을 보세요."
        case .failed: finish(testing ? "얼굴 인식 시험 실패 · 비밀번호 입력은 하지 않았습니다." : "얼굴 확인 실패 · 이 잠금 세션에서 다시 시도하지 않습니다.")
        case .passed:
            if testing {
                finish("얼굴 일치와 고개 움직임 확인을 통과했습니다. 시스템 인증을 대신한 것은 아닙니다.")
                return
            }
            guard let target, let epoch = gate.epoch,
                  gate.claim(epoch: epoch, challenge: current, enabled: enabled,
                             sessionIsOwner: driver.ownsConsoleSession,
                             targetVerified: driver.sameTarget(target, requireEmpty: true)) else { finish("잠금 화면을 확인하지 못해 입력을 차단했습니다."); return }
            do {
                guard var bytes = try secrets.read("login-password") else { finish("저장한 비밀번호를 읽지 못했습니다."); return }
                defer { bytes.resetBytes(in: 0..<bytes.count) }
                let result = driver.enter(bytes, target: target)
                finish(result == .posted ? "입력 이벤트를 전송했습니다. 잠금 해제 성공 여부는 별도 확인이 필요합니다." : "대상이 바뀌어 입력을 차단했습니다.")
            } catch { finish("키체인 접근 실패 · 입력하지 않았습니다.") }
        }
    }
    private func finish(_ message: String) {
        if testing { lastTestResult = message }
        waitingForTestFrame = false
        // Keeping the completed/failed challenge prevents retries in this lock session.
        if enrolling { enrollmentStep = "failed" }
        refreshRegistration(); showingPreview = false
        cameraState = "카메라 꺼짐"
        testing = false; busy = false; enrolling = false; samples.removeAll(); camera.stop(); status = message
        if !enabled { timer?.invalidate(); timer = nil }
    }
}

struct FacePreview: NSViewRepresentable {
    let session: AVCaptureSession
    final class Preview: NSView {
        let preview = AVCaptureVideoPreviewLayer()
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true; layer = CALayer()
            preview.videoGravity = .resizeAspectFill
            layer?.addSublayer(preview)
        }
        required init?(coder: NSCoder) { nil }
        override func layout() {
            super.layout()
            // Explicit layer mirroring also works when AVCapture preview mirroring is ignored.
            // Reference: jonnyoo/glance CameraPreviewView.swift (MIT; see Licenses).
            CATransaction.begin(); CATransaction.setDisableActions(true)
            preview.bounds = CGRect(origin: .zero, size: bounds.size)
            preview.position = CGPoint(x: bounds.midX, y: bounds.midY)
            preview.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
            CATransaction.commit()
        }
        func attach(_ session: AVCaptureSession) {
            if preview.session !== session { preview.session = session }
            if let connection = preview.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false // One mirror only, performed by the display layer.
            }
            needsLayout = true
        }
    }
    func makeNSView(context: Context) -> Preview { let view = Preview(frame: .zero); view.attach(session); return view }
    func updateNSView(_ view: Preview, context: Context) { view.attach(session) }

}
struct FaceSettingsView: View {
    @ObservedObject var model: FaceService
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            Label("HanjiME Face · 실험 기능", systemImage: "faceid").font(.title2.bold()).foregroundStyle(.green)
            Text("웹캠 기반 얼굴 인증입니다. Apple Face ID가 아니며 사진·영상 공격 방어와 오인식률을 검증하지 않았습니다. FileVault 부팅 잠금 해제는 지원하지 않습니다.").font(.callout)
            HStack {
                Button("얼굴 등록 / 다시 등록…") { model.openEnrollment() }.disabled(model.busy)
                Button("얼굴 인식 시험…") { model.testRecognition() }.disabled(model.busy)
            }
            if model.testing {
                FacePreview(session: model.camera.session).frame(width: 140, height: 140).clipShape(Circle())
                Text("인식 시험에서는 저장된 비밀번호를 읽거나 입력하지 않습니다.").font(.caption)
                Button("인식 시험 중지") { model.disable() }
            }
            if !model.lastTestResult.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("최근 인식 시험 결과").font(.headline)
                    Text(model.lastTestResult).textSelection(.enabled)
                    Button("다시 시험") { model.testRecognition() }.disabled(model.busy)
                }.padding(12).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
            Text("지원 범위: 얼굴 등록·인식 시험 / 실험용 Mac 잠금 해제. Apple Pay·패스키·다른 앱의 Touch ID 승인·FileVault 부팅 로그인은 대체하지 않습니다.").font(.caption).foregroundStyle(.secondary)
            SecureField("이 Mac의 로그인 비밀번호", text: $model.password).textFieldStyle(.roundedBorder)
            Button("비밀번호를 키체인에 저장…") { model.savePassword() }.disabled(model.password.isEmpty || model.busy)
            Text("비밀번호와 얼굴 특징은 이 Mac의 전용 키체인 항목에 저장합니다. 앱 재실행 시 자동 입력은 다시 꺼집니다.").font(.caption).foregroundStyle(.secondary)
            Toggle("실험 기능의 위험과 비밀번호 자동 입력에 동의합니다", isOn: $model.acknowledged)
            HStack {
                Button("자동 입력 켜기…") { model.enable() }.disabled(!model.acknowledged || model.enabled || model.busy)
                Button("중지") { model.disable() }
                Spacer()
                Button("등록 정보 삭제…", role: .destructive) { model.erase() }
            }
            HStack { Text(model.registration).font(.caption); Button("상태 확인") { model.refreshRegistration() } }
            if model.busy { Text(model.cameraState).font(.caption).foregroundStyle(.secondary) }
            Divider(); Text(model.status).font(.callout).textSelection(.enabled)
            Text("공개 API에서 잠금 화면의 비밀번호 칸을 확인할 수 없으면 입력하지 않습니다. 자동 입력 실패 시 원래의 Mac 비밀번호나 Touch ID를 사용하세요.").font(.caption).foregroundStyle(.secondary)
        }.padding(24) }.frame(width: 608, height: 620)

    }
}
@main struct FaceApp: App {
    @NSApplicationDelegateAdaptor(FaceDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}
@MainActor final class FaceDelegate: NSObject, NSApplicationDelegate {
    let model = FaceService()
    var window: NSWindow?
    var item: NSStatusItem?
    var enrollmentPanel: FaceEnrollmentPanel?
    private var ready = false
    private var pendingPage: String?
    private var restoreFaceSettings = false
    private var integrated: Bool { Bundle.main.bundleURL.path.contains("/Contents/Helpers/") }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.last, url.scheme == "hanjimeface", let page = url.host,
              ["enroll", "test", "settings"].contains(page) else { return }
        if ready { route(page) } else { pendingPage = page }
    }
    private func route(_ page: String) {
        if page == "enroll" { model.openEnrollment() }
        else {
            show()
            if page == "test", !model.busy { model.testRecognition() }
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 608, height: 520), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = integrated ? "한지미 노치 · 얼굴인식" : "HanjiME Face"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: FaceSettingsView(model: model)); window.center(); self.window = window
        if !integrated { item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) }
        item?.button?.image = NSImage(systemSymbolName: "faceid", accessibilityDescription: "HanjiME Face")
        let menu = NSMenu()
        for (title, action) in [("얼굴 인증 설정…", #selector(show)), ("자동 입력 중지", #selector(stop)), ("얼굴 서비스 종료", #selector(quit))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = self; menu.addItem(entry)
        }
        item?.menu = menu
        enrollmentPanel = FaceEnrollmentPanel(model: model)
        model.enrollmentVisibility = { [weak self] open in
            guard let self else { return }
            if open {
                self.restoreFaceSettings = self.window?.isVisible == true
                self.window?.orderOut(nil); self.enrollmentPanel?.present()
            } else {
                self.enrollmentPanel?.dismiss()
                if self.restoreFaceSettings { self.window?.orderFront(nil) }
            }
        }
        ready = true
        if let pendingPage { route(pendingPage); self.pendingPage = nil }
        else if !integrated { show() }
    }
    @objc func show() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func stop() { model.closeEnrollment() }
    @objc func quit() { model.closeEnrollment(); NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool { show(); return true }
    func applicationWillTerminate(_ notification: Notification) { model.disable(); enrollmentPanel?.shutdown() }
}
