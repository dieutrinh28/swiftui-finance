import SwiftUI
import Charts
import FinanceDomain

/// Series colours for charts.
///
/// Income/expense text keeps its green/red semantic colours, but green and red
/// can't be told apart by people with red-green colour blindness (validated:
/// ΔE 4.2 deutan). Two-series charts therefore use a blue/orange pair that
/// passes the colour-vision checks in light and dark mode, and every chart also
/// labels its series in a legend.
enum ChartPalette {
    /// Income, or the single series of a one-series chart.
    static let series1 = Color(light: 0x2A78D6, dark: 0x3987E5)
    /// Expenses.
    static let series2 = Color(light: 0xEB6834, dark: 0xD95926)
}

extension Money {
    /// For plotting only. Arithmetic always stays in `Money`.
    var chartValue: Double {
        NSDecimalNumber(decimal: majorUnits).doubleValue
    }
}

/// Y-axis labels in short form ("4M", "250K") with a recessive grid.
func compactCurrencyAxis() -> some AxisContent {
    AxisMarks(position: .leading) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
            .foregroundStyle(Color.secondary.opacity(0.3))
        AxisValueLabel {
            if let number = value.as(Double.self) {
                Text(number.formatted(.number.notation(.compactName)))
            }
        }
    }
}

/// Income and expenses per month, side by side. Tap or drag to see a month's figures.
struct MonthlyCashFlowChart: View {
    let points: [PeriodCashFlow]
    var height: CGFloat = 200

    @State private var selectedMonth: Date?

