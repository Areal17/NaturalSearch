import FoundationModels

/// Die sieben Finder-Farbtags. Spotlight speichert sie unter ihrem lokalisierten Namen
/// in `kMDItemUserTags`.
@Generable
enum TagColor: String, CaseIterable, Identifiable, Codable, Sendable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case gray

    var id: String { rawValue }

    /// Name des Tags, wie er im Finder (deutsch) heißt und in Spotlight steht.
    var title: String {
        switch self {
        case .red: "Rot"
        case .orange: "Orange"
        case .yellow: "Gelb"
        case .green: "Grün"
        case .blue: "Blau"
        case .purple: "Lila"
        case .gray: "Grau"
        }
    }

    init?(tagName: String) {
        guard let match = Self.allCases.first(where: { $0.title.localizedCaseInsensitiveCompare(tagName) == .orderedSame }) else {
            return nil
        }
        self = match
    }
}
