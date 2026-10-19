import SwiftUI

/// Linker Bereich: Verfeinern · Orte · Tags · Limit
struct RefinePane: View {
    @Environment(SearchModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: 0) {
                PaneHeader(title: "Verfeinern")
                section {
                    ForEach($model.criteria) { $criterion in
                        CriterionRow(
                            criterion: $criterion,
                            canRemove: model.criteria.count > 1,
                            onAdd: { model.addCriterion(after: criterion.id) },
                            onRemove: { model.removeCriterion(criterion.id) },
                            onDuplicate: { model.duplicateCriterion(criterion.id) }
                        )
                    }
                }

                PaneHeader(title: "Orte")
                section { LocationsSection() }

//                PaneHeader(title: "Tags")
//                section { TagsSection() }.padding(.vertical, 8)

                PaneHeader(title: "Limit")
                section { LimitSection() }
            }
        }
        .background(PaneStyle.headerBackground)
    }

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PaneStyle.contentBackground)
    }
}

/// Orte: Liste freigegebener Ordner (= `searchScopes`) und Ausschlüsse.
private struct LocationsSection: View {
    @Environment(SearchModel.self) private var model
    @State private var showsExclusions = false

    var body: some View {
        @Bindable var store = model.locations
        VStack(alignment: .leading, spacing: 10) {
            if store.included.isEmpty {
                grantRow
            }
            LocationRows(ids: $store.included, minimumCount: 1)

            if showsExclusions || !store.excluded.isEmpty {
                Text("Ausgeschlossen").font(.subheadline).foregroundStyle(.secondary)
                LocationRows(ids: $store.excluded, minimumCount: 0)
            }
            Button("Orte ausschließen") {
                showsExclusions = true
                if let location = store.requestAccess() { store.excluded.append(location.id) }
            }
            .controlSize(.regular)
        }
    }

    private var grantRow: some View {
        HStack {
            Text("Noch kein Ort freigegeben").foregroundStyle(.secondary)
            Spacer()
            Button("Benutzerordner freigeben …") {
                if let location = model.locations.requestAccess(startingAt: .home) {
                    model.locations.included.append(location.id)
                }
            }
        }
    }
}

/// Zeilen mit Ordner-Auswahl und − / +.
private struct LocationRows: View {
    @Environment(SearchModel.self) private var model
    @Binding var ids: [UUID]
    let minimumCount: Int

    var body: some View {
        ForEach(Array(ids.enumerated()), id: \.element) { index, id in
            HStack(spacing: 8) {
                Picker("Ort", selection: choice(at: index)) {
                    ForEach(model.locations.known) { location in
                        Text(model.locations.displayName(for: location)).tag(LocationChoice.location(location.id))
                    }
                    Divider()
                    ForEach(model.locations.missingStandardFolders) { folder in
                        Text("\(folder.title) freigeben …").tag(LocationChoice.standard(folder))
                    }
                    Text("Anderer Ordner …").tag(LocationChoice.other)
                }
                .labelsHidden()
                .buttonSizing(.flexible)
                .frame(maxWidth: .infinity)

                Button { ids.remove(at: index) } label: { Image(systemName: "minus") }
                    .disabled(ids.count <= minimumCount)
                Button { addLocation(after: index) } label: { Image(systemName: "plus") }
            }
            .buttonStyle(.square)
            .padding(.trailing, 28)
        }
    }

    private func choice(at index: Int) -> Binding<LocationChoice> {
        Binding(
            get: { .location(ids[index]) },
            set: { newValue in
                switch newValue {
                case .location(let id):
                    ids[index] = id
                case .standard(let folder):
                    if let location = model.locations.requestAccess(startingAt: folder) { ids[index] = location.id }
                case .other:
                    if let location = model.locations.requestAccess() { ids[index] = location.id }
                }
            }
        )
    }

    private func addLocation(after index: Int) {
        guard let location = model.locations.requestAccess(), !ids.contains(location.id) else { return }
        ids.insert(location.id, at: index + 1)
    }
}

private enum LocationChoice: Hashable {
    case location(UUID)
    case standard(StandardFolder)
    case other
}

/// Die Finder-Farbtags als umschaltbare Filter.
private struct TagsSection: View {
    @Environment(SearchModel.self) private var model

    var body: some View {
        FlowLayout(spacing: 22, lineSpacing: 16) {
            ForEach(TagColor.allCases) { tag in
                let isOn = model.tags.contains(tag)
                Button {
                    if isOn { model.tags.remove(tag) } else { model.tags.insert(tag) }
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(tag.color.gradient)
                            .frame(width: 20, height: 20)
                            .overlay {
                                if isOn {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        Text(tag.title).font(.system(size: 16))
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .background(Capsule().fill(isOn ? tag.color.opacity(0.15) : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

/// Limit: Anzahl · Richtung · Datum, nach dem Spotlight sortiert.
private struct LimitSection: View {
    @Environment(SearchModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 10) {
            Picker("Anzahl", selection: $model.limit) {
                ForEach(ResultLimit.allCases) { Text($0.title).tag($0) }
            }
            .frame(width: 145)
            Picker("Richtung", selection: $model.sortDirection) {
                ForEach(SortDirection.allCases) { Text($0.title).tag($0) }
            }
            .frame(width: 160)
            Picker("Datum", selection: $model.sortField) {
                ForEach(SortField.allCases) { Text($0.title).tag($0) }
            }
            .frame(maxWidth: .infinity)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .buttonSizing(.flexible)
    }
}

#Preview {
    RefinePane()
        .environment(SearchModel())
        .frame(width: 560, height: 800)
}
