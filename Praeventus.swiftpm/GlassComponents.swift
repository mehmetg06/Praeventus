#if canImport(SwiftUI)
import SwiftUI

/// Non-observable scroll-offset holder shared between `HomeView`'s `ScrollView`
/// and `AtmosphereBackgroundView` (instantiated one level up in the view tree,
/// in `PraeventusRootView`). Conforms to `ObservableObject` so mutating
/// `value` triggers immediate redrawing of observed background layers at 60/120fps,
/// while keeping low-rate updates when idle.
@MainActor
final class ScrollOffsetTracker: ObservableObject {
    @Published var value: CGFloat = 0
}

/// Reports the home scroll content's offset (via a zero-height `GeometryReader`)
/// up to `HomeView`'s `.onPreferenceChange`, using the classic iOS-17-compatible
/// pattern (the newer `onScrollGeometryChange` API requires iOS 18+).
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// The shared "Liquid Glass" recipe: material fill, a top-leading specular
/// highlight, a fainter bottom-trailing counter-highlight (real refractive
/// glass/visionOS panels catch light on two edges, not one), a thin dark
/// refraction rim just inside the border to suggest thickness, an optional
/// low-opacity ambient tint, and a drop shadow to read as floating. Generic
/// over `Shape` so both card-style rounded rectangles (`ThinGlassShape`) and
/// the pill-shaped dock (`ThinGlassCapsule`) share one implementation instead
/// of hand-copying the same overlay stack.
struct ThinGlassBackground<S: InsettableShape>: View {
    var shape: S
    /// Low-opacity ambient tint layered under the material. Defaults to
    /// `.white`, which is skipped entirely — existing call sites render
    /// pixel-identical to before unless a caller opts into a weather-mood tint.
    var tint: Color = .white
    /// Shadow tuning — defaults match the original card recipe. The dock
    /// passes a heavier shadow so it reads as floating above the cards.
    var shadowOpacity: Double = 0.40
    var shadowRadius: CGFloat = 10
    var shadowY: CGFloat = 8

    @Environment(\.performanceMode) private var performanceMode

    var body: some View {
        glassFill
            .overlay {
                // Primary specular highlight — top-leading edge light catch.
                shape.strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.62), location: 0.0),
                            .init(color: .white.opacity(0.14), location: 0.20),
                            .init(color: .clear, location: 0.48)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: performanceMode ? 0 : 0.85
                )
            }
            .overlay {
                // Secondary counter-highlight — bottom-trailing edge, fainter.
                if !performanceMode {
                    shape.strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.18), location: 0.0),
                                .init(color: .clear, location: 0.35)
                            ],
                            startPoint: .bottomTrailing,
                            endPoint: .topLeading
                        ),
                        lineWidth: 0.6
                    )
                }
            }
            .overlay {
                // Refraction rim — soft dark inner edge suggesting glass thickness.
                if !performanceMode {
                    shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 1.25)
                }
            }
            // Performance mode drops the costly blur-backed material + shadow.
            .shadow(color: .black.opacity(performanceMode ? 0 : shadowOpacity), radius: performanceMode ? 0 : shadowRadius, x: 0, y: performanceMode ? 0 : shadowY)
    }

    @ViewBuilder
    private var glassFill: some View {
        if performanceMode {
            shape.fill(Color.white.opacity(0.08))
        } else {
            shape.fill(Material.ultraThinMaterial)
                .overlay {
                    if tint != .white {
                        shape.fill(tint.opacity(0.05))
                    }
                }
        }
    }
}

struct ThinGlassShape: View {
    var cornerRadius: CGFloat = 24
    var tint: Color = .white

    var body: some View {
        ThinGlassBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint)
    }
}

/// Pill-shaped counterpart to `ThinGlassShape`, sharing the same glass recipe —
/// used by the floating dock instead of a hand-copied capsule background.
struct ThinGlassCapsule: View {
    var tint: Color = .white
    var shadowOpacity: Double = 0.40
    var shadowRadius: CGFloat = 10
    var shadowY: CGFloat = 8

    var body: some View {
        ThinGlassBackground(shape: Capsule(style: .continuous), tint: tint,
                            shadowOpacity: shadowOpacity, shadowRadius: shadowRadius, shadowY: shadowY)
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
            // Opacity, not scaleEffect: scaling a view backed by `.ultraThinMaterial`
            // forces the compositor to re-rasterize that blur every frame for the
            // whole animation, whereas opacity is a single alpha-multiply on the
            // already-cached texture (same reasoning as the background's "breathe"
            // animation in AtmosphereBackgroundView).
            .opacity(isBreathing ? 1.0 : 0.94)
            .onAppear {
                // Skip the perpetual breathing animation in performance mode.
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
