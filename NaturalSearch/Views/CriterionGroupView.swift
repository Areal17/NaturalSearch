import SwiftUI

/// Die Elemente einer Gruppe untereinander, jeweils mit und/oder-Verknüpfung zum vorherigen.
/// Untergruppen erscheinen als umrandete Box und können beliebig tief verschachtelt werden.
struct CriterionItemsView: View {
    @Environment(SearchModel.self) private var model
    @Binding var group: CriterionGroup

    var body: some View {
        ForEach($group.items) { $item in
            if item.id != group.items.first?.id {
                ConnectorPicker(connector: $item.connector)
            }
            switch item {
            case .criterion(let criterion):
                CriterionRow(
                    criterion: Self.criterionBinding($item, fallback: criterion),
                    canRemove: model.canRemove(item),
                    onAdd: { model.addCriterion(after: item.id) },
                    onRemove: { model.removeItem(item.id) },
                    onDuplicate: { model.duplicateItem(item.id) },
                    onAddGroup: { model.addGroup(after: item.id) },
                    onWrapInGroup: { model.wrapInGroup(item.id) }
                )
            case .group(let subgroup):
                // AnyView unterbricht die rekursive Typableitung (Box → Elemente → Box …).
                AnyView(CriterionGroupBox(group: Self.groupBinding($item, fallback: subgroup)))
            }
        }
    }

    /// Bindung an die Zeile im Element. Der Ersatzwert greift nur kurz, falls SwiftUI eine
    /// veraltete Bindung liest, nachdem sich das Element geändert hat.
    private static func criterionBinding(_ item: Binding<CriterionItem>, fallback: SearchCriterion) -> Binding<SearchCriterion> {
        Binding(
            get: { if case .criterion(let criterion) = item.wrappedValue { criterion } else { fallback } },
            set: { item.wrappedValue = .criterion($0) }
        )
    }

    private static func groupBinding(_ item: Binding<CriterionItem>, fallback: CriterionGroup) -> Binding<CriterionGroup> {
        Binding(
            get: { if case .group(let group) = item.wrappedValue { group } else { fallback } },
            set: { item.wrappedValue = .group($0) }
        )
    }
}

/// Eine Untergruppe: Kopfzeile mit − + ≡ und darunter ihre Elemente.
struct CriterionGroupBox: View {
    @Environment(SearchModel.self) private var model
    @Binding var group: CriterionGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            CriterionItemsView(group: $group)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(group.isNegated ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.12))
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(group.isNegated ? "Nicht (Gruppe)" : "Gruppe")
                .font(.subheadline)
                .foregroundStyle(group.isNegated ? Color.accentColor : .secondary)
            Spacer()
            Button { model.removeItem(group.id) } label: { Image(systemName: "minus") }
                .disabled(!model.canRemove(.group(group)))
                .help("Gruppe entfernen")
            Button { model.appendCriterion(to: group.id) } label: { Image(systemName: "plus") }
                .help("Zeile zur Gruppe hinzufügen")
            Menu {
                Toggle("Nicht (Gruppe umkehren)", isOn: $group.isNegated)
                Divider()
                Button("Gruppe duplizieren") { model.duplicateItem(group.id) }
                Button("In Gruppe einschließen") { model.wrapInGroup(group.id) }
                Button("Gruppe auflösen") { model.ungroup(group.id) }
            } label: {
                OptionsMenuLabel(isHighlighted: group.isNegated)
            }
            .optionsMenuStyle()
            .help("Gruppenoptionen")
        }
        .buttonStyle(.square)
    }
}

#Preview {
    @Previewable @State var model = {
        let model = SearchModel()
        var plan = SearchCriterion(.name, .contains, value: "Plan")
        plan.connector = .or
        var group = CriterionGroup(criteria: [SearchCriterion(.name, .contains, value: "Budget"), plan])
        group.isNegated = true
        model.filter = CriterionGroup([.criterion(SearchCriterion(.fileExtension, value: "pdf")), .group(group)])
        return model
    }()
    ScrollView {
        VStack(alignment: .leading, spacing: 10) {
            CriterionItemsView(group: $model.filter)
        }
        .padding()
    }
    .environment(model)
    .frame(width: 600, height: 500)
}
