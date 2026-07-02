#if canImport(SwiftUI)
import SwiftUI

struct SunHaloOpticsLayer: View {
    let windIntensity: Double
    @State private var rotate = false
    @State private var pulse = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let sunPoint = CGPoint(x: size.width * 0.84, y: size.height * 0.16)

            ZStack {
                SunCameraBloom(sunPoint: sunPoint, pulse: pulse)
                RadialSunStarburst(sunPoint: sunPoint, rotate: rotate, pulse: pulse)
                OrbitalLensHalo(sunPoint: sunPoint, rotate: rotate, pulse: pulse)
                MovingAtmosphericDust(size: size, pulse: pulse, windIntensity: windIntensity)
            }
            // Avoid flattening the halo into one Metal texture: on some devices
            // that offscreen texture shows up as a faint square/line in the sky.
            .blendMode(.screen)
            .onAppear {
                withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                    rotate = true
                }
                withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct SunCameraBloom: View {
    let sunPoint: CGPoint
    let pulse: Bool

    @Environment(\.performanceMode) private var performanceMode
    private func perfBlur(_ radius: CGFloat) -> CGFloat { performanceMode ? 0 : radius }

    var body: some View {
        ZStack {
            // Fixed sizes — only opacity animates to avoid SwiftUI layout recalculation every frame.
            Circle()
                .fill(Color.white.opacity(pulse ? 0.14 : 0.08))
                .frame(width: 168, height: 168)
                .blur(radius: perfBlur(20))

            Circle()
                .fill(Color.white.opacity(0.90))
                .frame(width: 82, height: 82)
                .blur(radius: perfBlur(0.35))

            Circle()
                .stroke(Color.white.opacity(pulse ? 0.22 : 0.14), lineWidth: 1.1)
                .frame(width: 170, height: 170)
                .blur(radius: perfBlur(2.4))

            Circle()
                .stroke(Color(red: 1.0, green: 0.86, blue: 0.52).opacity(pulse ? 0.16 : 0.09), lineWidth: 1.0)
                .frame(width: 290, height: 290)
                .blur(radius: perfBlur(7))

            Circle()
                .stroke(Color.white.opacity(pulse ? 0.08 : 0.04), lineWidth: 0.8)
                .frame(width: 465, height: 465)
                .blur(radius: perfBlur(18))
        }
        .position(x: sunPoint.x, y: sunPoint.y)
    }
}

private struct RadialSunStarburst: View {
    let sunPoint: CGPoint
    let rotate: Bool
    let pulse: Bool

    @Environment(\.performanceMode) private var performanceMode
    private var rotation: Double { rotate ? 360 : 0 }

    var body: some View {
        ZStack {
            raysSet(rotationOffset: 0, long: true)
            raysSet(rotationOffset: 15, long: false)
            raysSet(rotationOffset: 30, long: false)
        }
        .blur(radius: performanceMode ? 0 : 2.5)
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
        // Fixed length — size animation eliminated; blur moved to group level (1 pass vs 24).
        let length: CGFloat = long ? 410 : 245
        let thickness: CGFloat = long ? 4.2 : 2.4
        let opacity: Double = long ? 0.30 : 0.14

        return Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        .clear,
                        Color.white.opacity(opacity * 0.25),
                        Color.white.opacity(opacity),
                        Color(red: 1.0, green: 0.86, blue: 0.48).opacity(opacity * 0.50),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: length, height: thickness)
            .opacity(pulse ? 0.92 : 0.68)
            .offset(x: length / 2)
            .rotationEffect(.degrees(angle))
    }
}

private struct OrbitalLensHalo: View {
    let sunPoint: CGPoint
    let rotate: Bool
    let pulse: Bool

    @Environment(\.performanceMode) private var performanceMode
    private func perfBlur(_ radius: CGFloat) -> CGFloat { performanceMode ? 0 : radius }

    var body: some View {
        ZStack {
            // Fixed sizes — only opacity/stroke-opacity animates; no layout recalculation per frame.
            Circle()
                .stroke(Color.white.opacity(pulse ? 0.14 : 0.08), lineWidth: 0.9)
                .frame(width: 365, height: 365)
                .blur(radius: perfBlur(9))

            Circle()
                .stroke(Color.white.opacity(pulse ? 0.09 : 0.045), lineWidth: 0.8)
                .frame(width: 530, height: 530)
                .blur(radius: perfBlur(19))

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(pulse ? 0.08 : 0.04), Color(red: 1.0, green: 0.78, blue: 0.34).opacity(0.06), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 670, height: 40)
                .blur(radius: perfBlur(7))
                .rotationEffect(.degrees(rotate ? 360 : 0))
        }
        .position(x: sunPoint.x, y: sunPoint.y)
    }
}

private struct MovingAtmosphericDust: View {
    let size: CGSize
    let pulse: Bool
    let windIntensity: Double

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                dust(index: index)
            }
        }
    }

    private func dust(index: Int) -> some View {
        let side = CGFloat(1.4 + Double(index % 3) * 0.9)
        let movement = pulse ? CGFloat(index % 6) * 22 : -CGFloat(index % 6) * 22
        let wind = CGFloat(windIntensity) * CGFloat(index % 4) * 6

        return Circle()
            .fill(Color(red: 1.0, green: 0.91, blue: 0.62).opacity(0.050))
            .frame(width: side, height: side)
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