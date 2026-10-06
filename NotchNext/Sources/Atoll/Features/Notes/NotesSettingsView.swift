import SwiftUI

/// Settings pane for the Notes widget. Add to the settings window as a
/// "Notes" tab/section.
struct NotesSettingsView: View {
    @ObservedObject private var store = NotesStore.shared

    @AppStorage("notes.fontSize") private var fontSize = 13.0
    @AppStorage("notes.sortOrder") private var sortOrderRaw = NotesSortOrder.recentlyEdited.rawValue

    var body: some View {
        Form {
            Section(HL("Editor")) {
                HStack {
                    Text(HL("Font size"))
                    Slider(value: $fontSize, in: 11...18, step: 1)
                    Text("\(Int(fontSize)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
            }
            Section(HL("Note list")) {
                Picker(HL("Sort notes by"), selection: $sortOrderRaw) {
                    ForEach(NotesSortOrder.allCases) { order in
                        Text(order.label).tag(order.rawValue)
                    }
                }
            }
            Section(HL("Storage")) {
                LabeledContent(HL("Notes"), value: "\(store.notes.count)")
                Button(HL("Reveal Notes File in Finder")) {
                    store.revealInFinder()
                }
            }
        }
        .formStyle(.grouped)
    }
}
