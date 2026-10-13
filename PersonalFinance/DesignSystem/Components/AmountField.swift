import SwiftUI
import FinanceDomain

/// Large amount entry with the currency code beside it and live feedback:
/// the parsed value formatted for the locale, or why the input is invalid.
struct AmountField: View {
    @Binding var text: String
    let currency: CurrencyDefinition
    var tone: AmountTone = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                TextField("0", text: $text)
                    .keyboardType(currency.minorUnitDigits == 0 ? .numberPad : .decimalPad)
                    .font(.amountHero)
                    .accessibilityLabel(Text("Amount in \(currency.code)"))
                Text(currency.code)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            feedback
                .font(.footnote)
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            EmptyView()
        } else {
            switch Result(catching: { try AmountInputParser().parse(text, currency: currency) }) {
            case .success(let money):
                MoneyText(money: money, tone: tone, font: .footnote)
            case .failure(let error):
                Text((error as? LocalizedError)?.errorDescription ?? "")
                    .foregroundStyle(AppColor.expense)
            }
        }
    }
}

#Preview {
    @Previewable @State var text = "65.000"
    Form {
        AmountField(text: $text, currency: .vnd, tone: .expense)
    }
}
