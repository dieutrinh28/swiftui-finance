import SwiftUI

/// An SF Symbol on a tinted rounded square. Scales with Dynamic Type.
struct IconBadge: View {
    let systemName: String
    let tint: Color

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        IconBadge(systemName: "fork.knife", tint: .orange)
        IconBadge(systemName: "banknote", tint: .green)
        IconBadge(systemName: "creditcard", tint: .blue)
    }
    .padding()
}
