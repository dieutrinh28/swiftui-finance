import SwiftUI

/// A rounded progress meter on a muted track. Purely visual: the caller always
/// shows the same value as text (spent / remaining / percent), so the meaning
/// never depends on the bar or its colour.
struct MeterBar: View {
    /// 0…1; values outside are clamped.
    let fraction: Double
    var tint: Color = AppColor.accent

    @ScaledMetric(relativeTo: .body) private var height = ComponentSize.meterHeight

    var body: some View {
        Capsule()
            .fill(AppColor.surfaceMuted)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * clamped)
                }
            }
            .frame(height: height)
            .clipShape(Capsule())
            .accessibilityHidden(true)
    }

    private var clamped: CGFloat {
        CGFloat(min(max(fraction, 0), 1))
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        MeterBar(fraction: 0.35, tint: AppColor.positive)
        MeterBar(fraction: 0.85, tint: AppColor.warning)
        MeterBar(fraction: 1.2, tint: AppColor.negative)
    }
    .padding(Spacing.screen)
}
