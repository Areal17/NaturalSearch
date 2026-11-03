import Foundation

/// Baut aus den Filterzeilen eine Spotlight-Abfrage (MDQuery-Syntax wie bei `mdfind`)
/// und daraus ein `NSPredicate` für `NSMetadataQuery`.
///
/// Die Abfragesprache wird gewählt, weil `NSPredicate(format:)` keine wortbasierte Suche
/// (Modifikator `w`) und keine relativen Daten (`$time.today(-7)`) kennt.
enum PredicateBuilder {
    private enum Key {
        static let displayName = "kMDItemDisplayName"
        static let fsName = "kMDItemFSName"
        static let textContent = "kMDItemTextContent"
        static let contentTypeTree = "kMDItemContentTypeTree"
        static let modified = "kMDItemContentModificationDate"
        static let created = "kMDItemContentCreationDate"
        static let lastUsed = "kMDItemLastUsedDate"
        static let size = "kMDItemFSSize"
        static let authors = "kMDItemAuthors"
        static let comment = "kMDItemFinderComment"
        static let tags = "kMDItemUserTags"
    }

    /// Gesamte Abfrage oder `nil`, wenn nichts eingeschränkt ist.
    static func queryString(
        filter: CriterionGroup,
        freeText: String = "",
        mode: SearchMode = .natural,
        tags: Set<TagColor> = []
    ) -> String? {
        var clauses = clauses(for: filter)
        if let free = freeTextClause(freeText, mode: mode) { clauses.append(free) }
        if let tagClause = tagClause(tags) { clauses.append(tagClause) }
        guard !clauses.isEmpty else { return nil }
        return clauses.map { "(\($0))" }.joined(separator: " && ")
    }

    /// Wie oben, für eine flache Liste von Zeilen.
    static func queryString(
        criteria: [SearchCriterion],
        freeText: String = "",
        mode: SearchMode = .natural,
        tags: Set<TagColor> = []
    ) -> String? {
        queryString(filter: CriterionGroup(criteria: criteria), freeText: freeText, mode: mode, tags: tags)
    }

    static func predicate(from queryString: String) -> NSPredicate? {
        NSPredicate(fromMetadataQueryString: queryString)
    }

    // MARK: - Boolesche Verknüpfung

    /// Logischer Ausdruck, bevor er als MDQuery-Text ausgegeben wird.
    private indirect enum Expression {
        case clause(String)
        case all([Expression])
        case any([Expression])

        /// Fasst gleichartige Verschachtelungen zusammen und lässt Ein-Element-Listen weg.
        static func all(of parts: [Expression]) -> Expression {
            let flat = parts.flatMap { if case .all(let inner) = $0 { inner } else { [$0] } }
            return flat.count == 1 ? flat[0] : .all(flat)
        }

        static func any(of parts: [Expression]) -> Expression {
            let flat = parts.flatMap { if case .any(let inner) = $0 { inner } else { [$0] } }
            return flat.count == 1 ? flat[0] : .any(flat)
        }

        var text: String {
            switch self {
            case .clause(let clause): clause
            case .all(let parts): parts.map { "(\($0.text))" }.joined(separator: " && ")
            case .any(let parts): parts.map { "(\($0.text))" }.joined(separator: " || ")
            }
        }
    }

    /// Die UND-verknüpften Teile der Gruppe – oder genau ein Ausdruck, wenn ODER beteiligt ist.
    static func clauses(for group: CriterionGroup) -> [String] {
        switch expression(for: group) {
        case nil: []
        case .all(let parts): parts.map(\.text)
        case let expression?: [expression.text]
        }
    }

    static func criteriaClauses(_ criteria: [SearchCriterion]) -> [String] {
        clauses(for: CriterionGroup(criteria: criteria))
    }

    /// Verknüpft die Elemente einer Gruppe. UND bindet stärker, daher entstehen ODER-verknüpfte
    /// Teilfolgen von UND-Elementen. Eine umgekehrte Gruppe wird nach De Morgan aufgelöst, weil
    /// die Abfragesprache keine Negation von Klammern kennt: Jede Zeile wird umgekehrt
    /// (wie mit der Option „Nicht“), und UND und ODER tauschen die Rollen.
    private static func expression(for group: CriterionGroup, negated: Bool = false) -> Expression? {
        let negate = negated != group.isNegated
        var conjunctions: [[Expression]] = []
        for item in group.items {
            let part: Expression?
            switch item {
            case .criterion(var criterion):
                if negate { criterion.isNegated.toggle() }
                part = clause(for: criterion).map(Expression.clause)
            case .group(let subgroup):
                part = expression(for: subgroup, negated: negate)
            }
            guard let part else { continue }
            if conjunctions.isEmpty || item.connector == .or {
                conjunctions.append([part])
            } else {
                conjunctions[conjunctions.count - 1].append(part)
            }
        }
        guard !conjunctions.isEmpty else { return nil }
        // nicht ((A und B) oder C) = (nicht A oder nicht B) und nicht C
        return negate
            ? .all(of: conjunctions.map { .any(of: $0) })
            : .any(of: conjunctions.map { .all(of: $0) })
    }

    // MARK: - Einzelne Zeilen

