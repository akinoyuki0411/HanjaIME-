//
//  SwiftIOKit.swift
//  SwiftIOKit
//
//  Created by Jeong YunWon on 2018. 9. 1..
//  Copyright © 2018 youknowone.org. All rights reserved.
//

import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem

public enum SIOError: Error {
  case kernel(kern_return_t)
}

public class SIOConnect {
  public let rawValue: io_connect_t

  public init(rawValue: io_connect_t) {
    self.rawValue = rawValue
  }

  deinit {
    _ = close()
    IOObjectRelease(rawValue)
  }

  public struct Selector {
    public let rawValue: Int32

    public static let capsLock = Selector(rawValue: Int32(kIOHIDCapsLockState))
    public static let numLock = Selector(rawValue: Int32(kIOHIDNumLockState))
    public static let activityUserIdle = Selector(rawValue: Int32(kIOHIDActivityUserIdle))
    public static let activityDisplayOn = Selector(rawValue: Int32(kIOHIDActivityDisplayOn))
  }

  @discardableResult
  public func close() -> Result<Void, SIOError> {
    let kr = IOServiceClose(rawValue)
    guard kr == KERN_SUCCESS else {
      return .failure(SIOError.kernel(kr))
    }
    return .success(())
  }

  public func getState(selector: Selector) -> Result<UInt32, SIOError> {
    var state: UInt32 = 0
    let kr = IOHIDGetStateForSelector(rawValue, selector.rawValue, &state)
    if kr != KERN_SUCCESS {
      return .failure(SIOError.kernel(kr))
    }
    return .success(state)
  }

  @discardableResult
  public func setState(selector: Selector, state: UInt32) -> Result<Void, SIOError> {
    let kr = IOHIDSetStateForSelector(rawValue, selector.rawValue, state)
    if kr != KERN_SUCCESS {
      return .failure(SIOError.kernel(kr))
    }
    return .success(())
  }

  public func getModifierLock(selector: Selector) -> Result<Bool, SIOError> {
    var state: Bool = false
    let kr = IOHIDGetModifierLockState(rawValue, selector.rawValue, &state)
    if kr != KERN_SUCCESS {
      return .failure(SIOError.kernel(kr))
    }
    return .success(state)
  }

  @discardableResult
  public func setModifierLock(selector: Selector, state: Bool) -> Result<Void, SIOError> {
    let kr = IOHIDSetModifierLockState(rawValue, selector.rawValue, state)
    if kr != KERN_SUCCESS {
      return .failure(SIOError.kernel(kr))
    }
    return .success(())
  }
}

public class SIOService {
  public let rawValue: io_service_t

  public init?(port: mach_port_t, matching: NSDictionary?) {
    rawValue = IOServiceGetMatchingService(port, matching)
    guard rawValue != 0 else {
      return nil
    }
  }

  public convenience init?(name: String) {
    self.init(port: kIOMasterPortDefault, matching: SIOService.matching(name: name))
  }

  deinit {
    IOObjectRelease(rawValue)
  }

  public static func matching(name: String) -> NSDictionary? {
    return IOServiceMatching(name)
  }

  public func open(owningTask: mach_port_t, type: Int) -> Result<SIOConnect, SIOError> {
    var connect: io_connect_t = 0
    let kr = IOServiceOpen(rawValue, owningTask, UInt32(type), &connect)
    guard kr == KERN_SUCCESS else {
      return .failure(SIOError.kernel(kr))
    }
    return .success(SIOConnect(rawValue: connect))
  }
}

extension IOHIDValueScaleType {
  public static let Calibrated = kIOHIDValueScaleTypeCalibrated
  public static let Physical = kIOHIDValueScaleTypePhysical
  public static let Exponent = kIOHIDValueScaleTypeExponent
}

extension IOHIDValue {
  public typealias ScaleType = IOHIDValueScaleType
  public typealias Callback = IOHIDValueCallback
  public typealias MultipleCallback = IOHIDValueMultipleCallback

  public var element: IOHIDElement {
    return IOHIDValueGetElement(self)
  }

  public var timestamp: UInt64 {
    return IOHIDValueGetTimeStamp(self)
  }

  public var length: CFIndex {
    return IOHIDValueGetLength(self)
  }

  public var integerValue: CFIndex {
    return IOHIDValueGetIntegerValue(self)
  }

  public func scaledValue(ofType type: ScaleType) -> Double {
    return IOHIDValueGetScaledValue(self, type)
  }
}

extension IOHIDElement {
  public class func create(dictionary: NSDictionary) -> IOHIDElement {
    return IOHIDElementCreateWithDictionary(kCFAllocatorDefault, dictionary)
  }

  public var device: IOHIDDevice {
    return IOHIDElementGetDevice(self)
  }

