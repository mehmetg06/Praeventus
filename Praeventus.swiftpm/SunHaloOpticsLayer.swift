#if canImport(SwiftUI)
import SwiftUI

struct SunHaloOpticsLayer: View {
    let windIntensity: Double
    @State private var animate = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let sunPoint = CGPoint(x: size.width * 0.84, y: size.height * 0.16)

            ZStack {
                SunCameraBloom(sunPoint: sunPoint, animate: animate)
                SunSharpStarburst(sunPoint: sunPoint, animate: animate)
                FastCameraFlare(size: size, animate: animate)
                MovingAtmosphericDust(size: size, animate: animate, windIntensity: windIntensity)
            }
            .blendMode(.screen)
            .animation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true), value: animate)
            .onAppear { animate = true }
        }
        .ignoresSafeArea()
    }
}

private struct SunCameraBloom: View {
    let sunPoint: CGPoint
    let animate: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(animate ? 0.32 : 0.20), lineWidth: 1.4)
                .frame(width: animate ? 178 : 148, height: animate ? 178 : 148)
                .blur(radius: 1.4)

            Circle()
                .stroke(Color(red: 1.0, green: 0.86, blue: 0.52).opacity(animate ? 0.24 : 0.15), lineWidth: 1.2)
                .frame(width: animate ? 270 : 230, height: animate ? 270 : 230)
                .blur(radius: 4)

            Circle()
                .stroke(Color.white.opacity(animate ? 0.15 : 0.08), lineWidth: 0.9)
                .frame(width: animate ? 410 : 350, height: animate ? 410 : 350)
                .blur(radius: 10)

            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: animate ? 118 : 104, height: animate ? 118 : 104)
                .blur(radius: 16)

            Circle()
                .fill(Color.white.opacity(0.88))
                .frame(width: animate ? 82 : 76, height: animate ? 82 : 76)
                .blur(radius: 0.35)
        }
        .position(x: sunPoint.x, y: sunPoint.y)
    }
}

private struct SunSharpStarburst: View {
    let sunPoint: CGPoint
    let animate: Bool

    var body: some View {
        ZStack {
            ray(width: 560, height: 4.0, angle: 0, opacity: 0.46)
            ray(width: 620, height: 3.2, angle: 90, opacity: 0.36)
            ray(width: 500, height: 3.2, angle: 45, opacity: 0.38)
            ray(width: 500, height: 3.2, angle: -45, opacity: 0.38)
            ray(width: 390, height: 2.2, angle: 22, opacity: 0.24)
            ray(width: 390, height: 2.2, angle: -22, opacity: 0.24)
            ray(width: 340, height: 1.8, angle: 68, opacity: 0.18)
            ray(width: 340, height: 1.8, angle: -68, opacity: 0.18)
        }
        .position(x: sunPoint.x, y: sunPoint.y)
        .rotationEffect(.degrees(animate ? 4.5 : -4.5))
    }

    private func ray(width: CGFloat, height: CGFloat, angle: Double, opacity: Double) -> some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        .clear,
                        Color.white.opacity(opacity * 0.50),
                        Color.white.opacity(opacity),
                        Color(red: 1.0, green: 0.86, blue: 0.48).opacity(opacity * 0.55),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: animate ? width * 1.12 : width * 0.92, height: height)
            .blur(radius: 0.65)
            .rotationEffect(.degrees(angle))
    }
}

private struct FastCameraFlare: View {
    let size: CGSize
    let animate: Bool

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.16),
                            Color(red: 1.0, green: 0.78, blue: 0.34).opacity(0.10),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: size.width * 0.74, height: animate ? 42 : 32)
                .blur(radius: 5)
                .rotationEffect(.degrees(-18))
                .position(x: size.width * (animate ? 0.48 : 0.43), y: size.height * (animate ? 0.285 : 0.248))

            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.22))
                .frame(width: size.width * 0.50, height: 2.4)
                .blur(radius: 0.6)
                .rotationEffect(.degrees(-18))
                .position(x: size.width * (animate ? 0.55 : 0.49), y: size.height * (animate ? 0.274 : 0.254))
        }
    }
}

private struct MovingAtmosphericDust: View {
    let size: CGSize
    let animate: Bool
    let windIntensity: Double

    var body: some View {
        ZStack {
            ForEach(0..<20, id: \.self) { index in
                dust(index: index)
            }
        }
    }

    private func dust(index: Int) -> some View {
        let side = CGFloat(1.4 + Double(index % 3) * 0.9)
        let movement = animate ? CGFloat(index % 6) * 18 : -CGFloat(index % 6) * 18
        let wind = CGFloat(windIntensity) * CGFloat(index % 4) * 6

        return Circle()
            .fill(Color(red: 1.0, green: 0.91, blue: 0.62).opacity(0.052))
            .frame(width: side, height: side)
            .blur(radius: 0.25)
            .position(
                x: size.width * dustX(index) + movement + wind,
                y: size.height * dustY(index)
            )
    }

    private func dustX(_ index: Int) -> CGFloat {
        let value = sin(Double(index * 37 + 11)) * 43758.5453
        return CGFloat(value - floor(value))
    }

    private func dustY(_ index: Int) -> CGFloat {
        let value = sin(Double(index * 53 + 17)) * 24634.6345
        return CGFloat(value - floor(value))
    }
}
#endif