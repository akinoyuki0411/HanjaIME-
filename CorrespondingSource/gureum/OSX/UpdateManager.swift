import Foundation
import GureumCore

// Preserve the preferences interface without calling Gureum's updater or any network API.
class UpdateManager {
  static let shared = UpdateManager()
  struct UpdateInfo: Decodable {
    let version: String
    let description: String
    let url: String
  }
  struct VersionInfo {
    let current: String? = Bundle.main.version
    let update: UpdateInfo
    let experimental: Bool
  }
  func requestVersionInfo(mode: UpdateMode, _ done: @escaping (VersionInfo?) -> Void) { done(nil) }
  func requestAutoUpdateVersionInfo(_ done: @escaping (VersionInfo?) -> Void) { done(nil) }
  class func notifyUpdate(info: VersionInfo) {}
  func notifyUpdateIfNeeded() {}
}
