import Foundation
@main struct InstallTests {
    static func main() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("hanjimi-install-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }
        for component in Component.allCases {
            try SettingsModel.installPayload(component, fixtureDirectory: temp)
            precondition(Bundle(url: temp.appendingPathComponent(component.filename))?.bundleIdentifier == component.bundleID)
            do {
                try SettingsModel.installPayload(component, fixtureDirectory: temp)
                fatalError("Existing app overwritten")
            } catch { precondition((error as NSError).code == 4) }
        }
        print("All three bundled installers and overwrite protection passed; no live input source changed.")
    }
}
