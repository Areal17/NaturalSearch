import Foundation

/// Eine Gruppe von Filterzeilen und Untergruppen im Bereich „Verfeinern“.
///
/// Innerhalb einer Gruppe gilt dieselbe Regel wie auf oberster Ebene: Jedes Element ist über
/// `connector` mit dem vorherigen verknüpft, „und“ bindet stärker als „oder“.
/// Eine Gruppe wirkt wie eine Klammer: `A und (B oder C)`.
struct CriterionGroup: Identifiable, Hashable, Sendable {
    var id = UUID()
    var items: [CriterionItem]
    /// Verknüpfung mit dem vorherigen Element; bei der Wurzel ohne Bedeutung.
    var connector: LogicalConnector = .and
    /// Kehrt die ganze Gruppe um: `nicht (A oder B)`.
    var isNegated = false

    init(_ items: [CriterionItem], connector: LogicalConnector = .and) {
        self.items = items
        self.connector = connector
    }

    init(criteria: [SearchCriterion]) {
        self.init(criteria.map(CriterionItem.criterion))
    }

    /// Die Zeilen, mit denen das Fenster startet.
    static var defaultRoot: CriterionGroup {
        CriterionGroup(criteria: SearchCriterion.defaultSet)
    }

    /// Anzahl der Filterzeilen in dieser Gruppe und allen Untergruppen.
    var criterionCount: Int {
        items.reduce(0) { $0 + $1.criterionCount }
    }

    // MARK: - Bearbeiten

    /// Sucht rekursiv die Liste, die das Element `id` enthält, und wendet `transform` darauf an.
    /// Danach werden leer gewordene Untergruppen entfernt.
    @discardableResult
    mutating func modifyItems(containing id: CriterionItem.ID, _ transform: (inout [CriterionItem], Int) -> Void) -> Bool {
        if let index = items.firstIndex(where: { $0.id == id }) {
            transform(&items, index)
            removeEmptyGroups()
            return true
        }
        for index in items.indices {
            guard case .group(var group) = items[index], group.modifyItems(containing: id, transform) else { continue }
            items[index] = .group(group)
            removeEmptyGroups()
            return true
        }
        return false
    }

    /// Bearbeitet die Untergruppe `id` selbst.
    mutating func modifyGroup(_ id: CriterionGroup.ID, _ transform: (inout CriterionGroup) -> Void) {
        modifyItems(containing: id) { items, index in
            guard case .group(var group) = items[index] else { return }
            transform(&group)
            items[index] = .group(group)
        }
    }

    private mutating func removeEmptyGroups() {
        items.removeAll { item in
            if case .group(let group) = item { group.items.isEmpty } else { false }
        }
    }
}

/// Ein Element einer Gruppe: eine Filterzeile oder eine Untergruppe.
enum CriterionItem: Identifiable, Hashable, Sendable {
    case criterion(SearchCriterion)
    case group(CriterionGroup)

    var id: UUID {
        switch self {
        case .criterion(let criterion): criterion.id
        case .group(let group): group.id
        }
    }

    var connector: LogicalConnector {
        get {
            switch self {
            case .criterion(let criterion): criterion.connector
            case .group(let group): group.connector
            }
        }
        set {
            switch self {
            case .criterion(var criterion):
                criterion.connector = newValue
                self = .criterion(criterion)
            case .group(var group):
                group.connector = newValue
                self = .group(group)
            }
        }
    }

    var criterionCount: Int {
        switch self {
        case .criterion: 1
        case .group(let group): group.criterionCount
        }
    }

    /// Kopie mit neuen IDs für sich und alle enthaltenen Elemente (für „Duplizieren“).
    func withNewIDs() -> CriterionItem {
        switch self {
        case .criterion(var criterion):
            criterion.id = UUID()
            return .criterion(criterion)
        case .group(var group):
            group.id = UUID()
            group.items = group.items.map { $0.withNewIDs() }
            return .group(group)
        }
    }
}
