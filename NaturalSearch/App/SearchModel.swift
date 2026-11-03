import AppKit
import Observation

/// Verbindet Suchfeld, Foundation Model, Filterzeilen und Spotlight:
///
///     Suchfeld → QueryParser → FileSearchQuery → Verfeinern-Zeilen
///              → PredicateBuilder → NSPredicate → SpotlightSearch → Resultate
@MainActor
@Observable
final class SearchModel {
    // Suchfeld
    var searchText = ""
    var mode: SearchMode = QueryParser.isAvailable ? .natural : .anyText
    private(set) var isParsing = false
    private(set) var recentRequests: [String] = []
    /// Zuletzt vom Modell in Filterzeilen übersetzte Anfrage. Solange der Text gleich bleibt,
    /// sucht Return/▶ nur erneut und überschreibt die Verfeinerungen des Benutzers nicht.
    private var interpretedRequest: String?

    // Verfeinern
    /// Filterzeilen und verschachtelte Gruppen; die Wurzel ist selbst eine Gruppe.
    var filter: CriterionGroup = .defaultRoot
    var tags: Set<TagColor> = []
    var limit: ResultLimit = .hundredThousand
    var sortDirection: SortDirection = .newest
    var sortField: SortField = .opened

    // Resultate
    var selection: Set<SearchResult.ID> = []
    var layout: ResultsLayout = .list
    var tableSortOrder: [KeyPathComparator<SearchResult>] = [] {
        didSet { refreshDisplayedResults() }
    }
    private(set) var displayedResults: [SearchResult] = []
    private(set) var message: String?

    // Oberfläche
    var showsRefinePane = true
    var showsInfoPane = false
    var infoTab: InfoTab = .info
    var showsSavedQueries = false

    let spotlight = SpotlightSearch()
    let locations = LocationStore()
    let summarizer = ResultSummarizer()
    let savedQueries = SavedQueryStore()
    private let parser = QueryParser()
    private static let noScopeMessage = "Kein Ort freigegeben – unter „Orte“ einen Ordner auswählen."

    init() {
        spotlight.onResultsChanged = { [weak self] in self?.refreshDisplayedResults() }
        parser.prewarm()
    }

    // MARK: - Abgeleitete Werte

    var queryString: String? {
        PredicateBuilder.queryString(filter: filter, freeText: searchText, mode: mode, tags: tags)
    }

    /// Ändert sich dieser Schlüssel, startet die Ansicht die Suche neu.
    var searchKey: SearchKey {
        SearchKey(
            query: queryString,
            scopes: locations.includedURLs,
            excluded: locations.excludedPaths,
            sortField: sortField,
            sortDirection: sortDirection,
            limit: limit
        )
    }

    var selectedResults: [SearchResult] {
        displayedResults.filter { selection.contains($0.id) }
    }

    var statusText: String {
        if isParsing { return "Apple Intelligence interpretiert die Anfrage …" }
        if let message { return message }
        guard spotlight.hasRun else { return "Suchbegriff eingeben oder Filter setzen" }
        let shown = displayedResults.count.formatted()
        let total = spotlight.totalCount.formatted()
        let suffix = spotlight.isGathering ? " – Suche läuft …" : ""
        return shown == total ? "\(shown) Treffer\(suffix)" : "\(shown) von \(total) Treffern\(suffix)"
    }

    // MARK: - Aktionen

    /// Return im Suchfeld oder ▶: in natürlicher Sprache erst das Modell fragen –
    /// außer die Anfrage wurde schon interpretiert, dann gelten die (ggf. verfeinerten) Zeilen.
    func submit() {
        let request = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .natural, !request.isEmpty, request != interpretedRequest else {
            performSearch()
            return
        }
        Task { await interpret(request) }
    }

    func interpret(_ request: String) async {
        isParsing = true
        message = nil
        defer { isParsing = false }
        do {
            let query = try await parser.parse(request)
            apply(query, fallbackText: request)
            interpretedRequest = request
            remember(request)
        } catch {
            message = "Anfrage konnte nicht interpretiert werden: \(error.localizedDescription)"
        }
    }

    /// Überträgt die Modellantwort in die sichtbaren Filter.
    func apply(_ query: FileSearchQuery, fallbackText: String) {
        let rows = query.criteria
        filter = CriterionGroup(criteria: rows.isEmpty ? [SearchCriterion(.anyText, .containsPrefixes, value: fallbackText)] : rows)
        tags = Set(query.tags)
        if query.days > 0 { sortField = query.dateField.sortField }
        if !query.scope.isEmpty {
            if let location = locations.resolveScope(named: query.scope) {
                locations.included = [location.id]
            } else {
                message = "Ort „\(query.scope)“ ist nicht freigegeben – unter „Orte“ hinzufügen."
            }
        }
    }

