import AppKit
import SwiftUI

/// User-triggered player actions. Scripts never receive unescaped track text.
@MainActor final class MediaDestination: ObservableObject {
    @Published var favorite: Bool?
    @Published var busy = false
    @Published var message: String?
    private let queue = DispatchQueue(label: "org.hanjaime.media.destination")
    @Published private(set) var isReadingFavorite = false
    @Published private(set) var favoriteUnavailable = false
    private var identity = ""
    private var readToken: UUID?
    private let favoriteExecutor: @Sendable (String) -> Bool?

    init(favoriteExecutor: @escaping @Sendable (String) -> Bool? = { MediaDestination.executeFavoriteScript($0) }) {
        self.favoriteExecutor = favoriteExecutor
    }
    nonisolated private static func executeFavoriteScript(_ source: String) -> Bool? {
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil else { return nil }
        return result.booleanValue
    }
    private func key(_ track: MediaPlaybackState?) -> String {
        (track?.bundleIdentifier ?? "") + "|" + (track?.trackIdentity ?? "")
    }
    private func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\""
    }
    private func trackGuard(_ track: MediaPlaybackState) -> String {
        var lines = "if name of current track is not \(quote(track.title)) then error \"Track changed\"\n"
        lines += "if artist of current track is not \(quote(track.artist)) then error \"Track changed\""
        if !track.album.isEmpty { lines += "\nif album of current track is not \(quote(track.album)) then error \"Track changed\"" }
        return lines
    }
    /// Read the existing value without changing the user's Music library.
    /// A failed background read stays unknown and is retried only explicitly
    /// or on a new track, rather than repeatedly prompting for Automation access.
    func refresh(_ track: MediaPlaybackState?, force: Bool = false) {
        let currentKey = key(track)
        if identity != currentKey {
            identity = currentKey
            readToken = nil; isReadingFavorite = false
            favorite = nil; favoriteUnavailable = false; message = nil
        }
        guard let track, track.bundleIdentifier == "com.apple.Music",
              !busy, !isReadingFavorite, force || !favoriteUnavailable else { return }
        let token = UUID()
        readToken = token; isReadingFavorite = true
        let source = """
        tell application id "com.apple.Music"
            if not running then error "Music is not running"
            \(trackGuard(track))
            return favorited of current track
        end tell
        """
        let execute = favoriteExecutor
        queue.async { [weak self] in
            let result = execute(source)
            Task { @MainActor [weak self] in
                guard let self, self.readToken == token, self.identity == currentKey else { return }
                self.readToken = nil; self.isReadingFavorite = false
                self.favorite = result; self.favoriteUnavailable = result == nil
                if result == nil && force {
                    self.message = HL("Apple Music could not update the favorite. Check Automation permission.")
                }
            }
        }
    }
    func toggleFavorite(_ track: MediaPlaybackState?) {
        guard let track, track.bundleIdentifier == "com.apple.Music", !busy else { return }
        guard identity == key(track), favorite != nil else { refresh(track, force: true); return }
        let currentKey = key(track)
        let previous = favorite!
        let wanted = !previous
        favorite = wanted
        message = nil
        readToken = nil; isReadingFavorite = false; busy = true
        let script = """
        tell application id "com.apple.Music"
            if not running then error "Music is not running"
            \(trackGuard(track))
            set wanted to \(wanted ? "true" : "false")
            set favorited of current track to wanted
            return favorited of current track
        end tell
        """
        let execute = favoriteExecutor
        queue.async { [weak self] in
            let result = execute(script)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.busy = false
                guard self.identity == currentKey else { return }
                if let result { self.favorite = result; self.favoriteUnavailable = false }
                else {
                    self.favorite = previous; self.favoriteUnavailable = false
                    self.message = HL("Apple Music could not update the favorite. Check Automation permission.")
                }
            }
        }
    }
    func open(_ track: MediaPlaybackState?) {
        guard let track else { return }
        if let raw = track.contentURL, let url = URL(string: raw), url.scheme == "https", url.host != nil {
            NSWorkspace.shared.open(url); return
        }
        if let bundle = track.bundleIdentifier, ["com.apple.Music", "com.spotify.client"].contains(bundle) {
            let property = bundle == "com.spotify.client" ? "spotify url" : "address"
            let script = """
            tell application id \(quote(bundle))
                if not running then error "Player closed"
                if name of current track is not \(quote(track.title)) then error "Track changed"
                return \(property) of current track
            end tell
            """
            queue.async { [weak self] in
                var error: NSDictionary?
                let raw = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let raw, let url = Self.webURL(raw) { NSWorkspace.shared.open(url) }
                    else { self.revealPlayer(bundle) }
                }
            }
            return
        }
        if let bundle = track.bundleIdentifier { revealPlayer(bundle) }
        else { message = HL("The player did not provide a playback link.") }
    }
    static func webURL(_ raw: String) -> URL? {
        if raw.hasPrefix("spotify:track:") {
            let id = String(raw.dropFirst("spotify:track:".count))
            guard !id.isEmpty, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
            return URL(string: "https://open.spotify.com/track/" + id)
        }
        guard let url = URL(string: raw), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
    private func revealPlayer(_ bundle: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else { message = HL("The player did not provide a playback link.") }
    }
}
