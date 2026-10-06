import SwiftUI
import Combine

struct CodeActivityEvent: Codable {
    let id: String
    let title: String
    let phase: String
    let progress: Double?
    let date: Date
}
@MainActor final class CodeActivityStore: ObservableObject {
    static let shared = CodeActivityStore()
    @Published private(set) var event: CodeActivityEvent?
    @Published private(set) var error = ""
    let messages = PassthroughSubject<CodeActivityEvent, Never>()
    var url: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HanjiME/code-activity.json") }
    private var timer: Timer?
    private var lastData: Data?
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    func refresh() {
        guard UserDefaults.standard.bool(forKey: "code.activity.enabled") else { event = nil; return }
        do {
            let data = try Data(contentsOf: url)
            guard data != lastData else {
                if let event, abs(event.date.timeIntervalSinceNow) >= 300 { self.event = nil }
                return
            }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let parsed = try decoder.decode(CodeActivityEvent.self, from: data)
            guard ["thinking", "working", "completed", "failed"].contains(parsed.phase), parsed.title.count <= 200,
                  parsed.progress.map({ $0.isFinite && (0...1).contains($0) }) ?? true else { throw CocoaError(.fileReadCorruptFile) }
            lastData = data; error = ""
            guard abs(parsed.date.timeIntervalSinceNow) < 300 else { event = nil; return }
            event = parsed
            if FocusActivityPolicy.allows("Code") { messages.send(parsed) }
        } catch let readError as CocoaError where readError.code == .fileReadNoSuchFile { error = "" }
        catch { self.error = HL("Code activity file could not be read") }
    }
}
struct CodeActivitySettingsView: View {
    @AppStorage("code.activity.enabled") private var enabled = false
    @ObservedObject private var store = CodeActivityStore.shared
    var body: some View {
        Form {
            Section(HL("Code activity")) {
                Toggle(HL("Show local task events"), isOn: $enabled)
                Text(HL("Only reads the dedicated event file. Does not access accounts, conversations, or approve commands.")).font(.caption)
                if let event = store.event { Text(event.title); Text(HL(event.phase.capitalized)); if let progress = event.progress { ProgressView(value: progress) } }
                Text(store.url.path).font(.caption).textSelection(.enabled)
                Button(HL("Copy event file path")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.url.path, forType: .string) }
                if !store.error.isEmpty { Text(store.error).foregroundStyle(.orange) }
            }
        }.formStyle(.grouped)
    }
}
