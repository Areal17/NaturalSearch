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
