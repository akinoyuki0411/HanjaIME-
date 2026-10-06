import Foundation
@main struct FocusFileTests {
 static func main() throws {
  let off = try FocusFileSnapshot.decode(Data(#"{"data":[{"storeAssertionRecords":[]}]}"#.utf8)); precondition(!off.enabled && off.modeID == nil)
  let on = try FocusFileSnapshot.decode(Data(#"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"custom.work"}}]}]}"#.utf8)); precondition(on.enabled && on.modeID == "custom.work")
  for empty in [#"{"data":[{}]}"#, #"{"data":[]}"#] { let snapshot = try FocusFileSnapshot.decode(Data(empty.utf8)); precondition(!snapshot.enabled) }
  for invalid in ["{}", #"{"data":[{"storeAssertionRecords":"invalid"}]}"#] {
   do { _ = try FocusFileSnapshot.decode(Data(invalid.utf8)); fatalError("Invalid schema accepted") } catch {}
  }
  let custom: [String:Any] = ["data":[["modeConfigurations":[["mode": ["modeIdentifier":"custom.work", "name":"Work", "tintColorName":"systemBlueColor"]]]]]]
  precondition(FocusFileSnapshot.configuration(modeID:"custom.work", in:custom)?["name"] as? String == "Work")
  precondition(FocusFileSnapshot.configuration(modeID:"missing", in:custom) == nil)
  print("Focus files: 8 checks passed")
 }
}
