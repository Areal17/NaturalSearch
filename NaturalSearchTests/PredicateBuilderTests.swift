import Foundation
import Testing
@testable import NaturalSearch

@Suite("PredicateBuilder")
struct PredicateBuilderTests {
    @Test func emptyCriteriaProduceNoQuery() {
        #expect(PredicateBuilder.queryString(criteria: SearchCriterion.defaultSet) == nil)
    }

    @Test func nameContainsIsCaseAndDiacriticInsensitive() {
        let query = PredicateBuilder.queryString(criteria: [SearchCriterion(.name, .contains, value: "Budget")])
        #expect(query == #"(kMDItemDisplayName == "*Budget*"cd)"#)
    }

    @Test func textContentPrefixesMatchEveryWord() {
        let clause = PredicateBuilder.clause(for: SearchCriterion(.textContent, .containsPrefixes, value: "rech steu"))
        #expect(clause == #"(kMDItemTextContent == "rech*"cdw) && (kMDItemTextContent == "steu*"cdw)"#)
    }

    @Test func anyTextSearchesNameAndContent() {
        // Im Namen auch mitten im Wort („Stromrechnung“), im Inhalt am Wortanfang.
        let clause = PredicateBuilder.clause(for: SearchCriterion(.anyText, .containsPrefixes, value: "Rechnung"))
        #expect(clause == #"kMDItemDisplayName == "*Rechnung*"cd || kMDItemTextContent == "Rechnung*"cdw"#)
    }

    @Test func anyTextShortWordStaysWordPrefixInName() {
        let clause = PredicateBuilder.clause(for: SearchCriterion(.anyText, .containsPrefixes, value: "KI"))
        #expect(clause == #"kMDItemDisplayName == "KI*"cdw || kMDItemTextContent == "KI*"cdw"#)
    }

    @Test func anyTextContainsWordsKeepsWholeWords() {
        let clause = PredicateBuilder.clause(for: SearchCriterion(.anyText, .containsWords, value: "Rechnung"))
        #expect(clause == #"kMDItemDisplayName == "Rechnung"cdw || kMDItemTextContent == "Rechnung"cdw"#)
    }

    @Test func negatedAnyTextExcludesNameAndContent() {
        var criterion = SearchCriterion(.anyText, .containsPrefixes, value: "Entwurf")
        criterion.isNegated = true
        #expect(PredicateBuilder.clause(for: criterion) == #"kMDItemDisplayName != "*Entwurf*"cd && kMDItemTextContent != "Entwurf*"cdw"#)
    }

    @Test func anyTextWithSeveralWordsIsAcceptedBySpotlight() throws {
        let query = try #require(PredicateBuilder.queryString(criteria: [SearchCriterion(.anyText, .containsPrefixes, value: "Strom Rechnung")]))
        #expect(query.contains(#"kMDItemDisplayName == "*Strom*"cd"#))
        #expect(PredicateBuilder.predicate(from: query) != nil)
    }

    @Test func extensionsAreOredAndStripped() {
        let clause = PredicateBuilder.clause(for: SearchCriterion(.fileExtension, value: ".pdf, docx"))
        #expect(clause == #"kMDItemFSName == "*.pdf"c || kMDItemFSName == "*.docx"c"#)
    }

    @Test func negationUsesDeMorgan() {
        var criterion = SearchCriterion(.fileExtension, value: "pdf docx")
        criterion.isNegated = true
        #expect(PredicateBuilder.clause(for: criterion) == #"kMDItemFSName != "*.pdf"c && kMDItemFSName != "*.docx"c"#)
    }

    @Test func nameNotContainsExcludesSubstring() {
        let clause = PredicateBuilder.clause(for: SearchCriterion(.name, .notContains, value: "Entwurf"))
        #expect(clause == #"kMDItemDisplayName != "*Entwurf*"cd"#)
    }

