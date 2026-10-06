import Foundation

// Research thresholds, not a measured false-accept rate or a Face ID equivalent.
struct FaceTemplate: Codable {
    static let model = "opencv-sface-2021dec-v1"
    let model: String
    let samples: [[Float]]
    var valid: Bool { model == Self.model && (3...12).contains(samples.count) && samples.allSatisfy(FacePolicy.valid) }
}
enum FacePolicy {
    static let threshold: Float = 0.65
    static func valid(_ vector: [Float]) -> Bool {
        guard vector.count == 128, vector.allSatisfy({ $0.isFinite }) else { return false }
        let norm = vector.reduce(Float(0)) { $0 + $1*$1 }
        return norm > 0.98 && norm < 1.02
    }
    static func score(_ a: [Float], _ b: [Float]) -> Float? {
        guard valid(a), valid(b) else { return nil }
        return zip(a,b).reduce(Float(0)) { $0 + $1.0 * $1.1 }
    }
    static func matches(_ vector: [Float], template: FaceTemplate) -> Bool {
        guard template.valid else { return false }
        // Require agreement with every enrolled frame, not just one accidental match.
        return template.samples.allSatisfy { (score(vector,$0) ?? -1) >= threshold }
    }
    static func enrollmentIsConsistent(_ template: FaceTemplate) -> Bool {
        guard template.valid else { return false }
        return template.samples.allSatisfy { candidate in
            template.samples.allSatisfy { (score(candidate, $0) ?? -1) >= threshold }
        }
    }
}
struct FaceChallenge {
    enum Stage: Equatable { case center, turn, returnToCenter, passed, failed }
    private(set) var stage = Stage.center
    let direction: Int
    let started: TimeInterval
    private var stable = 0
    private var frames = 0
    private var lastTime: TimeInterval = -.infinity
    init(now: TimeInterval, direction: Int = Bool.random() ? 1 : -1) { self.started = now; self.direction = direction >= 0 ? 1 : -1 }
    mutating func observe(matches: Bool, yaw: Double?, now: TimeInterval) {
        guard stage != .passed && stage != .failed else { return }
        guard now.isFinite, now >= started, now - started <= 18, now > lastTime else { stage = .failed; return }
        if lastTime.isFinite && now - lastTime > 2 { stage = .failed; return }
        lastTime = now
        guard matches, let yaw, yaw.isFinite else { stage = .failed; return }
        frames += 1
        let good: Bool
        switch stage {
        case .center, .returnToCenter: good = abs(yaw) < 0.13
        case .turn: good = yaw * Double(direction) > 0.25 && abs(yaw) < 0.65
        default: return
        }
        stable = good ? stable + 1 : 0
        if stable >= 3 {
            stable = 0
            switch stage {
            case .center: stage = .turn
            case .turn: stage = .returnToCenter
            case .returnToCenter: if frames >= 9 && now - started >= 2 { stage = .passed }
            default: break
            }
        }
    }
}
struct UnlockAttemptGate {
    private(set) var epoch: UUID?
    private(set) var attempted = false
    mutating func locked() { if epoch == nil { epoch = UUID(); attempted = false } }
    mutating func unlocked() { epoch = nil; attempted = false }
    mutating func claim(epoch expected: UUID, challenge: FaceChallenge, enabled: Bool, sessionIsOwner: Bool, targetVerified: Bool) -> Bool {
        guard enabled, sessionIsOwner, targetVerified, epoch == expected, !attempted, challenge.stage == .passed else { return false }
        attempted = true; return true
    }
}

// Keep engine outcomes distinct: enrollment must never silently remain "analyzing".
enum FaceInferenceReply {
    case embedding([Float])
    case rejected(String)
    static func decode(_ data: Data) -> Self {
        guard !data.isEmpty, data.count < 8192,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .rejected("얼굴 분석 응답을 읽지 못했습니다. 등록을 다시 시작해 주세요.")
        }
        if let error = object["error"] as? String {
            switch error {
            case "face_not_found": return .rejected("얼굴 특징이 선명하지 않습니다. 정면을 보고 얼굴에 빛이 비추도록 해 주세요.")
            case "multiple_faces": return .rejected("두 명 이상의 얼굴이 감지됐습니다. 혼자 카메라 앞에 서 주세요.")
            case "face_too_small": return .rejected("얼굴이 너무 작게 보입니다. 카메라에 조금 더 가까이 와 주세요.")
            default: return .rejected("얼굴 특징 분석에 실패했습니다. 정면에서 다시 시도해 주세요.")
            }
        }
        guard let numbers = object["embedding"] as? [NSNumber] else {
            return .rejected("얼굴 특징 응답이 비어 있습니다. 등록을 다시 시작해 주세요.")
        }
        let vector = numbers.map(\.floatValue)
        guard FacePolicy.valid(vector) else {
            return .rejected("얼굴 특징의 품질 검사를 통과하지 못했습니다. 밝은 곳에서 다시 시도해 주세요.")
        }
        return .embedding(vector)
    }
}

// Devices (including virtual/continuity cameras) may ignore the requested preset.
// Fit the actual frame into the inference budget without changing its aspect ratio.
enum FaceInferenceSize {
    static func fitted(width: Int, height: Int) -> (width: Int, height: Int)? {
        guard (64...16384).contains(width), (64...16384).contains(height) else { return nil }
        let scale = min(1, min(640.0 / Double(width), 480.0 / Double(height)))
        let w = Int((Double(width) * scale).rounded()), h = Int((Double(height) * scale).rounded())
        guard w >= 64, h >= 64 else { return nil }
        return (w, h)
    }
}
