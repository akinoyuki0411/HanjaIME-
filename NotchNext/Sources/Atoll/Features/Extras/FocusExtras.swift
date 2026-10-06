import SwiftUI
import AVFoundation
import Combine

struct FocusSessionRecord: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let seconds: Double
    let task: String
}
@MainActor final class FocusHistory: ObservableObject {
    static let shared = FocusHistory()
    @Published private(set) var records: [FocusSessionRecord]
    private let key = "focus.history.records"
    init() { records = (UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([FocusSessionRecord].self, from: $0) }) ?? [] }
    func record(seconds: Double, task: String) {
        guard UserDefaults.standard.object(forKey: "focus.history.enabled") as? Bool ?? true, seconds > 0 else { return }
        records.append(.init(date: Date(), seconds: seconds, task: task))
        records = Array(records.suffix(10000)); save()
    }
    func clear() { records = []; save() }
    private func save() { if let data = try? JSONEncoder().encode(records) { UserDefaults.standard.set(data, forKey: key) } }
}
struct FocusInsightsView: View {
    @ObservedObject private var history = FocusHistory.shared
    @AppStorage("focus.history.enabled") private var enabled = true
    @State private var days = 7
    @State private var confirmDelete = false
    private var filtered: [FocusSessionRecord] {
        let start = days == 0 ? Date.distantPast : Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: Date()))!
        return history.records.filter { $0.date >= start }
    }
    var body: some View {
        Form {
            Section(HL("Focus history")) {
                Toggle(HL("Save completed sessions locally"), isOn: $enabled)
                Picker(HL("Period"), selection: $days) {
                    Text(HL("Today")).tag(1); Text(HL("Week")).tag(7); Text(HL("Month")).tag(30); Text(HL("Year")).tag(365); Text(HL("All")).tag(0)
                }.pickerStyle(.segmented)
                LabeledContent(HL("Completed focus sessions"), value: "\(filtered.count)")
                LabeledContent(HL("Completed focus time"), value: "\(Int(filtered.reduce(0) { $0 + $1.seconds } / 60)) \(HL("minutes"))")
                ForEach(filtered.reversed().prefix(30)) { record in
                    HStack { VStack(alignment: .leading) { Text(record.task.isEmpty ? HL("Focus") : record.task); Text(record.date, style: .date).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("\(Int(record.seconds / 60)) \(HL("minutes"))") }
                }
                Button(HL("Delete session history"), role: .destructive) { confirmDelete = true }
                    .confirmationDialog(HL("Delete session history?"), isPresented: $confirmDelete) { Button(HL("Delete"), role: .destructive) { history.clear() } }
            }
        }.formStyle(.grouped)
    }
}
@MainActor final class AmbientAudio: ObservableObject {
    static let shared = AmbientAudio()
    @Published private(set) var playing = false
    @Published private(set) var error = ""
    @AppStorage("focus.ambient.volume") var volume = 0.15
    @AppStorage("focus.ambient.brown") var brown = true
    private var engine: AVAudioEngine?
    private var source: AVAudioSourceNode?
    private var timer: Timer?
    func start() {
        stop(); error = ""
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        // Generate one looping buffer outside the audio callback; no allocation in render.
        var samples = [Float](repeating: 0, count: 44100 * 8)
        var previous: Float = 0
        for index in samples.indices {
            let white = Float.random(in: -1...1)
            previous = (previous + 0.02 * white) / 1.02
            samples[index] = brown ? previous * 3.5 : white * 0.15
        }
        var cursor = 0
        let node = AVAudioSourceNode { _, _, frames, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            for frame in 0..<Int(frames) {
                let value = samples[cursor]; cursor = (cursor + 1) % samples.count
                for buffer in buffers { buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value }
            }
            return noErr
        }
        engine.attach(node); engine.connect(node, to: engine.mainMixerNode, format: format)
        self.engine = engine; source = node
        updateVolume()
        do { try engine.start(); playing = true }
        catch { self.error = HL("Could not start background audio"); stop() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in Task { @MainActor in self?.updateVolume() } }
    }
    private func updateVolume() {
        engine?.mainMixerNode.outputVolume = MusicManager.shared.playback?.isPlaying == true ? 0 : Float(min(0.6, max(0, volume)))
    }
    func stop() { timer?.invalidate(); timer = nil; engine?.stop(); engine = nil; source = nil; playing = false }
}
struct AmbientSettingsView: View {
    @ObservedObject private var audio = AmbientAudio.shared
    @AppStorage("focus.allowMusic") private var allowMusic = true
    @AppStorage("focus.allowCalendar") private var allowCalendar = true
    @AppStorage("focus.allowCode") private var allowCode = true
    @AppStorage("focus.allowHUD") private var allowHUD = true
    var body: some View {
        Form {
            Section(HL("Focus background audio")) {
                Picker(HL("Sound"), selection: $audio.brown) { Text(HL("Brown noise")).tag(true); Text(HL("White noise")).tag(false) }.disabled(audio.playing)
                Slider(value: $audio.volume, in: 0...0.6) { Text(HL("Volume")) }
                Button(audio.playing ? HL("Stop") : HL("Play")) { audio.playing ? audio.stop() : audio.start() }
                Text(HL("Generated on this Mac. Automatically quiet while music is playing.")).font(.caption).foregroundStyle(.secondary)
                if !audio.error.isEmpty { Text(audio.error).foregroundStyle(.orange) }
            }
            Section(HL("Activities during focus timer")) {
                Toggle(HL("Music"), isOn: $allowMusic); Toggle(HL("Calendar"), isOn: $allowCalendar)
                Toggle(HL("Code activity"), isOn: $allowCode); Toggle(HL("HUD"), isOn: $allowHUD)
                Text(HL("These filters apply only during a running Pomodoro focus phase.")).font(.caption)
            }
        }.formStyle(.grouped)
    }
}
enum FocusActivityPolicy {
    @MainActor static func allows(_ key: String) -> Bool {
        let timer = TimerManager.shared
        return !(timer.isPomodoroRunning && timer.pomodoroPhase == .focus) || (UserDefaults.standard.object(forKey: "focus.allow" + key) as? Bool ?? true)
    }
}
