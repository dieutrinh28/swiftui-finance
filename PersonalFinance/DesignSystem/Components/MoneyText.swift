import SwiftUI
import FinanceDomain

/// How an amount is presented. Income and expense are distinguished by both
/// sign and colour, so the meaning never relies on colour alone.
enum AmountTone {
    /// A balance or plain amount: shown with its own sign, primary colour.
    case neutral
    /// Money in: "+", income colour. Pass an unsigned amount.
    case income
    /// Money out: "−", expense colour. Pass an unsigned amount.
    case expense
    /// Movement between own wallets: no sign, transfer colour.
    case transfer
    /// A balance that may be negative (debt): own sign, negative colour when below zero.
    case balance
    /// A transfer seen from the wallet it leaves: "−", transfer colour.
    case transferOut
    /// A transfer seen from the wallet it arrives in: "+", transfer colour.
    case transferIn
}

struct MoneyText: View {
    let money: Money
    var tone: AmountTone = .neutral
    var font: Font = .amountRow

    var body: some View {
        Text(formatted)
            .font(font)
            .foregroundStyle(color)
            .accessibilityLabel(accessibilityText)
    }

    private var base: String {
        MoneyFormatter().string(from: money)
    }

    private var formatted: String {
        switch tone {
        case .neutral, .transfer, .balance: base
        case .income, .transferIn: "+" + base
        case .expense, .transferOut: "−" + base
        }
    }

    private var color: Color {
        switch tone {
        case .neutral: AppColor.textPrimary
        case .income: AppColor.income
        case .expense: AppColor.expense
        case .transfer, .transferIn, .transferOut: AppColor.transfer
        // Debt and overdrafts: minus sign plus the negative colour, never shown as available money.
        case .balance: money.isNegative ? AppColor.negative : AppColor.textPrimary
        }
    }

    private var accessibilityText: Text {
        switch tone {
        case .neutral, .balance: Text(base)
        case .income: Text("Income \(base)")
        case .expense: Text("Expense \(base)")
        case .transfer: Text("Transfer \(base)")
        case .transferOut: Text("Transfer out \(base)")
        case .transferIn: Text("Transfer in \(base)")
        }
    }
}

#Preview {
    VStack(alignment: .trailing, spacing: Spacing.sm) {
        MoneyText(money: Money(minorUnits: 25_000_000, currency: .vnd), tone: .income)
        MoneyText(money: Money(minorUnits: 65_000, currency: .vnd), tone: .expense)
        MoneyText(money: Money(minorUnits: 2_000_000, currency: .vnd), tone: .transfer)
        MoneyText(money: Money(minorUnits: 1_999, currency: .usd))
        MoneyText(money: Money(minorUnits: -2_350_000, currency: .vnd), font: .amountHero)
    }
    .padding()
}
