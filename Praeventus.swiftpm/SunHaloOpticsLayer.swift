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
                SunHaloRings(sunPoint: sunPoint, animate: animate)
                CameraStarburst(sunPoint: sunPoint, animate: animate)
                CameraFlareStreak(size: size, animate: animate)
                SunDustParticles(size: size, animate: animate, windIntensity: windIntensity)
            }
            .blendMode(.screen)
            .animation(.easeInOut(duration: 7.5).repeatForever(autoreverses: true), value: animate)
            .onAppear { animate = true }
        }
        .ignoresSafeArea()
    }
}

private struct SunHaloRings: View {
    let sunPoint: CGPoint
    let animate: Bool

    var body: some View {
        ZStack {
            halo(base: 150, grow: 24, opacity: 0.28, blur: 3, lineWidth: 1.2)
            halo(base: 220, grow: 34, opacity: 0.20, blur: 8, lineWidth: 1.0)
            halo(base: 330, grow: 46, opacity: 0.14, blur: 16, lineWidth: 0.9)
            halo(base: 470, grow: 62, opacity: 0.08, blur: 28, lineWidth: 0.8)
        }
    }

    private func halo(base: CGFloat, grow: CGFloat, opacity: Double, blur: CGFloat, lineWidth: CGFloat) -> some View {
        Circle()
            .stroke(Color.white.opacity(opacity), lineWidth: lineWidth)
            .frame(width: base + (animate ? grow : 0), height: base + (animate ? grow : 0))
            .blur(radius: blur)
            .position(x: sunPoint.x, y: sunPoint.y)
    }
}

private struct CameraStarburst: View {
    let sunPoint: CGPoint
    let animate: Bool

    var body: some View {
        ZStack {
            ray(width: 470, height: 7, angle: 0, opacity: 0.34)
            ray(width: 560, height: 5, angle: 90, opacity: 0.24)
            ray(width: 440, height: 5, angle: 45, opacity: 0.26)
            ray(width: 440, height: 5, angle: -45, opacity: 0.26)
            ray(width: 360, height: 3.5, angle: 22, opacity: 0.16)
            ray(width: 360, height: 3.5, angle: -22, opacity: 0.16)
        }
        .position(x: sunPoint.x, y: sunPoint.y)
        .rotationEffect(.degrees(animate ? 2.4 : -2.4))
    }

    private func ray(width: CGFloat, height: CGFloat, angle: Double, opacity: Double) -> some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.clear, .white.opacity(opacity), Color(red: 1.0, green: 0.82, blue: 0.45).opacity(opacity * 0.45), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: animate ? width * 1.08 : width * 0.94, height: height)
            .blur(radius: height * 1.4)
            .rotationEffect(.degrees(angle))
    }
}

private struct CameraFlareStreak: View {
    let size: CGSize
    let animate: Bool

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(flareGradient)
                .frame(width: size.width * 0.74, height: animate ? 64 : 48)
                .blur(radius: 10)
                .rotationEffect(.degrees(-18))
                .position(x: size.width * 0.46, y: size.height * (animate ? 0.282 : 0.250))

            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.10))
                .frame(width: size.width * 0.46, height: 3)
                .blur(radius: 2)
                .rotationEffect(.degrees(-18))
                .position(x: size.width * 0.52, y: size.height * (animate ? 0.274 : 0.255))
        }
    }

    private var flareGradient: LinearGradient {
        LinearGradient(
            colors: [
                .clear,
                Color.white.opacity(0.13),
                Color(red: 1.0, green: 0.78, blue: 0.34).opacity(0.09),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct SunDustParticles: View {
    let size: CGSize
    let animate: Bool
    let windIntensity: Double

    var body: some View {
        ZStack {
            ForEach(0..<18, id: \.self) { index in
                dust(index: index)
            }
        }
    }

    private func dust(index: Int) -> some View {
        let side = CGFloat(2.0 + Double(index % 3))
        let movement = animate ? CGFloat(index % 5) * 8 : -CGFloat(index % 5) * 8
        let wind = CGFloat(windIntensity) * CGFloat(index % 4) * 3

        return Circle()
            .fill(Color(red: 1.0, green: 0.91, blue: 0.62).opacity(0.040))
            .frame(width: side, height: side)
            .blur(radius: 0.7)
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