import SwiftUI

/// Farben der drei Bereiche, angelehnt an den Finder-Suchdialog.
enum PaneStyle {
    static let headerBackground = Color(nsColor: .windowBackgroundColor)
    static let contentBackground = Color(nsColor: .controlBackgroundColor)
    static let cardBackground = Color.primary.opacity(0.035)
    static let placeholder = Color(nsColor: .tertiaryLabelColor)
}

/// Kopfzeile eines Bereichs („Verfeinern“, „Resultate“, „Info“).
struct PaneHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Spacer(minLength: 0)
            accessory
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(PaneStyle.headerBackground)
    }
}

extension PaneHeader where Accessory == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// Kleine eckige Schaltfläche für −, + und ≡ neben den Filterzeilen.
struct SquareButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(isEnabled ? Color.secondary : PaneStyle.placeholder)
            .frame(width: 22, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.12) : PaneStyle.contentBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.primary.opacity(0.12))
            )
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == SquareButtonStyle {
    static var square: SquareButtonStyle { SquareButtonStyle() }
}

/// Abgerundete Karte im Info-Bereich.
struct InfoCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(PaneStyle.cardBackground))
    }
}

/// Zeilenumbrechendes, zentriertes Layout für die Tag-Auswahl.
struct FlowLayout: Layout {
    var spacing: CGFloat = 24
    var lineSpacing: CGFloat = 14

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

extension TagColor {
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .gray: .gray
        }
    }
}

/// Dateisymbol aus dem Finder.
struct FileIcon: View {
    let url: URL
    var size: CGFloat = 16

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

#Preview {
    VStack(spacing: 16) {
        PaneHeader(title: "Resultate") {
            Button {} label: { Image(systemName: "plus") }
                .buttonStyle(.square)
        }
        InfoCard {
            HStack {
                FileIcon(url: URL(fileURLWithPath: "/Applications"), size: 32)
                Text("Programme")
            }
        }
        FlowLayout {
            ForEach(TagColor.allCases, id: \.self) { tag in
                Circle().fill(tag.color).frame(width: 14, height: 14)
            }
        }
    }
    .padding()
    .frame(width: 400)
}
