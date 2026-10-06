import SwiftUI

/// Shelf preferences — add as a section/tab in the settings window.
struct ShelfSettingsView: View {
    @AppStorage(ShelfSettingsKeys.autoOpenOnDrag) private var autoOpenOnDrag = true
    @AppStorage(ShelfSettingsKeys.autoRemoveAfterDrag) private var autoRemoveAfterDrag = false
    @AppStorage(ShelfSettingsKeys.clearOnQuit) private var clearOnQuit = false

    var body: some View {
        Form {
            Section {
                Toggle(HL("Open shelf when dragging files toward the notch"), isOn: $autoOpenOnDrag)
                Toggle(HL("Remove items after dragging them out"), isOn: $autoRemoveAfterDrag)
                Toggle(HL("Clear shelf when quitting"), isOn: $clearOnQuit)
            } header: {
                Text(HL("Shelf"))
            } footer: {
                Text(HL("Items stay on the shelf across restarts unless cleared. Files are referenced in place — dropped data and pasted images are stored in Atoll's Application Support folder."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
