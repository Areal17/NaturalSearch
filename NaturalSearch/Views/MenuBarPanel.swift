import SwiftUI

/// Kompakte Suche in der Menüleiste: Suchfeld, die ersten Treffer und gespeicherte Anfragen.
/// Teilt sich das `SearchModel` mit dem Hauptfenster.
struct MenuBarPanel: View {
    @Environment(SearchModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @FocusState private var isFocused: Bool

    private static let resultLimit = 8
    private static let requestLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                searchField
                scopeMenu
            }
            .padding(10)

            Divider()
            results

            if !requests.isEmpty {
                Divider()
                savedRequests
            }

            Divider()
            footer
        }
        .frame(width: 360)
        .autoSearch()
        .onAppear { isFocused = true }
    }

    // MARK: - Suchfeld

    private var searchField: some View {
        @Bindable var model = model
        return HStack(spacing: 6) {
            Image(systemName: model.mode.systemImage)
                .foregroundStyle(.secondary)
            TextField("Suche", text: $model.searchText, prompt: Text(model.mode.placeholder))
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(model.submit)
            if model.isParsing || model.spotlight.isGathering {
                ProgressView().controlSize(.small)
            }
            if !model.searchText.isEmpty {
                Button { model.reset() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .help("Suche zurücksetzen")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.15)))
    }

    // MARK: - Suchort

    /// Wählt den durchsuchten Ordner: ein freigegebener Ort, alle zusammen oder ein neuer.
    private var scopeMenu: some View {
        let store = model.locations
        return Menu {
            if store.known.count > 1 {
                Toggle("Alle freigegebenen Orte", isOn: Binding(
                    get: { Set(store.included) == Set(store.known.map(\.id)) },
                    set: { _ in store.included = store.known.map(\.id) }
                ))
                Divider()
            }
            ForEach(store.known) { location in
                Toggle(store.displayName(for: location), isOn: Binding(
                    get: { store.included == [location.id] },
                    set: { _ in store.included = [location.id] }
                ))
            }
            if !store.known.isEmpty { Divider() }
            ForEach(store.missingStandardFolders) { folder in
                Button("\(folder.title) freigeben …") { grantAccess(startingAt: folder) }
            }
            Button("Anderer Ordner …") { grantAccess(startingAt: nil) }
        } label: {
            Label(scopeTitle, systemImage: "folder")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("Ordner wählen, der durchsucht wird")
    }

    private var scopeTitle: String {
        let store = model.locations
        let included = store.included.compactMap(store.location)
        switch included.count {
        case 0: return "Ordner wählen …"
        case 1: return "Suchen in: \(store.displayName(for: included[0]))"
        default: return "Suchen in: \(included.count) Orten"
        }
    }

    /// Öffnet den Freigabe-Dialog und durchsucht danach nur den gewählten Ordner.
    private func grantAccess(startingAt folder: StandardFolder?) {
        // Ohne Aktivierung erscheint der Dialog hinter anderen Apps.
        NSApp.activate()
        if let location = model.locations.requestAccess(startingAt: folder) {
            model.locations.included = [location.id]
        }
    }

    // MARK: - Treffer

    private var results: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.displayedResults.prefix(Self.resultLimit)) { result in
                MenuBarResultRow(result: result)
            }
            HStack {
                Text(model.statusText)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .padding(6)
    }

    // MARK: - Gespeicherte und letzte Anfragen

    /// Gespeicherte Anfragen zuerst, danach zuletzt verwendete, ohne Duplikate.
    private var requests: [String] {
        let saved = model.savedQueries.queries.prefix(Self.requestLimit).map(\.text)
        let recent = model.recentRequests.filter { !saved.contains($0) }.prefix(Self.requestLimit)
        return Array((saved + recent).prefix(Self.requestLimit * 2))
    }

    private var savedRequests: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Anfragen")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.bottom, 2)
            ForEach(requests, id: \.self) { request in
                let isSaved = model.savedQueries.contains(request)
                MenuBarRowButton {
                    model.run(request: request)
                } label: {
                    Label(request, systemImage: isSaved ? "bookmark" : "clock")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .disabled(model.isParsing)
            }
        }
        .padding(6)
    }

    // MARK: - Fußzeile

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuBarRowButton(action: showMainWindow) {
                Label("Im Hauptfenster öffnen", systemImage: "macwindow")
            }
            MenuBarRowButton {
                NSApp.terminate(nil)
            } label: {
                Label("NaturalSearch beenden", systemImage: "power")
            }
        }
        .padding(6)
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }
}

/// Ein Treffer: Klick öffnet die Datei, Kontextmenü für Finder und Pfad.
private struct MenuBarResultRow: View {
    @Environment(SearchModel.self) private var model
    let result: SearchResult

    var body: some View {
        MenuBarRowButton {
            model.open([result.id])
        } label: {
            HStack(spacing: 8) {
                FileIcon(url: result.url, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(result.folderPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 4)
                if let date = result.lastOpened ?? result.modified {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .help(result.url.path)
        .contextMenu {
            Button("Öffnen") { model.open([result.id]) }
            Button("Im Finder zeigen") { model.revealInFinder([result.id]) }
            Button("Pfad kopieren") { model.copyPaths([result.id]) }
        }
    }
}

/// Zeile im Stil eines Menüeintrags mit Hover-Hervorhebung.
private struct MenuBarRowButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: Label
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.primary.opacity(0.08) : .clear)
        )
        .onHover { isHovering = $0 }
    }
}

#Preview {
    MenuBarPanel()
        .environment(SearchModel())
}
