import Foundation
import Observation

/// Dünne Hülle um `NSMetadataQuery`: startet eine Live-Suche und liefert die Treffer
/// als `SearchResult`. Spotlight meldet Änderungen im Dateisystem weiter, solange die
/// Abfrage läuft.
@MainActor
@Observable
final class SpotlightSearch {
    struct Configuration {
        var predicate: NSPredicate
        var scopes: [URL]
        var excludedPaths: [String]
        var sortKey: String
        var ascending: Bool
        var limit: Int
    }

    private(set) var results: [SearchResult] = []
    private(set) var totalCount = 0
    private(set) var isGathering = false
    private(set) var hasRun = false

    /// Wird nach jeder Aktualisierung der Treffer aufgerufen.
    @ObservationIgnored var onResultsChanged: (() -> Void)?

    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var configuration: Configuration?

    func start(_ configuration: Configuration) {
        stop()
        self.configuration = configuration

        let query = NSMetadataQuery()
        query.predicate = configuration.predicate
        query.searchScopes = configuration.scopes
        query.sortDescriptors = [NSSortDescriptor(key: configuration.sortKey, ascending: configuration.ascending)]
        query.notificationBatchingInterval = 0.4
        observe(query)

        self.query = query
        isGathering = true
        hasRun = true
        if !query.start() {
            isGathering = false
        }
    }

    func stop() {
        query?.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        query = nil
        isGathering = false
    }

    /// Setzt alles zurück, z. B. wenn keine Abfrage mehr übrig ist.
    func clear() {
        stop()
        results = []
        totalCount = 0
        hasRun = false
        onResultsChanged?()
    }

    private func observe(_ query: NSMetadataQuery) {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .NSMetadataQueryGatheringProgress,
            .NSMetadataQueryDidFinishGathering,
            .NSMetadataQueryDidUpdate,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: query, queue: .main) { [weak self] notification in
                let finished = notification.name == .NSMetadataQueryDidFinishGathering
                MainActor.assumeIsolated {
                    self?.collect(finishedGathering: finished)
                }
            }
        }
    }

    private func collect(finishedGathering: Bool) {
        guard let query, let configuration else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        let count = query.resultCount
        var collected: [SearchResult] = []
        collected.reserveCapacity(min(count, configuration.limit))
        for index in 0..<count where collected.count < configuration.limit {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let result = SearchResult(item: item),
                  !isExcluded(result.id, configuration.excludedPaths)
            else { continue }
            collected.append(result)
        }

        results = collected
        totalCount = count
        if finishedGathering { isGathering = false }
        onResultsChanged?()
    }

    private func isExcluded(_ path: String, _ excluded: [String]) -> Bool {
        excluded.contains { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }
}
