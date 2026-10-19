import FoundationModels

/// Allgemeine Inhaltsart einer Datei. Wird sowohl in der Oberfläche („Inhaltsart ist …“)
/// als auch vom Foundation Model (`@Generable`) verwendet.
@Generable
enum ContentKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case any
    case document
    case pdf
    case image
    case movie
    case audio
    case text
    case presentation
    case spreadsheet
    case sourceCode
    case archive
    case application
    case folder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "- Beliebig"
        case .document: "Dokument"
        case .pdf: "PDF"
        case .image: "Bild"
        case .movie: "Film"
        case .audio: "Musik"
        case .text: "Text"
        case .presentation: "Präsentation"
        case .spreadsheet: "Tabelle"
        case .sourceCode: "Quelltext"
        case .archive: "Archiv"
        case .application: "Programm"
        case .folder: "Ordner"
        }
    }

    /// Uniform Type Identifiers, gegen die `kMDItemContentTypeTree` geprüft wird.
    var contentTypes: [String] {
        switch self {
        case .any: []
        case .document: ["public.composite-content", "public.rtf", "public.plain-text"]
        case .pdf: ["com.adobe.pdf"]
        case .image: ["public.image"]
        case .movie: ["public.movie"]
        case .audio: ["public.audio"]
        case .text: ["public.text"]
        case .presentation: ["public.presentation"]
        case .spreadsheet: ["public.spreadsheet"]
        case .sourceCode: ["public.source-code"]
        case .archive: ["public.archive"]
        case .application: ["com.apple.application"]
        case .folder: ["public.folder"]
        }
    }
}
