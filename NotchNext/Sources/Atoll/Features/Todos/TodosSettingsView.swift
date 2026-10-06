import SwiftUI

/// Settings pane for the To-dos widget; the integrator adds it as a
/// section/tab of the settings window. Uses standard system styling
/// (the settings window is a normal light/dark window, not the notch).
struct TodosSettingsView: View {
    @AppStorage("todos.autoArchiveHours") private var autoArchiveHours = 24.0
    @AppStorage("todos.showCompleted") private var showCompleted = true
    @AppStorage("todos.showArchived") private var showArchived = true
    @ObservedObject private var store = TodosStore.shared

    var body: some View {
        Form {
            Section {
                Toggle(HL("Show completed tasks"), isOn: $showCompleted)
                Picker(HL("Auto-archive completed"), selection: $autoArchiveHours) {
                    Text(HL("After 1 hour")).tag(1.0)
                    Text(HL("After 6 hours")).tag(6.0)
                    Text(HL("After 12 hours")).tag(12.0)
                    Text(HL("After 24 hours")).tag(24.0)
                    Text(HL("After 2 days")).tag(48.0)
                    Text(HL("After 1 week")).tag(168.0)
                    Text(HL("Never")).tag(0.0)
                }
                .onChange(of: autoArchiveHours) { _, _ in
                    store.archiveSweep()
                }
                Toggle(HL("Show archived section in widget"), isOn: $showArchived)
            } header: {
                Text(HL("To-dos"))
            } footer: {
                Text(HL("Completed to-dos stay visible (struck through) until the auto-archive delay passes, then move to the archive."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section(HL("Archive")) {
                LabeledContent(HL("Archived items"), value: "\(store.archived.count)")
                Button(HL("Clear Archive"), role: .destructive) {
                    store.clearArchive()
                }
                .disabled(store.archived.isEmpty)
            }
        }
        .formStyle(.grouped)
    }
}
