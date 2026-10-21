import SwiftUI

/// Fenster mit allen gespeicherten Anfragen: Doppelklick oder ▶ führt aus, − entfernt.
struct SavedQueriesView: View {
    @Environment(SearchModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selection: SavedQuery.ID?

    var body: some View {
        let store = model.savedQueries
        VStack(spacing: 0) {
            PaneHeader(title: "Gespeicherte Anfragen")

            if store.queries.isEmpty {
                ContentUnavailableView(
                    "Keine gespeicherten Anfragen",
                    systemImage: "bookmark",
                    description: Text("Über „Gespeicherte Anfragen“ › „Letzte Anfrage speichern“ hinzufügen.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(store.queries, selection: $selection) { query in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(query.text)
                            .lineLimit(2)
                        Text("Gespeichert am \(query.savedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .tag(query.id)
                }
                .contextMenu(forSelectionType: SavedQuery.ID.self) { ids in
                    if let query = query(for: ids) {
                        Button("Ausführen") { run(query) }
                        Button("Entfernen", role: .destructive) { store.remove(query.id) }
                    }
                } primaryAction: { ids in
                    if let query = query(for: ids) { run(query) }
                }
                .onDeleteCommand(perform: removeSelection)
            }

            Divider()
            HStack {
                Button { removeSelection() } label: { Image(systemName: "minus") }
                    .buttonStyle(.square)
                    .disabled(selection == nil)
                    .help("Ausgewählte Anfrage entfernen")
                Spacer()
                Button("Ausführen") {
                    if let query = selectedQuery { run(query) }
                }
                .disabled(selectedQuery == nil || model.isParsing)
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(10)
        }
        .frame(minWidth: 420, idealWidth: 480, minHeight: 320, idealHeight: 400)
    }

    private var selectedQuery: SavedQuery? {
        model.savedQueries.queries.first { $0.id == selection }
    }

    private func query(for ids: Set<SavedQuery.ID>) -> SavedQuery? {
        guard let id = ids.first else { return nil }
        return model.savedQueries.queries.first { $0.id == id }
    }

    private func run(_ query: SavedQuery) {
        model.run(request: query.text)
        dismiss()
    }

    private func removeSelection() {
        guard let selection else { return }
        model.savedQueries.remove(selection)
        self.selection = nil
    }
}

#Preview {
    SavedQueriesView()
        .environment(SearchModel())
}
