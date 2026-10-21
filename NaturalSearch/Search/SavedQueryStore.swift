import Foundation
import Observation

/// Eine dauerhaft gespeicherte Anfrage in natürlicher Sprache.
struct SavedQuery: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var savedAt: Date
}

/// Verwaltet die gespeicherten Anfragen und sichert sie in den `UserDefaults`.
@MainActor
@Observable
final class SavedQueryStore {
    private(set) var queries: [SavedQuery] = [] { didSet { save() } }

    private static let defaultsKey = "SavedQueries.v1"

    init() {
        load()
    }

    func contains(_ text: String) -> Bool {
        queries.contains { $0.text == text }
    }

    /// Speichert eine Anfrage oben in der Liste; Duplikate werden nicht angelegt.
    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !contains(trimmed) else { return }
        queries.insert(SavedQuery(id: UUID(), text: trimmed, savedAt: .now), at: 0)
    }

    func remove(_ id: SavedQuery.ID) {
        queries.removeAll { $0.id == id }
    }

    // MARK: - Persistenz

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let stored = try? JSONDecoder().decode([SavedQuery].self, from: data)
        else { return }
        queries = stored
    }

    private func save() {
        if let data = try? JSONEncoder().encode(queries) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
