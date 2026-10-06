import Foundation

// Original implementation of a nine-pose guided enrollment interaction.
// Vision yaw is positive toward the user's left; pitch is positive downward.
struct EnrollmentPose: Equatable {
    let label: String
    let symbol: String
    let x: Int
    let y: Int
    static let all: [EnrollmentPose] = [
        .init(label: "카메라를 정면으로 보세요", symbol: "viewfinder", x: 0, y: 0),
        .init(label: "고개를 왼쪽으로 조금 돌려 주세요", symbol: "arrow.left", x: -1, y: 0),
        .init(label: "왼쪽 위를 바라봐 주세요", symbol: "arrow.up.left", x: -1, y: -1),
        .init(label: "고개를 조금 들어 주세요", symbol: "arrow.up", x: 0, y: -1),
        .init(label: "오른쪽 위를 바라봐 주세요", symbol: "arrow.up.right", x: 1, y: -1),
        .init(label: "고개를 오른쪽으로 조금 돌려 주세요", symbol: "arrow.right", x: 1, y: 0),
        .init(label: "오른쪽 아래를 바라봐 주세요", symbol: "arrow.down.right", x: 1, y: 1),
        .init(label: "고개를 조금 내려 주세요", symbol: "arrow.down", x: 0, y: 1),
        .init(label: "왼쪽 아래를 바라봐 주세요", symbol: "arrow.down.left", x: -1, y: 1)
    ]
    func accepts(yaw: Double, pitch: Double) -> Bool {
        guard yaw.isFinite, pitch.isFinite, abs(yaw) < 0.7, abs(pitch) < 0.6 else { return false }
        func axis(_ value: Double, _ direction: Int) -> Bool {
            direction == 0 ? abs(value) < 0.16 : value * Double(direction) > 0.20
        }
        return axis(-yaw, x) && axis(pitch, y)
    }
}
struct EnrollmentGuide {
    private(set) var completed = 0
    private var stable = 0
    private var neutralPitch: Double?
    private var pendingPitch: Double?
    var stableFrames: Int { stable }
    private var lastTime = -Double.infinity
    var finished: Bool { completed == EnrollmentPose.all.count }
    var pose: EnrollmentPose { EnrollmentPose.all[min(completed, EnrollmentPose.all.count - 1)] }
    mutating func observe(yaw: Double?, pitch: Double?, now: Double) -> Bool {
        guard !finished, now.isFinite, now > lastTime else { return false }
        if now - lastTime > 2 { stable = 0 }
        lastTime = now
        guard let yaw, let pitch, yaw.isFinite, pitch.isFinite else { stable = 0; pendingPitch = nil; return false }
        if completed == 0 {
            // Calibrate the user's natural vertical gaze at a laptop camera. Keep
            // yaw frontal and require two consistent observations before accepting.
            guard abs(yaw) < 0.16, abs(pitch) < 0.45 else { stable = 0; pendingPitch = nil; return false }
            if let previous = pendingPitch, abs(previous - pitch) > 0.08 { stable = 0 }
            pendingPitch = pitch
        } else {
            guard pose.accepts(yaw: yaw, pitch: pitch - (neutralPitch ?? 0)) else { stable = 0; return false }
        }
        stable += 1
        guard stable >= 2 else { return false }
        if completed == 0 { neutralPitch = pitch }
        completed += 1; stable = 0; return true
    }
}
