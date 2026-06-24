#if canImport(SwiftUI)
import SwiftUI

struct SunHaloOpticsLayer: View {
    let windIntensity: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 14.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let sun = CGPoint(x: size.width * 0.84, y: size.height * 0.16)
                let pulse = CGFloat((sin(t * 0.38) + 1) * 0.5)

                // Soft halo rings around the sun.
                for index in 0..<3 {
                    let radius = CGFloat(160 + index * 78) + pulse * CGFloat(14 + index * 6)
                    let rect = CGRect(x: sun.x - radius / 2, y: sun.y - radius / 2, width: radius, height: radius)
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(Color.white.opacity(0.13 - Double(index) * 0.030)),
                        lineWidth: CGFloat(1.1 + index) * 0.55
                    )
                }

                // Diagonal optical streak that feels like light catching the camera glass.
                let streakHeight: CGFloat = 52 + pulse * 10
                let streakRect = CGRect(x: size.width * 0.13, y: size.height * 0.245 + pulse * 8, width: size.width * 0.64, height: streakHeight)
                context.fill(
                    Path(roundedRect: streakRect, cornerRadius: 34),
                    with: .linearGradient(
                        Gradient(colors: [
                            .clear,
                            Color.white.opacity(0.075),
                            Color(red: 1.0, green: 0.78, blue: 0.34).opacity(0.052),
                            .clear
                        ]),
                        startPoint: CGPoint(x: streakRect.minX, y: streakRect.midY),
                        endPoint: CGPoint(x: streakRect.maxX, y: streakRect.midY)
                    )
                )

                // Moving scatter beams from sun toward the lower-left atmosphere.
                for index in 0..<6 {
                    let wave = CGFloat(sin(t * (0.12 + Double(index) * 0.02))) * (7 + CGFloat(index))
                    var path = Path()
                    let startY = sun.y + CGFloat(index) * 16 - 36
                    path.move(to: CGPoint(x: sun.x - 22, y: startY))
                    path.addLine(to: CGPoint(x: -size.width * 0.08, y: size.height * (0.31 + CGFloat(index) * 0.095) + wave))
                    path.addLine(to: CGPoint(x: -size.width * 0.08, y: size.height * (0.38 + CGFloat(index) * 0.098) - wave * 0.7))
                    path.addLine(to: CGPoint(x: sun.x + 22, y: startY + 26))
                    path.closeSubpath()
                    context.fill(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [
                                Color.white.opacity(0.052 - Double(index) * 0.004),
                                Color(red: 1.0, green: 0.78, blue: 0.38).opacity(0.032 - Double(index) * 0.0025),
                                .clear
                            ]),
                            startPoint: sun,
                            endPoint: CGPoint(x: 0, y: size.height * 0.78)
                        )
                    )
                }

                // Tiny floating dust/sparkle particles inside the bright air.
                for index in 0..<18 {
                    let seed = Double(index * 37 + 11)
                    let rawX = sin(seed) * 43758.5453
                    let rawY = sin(seed * 1.7) * 24634.6345
                    let x = CGFloat(rawX - floor(rawX)) * size.width
                    let y = CGFloat(rawY - floor(rawY)) * size.height
                    let drift = CGFloat(sin(t * 0.15 + seed)) * (10 + CGFloat(windIntensity) * 15)
                    let r = CGFloat(1.0 + seed.truncatingRemainder(dividingBy: 2.0))
                    context.fill(
                        Path(ellipseIn: CGRect(x: x + drift, y: y, width: r, height: r)),
                        with: .color(Color(red: 1.0, green: 0.91, blue: 0.62).opacity(0.018))
                    )
                }
            }
        }
        .blur(radius: 1.3)
        .blendMode(.screen)
        .ignoresSafeArea()
    }
}
#endif