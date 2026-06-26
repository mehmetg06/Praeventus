#if canImport(SwiftUI)
import SwiftUI

struct ThinGlassShape: View {
    var cornerRadius: CGFloat = 24
    var intensity: Double = 0.14
    var highlightOpacity: Double = 0.20
    var innerShadowOpacity: Double = 0.22
    var borderOpacity: Double = 0.26
    var tintColor: Color = .clear

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        shape
            .fill(Material.ultraThinMaterial)
            // Colour-forward wash so the glass picks up the sky/palette instead of going flat grey.
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            tintColor.opacity(0.18),
                            tintColor.opacity(0.06),
                            .white.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            // Specular sheen across the upper portion — the glossy "reflection" catching the light.
            .overlay(alignment: .top) {
                shape.fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(highlightOpacity + 0.34),
                            .white.opacity(highlightOpacity * 0.5),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .blendMode(.screen)
            }
            // Bright top-left light catch for a wet-glass highlight.
            .overlay(alignment: .topLeading) {
                RadialGradient(
                    colors: [.white.opacity(highlightOpacity * 1.5), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 200
                )
                .blendMode(.screen)
                .clipShape(shape)
            }
            // Gentle inner shade at the base for depth (kept subtle to avoid greying the card).
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .black.opacity(innerShadowOpacity * 0.30)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(shape)
            }
            // Glossy rim that brightens at the top edge and fades around the body.
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.60),
                            .clear,
                            .white.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.15), radius: 15, y: 8)
    }
}

struct VisionGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var tintColor: Color = .clear
    @ViewBuilder let content: Content

    @State private var isBreathing = false

    var body: some View {
        content
            .background(
                ThinGlassShape(
                    cornerRadius: cornerRadius,
                    tintColor: tintColor
                )
            )
            .scaleEffect(isBreathing ? 1.01 : 0.99)
            .onAppear {
                withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
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
        VisionGlassCard(cornerRadius: 24, tintColor: tintColor) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 9) {
                    ZStack {
                        Circle()
                            .fill(accent.opacity(0.18))
                            .frame(width: 38, height: 38)
                        Image(systemName: symbol)
                            .font(.system(size: 16, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(accent)
                    }
                    Text(title)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 14)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(unit)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        }
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
