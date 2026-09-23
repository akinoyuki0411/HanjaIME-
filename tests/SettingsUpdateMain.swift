import Cocoa
import CryptoKit
@testable import GureumCore
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let suite = "org.hanjaime.preview." + UUID().uuidString
Configuration.shared = Configuration(suiteName: suite)!
let data = Data("fixture".utf8)
let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
let url = "https://github.com/akinoyuki0411/HanjaIME-/releases/download/v0.9.5/HanjaIME_v0.9.5_Test.zip"
let valid = HanjaIMEUpdateService.Asset(name: "HanjaIME_v0.9.5_Test.zip", browser_download_url: url, size: data.count, digest: "sha256:" + hash)
assert(HanjaIMEUpdateService.verified(data, asset: valid))
assert(!HanjaIMEUpdateService.verified(Data("changed".utf8), asset: valid))
for bad in ["http://github.com/akinoyuki0411/HanjaIME-/releases/download/v1/x.zip", "https://github.com.attacker.invalid/akinoyuki0411/HanjaIME-/releases/download/v1/x.zip", "https://github.com/other/repo/releases/download/v1/x.zip", "file:///tmp/x.zip"] { assert(!HanjaIMEUpdateService.validDownloadURL(bad)) }
assert(HanjaIMEUpdateService.selectAsset(.init(tag_name: "v0.9.5", draft: false, prerelease: false, assets: [valid])) != nil)
assert(HanjaIMEUpdateService.selectAsset(.init(tag_name: "v0.9.5", draft: true, prerelease: false, assets: [valid])) == nil)
assert(HanjaIMEUpdateService.selectAsset(.init(tag_name: "v0.9.5", draft: false, prerelease: true, assets: [valid])) == nil)
assert(HanjaIMEUpdateService.selectAsset(.init(tag_name: "v0.8.16", draft: false, prerelease: false, assets: [valid])) == nil)
let missing = HanjaIMEUpdateService.Asset(name: valid.name, browser_download_url: url, size: data.count, digest: nil)
assert(HanjaIMEUpdateService.selectAsset(.init(tag_name: "v0.9.5", draft: false, prerelease: false, assets: [missing])) == nil)

final class ReleaseStub: URLProtocol {
  static var status = 200
  static var payload = Data()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.payload)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
let sessionConfig = URLSessionConfiguration.ephemeral
sessionConfig.protocolClasses = [ReleaseStub.self]
let service = HanjaIMEUpdateService(session: URLSession(configuration: sessionConfig))
func check(_ code: Int, _ body: String, expected: String?) {
  ReleaseStub.status = code; ReleaseStub.payload = Data(body.utf8)
  service.check(manual: true)
  let limit = Date().addingTimeInterval(3)
  while service.busy && Date() < limit { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
  assert(!service.busy)
  assert(service.availableVersion == expected)
}
check(404, "{}", expected: nil)
assert(service.status.contains("릴리스"))
check(403, "{}", expected: nil)
assert(service.status.contains("못했습니다"))
check(200, "not json", expected: nil)
let releaseJSON = "{\"tag_name\":\"v0.9.5\",\"draft\":false,\"prerelease\":false,\"assets\":[{\"name\":\"HanjaIME_v0.9.5_Test.zip\",\"browser_download_url\":\"" + url + "\",\"size\":7,\"digest\":\"sha256:" + hash + "\"}]}"
check(200, releaseJSON, expected: "0.9.5")
check(200, releaseJSON.replacingOccurrences(of: "0.9.5", with: "0.9.4"), expected: nil)
assert(service.status.contains("최신"))
print("Update policy and HTTP fixture tests passed")

UserDefaults.standard.removePersistentDomain(forName: suite)
