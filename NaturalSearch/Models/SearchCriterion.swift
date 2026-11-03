import Foundation

/// Attribut, nach dem eine Zeile im Bereich „Verfeinern“ filtert.
enum SearchAttribute: String, CaseIterable, Identifiable, Codable, Sendable {
    case anyText
    case name
    case textContent
    case fileExtension
    case contentKind
    case modified
    case created
    case lastOpened
    case size
    case author
    case comment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anyText: "Beliebiger Text"
        case .name: "Name"
        case .textContent: "Textinhalt"
        case .fileExtension: "Dateierweiterung"
        case .contentKind: "Inhaltsart"
        case .modified: "Änderungsdatum"
        case .created: "Erstelldatum"
        case .lastOpened: "Zuletzt geöffnet"
        case .size: "Größe"
        case .author: "Autor"
        case .comment: "Kommentar"
        }
    }

    var operators: [SearchOperator] {
        switch self {
        case .anyText: [.containsPrefixes, .containsWords]
        case .name: [.contains, .beginsWith, .endsWith, .equals]
        case .textContent: [.containsPrefixes, .containsWords, .contains]
        case .fileExtension, .contentKind: [.equals, .notEquals]
        case .modified, .created, .lastOpened: [.withinLastDays, .olderThanDays, .today]
        case .size: [.greaterThan, .lessThan]
        case .author, .comment: [.contains, .equals]
        }
    }

    var valueKind: ValueKind {
        switch self {
        case .fileExtension: .fileExtension
        case .contentKind: .contentKind
        case .modified, .created, .lastOpened: .days
        case .size: .megabytes
        default: .text
        }
    }

    enum ValueKind {
        case text, fileExtension, contentKind, days, megabytes
    }
}

/// Vergleichsoperator einer Filterzeile.
enum SearchOperator: String, CaseIterable, Identifiable, Codable, Sendable {
    case contains
    case beginsWith
    case endsWith
    case equals
    case notEquals
    case containsPrefixes
    case containsWords
    case withinLastDays
    case olderThanDays
    case today
    case greaterThan
    case lessThan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contains: "enthält"
        case .beginsWith: "beginnt mit"
        case .endsWith: "endet mit"
        case .equals: "ist"
        case .notEquals: "ist nicht"
        case .containsPrefixes: "enthält Präfixe"
        case .containsWords: "enthält Wörter"
        case .withinLastDays: "in den letzten"
        case .olderThanDays: "vor mehr als"
        case .today: "ist heute"
        case .greaterThan: "größer als"
        case .lessThan: "kleiner als"
        }
    }

    /// `false` für Operatoren, die keinen Wert brauchen.
    var needsValue: Bool { self != .today }
}

/// Verknüpfung einer Zeile mit der vorherigen. UND bindet stärker als ODER:
/// `A und B oder C` bedeutet `(A und B) oder C`.
enum LogicalConnector: String, CaseIterable, Identifiable, Codable, Sendable {
    case and
    case or

    var id: String { rawValue }

    var title: String {
        switch self {
        case .and: "und"
        case .or: "oder"
        }
    }
}

/// Eine Zeile im Bereich „Verfeinern“.
struct SearchCriterion: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var attribute: SearchAttribute {
        didSet {
            if !attribute.operators.contains(op) { op = attribute.operators[0] }
        }
    }
    var op: SearchOperator
    var value: String
    var contentKind: ContentKind = .any
    var isCaseSensitive = false
    var isDiacriticSensitive = false
    var isNegated = false
    /// Verknüpfung mit der vorherigen nicht leeren Zeile; bei der ersten Zeile ohne Bedeutung.
    var connector: LogicalConnector = .and

    init(_ attribute: SearchAttribute, _ op: SearchOperator? = nil, value: String = "", contentKind: ContentKind = .any) {
        self.attribute = attribute
        self.op = op ?? attribute.operators[0]
        self.value = value
        self.contentKind = contentKind
    }

    /// Eine Zeile ohne Wert trägt nichts zur Abfrage bei.
    var isEmpty: Bool {
        switch attribute.valueKind {
        case .contentKind: contentKind == .any
        default: op.needsValue && value.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    /// Die Zeilen, mit denen das Fenster startet (wie im Finder-Suchdialog).
    static var defaultSet: [SearchCriterion] {
        [
            SearchCriterion(.name, .contains),
            SearchCriterion(.textContent, .containsPrefixes),
            SearchCriterion(.fileExtension),
            SearchCriterion(.contentKind),
        ]
    }
}
