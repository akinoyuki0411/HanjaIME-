import Foundation
@main struct MediaBridgeTests {
    static func main() {
        var checks = 0
        func check(_ value: Bool) { precondition(value); checks += 1 }
        check(MediaAdapterTransport.arguments(for: "toggle_play_pause") == ["send", "2"])
        check(MediaAdapterTransport.arguments(for: "set_time 1.5") == ["seek", "1500000"])
        check(MediaAdapterTransport.arguments(for: "set_time nan") == nil)
        check(MediaAdapterTransport.arguments(for: "set_time -1") == nil)
        check(MediaAdapterTransport.arguments(for: "set_repeat_mode 3") == ["repeat", "3"])
        check(MediaAdapterTransport.arguments(for: "set_shuffle_mode 99") == nil)
        check(MediaAdapterTransport.arguments(for: "quit; touch /tmp/no") == nil)
        check(MediaAdapterTransport.decode(Data("{}".utf8)) == nil)
        check(MediaAdapterTransport.decode(Data(#"{"diff":true,"payload":{"title":"stale"}}"#.utf8)) == nil)
        let payload = Data(#"{"diff":false,"payload":{"title":"Test","artist":"Artist","playing":true,"durationMicros":90000000,"elapsedTimeMicros":1500000,"timestampEpochMicros":1000000,"repeatMode":3,"shuffleMode":3}}"#.utf8)
        let value = MediaAdapterTransport.decode(payload)
        check(value?.title == "Test" && value?.duration == 90 && value?.elapsed == 1.5)
        check(value?.isPlaying == true && value?.repeatMode == .all && value?.shuffleMode == .songs)
        check(MediaAdapterTransport.decode(Data(#"{"diff":false,"payload":{}}"#.utf8)) == nil)
        print("PASS: \(checks) media protocol checks")
    }
}
