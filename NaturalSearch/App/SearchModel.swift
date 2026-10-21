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

    // Verfeinern
    var criteria: [SearchCriterion] = SearchCriterion.defaultSet
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
        PredicateBuilder.queryString(criteria: criteria, freeText: searchText, mode: mode, tags: tags)
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

    /// Return im Suchfeld oder ▶: in natürlicher Sprache erst das Modell fragen.
    func submit() {
        let request = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .natural, !request.isEmpty else {
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
            remember(request)
        } catch {
            message = "Anfrage konnte nicht interpretiert werden: \(error.localizedDescription)"
        }
    }

    /// Überträgt die Modellantwort in die sichtbaren Filter.
    func apply(_ query: FileSearchQuery, fallbackText: String) {
        let rows = query.criteria
        criteria = rows.isEmpty ? [SearchCriterion(.anyText, .containsPrefixes, value: fallbackText)] : rows
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
        criteria = SearchCriterion.defaultSet
        tags = []
        selection = []
        message = nil
        spotlight.clear()
    }

    // MARK: - Filterzeilen

    func addCriterion(after id: SearchCriterion.ID) {
        let index = criteria.firstIndex { $0.id == id }.map { $0 + 1 } ?? criteria.endIndex
        criteria.insert(SearchCriterion(.name), at: index)
    }

    func duplicateCriterion(_ id: SearchCriterion.ID) {
        guard let index = criteria.firstIndex(where: { $0.id == id }) else { return }
        var copy = criteria[index]
        copy.id = UUID()
        criteria.insert(copy, at: index + 1)
    }

    func removeCriterion(_ id: SearchCriterion.ID) {
        guard criteria.count > 1 else { return }
        criteria.removeAll { $0.id == id }
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
