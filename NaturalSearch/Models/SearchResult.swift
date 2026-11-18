import Foundation
import UniformTypeIdentifiers

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
    /// Aufbereiteter Dateiname für `RelevanceRanker`. Wird einmal beim Einlesen berechnet und
    /// liegt damit im Zwischenspeicher von `SpotlightSearch`; leer bei von Hand gebauten Treffern.
    var rankingName = ""

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
    /// Attribute, die `NSMetadataQuery.valueListAttributes` gleich mit den Treffern lädt.
    /// Ohne diese Liste kostet jeder Einzelabruf ~0,3 ms (XPC zu Spotlight) – bei
    /// Zehntausenden Treffern in Unterordnern blockiert das den Hauptthread minutenlang.
    /// `kMDItemKind` fehlt bewusst: Spotlight liefert es nie vorab, darum wird die Art
    /// aus dem Content-Type abgeleitet.
    static let metadataAttributes = [
        NSMetadataItemFSNameKey,
        NSMetadataItemContentTypeKey,
        NSMetadataItemFSCreationDateKey,
        NSMetadataItemContentModificationDateKey,
        "kMDItemLastUsedDate",
        NSMetadataItemFSSizeKey,
        "kMDItemUserTags",
        "kMDItemFinderComment",
    ]

    /// Liest einen Treffer aus dem Zwischenspeicher der Abfrage. Anders als
    /// `NSMetadataItem.value(forAttribute:)` fragt `value(ofAttribute:forResultAt:)` fehlende
    /// Werte (z. B. nie geöffnete Dateien ohne `kMDItemLastUsedDate`) nicht erneut bei Spotlight an.
    /// Der Pfad kommt vom Item, er ist dort immer schon vorhanden.
    /// `kindDescription` übersetzt einen Content-Type in die lokalisierte Art; der Aufrufer
    /// kann so pro Typ zwischenspeichern (es gibt nur wenige verschiedene Typen).
    init?(query: NSMetadataQuery, index: Int, kindDescription: (String) -> String = Self.kindDescription) {
        guard let item = query.result(at: index) as? NSMetadataItem,
              let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
        else { return nil }
        func value<T>(_ attribute: String) -> T? {
            query.value(ofAttribute: attribute, forResultAt: index) as? T
        }
        id = path
        // `.inferFromPath` statt `fileURLWithPath:` – das würde für jeden Treffer im
        // Dateisystem nachsehen, ob der Pfad ein Ordner ist.
        url = URL(filePath: path, directoryHint: .inferFromPath)
        name = value(NSMetadataItemFSNameKey) ?? url.lastPathComponent
        contentType = value(NSMetadataItemContentTypeKey)
        kind = contentType.map(kindDescription) ?? ""
        created = value(NSMetadataItemFSCreationDateKey)
        modified = value(NSMetadataItemContentModificationDateKey)
        lastOpened = value("kMDItemLastUsedDate")
        size = (value(NSMetadataItemFSSizeKey) as NSNumber?)?.int64Value
        tags = value("kMDItemUserTags") ?? []
        comment = value("kMDItemFinderComment")
        rankingName = RelevanceRanker.rankingName(for: name)
    }

    /// Lokalisierte Art wie im Finder, z. B. „PDF-Dokument“.
    static func kindDescription(for contentType: String) -> String {
        UTType(contentType)?.localizedDescription ?? ""
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
