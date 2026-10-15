import SwiftUI
import Charts
import FinanceDomain

/// Series colours for charts, harmonised with the pastel brand.
///
/// Income/expense text keeps its green/red semantic colours, but green and red
/// can't be told apart by people with red-green colour blindness (ΔE 4.2
/// deutan). Two-series charts therefore use a brand blue / coral pair, a mid-tone
/// step of the brand hues (pastels are too light for marks: < 3:1).
///
/// Validated with the dataviz palette checker (lightness band, chroma, CVD
/// separation, normal-vision floor, ≥ 3:1 vs surface), all PASS:
/// light on #FFFFFF: CVD ΔE 21.2 protan, normal ΔE 29.5;
/// dark on #19202A: CVD ΔE 20.6, normal ΔE 27.4.
/// Every chart also names its series in a legend.
enum ChartPalette {
    /// Income, or the single series of a one-series chart.
    static let series1 = Color(light: 0x3B7DD8, dark: 0x4C8CE2)
    /// Expenses.
    static let series2 = Color(light: 0xE0694F, dark: 0xE06E57)
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
            .foregroundStyle(AppColor.border)
        AxisValueLabel {
            if let number = value.as(Double.self) {
                Text(number.formatted(.number.notation(.compactName).locale(.app)))
            }
        }
    }
}

/// Income and expenses per month, side by side. Tap or drag to see a month's figures.
struct MonthlyCashFlowChart: View {
    let points: [PeriodCashFlow]
    var height: CGFloat = 200

    @Environment(\.calendar) private var calendar
    @State private var selectedMonth: Date?

    private var incomeLabel: String { String(localized: "Income", bundle: .l10n) }
    private var expenseLabel: String { String(localized: "Expenses", bundle: .l10n) }

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
                    .accessibilityLabel(Text(point.start.formatted(.dateTime.month(.wide).year().locale(.app))))
                    .accessibilityValue(Text("Income \(MoneyFormatter().string(from: point.income))"))

                    BarMark(
                        x: .value("Month", point.start, unit: .month),
                        y: .value("Amount", point.expenses.chartValue)
                    )
                    .foregroundStyle(by: .value("Series", expenseLabel))
                    .position(by: .value("Series", expenseLabel))
                    .cornerRadius(4)
                    .accessibilityLabel(Text(point.start.formatted(.dateTime.month(.wide).year().locale(.app))))
                    .accessibilityValue(Text("Expenses \(MoneyFormatter().string(from: point.expenses))"))
                }
                if let selected = selectedPoint {
                    RuleMark(x: .value("Month", selected.start, unit: .month))
                        .foregroundStyle(AppColor.textSecondary.opacity(0.5))
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
        return points.first { calendar.isDate($0.start, equalTo: selectedMonth, toGranularity: .month) }
    }

    @ViewBuilder
    private var selectionSummary: some View {
        if let point = selectedPoint {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(point.start.formatted(.dateTime.month(.wide).year().locale(.app)))
                    .font(.caption.weight(.semibold))
                HStack(spacing: Spacing.md) {
                    MoneyText(money: point.income, tone: .income, font: .caption)
                    MoneyText(money: point.expenses, tone: .expense, font: .caption)
                    Text("Net \(MoneyFormatter().string(from: point.net))")
                        .font(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        } else {
            Text("Tap a month to see its figures.")
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
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

    @Environment(\.calendar) private var calendar
    @State private var selectedDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let point = selectedPoint {
                HStack {
                    let style: Date.FormatStyle = unit == .month ? .dateTime.month(.wide).year() : .dateTime.day().month()
                    Text(point.date.formatted(style.locale(.app)))
                    Spacer()
                    MoneyText(money: point.value, tone: .balance, font: .caption)
                }
                .font(.caption)
            } else {
                Text("Tap the chart to see a value.")
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Chart {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: unit),
                        y: .value(seriesName, point.value.chartValue)
                    )
                    .foregroundStyle(ChartPalette.series1)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .accessibilityLabel(Text(point.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(.app))))
                    .accessibilityValue(Text(MoneyFormatter().string(from: point.value)))
                }
                if let point = selectedPoint {
                    RuleMark(x: .value("Date", point.date, unit: unit))
                        .foregroundStyle(AppColor.textSecondary.opacity(0.5))
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
        return points.first { calendar.isDate($0.date, equalTo: selectedDate, toGranularity: unit) }
    }
}

/// Ranked slices as labelled rows with a thin bar: easier to read than a pie,
/// and every value is printed, so nothing depends on colour.
/// Slices as rows with an amount, a share and a meter. A row that has
/// `details` (a category with sub-categories) opens to show them.
struct BreakdownList: View {
    struct Row: Identifiable {
        let id: AmountShare.Key
        let title: String
        let systemImage: String
        let tint: Color
        let share: AmountShare
    }

    let rows: [Row]
    /// Rows shown under a row when it is opened, keyed by the row's id.
    var details: [AmountShare.Key: [Row]] = [:]

    @State private var expanded: Set<AmountShare.Key> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(rows) { row in
                if let children = details[row.id], !children.isEmpty {
                    Button {
                        withAnimation(.snappy) {
                            if expanded.contains(row.id) { expanded.remove(row.id) } else { expanded.insert(row.id) }
                        }
                    } label: {
                        rowView(row, disclosure: expanded.contains(row.id) ? .open : .closed)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Shows the sub-categories"))
                    if expanded.contains(row.id) {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            ForEach(children) { child in rowView(child, compact: true) }
                        }
                        .padding(.leading, Spacing.xl)
                    }
                } else {
                    rowView(row)
                }
            }
        }
    }

    private enum Disclosure { case none, closed, open }

    private func rowView(_ row: Row, compact: Bool = false, disclosure: Disclosure = .none) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                IconBadge(systemName: row.systemImage, tint: row.tint, size: compact ? .small : .regular)
                Text(row.title)
                    .font(compact ? .meta : .subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                if disclosure != .none {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.textSecondary)
                        .rotationEffect(.degrees(disclosure == .open ? 0 : -90))
                        .accessibilityHidden(true)
                }
                Spacer(minLength: Spacing.sm)
                VStack(alignment: .trailing, spacing: 0) {
                    MoneyText(money: row.share.amount, font: .amountDetail)
                    Text(row.share.share.formatted(.percent.precision(.fractionLength(0...1)).locale(.app)))
                        .font(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .layoutPriority(1)
            }
            MeterBar(fraction: Double(fraction(row.share)), tint: compact ? ChartPalette.series1.opacity(0.6) : ChartPalette.series1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
            return .init(id: share.key, title: category?.name ?? String(localized: "Unknown category", bundle: .l10n),
                         systemImage: category?.iconName ?? "questionmark.circle",
                         tint: PaletteColor(identifier: category?.colorIdentifier ?? "gray").color, share: share)
        case .wallet(let id):
            return .init(id: share.key, title: walletNames[id] ?? String(localized: "Unknown wallet", bundle: .l10n),
                         systemImage: "wallet.pass", tint: .gray, share: share)
        case .uncategorized:
            return .init(id: share.key, title: String(localized: "Uncategorized", bundle: .l10n),
                         systemImage: "questionmark.circle", tint: .gray, share: share)
        case .other:
            return .init(id: share.key, title: String(localized: "Everything else", bundle: .l10n),
                         systemImage: "ellipsis.circle", tint: .gray, share: share)
        }
    }
}
