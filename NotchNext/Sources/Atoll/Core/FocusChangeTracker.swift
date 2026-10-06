/// Temporary file replacement or permission failures must not erase the last
/// confirmed state. Synced changes can arrive while the database is rewritten.
struct FocusChangeTracker {
    private var previous: Bool?
    mutating func update(_ focused: Bool?) -> Bool? {
        guard let focused else { return nil }
        defer { previous = focused }
        guard let previous, previous != focused else { return nil }
        return focused
    }
}
