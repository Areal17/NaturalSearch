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
        let clause = PredicateBuilder.clause(for: SearchCriterion(.anyText, .containsPrefixes, value: "Rechnung"))
        #expect(clause == #"kMDItemDisplayName == "Rechnung*"cdw || kMDItemTextContent == "Rechnung*"cdw"#)
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
}

@Suite("FileSearchQuery")
struct FileSearchQueryTests {
    private func query(
        keywords: [String] = [], nameKeywords: [String] = [], extensions: [String] = [],
        contentKind: ContentKind = .any, days: Int = 0, dateField: DateField = .modified,
        scope: String = "", tags: [TagColor] = []
    ) -> FileSearchQuery {
        FileSearchQuery(
            keywords: keywords, nameKeywords: nameKeywords, extensions: extensions,
            contentKind: contentKind, days: days, dateField: dateField, scope: scope, tags: tags
        )
    }

    @Test func invoicesFromLastMonthBecomeThreeRows() {
        let rows = query(keywords: ["Rechnung"], extensions: ["PDF"], days: 31).normalized().criteria
        #expect(rows.map(\.attribute) == [.anyText, .contentKind, .modified])
        #expect(rows[1].contentKind == .pdf)
        #expect(rows[2].value == "31")
    }

    @Test func normalizationDropsExtensionsAndFillerFromKeywords() {
        let normalized = query(keywords: ["pdf", "Dateien", "Steuer"], extensions: [".pdf"], contentKind: .document).normalized()
        #expect(normalized.keywords == ["Steuer"])
        #expect(normalized.extensions.isEmpty)
        #expect(normalized.contentKind == .pdf)
    }

    @Test func severalExtensionsStayExtensionsWithoutContentKind() {
        let normalized = query(extensions: ["pdf", "docx"], contentKind: .document).normalized()
        #expect(normalized.extensions == ["docx", "pdf"])
        #expect(normalized.contentKind == .any)
        #expect(normalized.criteria.map(\.attribute) == [.fileExtension])
    }

    @Test func openedDateMapsToLastOpened() {
        let rows = query(days: 2, dateField: .opened).criteria
        #expect(rows.first?.attribute == .lastOpened)
    }
}
