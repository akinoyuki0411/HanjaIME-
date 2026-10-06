import SwiftUI
import Speech
import AVFoundation

@MainActor final class VoiceStore: ObservableObject {
    static let shared = VoiceStore()
    @Published var text = ""
    @Published var error = ""
    @Published var recording = false
    @Published var preparing = false
    @AppStorage("voice.locale") var locale = "ko-KR"
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapped = false
    private var generation = UUID()
    func start() async {
        guard !recording && !preparing else { return }
        let pending = UUID(); generation = pending
        preparing = true; defer { preparing = false }; error = ""
        let speech = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        guard generation == pending else { return }
        guard speech == .authorized else { error = HL("Allow speech recognition in Privacy settings."); return }
        guard await AVCaptureDevice.requestAccess(for: .audio) else { error = HL("Allow microphone access in Privacy settings."); return }
        guard generation == pending else { return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            error = HL("On-device recognition is unavailable for this language. No audio was sent online."); return
        }
        stop(); let token = UUID(); generation = token; text = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request
        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0 && format.channelCount > 0 else { error = HL("Microphone unavailable"); return }
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        tapped = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, failure in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if let result { self.text = result.bestTranscription.formattedString }
                if failure != nil || result?.isFinal == true {
                    if failure != nil { self.error = HL("Recognition ended. Try recording again.") }
                    self.stop()
                }
            }
        }
        do { engine.prepare(); try engine.start(); recording = true }
        catch { self.error = HL("Microphone unavailable"); stop() }
    }
    func stop() {
        generation = UUID()
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        request?.endAudio(); task?.cancel(); task = nil; request = nil; recording = false
    }
}
struct VoiceWidget: View {
    @ObservedObject private var store = VoiceStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(HL("Voice")).font(.headline); Spacer()
                Button(store.recording ? HL("Stop") : HL("Record")) { if store.recording { store.stop() } else { Task { await store.start() } } }.disabled(store.preparing)
            }
            Picker(HL("Language"), selection: $store.locale) { Text("한국어").tag("ko-KR"); Text("English").tag("en-US") }.disabled(store.recording || store.preparing)
            TextEditor(text: $store.text).frame(minHeight: 90)
            HStack {
                Button(HL("Copy Text")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.text, forType: .string) }.disabled(store.text.isEmpty)
                Text(HL("On-device only")).font(.caption).foregroundStyle(.secondary)
            }
            if !store.error.isEmpty { Text(store.error).font(.caption).foregroundStyle(.orange) }
        }.padding(12).onDisappear { store.stop() }
    }
}
struct VoiceSettingsView: View {
    var body: some View { VoiceWidget().background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12)) }
}
