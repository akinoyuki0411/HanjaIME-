import AppKit
import Foundation

// HanjiME bridge to the documented BSD-3-Clause ungive adapter protocol.
// No ejbills Swift wrapper or its headers are used by this implementation.
final class MediaAdapterTransport {
    var onTrackInfo: ((MediaPlaybackState?) -> Void)?
    var onTerminated: (() -> Void)?
    private var process: Process?
    private let commandQueue = DispatchQueue(label: "org.hanjaime.media.commands")
    static var framework: URL? { Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework") }
    static var script: URL? { Bundle.main.resourceURL?.appendingPathComponent("mediaremote-adapter.pl") }
    static var isAvailable: Bool {
        guard let framework, let script else { return false }
        return FileManager.default.fileExists(atPath: framework.path) && FileManager.default.fileExists(atPath: script.path)
    }
    func start() {
        guard process == nil, Self.isAvailable, let framework = Self.framework, let script = Self.script else { return }
        let worker = Process(), output = Pipe()
        worker.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        worker.arguments = [script.path, framework.path, "stream", "--no-diff", "--micros", "--debounce=100"]
        worker.standardOutput = output; worker.standardError = FileHandle.nullDevice
        var buffer = Data()
        output.fileHandleForReading.readabilityHandler = { [weak self, weak worker] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { handle.readabilityHandler = nil; return }
            buffer.append(chunk)
            if buffer.count > 8 * 1024 * 1024 { buffer.removeAll(); return }
            while let end = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
                DispatchQueue.main.async {
                    guard let self, let worker, self.process === worker else { return }
                    self.onTrackInfo?(Self.decode(line))
                }
            }
        }
        worker.terminationHandler = { [weak self] worker in
            DispatchQueue.main.async {
                guard let self, self.process === worker else { return }
                self.process = nil; self.onTerminated?()
            }
        }
        do { try worker.run(); process = worker }
        catch { output.fileHandleForReading.readabilityHandler = nil; onTerminated?() }
    }
    func stop() {
        let old = process; process = nil
        (old?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if old?.isRunning == true { old?.terminate() }
    }
    deinit { stop() }
    static func arguments(for command: String) -> [String]? {
        let parts = command.split(separator: " ").map(String.init)
        guard let verb = parts.first else { return nil }
        let ids = ["play":"0", "pause":"1", "toggle_play_pause":"2", "stop":"3", "next_track":"4", "previous_track":"5"]
        if parts.count == 1, let id = ids[verb] { return ["send", id] }
        guard parts.count == 2, let value = Double(parts[1]), value.isFinite, value >= 0 else { return nil }
        switch verb {
        case "set_time": guard value <= 604800 else { return nil }; return ["seek", String(Int64(value * 1_000_000))]
        case "set_shuffle_mode", "set_repeat_mode":
            guard value.rounded() == value, (1...3).contains(Int(value)) else { return nil }
            return [verb == "set_shuffle_mode" ? "shuffle" : "repeat", String(Int(value))]
        default: return nil
        }
    }
    func send(_ command: String) {
        guard Self.isAvailable, let args = Self.arguments(for: command), let framework = Self.framework, let script = Self.script else { return }
        commandQueue.async {
            let worker = Process(); worker.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            worker.arguments = [script.path, framework.path] + args
            worker.standardOutput = FileHandle.nullDevice; worker.standardError = FileHandle.nullDevice
            do {
                try worker.run()
                let timeout = DispatchWorkItem { if worker.isRunning { worker.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: timeout)
                worker.waitUntilExit(); timeout.cancel()
            } catch { }
        }
    }
    static func decode(_ data: Data) -> MediaPlaybackState? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["diff"] as? Bool != true, let p = object["payload"] as? [String: Any], !p.isEmpty else { return nil }
        func number(_ key: String) -> Double { let n = (p[key] as? NSNumber)?.doubleValue ?? 0; return n.isFinite ? n : 0 }
        let title = p["title"] as? String ?? "", artist = p["artist"] as? String ?? ""
        guard !title.isEmpty || !artist.isEmpty else { return nil }
        let art = (p["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }.flatMap(NSImage.init(data:))
        let playing = p["playing"] as? Bool ?? false
        let shuffle = number("shuffleMode"), repeatValue = number("repeatMode")
        var state = MediaPlaybackState(title: title, artist: artist, album: p["album"] as? String ?? "", artworkImage: art,
            bundleIdentifier: p["bundleIdentifier"] as? String, isPlaying: playing,
            duration: number("durationMicros") / 1_000_000, elapsed: number("elapsedTimeMicros") / 1_000_000,
            timestamp: number("timestampEpochMicros") > 0 ? Date(timeIntervalSince1970: number("timestampEpochMicros") / 1_000_000) : Date(),
            playbackRate: number("playbackRate"),
            shuffleMode: shuffle == 2 ? .albums : shuffle == 3 ? .songs : .off,
            repeatMode: repeatValue == 2 ? .one : repeatValue == 3 ? .all : .off)
        if let raw = p["contentItemIdentifier"] as? String, let url = URL(string: raw), url.scheme == "https" {
            state.contentURL = raw
        }
        return state
    }
}
