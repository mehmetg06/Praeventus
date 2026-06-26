#if canImport(SwiftUI)
import SwiftUI

struct ThinGlassShape: View {
    var cornerRadius: CGFloat = 24

    @Environment(\.performanceMode) private var performanceMode

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        glassFill
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.4), location: 0.0),
                            .init(color: .clear, location: 0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
            }
            // Performance mode drops the costly blur-backed material + shadow.
            .shadow(color: .black.opacity(performanceMode ? 0 : 0.15), radius: performanceMode ? 0 : 15, y: performanceMode ? 0 : 8)
    }

    @ViewBuilder
    private var glassFill: some View {
        if performanceMode {
            shape.fill(Color.white.opacity(0.08))
        } else {
            shape.fill(Material.ultraThinMaterial)
        }
    }
}

struct VisionGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    @ViewBuilder let content: Content

    @State private var isBreathing = false
    @Environment(\.performanceMode) private var performanceMode
    @Environment(\.sandboxAnimationSpeed) private var animSpeed

    var body: some View {
        content
            .background(
                ThinGlassShape(
                    cornerRadius: cornerRadius
                )
            )
            .scaleEffect(isBreathing ? 1.01 : 0.99)
            .onAppear {
                // Skip the perpetual scale animation in performance mode.
                guard !performanceMode else { return }
                withAnimation(.easeInOut(duration: 4.0 / animSpeed).repeatForever(autoreverses: true)) {
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

    var body: some View {
        VisionGlassCard(cornerRadius: 24) {
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