  public var parent: IOHIDElement? {
    return IOHIDElementGetParent(self)
  }

  public var children: NSArray? {
    return IOHIDElementGetChildren(self)
  }

  public func attach(_ toAttach: IOHIDElement) {
    IOHIDElementAttach(self, toAttach)
  }

  public func detach(_ toDetach: IOHIDElement) {
    IOHIDElementAttach(self, toDetach)
  }

  public func attached() -> NSArray? {
    return IOHIDElementCopyAttached(self)
  }

  public var cookie: IOHIDElementCookie {
    return IOHIDElementGetCookie(self)
  }

  public var type: IOHIDElementType {
    return IOHIDElementGetType(self)
  }

  public var collectionType: IOHIDElementCollectionType {
    return IOHIDElementGetCollectionType(self)
  }

  public var usagePage: UInt32 {
    return IOHIDElementGetUsagePage(self)
  }

  public var usage: UInt32 {
    return IOHIDElementGetUsage(self)
  }

  public var isVirtual: Bool {
    return IOHIDElementIsVirtual(self)
  }

  public var isRelative: Bool {
    return IOHIDElementIsRelative(self)
  }

  public var isWrapping: Bool {
    return IOHIDElementIsWrapping(self)
  }

  public var isArray: Bool {
    return IOHIDElementIsArray(self)
  }

  public var isNonLinear: Bool {
    return IOHIDElementIsNonLinear(self)
  }

  public var hasPreferredState: Bool {
    return IOHIDElementHasPreferredState(self)
  }

  public var hasNullState: Bool {
    return IOHIDElementHasNullState(self)
  }

  public var name: NSString {
    return IOHIDElementGetName(self)
  }

  public var reportID: UInt32 {
    return IOHIDElementGetReportID(self)
  }

  public var reportSize: UInt32 {
    return IOHIDElementGetReportSize(self)
  }

  public var reportCount: UInt32 {
    return IOHIDElementGetReportCount(self)
  }

  public var unit: UInt32 {
    return IOHIDElementGetUnit(self)
  }

  public var unitExponent: UInt32 {
    return IOHIDElementGetUnitExponent(self)
  }
}

extension IOHIDManager {
  public class func create(options: IOOptionBits) -> IOHIDManager {
    return IOHIDManagerCreate(kCFAllocatorDefault, options)
  }

  public class func create() -> IOHIDManager {
    return create(options: IOOptionBits(kIOHIDOptionsTypeNone))
  }

  public func open() -> IOReturn {
    return open(options: IOOptionBits(kIOHIDOptionsTypeNone))
  }

  public func open(options: IOOptionBits) -> IOReturn {
    return IOHIDManagerOpen(self, options)
  }

  public func close() -> IOReturn {
    return close(options: IOOptionBits(kIOHIDOptionsTypeNone))
  }

  public func close(options: IOOptionBits) -> IOReturn {
    return IOHIDManagerClose(self, options)
  }

  public func schedule(runloop: RunLoop, mode: RunLoop.Mode) {
    IOHIDManagerScheduleWithRunLoop(self, runloop.getCFRunLoop(), mode.rawValue as CFString)
  }

  public func unschedule(runloop: RunLoop, mode: RunLoop.Mode) {
    IOHIDManagerUnscheduleFromRunLoop(self, runloop.getCFRunLoop(), mode.rawValue as CFString)
  }

  public func setDeviceMatching(page: Int, usage: Int) {
    let deviceMatching = IOHIDManager.deviceMatching(page: page, usage: usage)
    IOHIDManagerSetDeviceMatching(self, deviceMatching)
  }

  public func setInputValueMatching(min: Int, max: Int) {
    let inputValueMatching = IOHIDManager.inputValueMatching(min: min, max: max)
    IOHIDManagerSetInputValueMatching(self, inputValueMatching)
  }

  public func registerInputValueCallback(
    _ callback: @escaping IOHIDValue.Callback, context: UnsafeMutableRawPointer?
  ) {
    IOHIDManagerRegisterInputValueCallback(self, callback, context)
  }

  public func unregisterInputValueCallback() {
    IOHIDManagerRegisterInputValueCallback(self, nil, nil)
  }

  private class func deviceMatching(page: Int, usage: Int) -> NSDictionary {
    return [
      kIOHIDDeviceUsagePageKey as NSString: NSNumber(value: page),
      kIOHIDDeviceUsageKey as NSString: NSNumber(value: usage),
    ]
  }

  private class func inputValueMatching(min: Int, max: Int) -> NSDictionary {
    return [
      kIOHIDElementUsageMinKey as NSString: NSNumber(value: min),
      kIOHIDElementUsageMaxKey as NSString: NSNumber(value: max),
    ]
  }
}
