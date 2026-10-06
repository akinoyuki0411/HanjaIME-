import AppKit
import ApplicationServices
import Security

// No undocumented lock-state dictionary keys, global HID injection, or Secure Input bypass.
@MainActor final class UnlockDriver {
    struct Target {
        let pid: pid_t
        let field: AXUIElement
    }
    static let loginExecutable = "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow"
    var trusted: Bool { AXIsProcessTrusted() }
    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
    var ownsConsoleSession: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let uid = session[kCGSessionUserIDKey as String] as? NSNumber,
              uid.uint32Value == getuid(),
              session[kCGSessionLoginDoneKey as String] as? Bool == true,
              session[kCGSessionOnConsoleKey as String] as? Bool == true else { return false }
        return true
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func focusedElement() -> AXUIElement? {
        guard let value = attribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func appleLoginwindow(_ pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier == "com.apple.loginwindow",
              app.executableURL?.path == Self.loginExecutable else { return false }
        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple and identifier com.apple.loginwindow" as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
    private func hasLockSurface(_ pid: pid_t) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  let layer = window[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue >= Int(CGWindowLevelForKey(.screenSaverWindow)),
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            // Window metadata only: never capture screen pixels or read window titles.
            return NSScreen.screens.contains { screen in
                rect.width >= screen.frame.width - 2 && rect.height >= screen.frame.height - 2
            }
        }
    }
    // A focused secure field in the signed system loginwindow is required. If macOS
    // hides this field from Accessibility, automatic input is unavailable, not bypassed.
    func target(requireEmpty: Bool = true) -> Target? {
        guard trusted, ownsConsoleSession, let field = focusedElement() else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(field, &pid) == .success, appleLoginwindow(pid), hasLockSurface(pid),
              attribute(field, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole,
              attribute(field, kAXEnabledAttribute) as? Bool == true,
              attribute(field, kAXFocusedAttribute) as? Bool == true else { return nil }
        if requireEmpty {
            guard let value = attribute(field, kAXValueAttribute) as? String, value.isEmpty else { return nil }
        }
        return Target(pid: pid, field: field)
    }
    func sameTarget(_ expected: Target, requireEmpty: Bool) -> Bool {
        guard let actual = target(requireEmpty: requireEmpty) else { return false }
        return actual.pid == expected.pid && CFEqual(actual.field, expected.field)
    }
    var desktopIsActive: Bool {
        guard ownsConsoleSession, let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != "com.apple.loginwindow", let field = focusedElement() else { return false }
        var pid: pid_t = 0
        return AXUIElementGetPid(field, &pid) == .success && pid == app.processIdentifier
    }
    enum Result { case posted, blocked }
    func enter(_ bytes: Data, target expected: Target) -> Result {
        guard sameTarget(expected, requireEmpty: true), let password = String(data: bytes, encoding: .utf8),
              !password.isEmpty, password.utf16.count <= 256,
              !password.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return .blocked }
        var units = Array(password.utf16)
        defer { _ = units.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false),
              let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
              let enterUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false) else { return .blocked }
        units.withUnsafeBufferPointer { buffer in
            down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
        }
        guard sameTarget(expected, requireEmpty: true) else { return .blocked }
        down.postToPid(expected.pid); up.postToPid(expected.pid)
        guard sameTarget(expected, requireEmpty: false) else { return .blocked }
        enterDown.postToPid(expected.pid); enterUp.postToPid(expected.pid)
        return .posted // Delivery does not prove authentication or successful unlock.
    }
}
