import Foundation

/// Sortiert Treffer nach Relevanz für die Suchbegriffe: Treffer im Dateinamen zuerst,
/// kürzlich benutzte Dateien bekommen einen Bonus. Spotlight selbst liefert keine Relevanz.
enum RelevanceRanker {
    /// Punkte für einen Begriff im Dateinamen (ohne Endung). Jeder Namenstreffer liegt über
    /// dem höchsten Aktualitätsbonus (1,5), damit reine Inhaltstreffer immer dahinter landen.
    private enum NameMatch: Double {
        case equal = 8
        case prefix = 6
        case wordPrefix = 5
        case inside = 4
    }

    /// Sortiert über Indizes statt über die Treffer selbst – das Umkopieren der großen
    /// `SearchResult`-Werte beim Sortieren kostete bei 46.000 Treffern ein Mehrfaches.
    static func rank(_ results: [SearchResult], terms: [String], now: Date = .now) -> [SearchResult] {
        let foldedTerms = Array(Set(terms.map(fold).filter { !$0.isEmpty }))
        let dates = results.map { $0.lastOpened ?? $0.modified ?? .distantPast }
        let scores = results.indices.map { score(results[$0], terms: foldedTerms, date: dates[$0], now: now) }
        return results.indices
            .sorted { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : dates[$0] > dates[$1] }
            .map { results[$0] }
    }

    /// Dateiname ohne Endung, ohne Groß-/Kleinschreibung und Akzente.
    static func rankingName(for fileName: String) -> String {
        fold((fileName as NSString).deletingPathExtension)
    }

    /// `terms` sind bereits gefaltet (ohne Groß-/Kleinschreibung und Akzente).
    private static func score(_ result: SearchResult, terms: [String], date: Date, now: Date) -> Double {
        let recency = recencyBonus(age: now.timeIntervalSince(date))
        guard !terms.isEmpty else { return recency }
        let name = result.rankingName.isEmpty ? rankingName(for: result.name) : result.rankingName
        let nameScore = terms.reduce(0) { total, term in
            total + (nameMatch(term, in: name)?.rawValue ?? 0)
        }
        return nameScore + recency
    }

    /// Wörtliche Suche (beide Seiten sind gefaltet) – um ein Vielfaches schneller als die
    /// Unicode-Vergleiche von `contains`/`hasPrefix`. Ein Vorkommen am Wortanfang erkennt
    /// man am Zeichen davor (kein Buchstabe, keine Ziffer).
    private static func nameMatch(_ term: String, in name: String) -> NameMatch? {
        guard let first = name.range(of: term, options: .literal) else { return nil }
        if first.lowerBound == name.startIndex {
            return first.upperBound == name.endIndex ? .equal : .prefix
        }
        var occurrence: Range<String.Index>? = first
        while let current = occurrence {
            let before = name[name.index(before: current.lowerBound)]
            if !before.isLetter && !before.isNumber { return .wordPrefix }
            occurrence = name.range(of: term, options: .literal, range: current.upperBound..<name.endIndex)
        }
        return .inside
    }

    private static func recencyBonus(age: TimeInterval) -> Double {
        let day: TimeInterval = 86_400
        switch age {
        case ..<(7 * day): return 1.5
        case ..<(30 * day): return 1
        case ..<(365 * day): return 0.5
        default: return 0
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
