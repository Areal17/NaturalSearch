import AppIntents

/// Kurzbefehl-Aktion: übergibt eine Anfrage an NaturalSearch und führt die Suche aus –
/// wie Return im Suchfeld.
///
/// Der Typname ist ein öffentlicher Vertrag: gespeicherte Kurzbefehle verweisen darauf.
struct SearchFilesIntent: AppIntent {
    static let title: LocalizedStringResource = "Dateien suchen"
    static let description = IntentDescription(
        "Sucht mit NaturalSearch nach Dateien. Die Anfrage wird wie im Suchfeld von Apple Intelligence interpretiert."
    )

    // Die App muss nach vorn, bevor gesucht wird; der Suchzustand lebt im Hauptprozess.
    static var supportedModes: IntentModes { .foreground }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Anfrage", description: "z. B. „PDFs über Rechnungen vom letzten Monat“")
    var request: String

    @Dependency private var model: SearchModel

    static var parameterSummary: some ParameterSummary {
        Summary("Suche nach \(\.$request)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        // Wertabfrage vor jeder Änderung am Modell – perform() startet danach neu.
        guard !trimmed.isEmpty else {
            throw $request.needsValueError("Wonach soll gesucht werden?")
        }

        if QueryParser.isAvailable {
            model.run(request: trimmed)
        } else {
            // Ohne Apple Intelligence als beliebigen Text suchen, statt zu scheitern.
            model.mode = .anyText
            model.searchText = trimmed
            model.submit()
        }
        return .result()
    }
}
