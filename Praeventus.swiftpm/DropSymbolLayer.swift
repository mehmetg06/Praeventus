#if canImport(SwiftUI)
import SwiftUI

struct DropSymbolLayer: View {
    let windSpeed: Double
    let intensity: Double

    private var count: Int { Int(10 + intensity * 12) }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<count, id: \.self) { index in
                        let seed = Double(index * 53 + 17)
                        let base = point(seed: seed, size: proxy.size)
                        let slide = slide(seed: seed, time: time, height: proxy.size.height)
                        let size = dropSize(seed: seed)

                        Image(systemName: "drop.fill")
                            .font(.system(size: size, weight: .ultraLight))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white.opacity(0.34), .white.opacity(0.12), .white.opacity(0.03)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(alignment: .topLeading) {
                                Ellipse()
                                    .fill(.white.opacity(0.34))
                                    .frame(width: size * 0.24, height: size * 0.08)
                                    .blur(radius: 0.7)
                                    .offset(x: size * 0.30, y: size * 0.24)
                            }
                            .shadow(color: .black.opacity(0.18), radius: 2, x: 1, y: 2)
                            .rotationEffect(.degrees(seed.truncatingRemainder(dividingBy: 10) - 5))
                            .opacity(min(0.70, 0.30 + intensity * 0.32))
                            .position(
                                x: base.x + CGFloat(windSpeed * 0.04) * slide.progress,
                                y: base.y + slide.y
                            )
                            .blendMode(.screen)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func point(seed: Double, size: CGSize) -> CGPoint {
        let xUnit = (seed * 13).truncatingRemainder(dividingBy: 997) / 997
        let yUnit = (seed * 29).truncatingRemainder(dividingBy: 733) / 733
        let edge = seed.truncatingRemainder(dividingBy: 5)
        let x: CGFloat
        if edge < 1.2 {
            x = CGFloat(0.06 + xUnit * 0.18) * size.width
        } else if edge > 3.8 {
            x = CGFloat(0.76 + xUnit * 0.18) * size.width
        } else {
            x = CGFloat(0.24 + xUnit * 0.52) * size.width
        }
        let y = CGFloat(0.07 + yUnit * 0.80) * size.height
        return CGPoint(x: x, y: y)
    }

    private func dropSize(seed: Double) -> CGFloat {
        let large = seed.truncatingRemainder(dividingBy: 6) > 4.3
        return CGFloat(large ? 24 + seed.truncatingRemainder(dividingBy: 14) : 13 + seed.truncatingRemainder(dividingBy: 8))
    }

    private func slide(seed: Double, time: Double, height: CGFloat) -> (y: CGFloat, progress: CGFloat) {
        let movable = seed.truncatingRemainder(dividingBy: 10) > 7.0
        guard movable else { return (0, 0) }
        let cycle = 18 + seed.truncatingRemainder(dividingBy: 18)
        let raw = (time + seed).truncatingRemainder(dividingBy: cycle) / cycle
        let eased = raw * raw * (3 - 2 * raw)
        return (CGFloat(eased) * height * 0.16, CGFloat(eased))
    }
}
#endif
