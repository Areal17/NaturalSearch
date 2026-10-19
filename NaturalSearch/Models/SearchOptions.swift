import Foundation

/// Wie der Text im großen Suchfeld interpretiert wird.
enum SearchMode: String, CaseIterable, Identifiable, Sendable {
    case natural
    case anyText
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: "Natürliche Sprache (Apple Intelligence)"
        case .anyText: "Beliebiger Text"
        case .name: "Dateiname"
        }
    }

    var placeholder: String {
        switch self {
        case .natural: "Frag in natürlicher Sprache – z. B. „PDFs über Rechnungen vom letzten Monat“"
        case .anyText: "Beliebigen Text suchen"
        case .name: "Dateinamen suchen"
        }
    }

    var systemImage: String {
        switch self {
        case .natural: "sparkle.magnifyingglass"
        case .anyText: "magnifyingglass"
        case .name: "doc.text.magnifyingglass"
        }
    }
}

enum ResultLimit: Int, CaseIterable, Identifiable, Sendable {
    case hundred = 100
    case thousand = 1_000
    case tenThousand = 10_000
    case hundredThousand = 100_000

    var id: Int { rawValue }
    var title: String { rawValue.formatted(.number.locale(Locale(identifier: "de_DE"))) }
}

enum SortDirection: String, CaseIterable, Identifiable, Sendable {
    case newest
    case oldest

    var id: String { rawValue }
    var title: String { self == .newest ? "vor kürzester Zeit" : "vor längster Zeit" }
}

enum SortField: String, CaseIterable, Identifiable, Sendable {
    case opened
    case modified
    case created
    case added

    var id: String { rawValue }

    var title: String {
        switch self {
        case .opened: "geöffnet"
        case .modified: "geändert"
        case .created: "erstellt"
        case .added: "hinzugefügt"
        }
    }

    var spotlightKey: String {
        switch self {
        case .opened: "kMDItemLastUsedDate"
        case .modified: "kMDItemContentModificationDate"
        case .created: "kMDItemContentCreationDate"
        case .added: "kMDItemDateAdded"
        }
    }
}

enum ResultsLayout: String, CaseIterable, Identifiable, Sendable {
    case grid
    case list

    var id: String { rawValue }
}

enum InfoTab: String, CaseIterable, Identifiable, Sendable {
    case info
    case preview
    case summary

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .info: "info"
        case .preview: "eye"
        case .summary: "text.alignleft"
        }
    }

    var help: String {
        switch self {
        case .info: "Informationen"
        case .preview: "Vorschau"
        case .summary: "Zusammenfassung (Apple Intelligence)"
        }
    }
}
