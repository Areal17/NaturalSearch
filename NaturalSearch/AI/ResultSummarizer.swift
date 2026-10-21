import AppKit
import CoreSpotlight
import FoundationModels
import Observation
import PDFKit

/// Lässt das On-Device-Modell die Trefferliste oder eine einzelne Datei zusammenfassen
/// und beantwortet Fragen zum Inhalt der freigegebenen Orte über `SpotlightSearchTool`.
@MainActor
@Observable
final class ResultSummarizer {
    private(set) var text = ""
    private(set) var isRunning = false
    private(set) var errorMessage: String?
    /// Dateien, die das Spotlight-Werkzeug beim Beantworten einer Frage gefunden hat.
    private(set) var sources: [URL] = []

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var sourceTask: Task<Void, Never>?

    /// Das Modell hat nur ~4k Token Kontext – Eingaben werden entsprechend gekürzt.
    nonisolated private static let maxResults = 40
    nonisolated private static let maxFileCharacters = 3_000
    nonisolated private static let maxToolResults = 15
    nonisolated private static let maxToolResponseCharacters = 4_000

    func summarizeResults(_ results: [SearchResult], request: String) {
        let lines = results.prefix(Self.maxResults).map { result in
            let date = result.modified?.formatted(date: .numeric, time: .omitted) ?? "?"
            return "- \(result.name) (\(result.kind), geändert \(date), in \(result.folderPath))"
        }
        let prompt = """
            Suchanfrage: \(request.isEmpty ? "(keine)" : request)
            \(results.count) Treffer, die ersten \(lines.count):
            \(lines.joined(separator: "\n"))
            """
        run(
            instructions: "Fasse eine Liste von Suchtreffern auf Deutsch in 3–5 Sätzen zusammen. Nenne Muster (Themen, Ordner, Zeiträume, Dateitypen) und auffällige Einzeldateien. Keine Aufzählung aller Dateien.",
            prompt: { prompt }
        )
    }

    func summarizeFile(_ result: SearchResult) {
        let url = result.url
        run(
            instructions: "Fasse den Inhalt eines Dokuments auf Deutsch in höchstens 5 Sätzen zusammen. Nenne Art des Dokuments, Kernaussagen und wichtige Daten wie Beträge, Fristen oder Namen.",
            prompt: {
                let excerpt = await Self.extractText(from: url)
                guard !excerpt.isEmpty else { throw SummaryError.noText }
                return "Dateiname: \(url.lastPathComponent)\nInhalt (Auszug):\n\(excerpt)"
            }
        )
    }

    /// Beantwortet eine Frage zum Inhalt der Dateien in `scopes`. Das Modell sucht dafür
    /// selbst im Spotlight-Index und nutzt die gefundenen Dokumente als Kontext.
    func answerQuestion(_ question: String, scopes: [URL]) {
        var files = FileSource(fetchAttributes: [.displayName, .path, .contentURL, .kind, .contentDescription])
        files.scopes = scopes
        files.maximumResultCount = Self.maxToolResults

        // Das On-Device-Modell braucht einen `focused`-Guide im kompakten Format,
        // sonst sprengen die Suchergebnisse das Kontextfenster.
        var configuration = SpotlightSearchTool.Configuration(
            sources: [.files(files)],
            guide: SpotlightSearchTool.Guide(level: .focused(.documents), format: .compact)
        )
        configuration.maximumResponseSize = Self.maxToolResponseCharacters
        let tool = SpotlightSearchTool(configuration: configuration)

        run(
            instructions: "Beantworte Fragen zu Dateien auf diesem Mac auf Deutsch. Suche dafür immer zuerst mit dem Spotlight-Werkzeug. Stütze dich nur auf gefundene Dateien und nenne die Dateinamen, auf die sich die Antwort bezieht. Findest du nichts Passendes, sage das offen.",
            tools: [tool],
            prompt: { question },
            observeSources: { [weak self] in
                for await reply in tool.searchResults {
                    self?.collectSources(from: reply)
                }
            }
        )
    }

    func cancel() {
        task?.cancel()
        task = nil
        sourceTask?.cancel()
        sourceTask = nil
        isRunning = false
    }

    private func run(
        instructions: String,
        tools: [any Tool] = [],
        prompt: @escaping @MainActor () async throws -> String,
        observeSources: (@MainActor () async -> Void)? = nil
    ) {
        cancel()
        text = ""
        errorMessage = nil
        sources = []
        guard QueryParser.isAvailable else {
            errorMessage = QueryParser.availability.explanation
            return
        }
        isRunning = true
        // Vor der Session starten, damit keine frühe Werkzeug-Antwort verloren geht.
        let observer = observeSources.map { observe in Task { await observe() } }
        sourceTask = observer
        task = Task {
            defer {
                isRunning = false
                observer?.cancel()
            }
            do {
                let session = LanguageModelSession(tools: tools, instructions: instructions)
                let stream = session.streamResponse(to: try await prompt())
                for try await snapshot in stream {
                    text = snapshot.content
                }
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Übernimmt die Dateien aus einer Werkzeug-Antwort, ohne Duplikate und in Fundreihenfolge.
    private func collectSources(from reply: SpotlightSearchTool.SearchReply) {
        let items: [SearchableItem] = switch reply.content {
        case .items(let items): items
        case .groupedItems(let groups): groups.values.flatMap { $0 }
        case .scoredItems(let scored): scored.map(\.item)
        default: []
        }
        let known = Set(sources)
        let found = items.compactMap(Self.fileURL(of:)).filter { !known.contains($0) }
        var seen = Set<URL>()
        sources += found.filter { seen.insert($0).inserted }
    }

    /// Dateipfad eines Treffers: `contentURL`, sonst `path`, sonst der Bezeichner,
    /// der bei Dateien der absolute Pfad ist.
    private static func fileURL(of result: SearchableItem) -> URL? {
        let attributes = result.item.attributeSet
        if let url = attributes.contentURL, url.isFileURL { return url.standardizedFileURL }
        if let path = attributes.path { return URL(fileURLWithPath: path) }
        let identifier = result.item.uniqueIdentifier
        return identifier.hasPrefix("/") ? URL(fileURLWithPath: identifier) : nil
    }

    /// Liest Text aus PDF, Klartext oder Office-/RTF-Dateien – außerhalb des Main Actors.
    nonisolated private static func extractText(from url: URL) async -> String {
        let text: String
        if url.pathExtension.lowercased() == "pdf" {
            text = PDFDocument(url: url)?.string ?? ""
        } else if let plain = try? String(contentsOf: url, encoding: .utf8) {
            text = plain
        } else if let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
            text = attributed.string
        } else {
            text = ""
        }
        let condensed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(condensed.prefix(maxFileCharacters))
    }

    enum SummaryError: LocalizedError {
        case noText
        var errorDescription: String? { "Aus dieser Datei lässt sich kein Text lesen." }
    }
}
