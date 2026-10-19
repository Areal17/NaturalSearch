import Foundation
import FoundationModels

/// Übersetzt eine natürlichsprachliche Anfrage mit dem On-Device-Modell in eine `FileSearchQuery`.
@MainActor
final class QueryParser {
    private static let instructions = """
        Du übersetzt Suchanfragen nach Dateien auf einem Mac in eine strukturierte Spotlight-Suche.
        Antworte ausschließlich mit den Feldern der Struktur. Erfinde nichts, was nicht in der Anfrage steht.

        Beispiele:
        „PDFs über Rechnungen vom letzten Monat“ → keywords: [Rechnung], extensions: [pdf], days: 31, dateField: modified
        „Fotos vom Urlaub in Italien“ → keywords: [Urlaub, Italien], contentKind: image
        „Word-Dateien, die ich gestern geöffnet habe“ → extensions: [docx, doc], days: 2, dateField: opened
        „Präsentationen im Downloads-Ordner“ → contentKind: presentation, scope: Downloads
        „Dateien mit rotem Tag“ → tags: [red]
        „Datei namens Budget 2026“ → nameKeywords: [Budget 2026]
        """

    static var availability: SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    private var warmSession: LanguageModelSession?

    /// Lädt das Modell vorab, damit die erste Anfrage schneller antwortet.
    func prewarm() {
        guard Self.isAvailable else { return }
        let session = LanguageModelSession(instructions: Self.instructions)
        session.prewarm()
        warmSession = session
    }

    func parse(_ request: String) async throws -> FileSearchQuery {
        // Pro Anfrage eine frische Session, damit sich der Kontext nicht aufbläht.
        let session = warmSession ?? LanguageModelSession(instructions: Self.instructions)
        warmSession = nil
        let today = Date.now.formatted(date: .complete, time: .omitted)
        let prompt = "Heute ist \(today).\nAnfrage: \(request)"
        let response = try await session.respond(
            to: prompt,
            generating: FileSearchQuery.self,
            options: GenerationOptions(samplingMode: .greedy)
        )
        prewarm()
        return response.content.normalized()
    }
}

extension SystemLanguageModel.Availability {
    /// Deutsche Beschreibung für Statuszeile und Hinweise.
    var explanation: String {
        switch self {
        case .available:
            "Apple Intelligence ist bereit."
        case .unavailable(.deviceNotEligible):
            "Dieser Mac unterstützt Apple Intelligence nicht."
        case .unavailable(.appleIntelligenceNotEnabled):
            "Apple Intelligence ist in den Systemeinstellungen deaktiviert."
        case .unavailable(.modelNotReady):
            "Das Sprachmodell wird noch geladen."
        case .unavailable:
            "Apple Intelligence ist nicht verfügbar."
        }
    }
}