    @Test func textContentNotContainsExcludesSubstring() {
        let clause = PredicateBuilder.clause(for: SearchCriterion(.textContent, .notContains, value: "vertraulich"))
        #expect(clause == #"kMDItemTextContent != "*vertraulich*"cd"#)
    }

    @Test func negatedNotContainsMeansContains() {
        var criterion = SearchCriterion(.name, .notContains, value: "Entwurf")
        criterion.isNegated = true
        #expect(PredicateBuilder.clause(for: criterion) == #"kMDItemDisplayName == "*Entwurf*"cd"#)
    }

    @Test func notContainsInNegatedGroupFlipsBack() throws {
        var group = CriterionGroup(criteria: [SearchCriterion(.textContent, .notContains, value: "Entwurf")])
        group.isNegated = true
        let query = try #require(PredicateBuilder.queryString(filter: CriterionGroup([.group(group)])))
        #expect(query == #"(kMDItemTextContent == "*Entwurf*"cd)"#)
        #expect(PredicateBuilder.predicate(from: query) != nil)
    }

    @Test func contentKindUsesTypeTree() {
        let clause = PredicateBuilder.clause(for: SearchCriterion(.contentKind, contentKind: .image))
        #expect(clause == #"kMDItemContentTypeTree == "public.image""#)
    }

