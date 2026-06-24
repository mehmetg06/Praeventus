#if canImport(SwiftUI)
import SwiftUI

struct SunHaloOpticsLayer: View {
    let windIntensity: Double

    @State private var animate = false

    var body: some View {
        GeometryReader { geometry in
            let sunX = geometry.size.width * 0.84
            let sunY = geometry.size.height * 0.16

            ZStack {
                // Halo rings around the sun.
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(Color.white.opacity(0.13 - Double(index) * 0.03), lineWidth: 0.8)
                        .frame(
                            width: CGFloat(170 + index * 84) + (animate ? CGFloat(18 + index * 8) : 0),
                            height: CGFloat(170 + index * 84) + (animate ? CGFloat(18 + index * 8) : 0)
                        )
                        .blur(radius: CGFloat(5 + index * 7))
                        .position(x: sunX, y: sunY)
                }

                // A soft camera-glass streak crossing the sun.
                Capsule(style: .continuous)
                    .fill(
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
                    )
                    .frame(width: geometry.size.width * 0.66, height: animate ? 68 : 54)
                    .blur(radius: 14)
                    .rotationEffect(.degrees(-18))
                    .position(x: geometry.size.width * 0.45, y: geometry.size.height * (animate ? 0.272 : 0.246))

                // Scatter beams: large translucent triangles from sun to the lower-left air.
                ForEach(0..<5, id: \.self) { index in
                    LightBeamShape()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.050 - Double(index) * 0.005),
                                    Color(red: 1.0, green: 0.78, blue: 0.38).opacity(0.028 - Double(index) * 0.002),
                                    .clear
                                ],
                                startPoint: .topTrailing,
                                endPoint: .bottomLeading
                            )
                        )
                        .frame(width: geometry.size.width * 0.92, height: geometry.size.height * 0.50)
                        .rotationEffect(.degrees(-4 + Double(index) * 2 + (animate ? 1.4 : -1.4)))
                        .offset(x: -geometry.size.width * 0.18, y: geometry.size.height * (0.12 + CGFloat(index) * 0.036))
                        .blur(radius: CGFloat(10 + index * 2))
                        .opacity(0.85)
                }

                // Floating bright dust in the optical path.
                ForEach(0..<16, id: \.self) { index in
                    Circle()
                        .fill(Color(red: 1.0, green: 0.91, blue: 0.62).opacity(0.022))
                        .frame(width: CGFloat(1.5 + (index % 3)), height: CGFloat(1.5 + (index % 3)))
                        .blur(radius: 0.45)
                        .position(
                            x: geometry.size.width * dustX(index) + (animate ? CGFloat(index % 5) * 3 : -CGFloat(index % 5) * 3),
                            y: geometry.size.height * dustY(index)
                        )
                }
            }
            .blendMode(.screen)
            .animation(.easeInOut(duration: 11).repeatForever(autoreverses: true), value: animate)
            .onAppear { animate = true }
        }
        .ignoresSafeArea()
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