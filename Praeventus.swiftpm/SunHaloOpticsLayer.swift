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
                RadialSunStarburst(sunPoint: sunPoint, animate: animate)
                OrbitalLensHalo(sunPoint: sunPoint, animate: animate)
                MovingAtmosphericDust(size: size, animate: animate, windIntensity: windIntensity)
            }
            .blendMode(.screen)
            .animation(.linear(duration: 4.8).repeatForever(autoreverses: false), value: animate)
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
                .fill(Color.white.opacity(0.18))
                .frame(width: 145, height: 145)
                .blur(radius: 18)

            Circle()
                .fill(Color.white.opacity(0.90))
                .frame(width: 78, height: 78)
                .blur(radius: 0.25)

            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: 1.1)
                .frame(width: 150, height: 150)
                .blur(radius: 1.2)

            Circle()
                .stroke(Color(red: 1.0, green: 0.86, blue: 0.52).opacity(0.18), lineWidth: 1.0)
                .frame(width: 255, height: 255)
                .blur(radius: 4)
        }
        .position(x: sunPoint.x, y: sunPoint.y)
    }
}

private struct RadialSunStarburst: View {
    let sunPoint: CGPoint
    let animate: Bool

    private var rotation: Double { animate ? 360 : 0 }

    var body: some View {
        ZStack {
            raysSet(rotationOffset: 0, long: true)
            raysSet(rotationOffset: 15, long: false)
            raysSet(rotationOffset: 30, long: false)
        }
        .rotationEffect(.degrees(rotation))
        .position(x: sunPoint.x, y: sunPoint.y)
    }

    private func raysSet(rotationOffset: Double, long: Bool) -> some View {
        ZStack {
            radialRay(angle: rotationOffset + 0, long: long)
            radialRay(angle: rotationOffset + 45, long: long)
            radialRay(angle: rotationOffset + 90, long: long)
            radialRay(angle: rotationOffset + 135, long: long)
            radialRay(angle: rotationOffset + 180, long: long)
            radialRay(angle: rotationOffset + 225, long: long)
            radialRay(angle: rotationOffset + 270, long: long)
            radialRay(angle: rotationOffset + 315, long: long)
        }
    }

    private func radialRay(angle: Double, long: Bool) -> some View {
        let length: CGFloat = long ? 430 : 270
        let thickness: CGFloat = long ? 3.2 : 1.8
        let opacity: Double = long ? 0.34 : 0.16

        return Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(opacity),
                        Color.white.opacity(opacity * 0.55),
                        Color(red: 1.0, green: 0.84, blue: 0.42).opacity(opacity * 0.25),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: length, height: thickness)
            .blur(radius: long ? 0.55 : 0.9)
            .offset(x: length / 2)
            .rotationEffect(.degrees(angle))
    }
}

private struct OrbitalLensHalo: View {
    let sunPoint: CGPoint
    let animate: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 0.9)
                .frame(width: 330, height: 330)
                .blur(radius: 7)
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                .frame(width: 480, height: 480)
                .blur(radius: 16)
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.10), Color(red: 1.0, green: 0.78, blue: 0.34).opacity(0.06), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 560, height: 28)
                .blur(radius: 4)
                .rotationEffect(.degrees(animate ? 16 : 0))
        }
        .position(x: sunPoint.x, y: sunPoint.y)
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