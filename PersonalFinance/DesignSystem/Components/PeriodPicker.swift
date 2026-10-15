import SwiftUI
import FinanceDomain

extension ReportingPeriod {
    static let presets: [ReportingPeriod] = [.thisWeek, .thisMonth, .lastMonth, .thisYear]

    var displayName: String {
        switch self {
        case .thisWeek: String(localized: "This week", bundle: .l10n)
        case .thisMonth: String(localized: "This month", bundle: .l10n)
        case .lastMonth: String(localized: "Last month", bundle: .l10n)
        case .thisYear: String(localized: "This year", bundle: .l10n)
        case .custom(let first, let last):
            "\(first.formatted(.dateTime.day().month(.abbreviated).locale(.app))) – \(last.formatted(.dateTime.day().month(.abbreviated).year().locale(.app)))"
        }
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }
}

/// A compact menu for choosing a reporting period, with a sheet for custom dates.
struct PeriodPicker: View {
    @Binding var selection: ReportingPeriod

    @State private var showingCustom = false
    // The start is only a default for the custom range; CalendarPolicy is not reachable here.
    @State private var customStart = Date.now.addingTimeInterval(-6 * 86_400)
    @State private var customEnd = Date.now

    var body: some View {
        Menu {
            ForEach(ReportingPeriod.presets, id: \.self) { period in
                Button {
                    selection = period
                } label: {
                    if period == selection {
                        Label(period.displayName, systemImage: "checkmark")
                    } else {
                        Text(period.displayName)
                    }
                }
            }
            Divider()
            Button {
                if case .custom(let first, let last) = selection {
                    customStart = first
                    customEnd = last
                }
                showingCustom = true
            } label: {
                if selection.isCustom {
                    Label("Custom Range…", systemImage: "checkmark")
                } else {
                    Text("Custom Range…")
                }
            }
        } label: {
            Label(selection.displayName, systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
        }
        .accessibilityLabel(Text("Period: \(selection.displayName)"))
        .sheet(isPresented: $showingCustom) {
            NavigationStack {
                Form {
                    DatePicker("From", selection: $customStart, displayedComponents: .date)
                    DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
                }
                .navigationTitle("Custom Range")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingCustom = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            selection = .custom(firstDay: customStart, lastDay: max(customStart, customEnd))
                            showingCustom = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

#Preview {
    @Previewable @State var period: ReportingPeriod = .thisMonth
    PeriodPicker(selection: $period)
}
