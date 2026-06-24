#if canImport(SwiftUI)
import SwiftUI

struct ThinGlassShape: View {
    var cornerRadius: CGFloat = 28
    var intensity: Double = 0.14
    var highlightOpacity: Double = 0.20
    var innerShadowOpacity: Double = 0.22
    var borderOpacity: Double = 0.26

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial.opacity(intensity))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(highlightOpacity),
                                .white.opacity(0.045),
                                .black.opacity(innerShadowOpacity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
            }
            .overlay(alignment: .topLeading) {
                RadialGradient(
                    colors: [.white.opacity(highlightOpacity * 0.95), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 220
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .black.opacity(innerShadowOpacity)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(borderOpacity + 0.12),
                                .white.opacity(borderOpacity * 0.42),
                                .black.opacity(0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.28), radius: 28, y: 18)
    }
}

struct GlassMetric: View {
    let symbol: String
    let title: String
    let value: String
    let unit: String
    var accent: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.56))
                Spacer(minLength: 4)
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent.opacity(0.80))
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .foregroundStyle(.white)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(ThinGlassShape(cornerRadius: 18, intensity: 0.10, highlightOpacity: 0.14, innerShadowOpacity: 0.18, borderOpacity: 0.18))
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
