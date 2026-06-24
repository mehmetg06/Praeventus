#if canImport(SwiftUI)
import SwiftUI

/// Keeps large UI cards rounded, but turns small vertical rain-glass capsules into true 💧 silhouettes.
struct RoundedRectangle: Shape {
    var cornerRadius: CGFloat
    var style: RoundedCornerStyle = .continuous

    func path(in rect: CGRect) -> Path {
        let looksLikeRaindrop = rect.width < 40 && rect.height > rect.width * 1.22
        guard looksLikeRaindrop else {
            return Path(roundedRect: rect, cornerRadius: cornerRadius)
        }

        let w = rect.width
        let h = rect.height
        let x = rect.minX
        let y = rect.minY

        var path = Path()
        path.move(to: CGPoint(x: x + w * 0.50, y: y + h * 0.02))
        path.addCurve(
            to: CGPoint(x: x + w * 0.92, y: y + h * 0.44),
            control1: CGPoint(x: x + w * 0.72, y: y + h * 0.03),
            control2: CGPoint(x: x + w * 0.94, y: y + h * 0.20)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.50, y: y + h * 0.98),
            control1: CGPoint(x: x + w * 0.92, y: y + h * 0.70),
            control2: CGPoint(x: x + w * 0.66, y: y + h * 0.88)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.08, y: y + h * 0.44),
            control1: CGPoint(x: x + w * 0.34, y: y + h * 0.88),
            control2: CGPoint(x: x + w * 0.08, y: y + h * 0.70)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.50, y: y + h * 0.02),
            control1: CGPoint(x: x + w * 0.06, y: y + h * 0.20),
            control2: CGPoint(x: x + w * 0.28, y: y + h * 0.03)
        )
        return path
    }
}
#endif
