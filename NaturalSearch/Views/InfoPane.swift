import Quartz
import SwiftUI

/// Rechter Bereich: Info · Vorschau · Zusammenfassung
struct InfoPane: View {
    @Environment(SearchModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            PaneHeader(title: "Info") {
                Picker("Ansicht", selection: $model.infoTab) {
                    ForEach(InfoTab.allCases) { tab in
                        Image(systemName: tab.systemImage).help(tab.help).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            switch model.infoTab {
            case .info:
                ScrollView { InfoDetails(results: model.selectedResults).padding(8) }
            case .preview:
                PreviewTab(result: model.selectedResults.count == 1 ? model.selectedResults.first : nil)
            case .summary:
                SummaryTab()
            }
        }
        .background(PaneStyle.contentBackground)
    }
}

private struct InfoDetails: View {
    let results: [SearchResult]

    private var single: SearchResult? { results.count == 1 ? results.first : nil }
    private let none = "Nichts ausgewählt"

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                InfoCard {
                    HStack(spacing: 12) {
                        icon
                        VStack(alignment: .leading, spacing: 6) {
                            value(title, font: .title3)
                            value(subtitle)
                        }
                    }
                }
                InfoCard {
                    value(sizeText, font: .title3)
                    value(results.isEmpty ? none : "Größe")
                }
                .frame(width: 150)
            }
            .fixedSize(horizontal: false, vertical: true)

            InfoCard {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 14) {
                    dateRow("Erstellt", single?.created)
                    dateRow("Geändert", single?.modified)
                    dateRow("Geöffnet", single?.lastOpened)
                }
            }
            labeledCard("Wo", single?.folderPath)
            labeledCard("Kommentare", single?.comment)
            InfoCard {
                Text("Tags").foregroundStyle(.secondary)
                if let tags = single?.tags, !tags.isEmpty {
                    HStack { ForEach(tags, id: \.self, content: TagChip.init) }
                }
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let single {
            FileIcon(url: single.url, size: 44)
        } else {
            Image(systemName: results.isEmpty ? "doc" : "doc.on.doc")
                .font(.system(size: 30, weight: .thin))
                .foregroundStyle(PaneStyle.placeholder)
                .frame(width: 44)
        }
    }

    private var title: String {
        if let single { return single.name }
        return results.isEmpty ? none : "\(results.count) Objekte"
    }

    private var subtitle: String {
        if let single { return single.kind }
        return results.isEmpty ? none : "Mehrere Objekte"
    }

    private var sizeText: String {
        guard !results.isEmpty else { return none }
        let bytes = results.compactMap(\.size).reduce(0, +)
        return bytes.formatted(.byteCount(style: .file))
    }

    private func value(_ text: String, font: Font = .body) -> some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(results.isEmpty ? PaneStyle.placeholder : (font == .body ? .secondary : .primary))
    }

    private func dateRow(_ label: String, _ date: Date?) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(single == nil ? none : (date?.formatted(date: .long, time: .shortened) ?? "–"))
                .foregroundStyle(single == nil ? PaneStyle.placeholder : .primary)
        }
    }

    private func labeledCard(_ label: String, _ text: String?) -> some View {
        InfoCard {
            Text(label).foregroundStyle(.secondary)
            if let text, !text.isEmpty {
                Text(text).textSelection(.enabled)
            }
        }
    }
}

private struct TagChip: View {
    let name: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(TagColor(tagName: name)?.color ?? .secondary)
                .frame(width: 10, height: 10)
            Text(name)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

private struct PreviewTab: View {
    let result: SearchResult?

    var body: some View {
        if let result {
            QuickLookPreview(url: result.url)
        } else {
            ContentUnavailableView("Keine Vorschau", systemImage: "eye.slash", description: Text("Wähle genau einen Treffer aus."))
        }
    }
}

/// `QLPreviewView` aus Quartz, eingebettet in SwiftUI.
private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? URL) != url {
            view.previewItem = url as NSURL
        }
    }
}

/// Zusammenfassung der Treffer oder einer Datei durch das On-Device-Modell.
private struct SummaryTab: View {
    @Environment(SearchModel.self) private var model

    var body: some View {
        let summarizer = model.summarizer
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Treffer zusammenfassen") {
                    summarizer.summarizeResults(model.displayedResults, request: model.searchText)
                }
                .disabled(model.displayedResults.isEmpty)
                Button("Auswahl zusammenfassen") {
                    if let result = model.selectedResults.first { summarizer.summarizeFile(result) }
                }
                .disabled(model.selectedResults.count != 1)
                Spacer()
                if summarizer.isRunning {
                    ProgressView().controlSize(.small)
                    Button("Stopp", action: summarizer.cancel)
                }
            }
            .disabled(!QueryParser.isAvailable)

            if !QueryParser.isAvailable {
                Label(QueryParser.availability.explanation, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
            if let error = summarizer.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            ScrollView {
                Text(summarizer.text.isEmpty && !summarizer.isRunning ? "Apple Intelligence fasst die Trefferliste oder ein einzelnes Dokument zusammen – vollständig auf diesem Mac." : summarizer.text)
                    .foregroundStyle(summarizer.text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

#Preview {
    InfoPane()
        .environment(SearchModel())
        .frame(width: 430, height: 700)
}
