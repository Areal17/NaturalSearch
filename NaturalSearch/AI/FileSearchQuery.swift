import Foundation
import FoundationModels

/// Strukturierte Suche, die das On-Device-Modell aus einer natürlichsprachlichen Anfrage erzeugt.
@Generable(description: "Strukturierte Spotlight-Suche nach Dateien auf einem Mac")
struct FileSearchQuery: Equatable, Sendable {
    @Guide(description: "Inhaltliche Suchbegriffe, die in der Anfrage vorkommen, z. B. Rechnung, Steuer, Urlaub. Keine weiteren Themen erfinden. Keine Dateitypen, Zeitangaben, Ortsangaben oder Füllwörter wie Datei, Dokument, über.", .maximumCount(4))
    var keywords: [SearchTerm]

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

/// Ein Suchbegriff mit gleichbedeutenden Alternativen; gefunden wird, was einen davon enthält.
@Generable
struct SearchTerm: Equatable, Sendable {
    @Guide(description: "Suchbegriff in der Grundform (Singular)")
    var term: String

    @Guide(description: "Bis zu 3 Begriffe gleicher Bedeutung: Synonyme und die Übersetzung ins Englische bzw. Deutsche, in der Grundform. Leer, wenn es keine sinnvollen gibt.", .maximumCount(3))
    var alternatives: [String]
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

    /// Wörter, an denen eine Endung in der Anfrage erkennbar ist („Word-Dateien“ → docx).
    /// Die Endung selbst („PDFs“) zählt immer. Gefaltet, also ohne Umlaute.
    private static let extensionHints: [String: [String]] = [
        "doc": ["word"], "docx": ["word"],
        "xls": ["excel"], "xlsx": ["excel"], "numbers": ["numbers"],
        "ppt": ["powerpoint", "prasentation"], "pptx": ["powerpoint", "prasentation"], "key": ["keynote", "prasentation"],
        "jpg": ["foto", "bild", "photo"], "jpeg": ["foto", "bild", "photo"], "heic": ["foto", "bild", "photo"],
        "png": ["bild", "screenshot", "grafik"],
        "mov": ["video", "film"], "mp4": ["video", "film"],
        "txt": ["text"], "md": ["markdown", "notiz"],
    ]

    /// Wortteile, mit denen jemand ausdrücklich nach dem Dateinamen fragt.
    private static let nameHints = ["name", "heißt", "heisst", "titel", "called", "title"]

    /// Wörter ohne Groß-/Kleinschreibung und Akzente, an Satzzeichen getrennt.
    static func foldedWords(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// `true`, wenn ein Wort aus `phrase` in der Anfrage steckt – auch gebeugt oder als Teil
    /// eines zusammengesetzten Worts („Rechnung“ in „Stromrechnungen“).
    static func isMentioned(_ phrase: String, in requestWords: [String]) -> Bool {
        foldedWords(phrase).contains { word in
            let stem = String(word.prefix(5))
            return requestWords.contains { $0.contains(stem) }
        }
    }

    /// Verwirft, was das kleine Modell ohne Anhaltspunkt in der Anfrage ergänzt hat:
    /// zusätzliche Themen, Namensbegriffe, Endungen, „PDF“, Farbtags und Orte. Ein erfundener
    /// Ort wäre besonders lästig, weil er die gespeicherte Auswahl unter „Orte“ ersetzt.
    private func grounded(in request: String) -> FileSearchQuery {
        let words = Self.foldedWords(request)
        var copy = self
        copy.keywords = keywords.filter { Self.isMentioned($0.term, in: words) }
        let asksForName = words.contains { word in Self.nameHints.contains { word.contains($0) } }
        copy.nameKeywords = asksForName ? nameKeywords.filter { Self.isMentioned($0, in: words) } : []
        copy.extensions = extensions.filter { ext in
            words.contains { $0.hasPrefix(ext) }
                || (Self.extensionHints[ext] ?? []).contains { hint in words.contains { $0.contains(hint) } }
        }
        if contentKind == .pdf, !words.contains(where: { $0.hasPrefix("pdf") }) { copy.contentKind = .any }
        copy.tags = tags.filter { tag in
            let names = Self.foldedWords(tag.title) + [tag.rawValue]
            return words.contains { word in names.contains { word.hasPrefix($0) } }
        }
        if !scope.isEmpty, !Self.isMentioned(scope, in: words) { copy.scope = "" }
        return copy
    }

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
        copy.keywords = keywords.compactMap { Self.normalized($0, blocked: blocked) }
        copy.nameKeywords = nameKeywords.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let request { copy = copy.grounded(in: request) }
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
        copy.scope = copy.scope.trimmingCharacters(in: .whitespaces)
        return copy
    }

    /// Bereinigt einen Begriff: Füllwörter und Endungen fallen weg, Alternativen werden ohne
    /// Dubletten (auch gegenüber dem Begriff selbst) auf drei gekappt. Vom Modell erfundene
    /// Kürzel unter drei Zeichen („ML“) werden verworfen – als Präfix treffen sie zu viel („500 ml“).
    private static func normalized(_ keyword: SearchTerm, blocked: Set<String>) -> SearchTerm? {
        let term = keyword.term.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, !blocked.contains(term.lowercased()) else { return nil }
        var seen: Set<String> = [term.lowercased()]
        let alternatives = keyword.alternatives
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 && !blocked.contains($0.lowercased()) && seen.insert($0.lowercased()).inserted }
        return SearchTerm(term: term, alternatives: Array(alternatives.prefix(3)))
    }

    /// Übersetzt die Modellantwort in editierbare Zeilen für „Verfeinern“. Ein Begriff mit
    /// Alternativen wird zur Gruppe aus ODER-verknüpften Zeilen: `(Rechnung oder Beleg oder Invoice)`.
    var filter: CriterionGroup {
        var items: [CriterionItem] = keywords.map { keyword in
            let row = SearchCriterion(.anyText, .containsPrefixes, value: keyword.term)
            guard !keyword.alternatives.isEmpty else { return .criterion(row) }
            let alternatives = keyword.alternatives.map { alternative in
                var row = SearchCriterion(.anyText, .containsPrefixes, value: alternative)
                row.connector = .or
                return CriterionItem.criterion(row)
            }
            return .group(CriterionGroup([.criterion(row)] + alternatives))
        }
        items += nameKeywords.map { .criterion(SearchCriterion(.name, .contains, value: $0)) }
        if !extensions.isEmpty {
            items.append(.criterion(SearchCriterion(.fileExtension, value: extensions.joined(separator: ", "))))
        }
        if contentKind != .any {
            items.append(.criterion(SearchCriterion(.contentKind, contentKind: contentKind)))
        }
        if days > 0 {
            items.append(.criterion(SearchCriterion(dateField.attribute, .withinLastDays, value: String(days))))
        }
        return CriterionGroup(items)
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
