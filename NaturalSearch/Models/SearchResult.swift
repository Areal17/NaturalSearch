import Foundation

/// Ein Spotlight-Treffer, entkoppelt vom nicht-`Sendable` `NSMetadataItem`.
struct SearchResult: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let name: String
    let kind: String
    let contentType: String?
    let created: Date?
    let modified: Date?
    let lastOpened: Date?
    let size: Int64?
    let tags: [String]
    let comment: String?

    var folderPath: String {
        let folder = url.deletingLastPathComponent().path
        let home = RealHome.url.path
        return folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder
    }

    // Nicht-optionale Schlüssel für `KeyPathComparator` in der Tabelle.
    var modifiedSortKey: Date { modified ?? .distantPast }
    var lastOpenedSortKey: Date { lastOpened ?? .distantPast }
    var sizeSortKey: Int64 { size ?? -1 }
}

extension SearchResult {
    init?(item: NSMetadataItem) {
        guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
        id = path
        url = URL(fileURLWithPath: path)
        name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String ?? url.lastPathComponent
        kind = item.value(forAttribute: "kMDItemKind") as? String ?? ""
        contentType = item.value(forAttribute: NSMetadataItemContentTypeKey) as? String
        created = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date
        modified = item.value(forAttribute: NSMetadataItemContentModificationDateKey) as? Date
        lastOpened = item.value(forAttribute: "kMDItemLastUsedDate") as? Date
        size = (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value
        tags = item.value(forAttribute: "kMDItemUserTags") as? [String] ?? []
        comment = item.value(forAttribute: "kMDItemFinderComment") as? String
    }
}

/// Das echte Benutzerverzeichnis – in der Sandbox zeigt `homeDirectoryForCurrentUser`
/// auf den App-Container.
enum RealHome {
    static let url: URL = {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()
}
