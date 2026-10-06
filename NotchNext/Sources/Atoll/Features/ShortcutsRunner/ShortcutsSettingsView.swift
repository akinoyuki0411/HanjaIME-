import SwiftUI

/// Settings pane: choose which shortcuts appear in the notch widget
/// (hide individual shortcuts) and manage favorites.
struct ShortcutsSettingsView: View {
    @ObservedObject private var manager = ShortcutsManager.shared
    @State private var filterText = ""

    var body: some View {
        Form {
            statusSection
            listSection
        }
        .formStyle(.grouped)
        .onAppear { manager.refreshOnAppear() }
    }

    // MARK: Status / actions

    private var statusSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(HL("Shortcuts widget"))
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if manager.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(HL("Refresh")) { manager.refresh() }
                }
            }
            if !manager.hiddenNames.isEmpty {
                HStack {
                    Text("\(manager.hiddenNames.count) hidden")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(HL("Show All")) { manager.unhideAll() }
                }
            }
        } footer: {
            Text(HL("Hiding a shortcut only removes it from the notch widget — it stays available in the Shortcuts app."))
        }
    }

    private var statusLine: String {
        switch manager.loadState {
        case .idle, .loading:
            return HL("Loading shortcut list…")
        case .loaded:
            let total = manager.allShortcuts.count
            let shown = total - manager.hiddenNames.intersection(Set(manager.allShortcuts.map(\.name))).count
            return "\(shown) of \(total) shortcuts shown in the widget"
        case .unavailable:
            return HL("Shortcuts CLI not found on this Mac")
        case .failed:
            return HL("Couldn't read the shortcut list")
        }
    }

    // MARK: Shortcut list

    @ViewBuilder
    private var listSection: some View {
        switch manager.loadState {
        case .unavailable(let message), .failed(let message):
            Section {
                Label {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        default:
            if manager.allShortcuts.isEmpty {
                Section {
                    HStack {
                        Text(HL("No shortcuts found."))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(HL("Open Shortcuts App")) { manager.openShortcutsApp() }
                    }
                }
            } else {
                Section(HL("Shown in widget")) {
                    TextField(HL("Filter shortcuts"), text: $filterText)
                        .textFieldStyle(.roundedBorder)
                    ForEach(filteredShortcuts) { item in
                        ShortcutsSettingsRow(manager: manager, item: item)
                    }
                    if filteredShortcuts.isEmpty {
                        Text("No shortcut name contains \u{201C}\(filterText)\u{201D}.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var filteredShortcuts: [ShortcutsItem] {
        let query = filterText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return manager.settingsShortcuts }
        return manager.settingsShortcuts.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
    }
}

// MARK: - Row

private struct ShortcutsSettingsRow: View {
    @ObservedObject var manager: ShortcutsManager
    let item: ShortcutsItem

    var body: some View {
        Toggle(isOn: shownBinding) {
            HStack(spacing: 6) {
                Button {
                    manager.toggleFavorite(item.name)
                } label: {
                    Image(systemName: manager.isFavorite(item.name) ? "star.fill" : "star")
                        .foregroundStyle(manager.isFavorite(item.name) ? .yellow : .secondary)
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .help(manager.isFavorite(item.name) ? HL("Remove from favorites") : HL("Add to favorites"))
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }

    private var shownBinding: Binding<Bool> {
        Binding(
            get: { !manager.isHidden(item.name) },
            set: { manager.setHidden(item.name, !$0) }
        )
    }
}