    func performSearch() {
        guard let queryString, let predicate = PredicateBuilder.predicate(from: queryString) else {
            spotlight.clear()
            return
        }
        let scopes = locations.includedURLs
        guard !scopes.isEmpty else {
            spotlight.clear()
            message = Self.noScopeMessage
            return
        }
        if message == Self.noScopeMessage { message = nil }
        spotlight.start(.init(
            predicate: predicate,
            scopes: scopes,
            excludedPaths: locations.excludedPaths,
            sortKey: sortField.spotlightKey,
            ascending: sortDirection == .oldest,
            limit: limit.rawValue
        ))
    }

    /// Führt eine gespeicherte oder zuletzt verwendete Anfrage in natürlicher Sprache erneut aus.
    func run(request: String) {
        mode = .natural
        searchText = request
        // Bewusst gewählte Anfrage: immer frisch interpretieren.
        interpretedRequest = nil
        submit()
    }

    // MARK: - Gespeicherte Anfragen

    /// Die letzte Anfrage lässt sich speichern, sofern sie noch nicht in der Liste steht.
    var canSaveLastRequest: Bool {
        guard let last = recentRequests.first else { return false }
        return !savedQueries.contains(last)
    }

    func saveLastRequest() {
        guard let last = recentRequests.first else { return }
        savedQueries.add(last)
    }

    func reset() {
        searchText = ""
        interpretedRequest = nil
        filter = .defaultRoot
        tags = []
        selection = []
        message = nil
        spotlight.clear()
    }

    // MARK: - Filterzeilen und Gruppen

    /// Ein Element darf entfernt werden, solange danach mindestens eine Zeile übrig bleibt.
    func canRemove(_ item: CriterionItem) -> Bool {
        filter.criterionCount > item.criterionCount
    }

    func addCriterion(after id: CriterionItem.ID) {
        filter.modifyItems(containing: id) { items, index in
            items.insert(.criterion(SearchCriterion(.name)), at: index + 1)
        }
    }

    /// Hängt eine neue Zeile an das Ende der Gruppe an.
    func appendCriterion(to groupID: CriterionGroup.ID) {
        filter.modifyGroup(groupID) { $0.items.append(.criterion(SearchCriterion(.name))) }
    }

    /// Fügt hinter dem Element eine neue Gruppe mit einer leeren Zeile ein.
    func addGroup(after id: CriterionItem.ID) {
        filter.modifyItems(containing: id) { items, index in
            items.insert(.group(CriterionGroup([.criterion(SearchCriterion(.name))])), at: index + 1)
        }
    }

    /// Schließt das Element in eine neue Gruppe ein; die Gruppe übernimmt seine Verknüpfung.
    func wrapInGroup(_ id: CriterionItem.ID) {
        filter.modifyItems(containing: id) { items, index in
            var inner = items[index]
            let connector = inner.connector
            inner.connector = .and
            items[index] = .group(CriterionGroup([inner], connector: connector))
        }
    }

    /// Löst die Gruppe auf und setzt ihre Elemente an ihre Stelle (ohne Klammer und „Nicht“).
    func ungroup(_ id: CriterionGroup.ID) {
        filter.modifyItems(containing: id) { items, index in
            guard case .group(let group) = items[index] else { return }
            var children = group.items
            if !children.isEmpty { children[0].connector = group.connector }
            items.replaceSubrange(index...index, with: children)
        }
    }

    func duplicateItem(_ id: CriterionItem.ID) {
        filter.modifyItems(containing: id) { items, index in
            items.insert(items[index].withNewIDs(), at: index + 1)
        }
    }

    func removeItem(_ id: CriterionItem.ID) {
        // Vorab zählen: Während `modifyItems` läuft, darf `filter` nicht gelesen werden.
        let total = filter.criterionCount
        filter.modifyItems(containing: id) { items, index in
            guard total > items[index].criterionCount else { return }
            items.remove(at: index)
        }
    }

    // MARK: - Treffer

    func open(_ ids: Set<SearchResult.ID>) {
        displayedResults.filter { ids.contains($0.id) }.forEach { NSWorkspace.shared.open($0.url) }
    }

    func revealInFinder(_ ids: Set<SearchResult.ID>) {
        let urls = displayedResults.filter { ids.contains($0.id) }.map(\.url)
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func copyPaths(_ ids: Set<SearchResult.ID>) {
        let paths = displayedResults.filter { ids.contains($0.id) }.map(\.url.path)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }

    func copyQueryString() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(queryString ?? "", forType: .string)
    }

    private func refreshDisplayedResults() {
        let results = spotlight.results
        displayedResults = tableSortOrder.isEmpty ? results : results.sorted(using: tableSortOrder)
        let valid = Set(displayedResults.map(\.id))
        if !selection.isSubset(of: valid) { selection.formIntersection(valid) }
    }

    private func remember(_ request: String) {
        recentRequests.removeAll { $0 == request }
        recentRequests.insert(request, at: 0)
        recentRequests = Array(recentRequests.prefix(10))
    }
}

struct SearchKey: Hashable {
    var query: String?
    var scopes: [URL]
    var excluded: [String]
    var sortField: SortField
    var sortDirection: SortDirection
    var limit: ResultLimit
}
