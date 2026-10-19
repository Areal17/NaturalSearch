import AppKit
import FoundationModels
import Observation
import PDFKit

/// Lässt das On-Device-Modell die Trefferliste oder eine einzelne Datei zusammenfassen.
@MainActor
@Observable
final class ResultSummarizer {
    private(set) var text = ""
    private(set) var isRunning = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var task: Task<Void, Never>?

    /// Das Modell hat nur ~4k Token Kontext – Eingaben werden entsprechend gekürzt.
    nonisolated private static let maxResults = 40
    nonisolated private static let maxFileCharacters = 3_000

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

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func run(instructions: String, prompt: @escaping @MainActor () async throws -> String) {
        cancel()
        text = ""
        errorMessage = nil
        guard QueryParser.isAvailable else {
            errorMessage = QueryParser.availability.explanation
            return
        }
        isRunning = true
        task = Task {
            defer { isRunning = false }
            do {
                let session = LanguageModelSession(instructions: instructions)
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
