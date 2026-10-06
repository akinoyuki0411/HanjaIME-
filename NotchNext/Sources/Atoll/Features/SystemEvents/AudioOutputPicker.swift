import SwiftUI
import CoreAudio

struct AudioOutputDevice: Identifiable {
    let id: AudioObjectID
    let name: String
}

enum AudioOutputDevices {
    static func list() -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard !ids.isEmpty else { return [] }
        let status = ids.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr else { return [] }
        return ids.compactMap { id in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                    mScope: kAudioDevicePropertyScopeOutput,
                                                    mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                        mScope: kAudioObjectPropertyScopeGlobal,
                                                        mElement: kAudioObjectPropertyElementMain)
            var name: CFString = "Audio" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            let nameStatus = withUnsafeMutablePointer(to: &name) { pointer in
                AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, pointer)
            }
            guard nameStatus == noErr else { return nil }
            return AudioOutputDevice(id: id, name: name as String)
        }
    }
    static func current() -> AudioObjectID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        var value = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &value)
        return value
    }
    static func select(_ id: AudioObjectID) -> Bool {
        guard list().contains(where: { $0.id == id }) else { return false }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        var value = id
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                          UInt32(MemoryLayout<AudioObjectID>.size), &value) == noErr
    }
}

struct AudioOutputPicker: View {
    @State private var devices: [AudioOutputDevice] = []
    @State private var current: AudioObjectID = 0
    @State private var failed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(devices) { device in
                Button {
                    failed = !AudioOutputDevices.select(device.id)
                    current = AudioOutputDevices.current()
                } label: {
                    Label(device.name, systemImage: current == device.id ? "checkmark.circle.fill" : "speaker.wave.2")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.borderless)
            }
            Button(HL("Refresh audio outputs")) { refresh() }
            if failed { Text(HL("Could not switch audio output")).foregroundStyle(.red).font(.caption) }
        }.onAppear { refresh() }
    }
    private func refresh() {
        devices = AudioOutputDevices.list()
        current = AudioOutputDevices.current()
    }
}
