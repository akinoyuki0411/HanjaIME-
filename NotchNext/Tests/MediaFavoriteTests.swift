import Foundation
func HL(_ value: String) -> String { value }
final class FavoriteStub: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [Bool?] = [true, false, true, nil, true, nil]
    private var calls: [String] = []
    func execute(_ source: String) -> Bool? {
        lock.lock(); defer { lock.unlock() }
        calls.append(source)
        return replies.removeFirst()
    }
    var scripts: [String] { lock.lock(); defer { lock.unlock() }; return calls }
}
@main struct FavoriteTests {
    @MainActor static func wait(_ destination: MediaDestination) async {
        for _ in 0..<200 {
            if !destination.isReadingFavorite && !destination.busy { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        preconditionFailure("Favorite operation timed out")
    }
    @MainActor static func main() async {
        let stub = FavoriteStub()
        let destination = MediaDestination(favoriteExecutor: { stub.execute($0) })
        let track = MediaPlaybackState(title: "Test", artist: "Artist", album: "Album", bundleIdentifier: "com.apple.Music")
        destination.refresh(track); await wait(destination)
        precondition(destination.favorite == true)
        precondition(!stub.scripts[0].contains("set favorited"))
        destination.refresh(track); await wait(destination)
        precondition(destination.favorite == false)
        destination.toggleFavorite(track)
        precondition(destination.favorite == true && destination.busy, "Favorite must fill immediately before Music replies")
        await wait(destination)
        precondition(destination.favorite == true)
        precondition(stub.scripts[2].contains("set favorited"))
        destination.refresh(track); await wait(destination)
        precondition(destination.favorite == nil && destination.favoriteUnavailable)
        destination.refresh(track)
        precondition(stub.scripts.count == 4)
        destination.toggleFavorite(track); await wait(destination)
        precondition(destination.favorite == true)
        precondition(!stub.scripts[4].contains("set favorited"))
        destination.toggleFavorite(track)
        precondition(destination.favorite == false && destination.busy, "Unfavorite must clear immediately")
        await wait(destination)
        precondition(destination.favorite == true && destination.message != nil, "Failed writes restore the last confirmed value")
        destination.refresh(nil)
        precondition(destination.favorite == nil && stub.scripts.count == 6)
        print("13 favorite state assertions passed; no real music library changed")
    }
}
