import Foundation

@main struct AudioOutputTests {
    static func main() {
        let devices = AudioOutputDevices.list()
        precondition(Set(devices.map(\.id)).count == devices.count)
        precondition(devices.allSatisfy { !$0.name.isEmpty })
        let current = AudioOutputDevices.current()
        precondition(current == 0 || devices.contains { $0.id == current })
        precondition(!AudioOutputDevices.select(0), "Invalid device must not change the output")
        precondition(AudioOutputDevices.current() == current)
        print("5 audio output assertions passed; \(devices.count) outputs found")
    }
}
