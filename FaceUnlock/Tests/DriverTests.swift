import AppKit
@main struct DriverTests {
    @MainActor static func main() {
        let driver = UnlockDriver()
        // This test is run on the ordinary desktop. It never supplies a password,
        // requests permission, posts input, or locks the user's session.
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.loginwindow" else {
            print("SKIP: ordinary desktop required"); return
        }
        guard driver.target() == nil else { fatalError("Ordinary desktop must not be an unlock target") }
        print("PASS: live ordinary desktop is rejected as an automatic-input target")
    }
}
