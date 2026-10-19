import AppKit
import Observation

/// Ein vom Benutzer freigegebener Ordner, gespeichert als Security-Scoped Bookmark.
struct SearchLocation: Identifiable, Codable, Hashable {
    let id: UUID
    var bookmark: Data
    var path: String
}

/// Ordner, die sich mit einem Klick freigeben lassen.
enum StandardFolder: String, CaseIterable, Identifiable {
    case home
    case documents
    case desktop
    case downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Benutzerordner"
        case .documents: "Dokumente"
        case .desktop: "Schreibtisch"
        case .downloads: "Downloads"
        }
    }

    var url: URL {
        switch self {
        case .home: RealHome.url
        case .documents: RealHome.url.appending(path: "Documents", directoryHint: .isDirectory)
        case .desktop: RealHome.url.appending(path: "Desktop", directoryHint: .isDirectory)
        case .downloads: RealHome.url.appending(path: "Downloads", directoryHint: .isDirectory)
        }
    }

    /// Bezeichnungen, unter denen das Modell oder der Benutzer den Ordner nennen könnte.
    var aliases: [String] {
        switch self {
        case .home: ["benutzerordner", "home", "privat"]
        case .documents: ["dokumente", "documents"]
        case .desktop: ["schreibtisch", "desktop"]
        case .downloads: ["downloads", "download"]
        }
    }
}

/// Verwaltet die Suchorte der Sandbox-App: Bookmarks anlegen, auflösen, freigeben.
/// Diese URLs werden zu `NSMetadataQuery.searchScopes`.
@MainActor
@Observable
final class LocationStore {
    private(set) var known: [SearchLocation] = []
    /// Zeilen unter „Orte“.
    var included: [UUID] = [] { didSet { save() } }
    /// Zeilen unter „Orte ausschließen“.
    var excluded: [UUID] = [] { didSet { save() } }

    @ObservationIgnored private var resolvedURLs: [UUID: URL] = [:]
    private static let defaultsKey = "SearchLocations.v1"

    init() {
        load()
    }

    var includedURLs: [URL] { included.compactMap { resolvedURLs[$0] } }
    var excludedPaths: [String] { excluded.compactMap { resolvedURLs[$0]?.path } }

    func location(_ id: UUID) -> SearchLocation? {
        known.first { $0.id == id }
    }

    func displayName(for location: SearchLocation) -> String {
        let url = URL(fileURLWithPath: location.path)
        if url.standardizedFileURL == RealHome.url.standardizedFileURL { return StandardFolder.home.title }
        return FileManager.default.displayName(atPath: location.path)
    }

    /// Standardordner, die noch nicht freigegeben sind.
    var missingStandardFolders: [StandardFolder] {
        StandardFolder.allCases.filter { folder in
            !known.contains { $0.path == folder.url.path }
        }
    }

    // MARK: - Freigeben

    /// Zeigt einen Öffnen-Dialog; der Benutzer bestätigt damit den Zugriff auf den Ordner.
    func requestAccess(startingAt folder: StandardFolder? = nil) -> SearchLocation? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder?.url ?? RealHome.url
        panel.prompt = "Freigeben"
        panel.message = "Wähle den Ordner, in dem NaturalSearch mit Spotlight suchen darf."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return add(url)
    }

    /// Legt ein Bookmark für eine URL an, auf die die App gerade Zugriff hat.
    @discardableResult
    func add(_ url: URL) -> SearchLocation? {
        if let existing = known.first(where: { $0.path == url.path }) { return existing }
        guard let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return nil }
        let location = SearchLocation(id: UUID(), bookmark: bookmark, path: url.path)
        known.append(location)
        activate(location)
        save()
        return location
    }

    /// Findet einen Ort zu einer Angabe wie „Downloads“. Liegt der Ordner innerhalb
    /// eines freigegebenen Orts, wird dafür ein eigenes Bookmark angelegt.
    func resolveScope(named name: String) -> SearchLocation? {
        let needle = name.lowercased()
        if let match = known.first(where: { displayName(for: $0).lowercased() == needle }) { return match }
        let candidate = StandardFolder.allCases.first { $0.aliases.contains(needle) }?.url
            ?? RealHome.url.appending(path: name, directoryHint: .isDirectory)
        let isCovered = known.contains { candidate.path.hasPrefix($0.path + "/") || candidate.path == $0.path }
        guard isCovered, FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return add(candidate)
    }

    // MARK: - Persistenz

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return }
        known = stored.known
        known.forEach(activate)
        included = stored.included.filter { resolvedURLs[$0] != nil }
        excluded = stored.excluded.filter { resolvedURLs[$0] != nil }
    }

    private func save() {
        let stored = Stored(known: known, included: included, excluded: excluded)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    /// Löst das Bookmark auf und öffnet den Security Scope für die Laufzeit der App.
    private func activate(_ location: SearchLocation) {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: location.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }
        _ = url.startAccessingSecurityScopedResource()
        resolvedURLs[location.id] = url
        if isStale, let index = known.firstIndex(where: { $0.id == location.id }),
           let fresh = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) {
            known[index].bookmark = fresh
        }
    }

    private struct Stored: Codable {
        var known: [SearchLocation]
        var included: [UUID]
        var excluded: [UUID]
    }
}
