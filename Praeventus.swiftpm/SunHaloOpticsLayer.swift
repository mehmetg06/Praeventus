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
                CameraFlareStreak(size: size, animate: animate)
                SunScatterBeams(size: size, animate: animate)
                SunDustParticles(size: size, animate: animate, windIntensity: windIntensity)
            }
            .blendMode(.screen)
            .animation(.easeInOut(duration: 11).repeatForever(autoreverses: true), value: animate)
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
            halo(index: 0, base: 170, grow: 18, opacity: 0.13, blur: 5)
            halo(index: 1, base: 254, grow: 26, opacity: 0.10, blur: 12)
            halo(index: 2, base: 338, grow: 34, opacity: 0.07, blur: 19)
        }
    }

    private func halo(index: Int, base: CGFloat, grow: CGFloat, opacity: Double, blur: CGFloat) -> some View {
        Circle()
            .stroke(Color.white.opacity(opacity), lineWidth: 0.8)
            .frame(width: base + (animate ? grow : 0), height: base + (animate ? grow : 0))
            .blur(radius: blur)
            .position(x: sunPoint.x, y: sunPoint.y)
    }
}

private struct CameraFlareStreak: View {
    let size: CGSize
    let animate: Bool

    var body: some View {
        Capsule(style: .continuous)
            .fill(flareGradient)
            .frame(width: size.width * 0.66, height: animate ? 68 : 54)
            .blur(radius: 14)
            .rotationEffect(.degrees(-18))
            .position(x: size.width * 0.45, y: size.height * (animate ? 0.272 : 0.246))
    }

    private var flareGradient: LinearGradient {
        LinearGradient(
            colors: [
                .clear,
                Color.white.opacity(0.075),
                Color(red: 1.0, green: 0.78, blue: 0.34).opacity(0.052),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct SunScatterBeams: View {
    let size: CGSize
    let animate: Bool

    var body: some View {
        ZStack {
            beam(index: 0, y: 0.12, rotation: -4)
            beam(index: 1, y: 0.156, rotation: -2)
            beam(index: 2, y: 0.192, rotation: 0)
            beam(index: 3, y: 0.228, rotation: 2)
            beam(index: 4, y: 0.264, rotation: 4)
        }
    }

    private func beam(index: Int, y: CGFloat, rotation: Double) -> some View {
        LightBeamShape()
            .fill(beamGradient(index: index))
            .frame(width: size.width * 0.92, height: size.height * 0.50)
            .rotationEffect(.degrees(rotation + (animate ? 1.4 : -1.4)))
            .offset(x: -size.width * 0.18, y: size.height * y)
            .blur(radius: CGFloat(10 + index * 2))
            .opacity(0.85)
    }

    private func beamGradient(index: Int) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.050 - Double(index) * 0.005),
                Color(red: 1.0, green: 0.78, blue: 0.38).opacity(0.028 - Double(index) * 0.002),
                .clear
            ],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
    }
}

private struct SunDustParticles: View {
    let size: CGSize
    let animate: Bool
    let windIntensity: Double

    var body: some View {
        ZStack {
            ForEach(0..<16, id: \.self) { index in
                dust(index: index)
            }
        }
    }

    private func dust(index: Int) -> some View {
        let side = CGFloat(1.5 + Double(index % 3))
        let movement = animate ? CGFloat(index % 5) * 3 : -CGFloat(index % 5) * 3
        let wind = CGFloat(windIntensity) * CGFloat(index % 4)

        return Circle()
            .fill(Color(red: 1.0, green: 0.91, blue: 0.62).opacity(0.022))
            .frame(width: side, height: side)
            .blur(radius: 0.45)
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

private struct LightBeamShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.04))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.45))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.76))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.18))
        path.closeSubpath()
        return path
    }
}
#endif