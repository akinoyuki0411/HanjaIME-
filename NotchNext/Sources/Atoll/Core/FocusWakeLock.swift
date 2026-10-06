import Foundation
import IOKit.pwr_mgt

/// Holds the display awake only for an explicitly enabled, running focus phase.
final class FocusWakeLock {
    private var assertion: IOPMAssertionID = 0
    var isActive: Bool { assertion != 0 }

    func update(enabled: Bool, focusing: Bool, paused: Bool) {
        let needed = enabled && focusing && !paused
        if needed && assertion == 0 {
            var created: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "HanjiME Notch focus session" as CFString,
                &created
            )
            if result == kIOReturnSuccess { assertion = created }
        } else if !needed {
            release()
        }
    }

    private func release() {
        guard assertion != 0 else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
    }

    deinit { release() }
}
