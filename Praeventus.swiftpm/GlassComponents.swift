#if canImport(SwiftUI)
import SwiftUI

struct ThinGlassShape: View {
    var cornerRadius: CGFloat = 28
    var intensity: Double = 0.14
    var highlightOpacity: Double = 0.20
    var innerShadowOpacity: Double = 0.22
    var borderOpacity: Double = 0.26
    var tintColor: Color = .clear

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial.opacity(intensity))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tintColor.opacity(0.11))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(highlightOpacity + 0.04),
                                .white.opacity(0.05),
                                .black.opacity(innerShadowOpacity * 0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
            }
            .overlay(alignment: .topLeading) {
                RadialGradient(
                    colors: [.white.opacity(highlightOpacity * 1.1), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 240
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .black.opacity(innerShadowOpacity * 0.6)],
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
                                .white.opacity(borderOpacity + 0.18),
                                .white.opacity(borderOpacity * 0.5),
                                .black.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            }
            .shadow(color: .black.opacity(0.32), radius: 32, y: 20)
    }
}

struct GlassMetric: View {
    let symbol: String
    let title: String
    let value: String
    let unit: String
    var accent: Color = .white
    var tintColor: Color = .clear

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(accent)
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 12)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(unit)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
            }

            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.50))
                .lineLimit(1)
                .padding(.top, 3)
        }
        .padding(16)
        .frame(width: 130, height: 110, alignment: .leading)
        .background(ThinGlassShape(cornerRadius: 22, intensity: 0.13, highlightOpacity: 0.18, innerShadowOpacity: 0.20, borderOpacity: 0.22, tintColor: tintColor))
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
