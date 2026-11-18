import SwiftUI

/// Mittlerer Bereich: Trefferliste als Tabelle oder Symbolraster.
struct ResultsPane: View {
    @Environment(SearchModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            PaneHeader(title: "Resultate") {
                sortMenu
                Picker("Darstellung", selection: $model.layout) {
                    Image(systemName: "square.grid.2x2").tag(ResultsLayout.grid)
                    Image(systemName: "list.bullet").tag(ResultsLayout.list)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            switch model.layout {
            case .list: ResultsTable()
            case .grid: ResultsGrid()
            }
        }
        .background(PaneStyle.contentBackground)
    }

    private var sortMenu: some View {
        @Bindable var model = model
        return Menu {
            Picker("Sortiert nach", selection: $model.sortField) {
                ForEach(SortField.allCases) { field in
                    Text(field == .relevance ? field.title : "Zuletzt \(field.title)").tag(field)
                }
            }
            Picker("Reihenfolge", selection: $model.sortDirection) {
                Text("Neueste zuerst").tag(SortDirection.newest)
                Text("Älteste zuerst").tag(SortDirection.oldest)
            }
            .disabled(model.sortField == .relevance)
            Divider()
            Button("Spaltensortierung aufheben") { model.tableSortOrder = [] }
                .disabled(model.tableSortOrder.isEmpty)
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sortierung")
    }
}

private struct ResultsTable: View {
    @Environment(SearchModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Table(model.displayedResults, selection: $model.selection, sortOrder: $model.tableSortOrder) {
            TableColumn("Name", value: \.name) { result in
                HStack(spacing: 6) {
                    FileIcon(url: result.url)
                    Text(result.name).lineLimit(1)
                }
            }
            .width(min: 160, ideal: 260)

            TableColumn("Art", value: \.kind)
                .width(min: 80, ideal: 130)

            TableColumn("Änderungsdatum", value: \.modifiedSortKey) { result in
                Text(result.modified?.formatted(date: .abbreviated, time: .shortened) ?? "–")
            }
            .width(min: 120, ideal: 170)

            TableColumn("Größe", value: \.sizeSortKey) { result in
                Text(result.size.map { $0.formatted(.byteCount(style: .file)) } ?? "–")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 80)
        }
        .alternatingRowBackgrounds(.enabled)
        .contextMenu(forSelectionType: SearchResult.ID.self) { ids in
            ResultContextMenu(ids: ids)
        } primaryAction: { ids in
            model.open(ids)
        }
    }
}

private struct ResultsGrid: View {
    @Environment(SearchModel.self) private var model

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 14) {
                ForEach(model.displayedResults) { result in
                    let isSelected = model.selection.contains(result.id)
                    VStack(spacing: 6) {
                        FileIcon(url: result.url, size: 64)
                        Text(result.name)
                            .font(.callout)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                            .background(RoundedRectangle(cornerRadius: 4).fill(isSelected ? Color.accentColor : .clear))
                            .foregroundStyle(isSelected ? .white : .primary)
                    }
                    .frame(width: 112, height: 112, alignment: .top)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.open([result.id]) }
                    .onTapGesture { model.selection = [result.id] }
                    .contextMenu { ResultContextMenu(ids: [result.id]) }
                }
            }
            .padding(12)
        }
    }
}

private struct ResultContextMenu: View {
    @Environment(SearchModel.self) private var model
    let ids: Set<SearchResult.ID>

    var body: some View {
        Button("Öffnen") { model.open(ids) }
        Button("Im Finder zeigen") { model.revealInFinder(ids) }
        Button("Pfad kopieren") { model.copyPaths(ids) }
        if ids.count == 1, let id = ids.first, let result = model.displayedResults.first(where: { $0.id == id }) {
            Divider()
            Button("Mit Apple Intelligence zusammenfassen") {
                model.selection = ids
                model.showsInfoPane = true
                model.infoTab = .summary
                model.summarizer.summarizeFile(result)
            }
        }
    }
}

#Preview {
    ResultsPane()
        .environment(SearchModel())
        .frame(width: 600, height: 500)
}
