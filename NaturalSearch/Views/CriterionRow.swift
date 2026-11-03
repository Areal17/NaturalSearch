import SwiftUI

/// Eine Filterzeile: Attribut · Operator · Wert · − + ≡
struct CriterionRow: View {
    @Binding var criterion: SearchCriterion
    let canRemove: Bool
    let onAdd: () -> Void
    let onRemove: () -> Void
    let onDuplicate: () -> Void
    let onAddGroup: () -> Void
    let onWrapInGroup: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("Attribut", selection: $criterion.attribute) {
                ForEach(SearchAttribute.allCases) { Text($0.title).tag($0) }
            }
            .frame(width: 140)

            Picker("Operator", selection: $criterion.op) {
                ForEach(criterion.attribute.operators) { Text($0.title).tag($0) }
            }
            .frame(width: 140)

            valueField
                .frame(minWidth: 90, maxWidth: .infinity, alignment: .leading)

            rowButtons
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .buttonSizing(.flexible)
        .controlSize(.regular)
    }

    @ViewBuilder
    private var valueField: some View {
        switch criterion.attribute.valueKind {
        case .text:
            TextField("Wert", text: $criterion.value, prompt: Text(""))
                .textFieldStyle(.roundedBorder)
        case .fileExtension:
            ExtensionField(text: $criterion.value)
        case .contentKind:
            Picker("Inhaltsart", selection: $criterion.contentKind) {
                ForEach(ContentKind.allCases) { Text($0.title).tag($0) }
            }
        case .days:
            unitField(unit: "Tage", hidden: !criterion.op.needsValue)
        case .megabytes:
            unitField(unit: "MB", hidden: false)
        }
    }

    private func unitField(unit: String, hidden: Bool) -> some View {
        HStack(spacing: 6) {
            TextField("Wert", text: $criterion.value)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
            Text(unit).foregroundStyle(.secondary)
        }
        .opacity(hidden ? 0 : 1)
    }

    private var rowButtons: some View {
        HStack(spacing: 6) {
            Button(action: onRemove) { Image(systemName: "minus") }
                .disabled(!canRemove)
                .help("Zeile entfernen")
            Button(action: onAdd) { Image(systemName: "plus") }
                .help("Zeile hinzufügen")
            optionsMenu
        }
        .buttonStyle(.square)
    }

    private var optionsMenu: some View {
        Menu {
            Toggle("Nicht (Bedingung umkehren)", isOn: $criterion.isNegated)
            Toggle("Groß-/Kleinschreibung beachten", isOn: $criterion.isCaseSensitive)
            Toggle("Diakritische Zeichen beachten", isOn: $criterion.isDiacriticSensitive)
            Divider()
            Button("Zeile duplizieren", action: onDuplicate)
            Divider()
            Button("Gruppe hinzufügen", action: onAddGroup)
            Button("In Gruppe einschließen", action: onWrapInGroup)
        } label: {
            OptionsMenuLabel(isHighlighted: criterion.isNegated)
        }
        .optionsMenuStyle()
        .help("Optionen")
    }
}

/// Das ≡-Symbol der Options-Menüs von Zeilen und Gruppen.
struct OptionsMenuLabel: View {
    let isHighlighted: Bool

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(isHighlighted ? Color.accentColor : .secondary)
            .frame(width: 22, height: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(PaneStyle.contentBackground))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12)))
    }
}

extension View {
    /// Darstellung der ≡-Menüs: schlichter Knopf ohne Pfeil.
    func optionsMenuStyle() -> some View {
        menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
    }
}

/// Verknüpfung zwischen zwei Filterzeilen: und · oder
struct ConnectorPicker: View {
    @Binding var connector: LogicalConnector

    var body: some View {
        HStack(spacing: 8) {
            line
            Picker("Verknüpfung", selection: $connector) {
                ForEach(LogicalConnector.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("„und“ bindet stärker als „oder“: A und B oder C = (A und B) oder C")
            line
        }
    }

    private var line: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(height: 1)
    }
}

/// Textfeld mit Auswahlmenü gängiger Endungen (wie eine Combo-Box).
private struct ExtensionField: View {
    @Binding var text: String
    private static let suggestions = ["pdf", "docx", "xlsx", "pptx", "pages", "numbers", "key", "txt", "md", "rtf", "jpg", "png", "heic", "mov", "mp4", "zip", "swift"]

    var body: some View {
        HStack(spacing: 0) {
            TextField("Endung", text: $text, prompt: Text(""))
                .textFieldStyle(.plain)
                .padding(.leading, 6)
            Menu {
                ForEach(Self.suggestions, id: \.self) { ext in
                    Button(ext) { text = ext }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15)))
    }
}

#Preview {
    @Previewable @State var criteria = SearchCriterion.defaultSet
    VStack(spacing: 8) {
        ForEach($criteria) { $criterion in
            if criterion.id != criteria.first?.id {
                ConnectorPicker(connector: $criterion.connector)
            }
            CriterionRow(
                criterion: $criterion, canRemove: criteria.count > 1,
                onAdd: {}, onRemove: {}, onDuplicate: {}, onAddGroup: {}, onWrapInGroup: {}
            )
        }
    }
    .padding()
    .frame(width: 560)
}
