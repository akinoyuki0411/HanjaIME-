//
//  FSEvents.swift
//  SwiftCoreServices
//
//  Created by Jeong YunWon on 05/06/2019.
//  Copyright © 2019 Jeong YunWon. All rights reserved.
//

import CoreServices
import Foundation

private let _bridgeCallback: FSEventStreamCallback = {
  (
    stream: ConstFSEventStreamRef,
    contextInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
  ) in

  guard let contextInfo = contextInfo else {
    assert(false)
    return
  }

  let unmanagedInfo = Unmanaged<NSArray>.fromOpaque(contextInfo)
  let info = unmanagedInfo.takeUnretainedValue()
  assert(info.count == 1)
  let callback = info[0] as! SFSEventStream.Callback
  let paths = Unmanaged<NSArray>.fromOpaque(eventPaths).takeUnretainedValue()
  let events = SFSEventStream.CallbackEvents(
    count: numEvents, paths: paths, flags: eventFlags, ids: eventIds)
  callback(stream, events)
}

public struct SFSEventStream {
  public let rawValue: FSEventStreamRef

  public typealias EventId = FSEventStreamEventId
  public typealias CreateFlags = FSEventStreamCreateFlags
  public typealias EventFlags = FSEventStreamEventFlags

  public static let EventIdSinceNow: EventId = UInt64(kFSEventStreamEventIdSinceNow)

  public enum CreateFlag {
    public static let none = UInt32(kFSEventStreamCreateFlagNone)
    // CFType is not listed on - always passed by default
    public static let noDefer = UInt32(kFSEventStreamCreateFlagNoDefer)
    public static let watchRoot = UInt32(kFSEventStreamCreateFlagWatchRoot)
    public static let ignoreSelf = UInt32(kFSEventStreamCreateFlagIgnoreSelf)
    public static let fileEvents = UInt32(kFSEventStreamCreateFlagFileEvents)
    public static let markSelf = UInt32(kFSEventStreamCreateFlagMarkSelf)
    // No extended flags support
  }

  public struct CallbackEvents: Sequence {
    let count: Int
    let paths: NSArray
    let flags: UnsafePointer<FSEventStreamEventFlags>
    let ids: UnsafePointer<FSEventStreamEventId>

    public struct Iterator: IteratorProtocol {
      let events: CallbackEvents
      var index: Int = 0

      public mutating func next() -> Event? {
        defer { index += 1 }
        guard index < events.count else {
          return nil
        }
        guard let path = events.paths[index] as? NSString else {
          return nil
        }
        return Event(path: path, flags: events.flags[index], id: events.ids[index])
      }
    }

    public func makeIterator() -> CallbackEvents.Iterator {
      return Iterator(events: self, index: 0)
    }
  }

  public struct Event {
    let path: NSString
    let flags: EventFlags
    let id: EventId
  }

  public typealias Callback = (ConstFSEventStreamRef, CallbackEvents) -> Void

  public static func create(
    paths: [String], eventId: EventId, latancy: TimeInterval, flags: CreateFlags,
    _ callback: @escaping Callback
  ) -> SFSEventStream? {
    let info = NSArray(object: callback)
    let unmanagedInfo = Unmanaged.passUnretained(info)
    var context = FSEventStreamContext(
      version: 0, info: unmanagedInfo.toOpaque(),
      retain: {
        contextInfo in
        guard let contextInfo = contextInfo else {
          assert(false)
          return nil
        }
        let unmanagedInfo = Unmanaged<NSArray>.fromOpaque(contextInfo)
        let retained = unmanagedInfo.retain()
        // print("retained")
        return UnsafeRawPointer(retained.toOpaque())
      },
      release: {
        contextInfo in
        guard let contextInfo = contextInfo else {
          assert(false)
          return
        }
        let unmanagedInfo = Unmanaged<NSArray>.fromOpaque(contextInfo)
        unmanagedInfo.release()
        // print("release")
      }, copyDescription: nil)

    guard
      let ref = FSEventStreamCreate(
        nil,
        _bridgeCallback,
        &context,
        paths as NSArray,
        eventId,
        latancy,
        flags | UInt32(kFSEventStreamCreateFlagUseCFTypes)
      )
    else {
      return nil
    }
    return SFSEventStream(rawValue: ref)
  }

  public func schedule(runLoop: RunLoop, mode: RunLoop.Mode) {
    let runLoop = runLoop.getCFRunLoop()
    let mode = mode as CFString
    FSEventStreamScheduleWithRunLoop(rawValue, runLoop, mode)
  }

  public func start() {
    FSEventStreamStart(rawValue)
  }

  public func stop() {
    FSEventStreamStop(rawValue)
  }

  public func invalidate() {
    FSEventStreamInvalidate(rawValue)
  }

  public func retain() {
    FSEventStreamRetain(rawValue)
  }

  public func release() {
    FSEventStreamRelease(rawValue)
  }

  public func show() {
    FSEventStreamShow(rawValue)
  }
}
