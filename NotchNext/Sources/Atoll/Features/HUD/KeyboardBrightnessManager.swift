import AppKit
import Combine
import ObjectiveC
import Carbon.HIToolbox

/// Runtime-only bridge. Never changes ambient sensing or idle-dimming settings.
@MainActor final class KeyboardBrightnessManager: ObservableObject {
    static let shared = KeyboardBrightnessManager()
    @Published private(set) var brightness: Float = 0
    @Published private(set) var isAvailable = false
    @Published private(set) var writeFailed = false
    @Published private(set) var shortcutsAvailable = false
    private var decreaseShortcut: GlobalHotKey?
    private var increaseShortcut: GlobalHotKey?
    func registerShortcuts() {
        guard decreaseShortcut == nil, increaseShortcut == nil, isAvailable else { return }
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        decreaseShortcut = GlobalHotKey(keyCode: UInt32(kVK_DownArrow), modifiers: modifiers, id: 2) { [weak self] in
            Task { @MainActor in self?.adjustFromShortcut(-1.0 / 16.0) }
        }
        increaseShortcut = GlobalHotKey(keyCode: UInt32(kVK_UpArrow), modifiers: modifiers, id: 3) { [weak self] in
            Task { @MainActor in self?.adjustFromShortcut(1.0 / 16.0) }
        }
        shortcutsAvailable = decreaseShortcut != nil && increaseShortcut != nil
        if !shortcutsAvailable { decreaseShortcut = nil; increaseShortcut = nil }
    }
    private func adjustFromShortcut(_ delta: Float) {
        if let value = step(by: delta) { SneakPeekCoordinator.shared.show(type: .keyboardBrightness, value: value) }
    }
    private var client: NSObject?
    private var keyboardID: UInt64 = 0
    private typealias Read = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias Write = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
    private var read: Read?
    private var write: Write?
    private let readSelector = NSSelectorFromString("brightnessForKeyboard:")
    private let writeSelector = NSSelectorFromString("setBrightness:forKeyboard:")

    private init() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return }
        let object = type.init()
        let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard object.responds(to: idsSelector), object.responds(to: readSelector), object.responds(to: writeSelector),
              let ids = object.perform(idsSelector)?.takeRetainedValue() as? [NSNumber], let first = ids.first,
              let getter = class_getInstanceMethod(type, readSelector),
              let setter = class_getInstanceMethod(type, writeSelector) else { return }
        client = object; keyboardID = first.uint64Value
        read = unsafeBitCast(method_getImplementation(getter), to: Read.self)
        write = unsafeBitCast(method_getImplementation(setter), to: Write.self)
        isAvailable = refresh() != nil
    }
    @discardableResult func refresh() -> Float? {
        guard let client, let read else { return nil }
        let value = read(client, readSelector, keyboardID)
        guard value.isFinite, (0...1).contains(value) else { return nil }
        brightness = value
        return value
    }
    @discardableResult func setBrightness(_ value: Float) -> Float? {
        guard value.isFinite, let client, let write else { return nil }
        let target = min(1, max(0, value))
        guard write(client, writeSelector, target, keyboardID) else { writeFailed = true; return nil }
        guard let actual = refresh(), abs(actual - target) < 0.08 else { writeFailed = true; return nil }
        writeFailed = false
        return actual
    }
    func step(by delta: Float) -> Float? {
        guard let current = refresh() else { return nil }
        return setBrightness(current + delta)
    }
}
