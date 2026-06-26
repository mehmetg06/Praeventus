#if canImport(SwiftUI)
import SwiftUI

/// Environment plumbing for the Weather Lab "Ultimate Developer Sandbox".
///
/// These keys let the sandbox push live overrides into the whole view tree —
/// the shared atmosphere background, the glass components and the particle
/// layers all read them directly, so dragging a slider in the Lab is felt
/// everywhere in real time without threading parameters through every view.

private struct PerformanceModeKey: EnvironmentKey { static let defaultValue = false }
private struct ShowLayoutBoundsKey: EnvironmentKey { static let defaultValue = false }
private struct SandboxAnimationSpeedKey: EnvironmentKey { static let defaultValue = 1.0 }
/// Synodic cycle position (0…1) for an overridden moon; `-1` means "use live".
private struct MoonCycleOverrideKey: EnvironmentKey { static let defaultValue = -1.0 }

extension EnvironmentValues {
    /// When true, blurs and ultra-thin materials are dropped to test layout
    /// performance on older devices.
    var performanceMode: Bool {
        get { self[PerformanceModeKey.self] }
        set { self[PerformanceModeKey.self] = newValue }
    }
    /// When true, major layers draw a 1px red border for clipping/tiling debug.
    var showLayoutBounds: Bool {
        get { self[ShowLayoutBoundsKey.self] }
        set { self[ShowLayoutBoundsKey.self] = newValue }
    }
    /// Multiplier (0.1…2.0) applied to particle/animation time bases.
    var sandboxAnimationSpeed: Double {
        get { self[SandboxAnimationSpeedKey.self] }
        set { self[SandboxAnimationSpeedKey.self] = newValue }
    }
    /// Overridden moon cycle position (0…1), or `-1` when following live data.
    var moonCycleOverride: Double {
        get { self[MoonCycleOverrideKey.self] }
        set { self[MoonCycleOverrideKey.self] = newValue }
    }
}

/// Adds a 1px red outline while the sandbox "Show Layout Bounds" toggle is on,
/// for spotting clipping or tiling artefacts in the rendering stack.
private struct LayoutBoundsModifier: ViewModifier {
    @Environment(\.showLayoutBounds) private var showLayoutBounds
    func body(content: Content) -> some View {
        content.border(Color.red.opacity(showLayoutBounds ? 0.9 : 0), width: showLayoutBounds ? 1 : 0)
    }
}

extension View {
    /// Outlines a major layer in red while the layout-bounds debugger is active.
    func layoutBounds() -> some View { modifier(LayoutBoundsModifier()) }
}
#endif
