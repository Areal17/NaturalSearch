import SwiftUI

struct ContentView: View {
    @Environment(SearchModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                if model.showsRefinePane {
                    RefinePane()
                        .frame(minWidth: 480, idealWidth: 500, maxWidth: 621)
                }
                ResultsPane()
                    .frame(minWidth: 360, maxWidth: .infinity)
                if model.showsInfoPane {
                    InfoPane()
                        .frame(minWidth: 320, idealWidth: 430, maxWidth: 560)
                }
            }
            Divider()
            StatusBar()
        }
        .toolbar { MainToolbar() }
        .toolbar(removing: .title)
        // Jede Änderung an Filtern, Orten oder Sortierung startet die Suche neu (entprellt).
        .task(id: model.searchKey) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            model.performSearch()
        }
    }
}

private struct MainToolbar: ToolbarContent {
    @Environment(SearchModel.self) private var model

    var body: some ToolbarContent {
        @Bindable var model = model

        ToolbarItemGroup(placement: .navigation) {
            Button { model.showsRefinePane.toggle() } label: { Image(systemName: "sidebar.left") }
                .help("Verfeinern ein-/ausblenden")
            Menu {
                if model.recentRequests.isEmpty {
                    Text("Noch keine Anfragen")
                }
                ForEach(model.recentRequests, id: \.self) { request in
                    Button(request) {
                        model.mode = .natural
                        model.searchText = request
                        model.submit()
                    }
                }
            } label: {
                Image(systemName: "rectangle.and.text.magnifyingglass")
            }
            .help("Letzte Anfragen")
        }

        ToolbarItem(placement: .principal) {
            SearchBar()
                .frame(minWidth: 320, idealWidth: 760, maxWidth: .infinity)
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                Button { model.showsRefinePane.toggle() } label: { Image(systemName: "rectangle.leadinghalf.inset.filled") }
                    .help("Verfeinern")
                Button {
                    let showAll = !(model.showsRefinePane || model.showsInfoPane)
                    model.showsRefinePane = showAll
                    model.showsInfoPane = showAll
                } label: { Image(systemName: "rectangle.center.inset.filled") }
                    .help("Nur Resultate")
                Button { model.showsInfoPane.toggle() } label: { Image(systemName: "rectangle.trailinghalf.inset.filled") }
                    .help("Info")
            }

            Menu {
                Button("Suche zurücksetzen", action: model.reset)
                Button("Spotlight-Abfrage kopieren", action: model.copyQueryString)
                    .disabled(model.queryString == nil)
                Divider()
                Button("Im Finder zeigen") { model.revealInFinder(model.selection) }
                    .disabled(model.selection.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }

            ShareLink(items: model.selectedResults.map(\.url)) {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(model.selection.isEmpty)
        }
    }
}

/// Großes Suchfeld mit Modus-Menü (Lupe) und ▶ zum Ausführen.
private struct SearchBar: View {
    @Environment(SearchModel.self) private var model
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                modeMenu
                TextField("Suche", text: $model.searchText, prompt: Text(model.mode.placeholder))
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit(model.submit)
                if model.isParsing {
                    ProgressView().controlSize(.small)
                }
                if !model.searchText.isEmpty {
                    Button { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isFocused ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.15), lineWidth: isFocused ? 3 : 1)
            )

            Button(action: model.submit) { Image(systemName: "play.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(model.isParsing)
                .help(model.mode == .natural ? "Anfrage mit Apple Intelligence interpretieren" : "Suchen")
        }
        .onAppear { isFocused = true }
    }

    private var modeMenu: some View {
        @Bindable var model = model
        return Menu {
            Picker("Suchmodus", selection: $model.mode) {
                ForEach(SearchMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.inline)
            if !QueryParser.isAvailable {
                Divider()
                Text(QueryParser.availability.explanation)
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: model.mode.systemImage)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private struct StatusBar: View {
    @Environment(SearchModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            if model.spotlight.isGathering || model.isParsing {
                ProgressView().controlSize(.mini)
            }
            Text(model.statusText)
            Spacer()
            if let query = model.queryString {
                Text(query)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(query)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(PaneStyle.headerBackground)
    }
}

#Preview {
    ContentView()
        .environment(SearchModel())
        .frame(width: 1500, height: 900)
}