    static func clause(for criterion: SearchCriterion) -> String? {
        guard !criterion.isEmpty else { return nil }
        let value = criterion.value.trimmingCharacters(in: .whitespaces)
        switch criterion.attribute {
        case .anyText:
            return wordClause([Key.displayName, Key.textContent], words: value, criterion: criterion)
        case .textContent where criterion.op != .contains && criterion.op != .notContains:
            return wordClause([Key.textContent], words: value, criterion: criterion)
        case .name, .textContent, .author, .comment:
            return stringClause(keys(for: criterion.attribute), value: value, criterion: criterion)
        case .fileExtension:
            return extensionClause(value, negated: excludes(criterion))
        case .contentKind:
            return anyOf(Key.contentTypeTree, values: criterion.contentKind.contentTypes, negated: excludes(criterion))
        case .modified, .created, .lastOpened:
            return dateClause(keys(for: criterion.attribute)[0], days: Int(value) ?? 0, criterion: criterion)
        case .size:
            return sizeClause(megabytes: value, criterion: criterion)
        }
    }

    private static func keys(for attribute: SearchAttribute) -> [String] {
        switch attribute {
        case .name: [Key.displayName]
        case .textContent: [Key.textContent]
        case .author: [Key.authors]
        case .comment: [Key.comment]
        case .modified: [Key.modified]
        case .created: [Key.created]
        case .lastOpened: [Key.lastUsed]
        default: []
        }
    }

    /// Jedes Wort muss vorkommen (UND), in einem der Attribute (ODER).
    private static func wordClause(_ keys: [String], words: String, criterion: SearchCriterion) -> String? {
        let prefix = criterion.op == .containsPrefixes
        let parts = words.split(whereSeparator: \.isWhitespace).map { word in
            let pattern = escape(String(word)) + (prefix ? "*" : "")
            return compare(keys, pattern: pattern, modifiers: modifiers(criterion, wordBased: true), negated: criterion.isNegated)
        }
        guard !parts.isEmpty else { return nil }
        return parts.count == 1 ? parts[0] : parts.map { "(\($0))" }.joined(separator: " && ")
    }

    private static func stringClause(_ keys: [String], value: String, criterion: SearchCriterion) -> String {
        let escaped = escape(value)
        let pattern = switch criterion.op {
        case .beginsWith: "\(escaped)*"
        case .endsWith: "*\(escaped)"
        case .equals: escaped
        default: "*\(escaped)*"
        }
        return compare(keys, pattern: pattern, modifiers: modifiers(criterion, wordBased: false), negated: excludes(criterion))
    }

    private static func extensionClause(_ value: String, negated: Bool) -> String? {
        let extensions = value
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty }
        guard !extensions.isEmpty else { return nil }
        let joiner = negated ? " && " : " || "
        return extensions
            .map { "\(Key.fsName) \(negated ? "!=" : "==") \"*.\(escape($0))\"c" }
            .joined(separator: joiner)
    }

    private static func anyOf(_ key: String, values: [String], negated: Bool) -> String? {
        guard !values.isEmpty else { return nil }
        return values
            .map { "\(key) \(negated ? "!=" : "==") \"\($0)\"" }
            .joined(separator: negated ? " && " : " || ")
    }

    private static func dateClause(_ key: String, days: Int, criterion: SearchCriterion) -> String? {
        let (isNewer, bound): (Bool, String) = switch criterion.op {
        case .today: (true, "$time.today")
        case .olderThanDays: (false, "$time.today(-\(max(days, 0)))")
        default: (true, "$time.today(-\(max(days, 0)))")
        }
        guard criterion.op == .today || days > 0 else { return nil }
        let newer = isNewer != criterion.isNegated
        return "\(key) \(newer ? ">=" : "<") \(bound)"
    }

    private static func sizeClause(megabytes: String, criterion: SearchCriterion) -> String? {
        let normalized = megabytes.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value >= 0 else { return nil }
        let bytes = Int64(value * 1_000_000)
        let greater = (criterion.op == .greaterThan) != criterion.isNegated
        return "\(Key.size) \(greater ? ">" : "<=") \(bytes)"
    }

    private static func freeTextClause(_ text: String, mode: SearchMode) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        switch mode {
        case .natural:
            return nil
        case .anyText:
            return clause(for: SearchCriterion(.anyText, .containsPrefixes, value: trimmed))
        case .name:
            return clause(for: SearchCriterion(.name, .contains, value: trimmed))
        }
    }

    private static func tagClause(_ tags: Set<TagColor>) -> String? {
        let names = TagColor.allCases.filter(tags.contains).map { escape($0.title) }
        return anyOf(Key.tags, values: names, negated: false)
    }

    // MARK: - Hilfsfunktionen

    /// „ist nicht“ und „enthält nicht“ schließen aus; die Option „Nicht“ kehrt das zusätzlich um.
    private static func excludes(_ criterion: SearchCriterion) -> Bool {
        criterion.op.isExclusive != criterion.isNegated
    }

    /// Vergleicht mehrere Attribute: positiv mit ODER, negiert (De Morgan) mit UND.
    private static func compare(_ keys: [String], pattern: String, modifiers: String, negated: Bool) -> String {
        keys
            .map { "\($0) \(negated ? "!=" : "==") \"\(pattern)\"\(modifiers)" }
            .joined(separator: negated ? " && " : " || ")
    }

    private static func modifiers(_ criterion: SearchCriterion, wordBased: Bool) -> String {
        (criterion.isCaseSensitive ? "" : "c")
            + (criterion.isDiacriticSensitive ? "" : "d")
            + (wordBased ? "w" : "")
    }

    /// Maskiert Zeichen mit Sonderbedeutung in MDQuery-Zeichenketten.
    static func escape(_ value: String) -> String {
        var result = ""
        for character in value {
            if character == "\\" || character == "\"" || character == "*" { result.append("\\") }
            result.append(character)
        }
        return result
    }
}