    @Test func relativeDates() {
        #expect(PredicateBuilder.clause(for: SearchCriterion(.modified, .withinLastDays, value: "31"))
            == "kMDItemContentModificationDate >= $time.today(-31)")
        #expect(PredicateBuilder.clause(for: SearchCriterion(.lastOpened, .olderThanDays, value: "7"))
            == "kMDItemLastUsedDate < $time.today(-7)")
        #expect(PredicateBuilder.clause(for: SearchCriterion(.created, .today)) == "kMDItemContentCreationDate >= $time.today")
    }

    @Test func sizeInMegabytes() {
        #expect(PredicateBuilder.clause(for: SearchCriterion(.size, .greaterThan, value: "1,5")) == "kMDItemFSSize > 1500000")
    }

    @Test func specialCharactersAreEscaped() {
        #expect(PredicateBuilder.escape(#"a"b*c\d"#) == #"a\"b\*c\\d"#)
    }

    @Test func freeTextAndTagsAreCombined() {
        let query = PredicateBuilder.queryString(criteria: [], freeText: "Urlaub", mode: .name, tags: [.blue, .red])
        #expect(query == #"(kMDItemDisplayName == "*Urlaub*"cd) && (kMDItemUserTags == "Rot" || kMDItemUserTags == "Blau")"#)
    }

    @Test func naturalModeIgnoresFreeText() {
        #expect(PredicateBuilder.queryString(criteria: [], freeText: "PDFs von gestern", mode: .natural) == nil)
    }

    @Test func orConnectorBuildsDisjunction() {
        var second = SearchCriterion(.fileExtension, value: "docx")
        second.connector = .or
        let query = PredicateBuilder.queryString(criteria: [SearchCriterion(.fileExtension, value: "pdf"), second])
        #expect(query == #"((kMDItemFSName == "*.pdf"c) || (kMDItemFSName == "*.docx"c))"#)
    }

    @Test func andBindsTighterThanOr() {
        var third = SearchCriterion(.name, .contains, value: "Budget")
        third.connector = .or
        let clauses = PredicateBuilder.criteriaClauses([
            SearchCriterion(.fileExtension, value: "pdf"),
            SearchCriterion(.size, .greaterThan, value: "1"),
            third,
        ])
        #expect(clauses == [#"((kMDItemFSName == "*.pdf"c) && (kMDItemFSSize > 1000000)) || (kMDItemDisplayName == "*Budget*"cd)"#])
    }

    @Test func emptyRowsAreSkippedInBooleanLogic() {
        var empty = SearchCriterion(.name)
        empty.connector = .or
        let clauses = PredicateBuilder.criteriaClauses([empty, SearchCriterion(.fileExtension, value: "pdf")])
        #expect(clauses == [#"kMDItemFSName == "*.pdf"c"#])
    }

    @Test func disjunctionIsAndedWithFreeText() throws {
        var second = SearchCriterion(.contentKind, contentKind: .image)
        second.connector = .or
        let query = try #require(PredicateBuilder.queryString(
            criteria: [SearchCriterion(.fileExtension, value: "pdf"), second],
            freeText: "Urlaub", mode: .name
        ))
        #expect(query.hasSuffix(#" && (kMDItemDisplayName == "*Urlaub*"cd)"#))
        #expect(PredicateBuilder.predicate(from: query) != nil)
    }

    @Test func nestedGroupActsAsParentheses() {
        // pdf und (Budget oder Plan)
        var plan = SearchCriterion(.name, .contains, value: "Plan")
        plan.connector = .or
        let filter = CriterionGroup([
            .criterion(SearchCriterion(.fileExtension, value: "pdf")),
            .group(CriterionGroup([.criterion(SearchCriterion(.name, .contains, value: "Budget")), .criterion(plan)])),
        ])
        #expect(PredicateBuilder.clauses(for: filter) == [
            #"kMDItemFSName == "*.pdf"c"#,
            #"(kMDItemDisplayName == "*Budget*"cd) || (kMDItemDisplayName == "*Plan*"cd)"#,
        ])
    }

    @Test func negatedGroupAppliesDeMorgan() {
        // nicht (pdf oder > 1 MB) = nicht pdf und <= 1 MB
        var size = SearchCriterion(.size, .greaterThan, value: "1")
        size.connector = .or
        var group = CriterionGroup(criteria: [SearchCriterion(.fileExtension, value: "pdf"), size])
        group.isNegated = true
        #expect(PredicateBuilder.clauses(for: CriterionGroup([.group(group)])) == [
            #"kMDItemFSName != "*.pdf"c"#,
            "kMDItemFSSize <= 1000000",
        ])
    }

    @Test func doubleNegationCancels() {
        var inner = CriterionGroup(criteria: [SearchCriterion(.fileExtension, value: "pdf")])
        inner.isNegated = true
        var outer = CriterionGroup([.group(inner)])
        outer.isNegated = true
        #expect(PredicateBuilder.clauses(for: CriterionGroup([.group(outer)])) == [#"kMDItemFSName == "*.pdf"c"#])
    }

    @Test func emptyGroupsContributeNothing() {
        let filter = CriterionGroup([
            .group(CriterionGroup([.criterion(SearchCriterion(.name))])),
            .criterion(SearchCriterion(.fileExtension, value: "pdf")),
        ])
        #expect(PredicateBuilder.queryString(filter: filter) == #"(kMDItemFSName == "*.pdf"c)"#)
    }

    @Test func deeplyNestedQueryIsAcceptedBySpotlight() throws {
        var negated = CriterionGroup(criteria: [
            SearchCriterion(.anyText, .containsPrefixes, value: "Entwurf"),
            SearchCriterion(.size, .lessThan, value: "0,1"),
        ])
        negated.isNegated = true
        var orGroup = CriterionGroup([.criterion(SearchCriterion(.contentKind, contentKind: .image))], connector: .or)
        orGroup.items.append(.group(negated))
        let filter = CriterionGroup([.criterion(SearchCriterion(.fileExtension, value: "pdf")), .group(orGroup)])
        let query = try #require(PredicateBuilder.queryString(filter: filter, tags: [.green]))
        #expect(PredicateBuilder.predicate(from: query) != nil)
    }

    @Test func generatedQueriesAreAcceptedBySpotlight() throws {
        let criteria = [
            SearchCriterion(.anyText, .containsPrefixes, value: "Rechnung"),
            SearchCriterion(.fileExtension, value: "pdf"),
            SearchCriterion(.modified, .withinLastDays, value: "31"),
        ]
        let query = try #require(PredicateBuilder.queryString(criteria: criteria, tags: [.green]))
        #expect(PredicateBuilder.predicate(from: query) != nil)
    }
}

