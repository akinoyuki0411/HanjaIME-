@main struct FocusChangeTests {
    static func main() {
        var tracker = FocusChangeTracker()
        precondition(tracker.update(nil) == nil)
        precondition(tracker.update(false) == nil, "Startup is a baseline, not a change")
        precondition(tracker.update(false) == nil, "Unchanged state must not repeat")
        precondition(tracker.update(true) == true, "Turning Focus on must emit")
        precondition(tracker.update(true) == nil)
        precondition(tracker.update(false) == false, "Turning Focus off must emit")
        precondition(tracker.update(nil) == nil, "Lost sharing must not imply Focus off")
        precondition(tracker.update(true) == true, "Synced change after a transient read failure must emit")
        precondition(tracker.update(false) == false)
        print("9 Focus transition assertions passed")
    }
}
