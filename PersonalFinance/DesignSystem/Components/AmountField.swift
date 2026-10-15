import SwiftUI
import FinanceDomain

/// Large amount entry with the currency beside it and live feedback below:
/// the parsed value formatted for the locale (with its sign and colour), or
/// why the input is invalid (with an icon, not colour alone).
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
                    .foregroundStyle(AppColor.textPrimary)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel(Text("Amount in \(currency.code)"))
                Text(currency.code)
                    .font(.headline)
                    .foregroundStyle(AppColor.textSecondary)
            }
            feedback
                .font(.meta)
        }
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private var feedback: some View {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            EmptyView()
        } else {
            switch Result(catching: { try AmountInputParser().parse(text, currency: currency) }) {
            case .success(let money):
                MoneyText(money: money, tone: tone, font: .meta.weight(.semibold))
            case .failure(let error):
                Label((error as? LocalizedError)?.errorDescription ?? "", systemImage: "exclamationmark.circle")
                    .foregroundStyle(AppColor.negative)
            }
        }
    }
}

#Preview {
    @Previewable @State var text = "65.000"
    @Previewable @State var invalid = "65,5"
    Form {
        AmountField(text: $text, currency: .vnd, tone: .expense)
        AmountField(text: $invalid, currency: .vnd)
    }
    .appGroupedStyle()
}