@Suite("CriterionGroup")
struct CriterionGroupTests {
    private let first = SearchCriterion(.name, .contains, value: "a")
    private let second = SearchCriterion(.name, .contains, value: "b")

    @Test func modifiesItemsInNestedGroups() {
        let inner = CriterionGroup(criteria: [second])
        var root = CriterionGroup([.criterion(first), .group(inner)])
        let found = root.modifyItems(containing: second.id) { items, index in
            items.insert(.criterion(SearchCriterion(.size)), at: index + 1)
        }
        #expect(found)
        #expect(root.criterionCount == 3)
        guard case .group(let changed) = root.items[1] else { Issue.record("Gruppe fehlt"); return }
        #expect(changed.items.count == 2)
    }

    @Test func groupsThatBecomeEmptyAreRemoved() {
        var root = CriterionGroup([.criterion(first), .group(CriterionGroup(criteria: [second]))])
        root.modifyItems(containing: second.id) { items, index in items.remove(at: index) }
        #expect(root.items.map(\.id) == [first.id])
    }

    @Test func duplicatesGetFreshIDs() {
        let group = CriterionItem.group(CriterionGroup(criteria: [first, second]))
        guard case .group(let copy) = group.withNewIDs() else { Issue.record("Gruppe erwartet"); return }
        #expect(copy.id != group.id)
        #expect(Set(copy.items.map(\.id)).isDisjoint(with: [first.id, second.id]))
    }

    @Test func connectorIsSettableOnBothCases() {
        var item = CriterionItem.group(CriterionGroup(criteria: [first]))
        item.connector = .or
        #expect(item.connector == .or)
    }

    @Test func positiveTextTermsSkipExcludedRowsAndNegatedGroups() {
        var negatedRow = SearchCriterion(.name, .contains, value: "Entwurf")
        negatedRow.isNegated = true
        var negatedGroup = CriterionGroup(criteria: [SearchCriterion(.anyText, .containsPrefixes, value: "alt")])
        negatedGroup.isNegated = true
        let root = CriterionGroup([
            .criterion(SearchCriterion(.anyText, .containsPrefixes, value: "Strom Rechnung")),
            .criterion(SearchCriterion(.textContent, .notContains, value: "vertraulich")),
            .criterion(negatedRow),
            .criterion(SearchCriterion(.fileExtension, value: "pdf")),
            .group(CriterionGroup(criteria: [SearchCriterion(.name, .contains, value: "Beleg")])),
            .group(negatedGroup),
        ])
        #expect(root.positiveTextTerms == ["Strom", "Rechnung", "Beleg"])
    }
}

