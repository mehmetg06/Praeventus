#if canImport(SwiftUI)
import SwiftUI

struct ThinGlassShape: View {
    var cornerRadius: CGFloat = 28
    var intensity: Double = 0.14

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial.opacity(intensity))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.20), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
    }
}

struct GlassMetric: View {
    let symbol: String
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.82))

            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.66))

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .light, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.78))
            }
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SectionHeader: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .light))
            Text(title)
                .font(.headline.weight(.medium))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .opacity(0.62)
        }
        .foregroundStyle(.white)
    }
}
#endif
