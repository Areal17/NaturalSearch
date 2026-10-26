import Foundation
import FoundationModels

/// Strukturierte Suche, die das On-Device-Modell aus einer natürlichsprachlichen Anfrage erzeugt.
@Generable(description: "Strukturierte Spotlight-Suche nach Dateien auf einem Mac")
struct FileSearchQuery: Equatable, Sendable {
    @Guide(description: "Inhaltliche Suchbegriffe in der Grundform (Singular), z. B. Rechnung, Steuer, Urlaub. Keine Dateitypen, Zeitangaben, Ortsangaben oder Füllwörter wie Datei, Dokument, über.", .maximumCount(4))
    var keywords: [String]

    @Guide(description: "Begriffe, die im Dateinamen stehen müssen. Nur füllen, wenn ausdrücklich nach dem Namen gefragt wird, sonst leer.", .maximumCount(3))
    var nameKeywords: [String]

    @Guide(description: "Konkrete Dateiendungen ohne Punkt, kleingeschrieben, z. B. pdf, docx, xlsx, key, pages, jpg, png, mov, txt, md, swift. Leer, wenn keine konkrete Endung gemeint ist.", .maximumCount(6))
    var extensions: [String]

    @Guide(description: "Allgemeine Inhaltsart, wenn keine konkrete Endung genannt wurde (Fotos → image, Videos → movie, Musik → audio). Sonst any.")
    var contentKind: ContentKind

    @Guide(description: "Zeitraum bis heute in Tagen. 0 = keine Zeitangabe. heute = 1, gestern = 2, diese Woche = 7, letzte Woche = 14, letzten Monat = 31, letztes Quartal = 92, dieses Jahr = 365.", .range(0...3650))
    var days: Int

    @Guide(description: "Auf welches Datum sich der Zeitraum bezieht: opened für geöffnet/benutzt, created für erstellt/angelegt/heruntergeladen, sonst modified.")
    var dateField: DateField

    @Guide(description: "Ordnername bei Ortsangaben wie „im Downloads-Ordner“ oder „auf dem Schreibtisch“ (Downloads, Schreibtisch, Dokumente). Sonst leer.")
    var scope: String

    @Guide(description: "Finder-Farbtags, nur wenn ausdrücklich nach Tags oder Farbmarkierungen gefragt wird.", .maximumCount(3))
    var tags: [TagColor]
}

@Generable
enum DateField: String, Sendable {
    case modified
    case created
    case opened
}

extension FileSearchQuery {
    private static let fillerWords: Set<String> = ["datei", "dateien", "dokument", "dokumente", "file", "files"]

    /// Wortanfänge, an denen sich eine Zeitangabe in der Anfrage erkennen lässt.
    private static let timeWordPrefixes = [
        "heute", "gestern", "vorgestern", "tag", "woche", "monat", "quartal", "jahr", "letzt", "vorig",
        "seit", "neulich", "kürzlich", "jüngst", "zuletzt", "neueste", "aktuell",
        "today", "yesterday", "day", "week", "month", "quarter", "year", "last", "recent", "since",
    ]

    /// Monatsnamen als ganze Wörter („Mai“ soll nicht auf „Mail“ passen).
    private static let monthNames: Set<String> = [
        "januar", "februar", "märz", "april", "mai", "juni", "juli", "august", "september", "oktober",
        "november", "dezember",
    ]

    /// `true`, wenn die Anfrage überhaupt einen Zeitraum nennt (Wort, Monat oder Jahreszahl).
    static func mentionsTime(_ request: String) -> Bool {
        let words = request.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return words.contains { word in
            (word.count == 4 && word.allSatisfy(\.isNumber))
                || monthNames.contains(word)
                || timeWordPrefixes.contains { word.hasPrefix($0) }
        }
    }

    /// Bereinigt typische Fehler des kleinen Modells (Endungen als Schlüsselwort, Punkte, Dubletten,
    /// erfundene Zeiträume). Mit `request` werden Angaben verworfen, die nicht in der Anfrage stehen.
    func normalized(request: String? = nil) -> FileSearchQuery {
        var copy = self
        copy.extensions = Array(Set(extensions.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased() }))
            .filter { !$0.isEmpty }
            .sorted()
        let blocked = Self.fillerWords.union(copy.extensions)
        copy.keywords = keywords
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !blocked.contains($0.lowercased()) }
        copy.nameKeywords = nameKeywords.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if copy.extensions == ["pdf"] {
            // Nur PDF gesucht: als Inhaltsart „PDF“ zeigen; sie prüft den Dateityp und findet
            // auch PDFs ohne bzw. mit abweichender Endung.
            copy.extensions = []
            copy.contentKind = .pdf
        } else if !copy.extensions.isEmpty {
            // Eine konkrete Endung ist genauer als die Inhaltsart; beides zusammen widerspricht sich oft.
            copy.contentKind = .any
        }
        // Das Modell setzt gern days = 1, obwohl die Anfrage keinen Zeitraum nennt.
        if let request, copy.days > 0, !Self.mentionsTime(request) { copy.days = 0 }
        copy.scope = scope.trimmingCharacters(in: .whitespaces)
        return copy
    }

    /// Übersetzt die Modellantwort in editierbare Zeilen für „Verfeinern“.
    var criteria: [SearchCriterion] {
        var rows: [SearchCriterion] = []
        if !keywords.isEmpty {
            rows.append(SearchCriterion(.anyText, .containsPrefixes, value: keywords.joined(separator: " ")))
        }
        rows += nameKeywords.map { SearchCriterion(.name, .contains, value: $0) }
        if !extensions.isEmpty {
            rows.append(SearchCriterion(.fileExtension, value: extensions.joined(separator: ", ")))
        }
        if contentKind != .any {
            rows.append(SearchCriterion(.contentKind, contentKind: contentKind))
        }
        if days > 0 {
            rows.append(SearchCriterion(dateField.attribute, .withinLastDays, value: String(days)))
        }
        return rows
    }
}

extension DateField {
    var attribute: SearchAttribute {
        switch self {
        case .modified: .modified
        case .created: .created
        case .opened: .lastOpened
        }
    }

    var sortField: SortField {
        switch self {
        case .modified: .modified
        case .created: .created
        case .opened: .opened
        }
    }
}