@Suite("RelevanceRanker")
struct RelevanceRankerTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func result(_ name: String, openedDaysAgo days: Double? = nil) -> SearchResult {
        let path = "/tmp/\(name)"
        return SearchResult(
            id: path, url: URL(filePath: path), name: name, kind: "", contentType: nil, created: nil,
            modified: nil, lastOpened: days.map { now.addingTimeInterval(-$0 * 86_400) }, size: nil, tags: [], comment: nil
        )
    }

    private func names(_ results: [SearchResult], terms: [String]) -> [String] {
        RelevanceRanker.rank(results, terms: terms, now: now).map(\.name)
    }

    @Test func nameMatchBeatsRecentContentOnlyMatch() {
        let results = [result("Notizen.txt", openedDaysAgo: 1), result("Stromrechnung.pdf", openedDaysAgo: 900)]
        #expect(names(results, terms: ["rechnung"]) == ["Stromrechnung.pdf", "Notizen.txt"])
    }

    @Test func betterNameMatchComesFirst() {
        let results = [
            result("Stromrechnung.pdf"), result("Alte Rechnungen.pdf"),
            result("Rechnung 2026.pdf"), result("rechnung.pdf"),
        ]
        #expect(names(results, terms: ["Rechnung"]) == ["rechnung.pdf", "Rechnung 2026.pdf", "Alte Rechnungen.pdf", "Stromrechnung.pdf"])
    }

    @Test func matchingIgnoresCaseAndDiacritics() {
        let results = [result("Notizen.txt"), result("Übersicht Gebühren.pdf")]
        #expect(names(results, terms: ["gebuhren"]).first == "Übersicht Gebühren.pdf")
    }

    @Test func recencyBreaksTiesBetweenEqualMatches() {
        let results = [result("Rechnung A.pdf", openedDaysAgo: 400), result("Rechnung B.pdf", openedDaysAgo: 3)]
        #expect(names(results, terms: ["rechnung"]) == ["Rechnung B.pdf", "Rechnung A.pdf"])
    }

    @Test func withoutTermsMostRecentComesFirst() {
        let results = [result("a.txt", openedDaysAgo: 50), result("b.txt"), result("c.txt", openedDaysAgo: 2)]
        #expect(names(results, terms: []) == ["c.txt", "a.txt", "b.txt"])
    }
}

@Suite("FileSearchQuery")
struct FileSearchQueryTests {
    private func query(
        keywords: [String] = [], terms: [SearchTerm] = [], nameKeywords: [String] = [], extensions: [String] = [],
        contentKind: ContentKind = .any, days: Int = 0, dateField: DateField = .modified,
        scope: String = "", tags: [TagColor] = []
    ) -> FileSearchQuery {
        FileSearchQuery(
            keywords: keywords.map { SearchTerm(term: $0, alternatives: []) } + terms,
            nameKeywords: nameKeywords, extensions: extensions,
            contentKind: contentKind, days: days, dateField: dateField, scope: scope, tags: tags
        )
    }

    /// Die Zeilen auf oberster Ebene (Gruppen ausgelassen).
    private func rows(_ group: CriterionGroup) -> [SearchCriterion] {
        group.items.compactMap { if case .criterion(let criterion) = $0 { criterion } else { nil } }
    }

    @Test func invoicesFromLastMonthBecomeThreeRows() {
        let rows = rows(query(keywords: ["Rechnung"], extensions: ["PDF"], days: 31).normalized().filter)
        #expect(rows.map(\.attribute) == [.anyText, .contentKind, .modified])
        #expect(rows[1].contentKind == .pdf)
        #expect(rows[2].value == "31")
    }

    @Test func normalizationDropsExtensionsAndFillerFromKeywords() {
        let normalized = query(keywords: ["pdf", "Dateien", "Steuer"], extensions: [".pdf"], contentKind: .document).normalized()
        #expect(normalized.keywords.map(\.term) == ["Steuer"])
        #expect(normalized.extensions.isEmpty)
        #expect(normalized.contentKind == .pdf)
    }

    @Test func severalExtensionsStayExtensionsWithoutContentKind() {
        let normalized = query(extensions: ["pdf", "docx"], contentKind: .document).normalized()
        #expect(normalized.extensions == ["docx", "pdf"])
        #expect(normalized.contentKind == .any)
        #expect(rows(normalized.filter).map(\.attribute) == [.fileExtension])
    }

    @Test func openedDateMapsToLastOpened() {
        let rows = rows(query(days: 2, dateField: .opened).filter)
        #expect(rows.first?.attribute == .lastOpened)
    }

