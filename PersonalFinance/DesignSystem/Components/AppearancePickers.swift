import SwiftUI

/// SF Symbols offered when customising wallets and categories.
enum SymbolCatalog {
    static let wallets = [
        "banknote", "building.columns", "creditcard", "iphone", "archivebox",
        "chart.line.uptrend.xyaxis", "wallet.pass", "dollarsign.circle", "bag",
        "briefcase", "house", "car", "gift", "star",
    ]

    static let categories = [
        "fork.knife", "cup.and.saucer", "cart", "bag", "house", "car", "bus", "fuelpump",
        "airplane", "bolt", "drop", "wifi", "phone", "cross.case", "pills", "figure.run",
        "dumbbell", "graduationcap", "book", "tv", "gamecontroller", "music.note", "film",
        "scissors", "tshirt", "gift", "heart", "pawprint", "figure.2.and.child.holdinghands",
        "wrench.and.screwdriver", "banknote", "laptopcomputer", "briefcase",
        "chart.line.uptrend.xyaxis", "plus.circle", "ellipsis.circle",
    ]
}

struct SymbolPicker: View {
    @Binding var selection: String
    let symbols: [String]
    let tint: Color

    @ScaledMetric(relativeTo: .body) private var cell: CGFloat = 44

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: cell), spacing: Spacing.sm)], spacing: Spacing.sm) {
            ForEach(symbols, id: \.self) { symbol in
                let isSelected = symbol == selection
                Button {
                    selection = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(isSelected ? tint : .secondary)
                        .frame(width: cell, height: cell)
                        .background(isSelected ? tint.opacity(0.15) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(isSelected ? tint : Color.clear, lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(symbol.replacingOccurrences(of: ".", with: " ")))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

struct PalettePicker: View {
    @Binding var selection: String

    @ScaledMetric(relativeTo: .body) private var dot: CGFloat = 32

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: dot + 8), spacing: Spacing.sm)], spacing: Spacing.sm) {
            ForEach(PaletteColor.allCases) { palette in
                let isSelected = palette.rawValue == selection
                Button {
                    selection = palette.rawValue
                } label: {
                    Circle()
                        .fill(palette.color)
                        .frame(width: dot, height: dot)
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(4)
                        .overlay {
                            Circle().strokeBorder(isSelected ? palette.color : Color.clear, lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(palette.rawValue.capitalized))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

#Preview {
    @Previewable @State var symbol = "banknote"
    @Previewable @State var color = "green"
    Form {
        Section { SymbolPicker(selection: $symbol, symbols: SymbolCatalog.wallets, tint: PaletteColor(identifier: color).color) }
        Section { PalettePicker(selection: $color) }
    }
}
