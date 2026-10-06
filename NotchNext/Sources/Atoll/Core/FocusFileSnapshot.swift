import Foundation
struct FocusFileSnapshot {
    let enabled: Bool
    let modeID: String?
    static func decode(_ data: Data) throws -> FocusFileSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stores = root["data"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
        // Empty stores and omitted active records are the normal inactive form.
        for store in stores {
            if let active = store["storeAssertionRecords"], !(active is [[String: Any]]) { throw CocoaError(.fileReadCorruptFile) }
        }
        let records = stores.flatMap { $0["storeAssertionRecords"] as? [[String: Any]] ?? [] }
        let mode = records.compactMap { ($0["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String }.last
        return FocusFileSnapshot(enabled: !records.isEmpty, modeID: mode)
    }
    static func configuration(modeID: String, in object: Any) -> [String: Any]? {
        if let dict = object as? [String: Any] {
            if dict["modeIdentifier"] as? String == modeID {
                return dict["mode"] as? [String: Any] ?? dict
            }
            if let match = dict[modeID] as? [String: Any] { return match["mode"] as? [String: Any] ?? match }
            for child in dict.values { if let match = configuration(modeID: modeID, in: child) { return match } }
        } else if let list = object as? [Any] {
            for child in list { if let match = configuration(modeID: modeID, in: child) { return match } }
        }
        return nil
    }
}
