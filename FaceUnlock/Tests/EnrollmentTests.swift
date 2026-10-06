import Foundation
@main struct EnrollmentTests {
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ name: String) { precondition(condition, name); count += 1 }
        var guide = EnrollmentGuide()
        check(!guide.observe(yaw: nil, pitch: nil, now: 0), "no face cannot advance")
        check(!guide.observe(yaw: .nan, pitch: 0, now: 0.1), "invalid angle rejected")
        var time = 1.0
        for pose in EnrollmentPose.all {
            check(guide.pose == pose, "expected next direction")
            let yaw = -Double(pose.x) * 0.3, pitch = Double(pose.y) * 0.3
            check(!guide.observe(yaw: yaw, pitch: pitch, now: time), "one frame insufficient")
            time += 0.4
            check(guide.observe(yaw: yaw, pitch: pitch, now: time), "stable pose captures exactly once")
            time += 0.4
        }
        check(guide.finished && guide.completed == 9, "all nine directions required")
        check(!guide.observe(yaw: 0, pitch: 0, now: 20), "completed flow cannot overflow")
        var held = EnrollmentGuide()
        for i in 0..<20 { _ = held.observe(yaw: 0, pitch: 0, now: Double(i) * 0.4) }
        check(held.completed == 1, "stationary face cannot fill all directions")
        var interrupted = EnrollmentGuide()
        _ = interrupted.observe(yaw: 0, pitch: 0, now: 0)
        check(!interrupted.observe(yaw: 0, pitch: 0, now: 3), "capture gap resets stability")
        var tilted = EnrollmentGuide()
        check(!tilted.observe(yaw: 0, pitch: 0.3, now: 0), "natural laptop pitch needs stable calibration")
        check(tilted.observe(yaw: 0, pitch: 0.31, now: 0.4), "natural laptop pitch can enroll center")
        check(!tilted.observe(yaw: 0.3, pitch: 0.31, now: 0.8), "left pose relative to neutral needs stability")
        check(tilted.observe(yaw: 0.3, pitch: 0.31, now: 1.2), "left pose uses calibrated vertical gaze")
        var unstable = EnrollmentGuide()
        _ = unstable.observe(yaw: 0, pitch: 0.3, now: 0)
        check(!unstable.observe(yaw: 0, pitch: -0.3, now: 0.4), "changing pitch cannot calibrate center")
        print("PASS: \(count) guided enrollment checks; camera accuracy deferred")
    }
}
