import Foundation

@main struct FocusWakeLockTests {
    static func main() {
        let lock = FocusWakeLock()
        lock.update(enabled: false, focusing: true, paused: false)
        precondition(!lock.isActive, "Disabled setting must not hold the display awake")
        lock.update(enabled: true, focusing: false, paused: false)
        precondition(!lock.isActive, "Break and idle phases must not hold the display awake")
        lock.update(enabled: true, focusing: true, paused: true)
        precondition(!lock.isActive, "Paused focus must not hold the display awake")
        lock.update(enabled: true, focusing: true, paused: false)
        precondition(lock.isActive, "A running, enabled focus must create a macOS assertion")
        lock.update(enabled: true, focusing: true, paused: false)
        precondition(lock.isActive, "Repeated updates must preserve the assertion")
        lock.update(enabled: true, focusing: true, paused: true)
        precondition(!lock.isActive, "Pause must immediately release the assertion")
        lock.update(enabled: true, focusing: true, paused: false)
        precondition(lock.isActive, "Resume must recreate the assertion")
        lock.update(enabled: true, focusing: false, paused: false)
        precondition(!lock.isActive, "Break must immediately release the assertion")
        lock.update(enabled: true, focusing: true, paused: false)
        precondition(lock.isActive)
        lock.update(enabled: false, focusing: true, paused: false)
        precondition(!lock.isActive, "Turning the option off must release the assertion")
        print("10 focus display-sleep assertions passed")
    }
}