    @Test func alternativesBecomeOrGroup() throws {
        let filter = query(terms: [SearchTerm(term: "Rechnung", alternatives: ["Beleg", "Invoice"])], extensions: ["pdf"])
            .normalized().filter
        guard case .group(let group) = filter.items.first else { Issue.record("ODER-Gruppe erwartet"); return }
        let alternatives = rows(group)
        #expect(alternatives.map(\.value) == ["Rechnung", "Beleg", "Invoice"])
        #expect(alternatives.map(\.connector) == [.and, .or, .or])
        #expect(alternatives.allSatisfy { $0.attribute == .anyText })
        let queryString = try #require(PredicateBuilder.queryString(filter: filter))
        #expect(PredicateBuilder.predicate(from: queryString) != nil)
    }

    @Test func termWithoutAlternativesStaysSingleRow() {
        let filter = query(keywords: ["Kubernetes"]).filter
        #expect(rows(filter).map(\.value) == ["Kubernetes"])
    }

    @Test func inventedDetailsAreDropped() {
        // Beobachtete Modellantwort auf „Rezepte mit Kartoffeln“.
        let model = query(
            terms: [
                SearchTerm(term: "Kartoffeln", alternatives: ["Knollen"]),
                SearchTerm(term: "Rezept", alternatives: ["recipe"]),
                SearchTerm(term: "kochen", alternatives: ["cooking"]),
            ],
            nameKeywords: ["rezept"], contentKind: .pdf, tags: [.red]
        )
        let normalized = model.normalized(request: "Rezepte mit Kartoffeln")
        #expect(normalized.keywords.map(\.term) == ["Kartoffeln", "Rezept"])
        #expect(normalized.keywords.first?.alternatives == ["Knollen"])
        #expect(normalized.nameKeywords.isEmpty)
        #expect(normalized.contentKind == .any)
        #expect(normalized.tags.isEmpty)
    }

    @Test func inventedTopicsAreDropped() {
        let model = query(terms: [
            SearchTerm(term: "Machine Learning", alternatives: ["maschinelles Lernen"]),
            SearchTerm(term: "Artificial Intelligence", alternatives: []),
            SearchTerm(term: "Computer Vision", alternatives: []),
        ], extensions: ["pdf"])
        let normalized = model.normalized(request: "PDFs über Machine Learning")
        #expect(normalized.keywords.map(\.term) == ["Machine Learning"])
        #expect(normalized.contentKind == .pdf)
    }

    @Test func mentionedDetailsAreKept() {
        #expect(query(keywords: ["Rechnung"]).normalized(request: "Stromrechnungen 2025").keywords.map(\.term) == ["Rechnung"])
        #expect(query(nameKeywords: ["Budget 2026"]).normalized(request: "Datei namens Budget 2026").nameKeywords == ["Budget 2026"])
        #expect(query(extensions: ["docx", "doc"]).normalized(request: "Word-Dateien von gestern").extensions == ["doc", "docx"])
        #expect(query(extensions: ["key", "pptx"]).normalized(request: "Präsentationen im Downloads-Ordner").extensions == ["key", "pptx"])
        #expect(query(tags: [.red]).normalized(request: "Dateien mit rotem Tag").tags == [.red])
        #expect(query(tags: [.green]).normalized(request: "grün markierte Dateien").tags == [.green])
    }

    @Test func scopeIsKeptOnlyWhenMentioned() {
        #expect(query(scope: "Downloads").normalized(request: "Präsentationen im Downloads-Ordner").scope == "Downloads")
        #expect(query(scope: "Downloads").normalized(request: "PDFs über Rechnungen").scope.isEmpty)
    }

    @Test func unmentionedExtensionIsDropped() {
        #expect(query(extensions: ["pdf"]).normalized(request: "Fotos vom Urlaub").extensions.isEmpty)
    }

    @Test func alternativesAreCleanedUp() {
        let term = SearchTerm(term: "Rechnung", alternatives: ["rechnung", " Beleg ", "beleg", "ML", "pdf", "Invoice", "Quittung", "Faktura"])
        let normalized = query(terms: [term], extensions: ["pdf"]).normalized()
        #expect(normalized.keywords.first?.alternatives == ["Beleg", "Invoice", "Quittung"])
    }
}
