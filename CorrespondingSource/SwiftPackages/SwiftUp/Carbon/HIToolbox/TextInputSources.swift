//
//  TextInputSources.swift
//  SwiftCarbon
//
//  Created by Jeong YunWon on 13/01/2019.
//  Copyright © 2019 youknowone.org. All rights reserved.
//

import Carbon.HIToolbox

public enum STISError: Error {
  case status(OSStatus)
}

public class STISProperty {
  public static let InputSourceIsEnabled = kTISPropertyInputSourceIsEnabled as String
  public static let InputSourceID = kTISPropertyInputSourceID as String
  public static let LocalizedName = kTISPropertyLocalizedName as String
}

extension TISInputSource {
  private class func _takeInputSource(fromUnmanaged unmanaged: Unmanaged<TISInputSource>?)
    -> TISInputSource?
  {
    guard let unmanaged = unmanaged else {
      return nil
    }
    return unmanaged.takeRetainedValue()
  }

  public class func currentKeyboard() -> TISInputSource? {
    return _takeInputSource(fromUnmanaged: TISCopyCurrentKeyboardInputSource())
  }

  public class func currentKeyboardLayout() -> TISInputSource? {
    return _takeInputSource(fromUnmanaged: TISCopyCurrentKeyboardLayoutInputSource())
  }

  public class func currentASCIICapableKeyboard() -> TISInputSource? {
    return _takeInputSource(fromUnmanaged: TISCopyCurrentASCIICapableKeyboardInputSource())
  }

  public class func currentASCIICapableKeyboardLayout() -> TISInputSource? {
    return _takeInputSource(fromUnmanaged: TISCopyCurrentASCIICapableKeyboardLayoutInputSource())
  }

  public class func register(location: URL) -> Result<Void, STISError> {
    let status = TISRegisterInputSource(location as CFURL)
    return _mapError(status: status)
  }

  public class func sources(withProperties properties: NSDictionary, includeAllInstalled: Bool)
    -> [TISInputSource]?
  {
    guard let unmanaged = TISCreateInputSourceList(properties, includeAllInstalled) else {
      return nil
    }
    return unmanaged.takeRetainedValue() as? [TISInputSource]
  }

  public class func ASCIICapableSources() -> [TISInputSource]? {
    guard let unmanaged = TISCreateASCIICapableInputSourceList() else {
      return nil
    }
    return unmanaged.takeRetainedValue() as? [TISInputSource]
  }

  @discardableResult
  public func select() -> Result<Void, STISError> {
    let status = TISSelectInputSource(self)
    return _mapError(status: status)
  }

  @discardableResult
  public func deselect() -> Result<Void, STISError> {
    let status = TISDeselectInputSource(self)
    return _mapError(status: status)
  }

  @discardableResult
  public func enable() -> Result<Void, STISError> {
    let status = TISEnableInputSource(self)
    return _mapError(status: status)
  }

  @discardableResult
  public func disable() -> Result<Void, STISError> {
    let status = TISDisableInputSource(self)
    return _mapError(status: status)
  }

  public func property(forKey key: String) -> Any? {
    guard let unmanaged = TISGetInputSourceProperty(self, key as CFString) else {
      return nil
    }
    return Unmanaged<AnyObject>.fromOpaque(unmanaged).takeUnretainedValue()
  }

  public var enabled: Bool {
    return property(forKey: STISProperty.InputSourceIsEnabled) as! Bool
  }

  public var identifier: String {
    return property(forKey: STISProperty.InputSourceID) as! String
  }

  public var localizedName: String {
    return property(forKey: STISProperty.LocalizedName) as! String
  }
}

private func _mapError(status: OSStatus) -> Result<Void, STISError> {
  if status == 0 {
    return .success(())
  } else {
    return .failure(STISError.status(status))
  }
}
