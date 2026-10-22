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
    /// Bereits umgewandelte Treffer der laufenden Abfrage. `NSMetadataQuery` liefert für
    /// einen Treffer über alle Meldungen hinweg dasselbe `NSMetadataItem`-Objekt, daher
    /// genügt dessen Identität als Schlüssel.
    @ObservationIgnored private var cache: [ObjectIdentifier: CachedResult] = [:]
    /// Lokalisierte Art je Content-Type; `UTType`-Abfragen sind teuer, Typen gibt es wenige.
    @ObservationIgnored private var kindDescriptions: [String: String] = [:]

    private struct CachedResult {
        /// Hält das Item fest, damit seine Adresse (= Schlüssel) nicht wiederverwendet wird.
        let item: NSMetadataItem
        /// `nil` für Treffer ohne Pfad oder in einem ausgeschlossenen Ort.
        let result: SearchResult?
    }

    func start(_ configuration: Configuration) {
        stop()
        self.configuration = configuration

        let query = NSMetadataQuery()
        query.predicate = configuration.predicate
        query.searchScopes = configuration.scopes
        query.valueListAttributes = SearchResult.metadataAttributes
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
        cache = [:]
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
                // Geänderte Items (z. B. umbenannt) müssen neu gelesen werden.
                let changed = (notification.userInfo?[NSMetadataQueryUpdateChangedItemsKey] as? [NSMetadataItem] ?? [])
                    .map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    self?.collect(finishedGathering: finished, changed: changed)
                }
            }
        }
    }

    /// Baut die Trefferliste in Spotlight-Reihenfolge neu auf. Nur Items, die noch nicht im
    /// Zwischenspeicher liegen oder sich geändert haben, werden umgewandelt – so kostet jede
    /// Zwischenmeldung nur so viel wie die neu hinzugekommenen Treffer.
    private func collect(finishedGathering: Bool, changed: [ObjectIdentifier]) {
        guard let query, let configuration else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        changed.forEach { cache[$0] = nil }
        let count = query.resultCount
        var collected: [SearchResult] = []
        collected.reserveCapacity(min(count, configuration.limit))
        // Neu aufgebaut, damit entfernte Treffer aus dem Zwischenspeicher verschwinden.
        var current: [ObjectIdentifier: CachedResult] = [:]
        current.reserveCapacity(count)
        for index in 0..<count where collected.count < configuration.limit {
            guard let item = query.result(at: index) as? NSMetadataItem else { continue }
            let key = ObjectIdentifier(item)
            let entry = cache[key] ?? CachedResult(
                item: item,
                result: SearchResult(query: query, index: index, kindDescription: kindDescription)
                    .flatMap { isExcluded($0.id, configuration.excludedPaths) ? nil : $0 }
            )
            current[key] = entry
            if let result = entry.result { collected.append(result) }
        }
        cache = current

        results = collected
        totalCount = count
        if finishedGathering { isGathering = false }
        onResultsChanged?()
    }

    private func kindDescription(for contentType: String) -> String {
        if let cached = kindDescriptions[contentType] { return cached }
        let description = SearchResult.kindDescription(for: contentType)
        kindDescriptions[contentType] = description
        return description
    }

    private func isExcluded(_ path: String, _ excluded: [String]) -> Bool {
        excluded.contains { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }
}