    private var incomeLabel: String { String(localized: "Income") }
    private var expenseLabel: String { String(localized: "Expenses") }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            selectionSummary
            Chart {
                ForEach(points) { point in
                    BarMark(
                        x: .value("Month", point.start, unit: .month),
                        y: .value("Amount", point.income.chartValue)
                    )
                    .foregroundStyle(by: .value("Series", incomeLabel))
                    .position(by: .value("Series", incomeLabel))
                    .cornerRadius(4)
                    .accessibilityLabel(Text(point.start.formatted(.dateTime.month(.wide).year())))
                    .accessibilityValue(Text("Income \(MoneyFormatter().string(from: point.income))"))

                    BarMark(
                        x: .value("Month", point.start, unit: .month),
                        y: .value("Amount", point.expenses.chartValue)
                    )
                    .foregroundStyle(by: .value("Series", expenseLabel))
                    .position(by: .value("Series", expenseLabel))
                    .cornerRadius(4)
                    .accessibilityLabel(Text(point.start.formatted(.dateTime.month(.wide).year())))
                    .accessibilityValue(Text("Expenses \(MoneyFormatter().string(from: point.expenses))"))
                }
                if let selected = selectedPoint {
                    RuleMark(x: .value("Month", selected.start, unit: .month))
                        .foregroundStyle(Color.secondary.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartForegroundStyleScale([incomeLabel: ChartPalette.series1, expenseLabel: ChartPalette.series2])
            .chartLegend(position: .top, alignment: .leading)
            .chartYAxis { compactCurrencyAxis() }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
            .chartXSelection(value: $selectedMonth)
            .frame(height: height)
        }
    }

    private var selectedPoint: PeriodCashFlow? {
        guard let selectedMonth else { return nil }
        return points.first { Calendar.current.isDate($0.start, equalTo: selectedMonth, toGranularity: .month) }
    }

    @ViewBuilder
    private var selectionSummary: some View {
        if let point = selectedPoint {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(point.start.formatted(.dateTime.month(.wide).year()))
                    .font(.caption.weight(.semibold))
                HStack(spacing: Spacing.md) {
                    MoneyText(money: point.income, tone: .income, font: .caption)
                    MoneyText(money: point.expenses, tone: .expense, font: .caption)
                    Text("Net \(MoneyFormatter().string(from: point.net))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Tap a month to see its figures.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// A single money series over time (net worth, cumulative spending).
struct MoneyLineChart: View {
    struct Point: Identifiable {
        let date: Date
        let value: Money
        var id: Date { date }
    }

    let points: [Point]
    let seriesName: String
    var unit: Calendar.Component = .month
    var height: CGFloat = 180

    @State private var selectedDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let point = selectedPoint {
                HStack {
                    Text(point.date.formatted(unit == .month ? .dateTime.month(.wide).year() : .dateTime.day().month()))
                    Spacer()
                    MoneyText(money: point.value, tone: .balance, font: .caption)
                }
                .font(.caption)
            } else {
                Text("Tap the chart to see a value.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Chart {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: unit),
                        y: .value(seriesName, point.value.chartValue)
                    )
                    .foregroundStyle(ChartPalette.series1)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .accessibilityLabel(Text(point.date.formatted(date: .abbreviated, time: .omitted)))
                    .accessibilityValue(Text(MoneyFormatter().string(from: point.value)))
                }
                if let point = selectedPoint {
                    RuleMark(x: .value("Date", point.date, unit: unit))
                        .foregroundStyle(Color.secondary.opacity(0.25))
                    PointMark(
                        x: .value("Date", point.date, unit: unit),
                        y: .value(seriesName, point.value.chartValue)
                    )
                    .foregroundStyle(ChartPalette.series1)
                    .symbolSize(80)
                }
            }
            .chartYAxis { compactCurrencyAxis() }
            .chartXSelection(value: $selectedDate)
            .frame(height: height)
        }
    }

    private var selectedPoint: Point? {
        guard let selectedDate else { return nil }
        return points.first { Calendar.current.isDate($0.date, equalTo: selectedDate, toGranularity: unit) }
    }
}

/// Ranked slices as labelled rows with a thin bar: easier to read than a pie,
/// and every value is printed, so nothing depends on colour.
struct BreakdownList: View {
    struct Row: Identifiable {
        let id: AmountShare.Key
        let title: String
        let systemImage: String
        let tint: Color
        let share: AmountShare
    }

    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.sm) {
                        IconBadge(systemName: row.systemImage, tint: row.tint)
                        Text(row.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: Spacing.sm)
                        VStack(alignment: .trailing, spacing: 0) {
                            MoneyText(money: row.share.amount, font: .amountDetail)
                            Text(row.share.share.formatted(.percent.precision(.fractionLength(0...1))))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    GeometryReader { proxy in
                        Capsule()
                            .fill(ChartPalette.series1)
                            .frame(width: max(4, proxy.size.width * fraction(row.share)))
                    }
                    .frame(height: 4)
                    .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func fraction(_ share: AmountShare) -> CGFloat {
        CGFloat(min(max(NSDecimalNumber(decimal: share.share).doubleValue, 0), 1))
    }
}

extension BreakdownList.Row {
    /// Builds a row for a category, wallet, "uncategorised" or "other" slice.
    static func make(
        _ share: AmountShare,
        categories: [UUID: CategorySnapshot],
        walletNames: [UUID: String] = [:]
    ) -> BreakdownList.Row {
        switch share.key {
        case .category(let id):
            let category = categories[id]
            return .init(id: share.key, title: category?.name ?? String(localized: "Unknown category"),
                         systemImage: category?.iconName ?? "questionmark.circle",
                         tint: PaletteColor(identifier: category?.colorIdentifier ?? "gray").color, share: share)
        case .wallet(let id):
            return .init(id: share.key, title: walletNames[id] ?? String(localized: "Unknown wallet"),
                         systemImage: "wallet.pass", tint: .gray, share: share)
        case .uncategorized:
            return .init(id: share.key, title: String(localized: "Uncategorized"),
                         systemImage: "questionmark.circle", tint: .gray, share: share)
        case .other:
            return .init(id: share.key, title: String(localized: "Everything else"),
                         systemImage: "ellipsis.circle", tint: .gray, share: share)
        }
    }
}
