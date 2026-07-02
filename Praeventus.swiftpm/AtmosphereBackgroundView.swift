#if canImport(SwiftUI)
import SwiftUI

struct AtmosphereBackgroundView: View {
    let atmosphere: AtmosphericState
    /// Current solar altitude in degrees (-90…90). Drives time-of-day transitions
    /// based on the sun's actual geometric position rather than a clock bucket.
    let sunAltitude: Double
    /// True while the sun is still climbing (before solar noon), false once it
    /// has passed the meridian. Used to distinguish dawn from sunset during the
    /// transitional twilight band (-12°…6°).
    let isBeforeSolarNoon: Bool
    let windSpeed: Double
    /// Shared with `HomeView`'s `ScrollView` (one level down in the view tree,
    /// via `PraeventusRootView`). Read directly inside the Canvas-driven mood
    /// layers' own `TimelineView` clocks.
    @ObservedObject var scrollTracker: ScrollOffsetTracker = ScrollOffsetTracker()

    private var mood: BackgroundMood { atmosphere.backgroundMood }
    private var timeOfDay: TimeOfDay { TimeOfDay(sunAltitude: sunAltitude, isRising: isBeforeSolarNoon) }
    private var windIntensity: Double { min(max(windSpeed / 90.0, 0.0), 1.0) }
    private var hotSunny: Bool {
        (mood == .clear || mood == .partlyCloudy) &&
        (atmosphere.condition == .clear || atmosphere.condition == .partlyCloudy) &&
        timeOfDay == .day
    }
    private var clearNight: Bool {
        (mood == .clear || mood == .partlyCloudy) && timeOfDay == .night
    }

    @State private var drift = false
    @State private var breathe = false

    @Environment(\.performanceMode) private var performanceMode
    @Environment(\.sandboxAnimationSpeed) private var animSpeed
    @Environment(\.moonCycleOverride) private var moonCycleOverride

    /// Drops a blur radius to zero in performance mode.
    private func perfBlur(_ radius: CGFloat) -> CGFloat { performanceMode ? 0 : radius }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: palette,
                startPoint: drift ? .topTrailing : .topLeading,
                endPoint: drift ? .bottomLeading : .bottomTrailing
            )
            .ignoresSafeArea()

            lightField
            if clearNight { starField }
            if hotSunny { sunDiskLayer }
            if hotSunny { SunHaloOpticsLayer(windIntensity: windIntensity) }
            airMassLayer
            moodLayer
            depthOverlay
        }
        .layoutBounds()
        .animation(.easeInOut(duration: 22 / animSpeed).repeatForever(autoreverses: true), value: drift)
        .animation(.easeInOut(duration: 0.65), value: mood)
        .animation(.easeInOut(duration: 0.65), value: timeOfDay)
        .onAppear {
            drift = true
            breathe = true
        }
    }

    // MARK: - Palette

    private var palette: [Color] {
        let base = atmosphere.condition.palette
        if hotSunny {
            return [
                Color(red: 0.02, green: 0.22, blue: 0.72),
                Color(red: 0.12, green: 0.52, blue: 0.96),
                Color(red: 0.68, green: 0.88, blue: 1.0),
                Color(red: 1.0, green: 0.80, blue: 0.42).opacity(0.95)
            ]
        }
        switch timeOfDay {
        case .dawn:   return dawnPalette(base: base)
        case .day:    return [base[0], base[1], base[2]]
        case .sunset: return sunsetPalette(base: base)
        case .night:  return nightPalette(base: base)
        }
    }

    private func dawnPalette(base: [Color]) -> [Color] {
        switch mood {
        case .storm:
            return [Color(red: 0.02, green: 0.01, blue: 0.08),
                    Color(red: 0.14, green: 0.08, blue: 0.24),
                    Color(red: 0.50, green: 0.30, blue: 0.44)]
        case .wet:
            return [Color(red: 0.04, green: 0.07, blue: 0.20),
                    Color(red: 0.28, green: 0.38, blue: 0.54),
                    Color(red: 0.72, green: 0.60, blue: 0.58)]
        case .snow:
            return [Color(red: 0.06, green: 0.08, blue: 0.24),
                    Color(red: 0.52, green: 0.62, blue: 0.80),
                    Color(red: 0.96, green: 0.84, blue: 0.84)]
        case .fog:
            return [Color(red: 0.46, green: 0.48, blue: 0.52),
                    Color(red: 0.74, green: 0.72, blue: 0.70),
                    Color(red: 0.94, green: 0.90, blue: 0.86)]
        default:
            return [Color(red: 0.10, green: 0.06, blue: 0.28),
                    Color(red: 0.64, green: 0.34, blue: 0.58),
                    Color(red: 1.0, green: 0.68, blue: 0.46)]
        }
    }

    private func sunsetPalette(base: [Color]) -> [Color] {
        switch mood {
        case .storm:
            return [Color(red: 0.01, green: 0.01, blue: 0.06),
                    Color(red: 0.20, green: 0.06, blue: 0.18),
                    Color(red: 0.42, green: 0.16, blue: 0.28)]
        case .wet:
            return [Color(red: 0.04, green: 0.06, blue: 0.18),
                    Color(red: 0.28, green: 0.22, blue: 0.38),
                    Color(red: 0.62, green: 0.44, blue: 0.40)]
        case .snow:
            return [Color(red: 0.06, green: 0.08, blue: 0.26),
                    Color(red: 0.42, green: 0.50, blue: 0.70),
                    Color(red: 0.92, green: 0.80, blue: 0.74)]
        case .fog:
            return [Color(red: 0.34, green: 0.30, blue: 0.28),
                    Color(red: 0.64, green: 0.56, blue: 0.48),
                    Color(red: 0.90, green: 0.80, blue: 0.70)]
        case .cloudy:
            return [Color(red: 0.08, green: 0.10, blue: 0.20),
                    Color(red: 0.32, green: 0.30, blue: 0.42),
                    Color(red: 0.62, green: 0.54, blue: 0.60)]
        default:
            return [Color(red: 0.06, green: 0.04, blue: 0.20),
                    Color(red: 0.50, green: 0.16, blue: 0.38),
                    Color(red: 1.0, green: 0.44, blue: 0.16)]
        }
    }

    private func nightPalette(base: [Color]) -> [Color] {
        switch mood {
        case .storm:
            return [Color(red: 0.01, green: 0.01, blue: 0.04),
                    Color(red: 0.04, green: 0.03, blue: 0.12),
                    Color(red: 0.14, green: 0.08, blue: 0.26)]
        case .fog:
            return [Color(red: 0.18, green: 0.20, blue: 0.24),
                    Color(red: 0.36, green: 0.38, blue: 0.44),
                    Color(red: 0.56, green: 0.58, blue: 0.62)]
        case .snow:
            return [Color(red: 0.03, green: 0.04, blue: 0.14),
                    Color(red: 0.10, green: 0.16, blue: 0.34),
                    Color(red: 0.28, green: 0.42, blue: 0.62)]
        default:
            return [Color(red: 0.01, green: 0.01, blue: 0.06),
                    Color(red: 0.02, green: 0.04, blue: 0.14),
                    base[0].opacity(0.45)]
        }
    }

    // MARK: - Horizon Color

    private var horizonColor: Color {
        if hotSunny { return Color(red: 1.0, green: 0.76, blue: 0.32) }
        switch mood {
        case .storm: return Color(red: 0.24, green: 0.18, blue: 0.50)
        case .wet:   return Color(red: 0.32, green: 0.50, blue: 0.68)
        case .snow:  return Color(red: 0.66, green: 0.82, blue: 1.0)
        case .fog:   return Color(red: 0.80, green: 0.84, blue: 0.80)
        default:
            switch timeOfDay {
            case .dawn:   return Color(red: 1.0, green: 0.68, blue: 0.46)
            case .day:    return Color(red: 0.64, green: 0.84, blue: 1.0)
            case .sunset: return Color(red: 1.0, green: 0.40, blue: 0.22)
            case .night:  return Color(red: 0.22, green: 0.34, blue: 0.80)
            }
        }
    }

    // MARK: - Light Field

    private var lightField: some View {
        ZStack {
            Circle()
                .fill(horizonColor.opacity(hotSunny ? 0.36 : (mood == .storm ? 0.10 : 0.24)))
                .frame(width: hotSunny ? 720 : 580, height: hotSunny ? 720 : 580)
                .blur(radius: perfBlur(hotSunny ? 155 : 120))
                .offset(x: drift ? -140 : -70, y: drift ? -330 : -240)

            Circle()
                .fill(accentLightColor.opacity(accentLightOpacity))
                .frame(width: 480, height: 480)
                .blur(radius: perfBlur(125))
                .offset(x: drift ? 160 : 100, y: drift ? 200 : 260)

            if hotSunny {
                Circle()
                    .fill(Color(red: 1.0, green: 0.72, blue: 0.28).opacity(breathe ? 0.14 : 0.06))
                    .frame(width: 650, height: 650)
                    .blur(radius: perfBlur(160))
                    .offset(x: 140, y: -60)

                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.82, blue: 0.40).opacity(0.20),
                        .clear,
                        Color(red: 1.0, green: 0.60, blue: 0.22).opacity(0.12)
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .ignoresSafeArea()
                .blendMode(.screen)
            }

            if mood == .storm {
                Circle()
                    .fill(Color(red: 0.28, green: 0.10, blue: 0.60).opacity(breathe ? 0.24 : 0.08))
                    .frame(width: 580, height: 580)
                    .blur(radius: perfBlur(130))
                    .offset(x: -160, y: -180)
                Circle()
                    .fill(Color(red: 0.10, green: 0.02, blue: 0.30).opacity(breathe ? 0.18 : 0.06))
                    .frame(width: 420, height: 420)
                    .blur(radius: perfBlur(100))
                    .offset(x: 120, y: -80)
            }

            if mood == .snow {
                Circle()
                    .fill(Color(red: 0.70, green: 0.86, blue: 1.0).opacity(breathe ? 0.18 : 0.08))
                    .frame(width: 540, height: 540)
                    .blur(radius: perfBlur(140))
                    .offset(x: 60, y: -140)
            }

            if clearNight {
                Circle()
                    .fill(Color(red: 0.20, green: 0.30, blue: 0.90).opacity(breathe ? 0.07 : 0.03))
                    .frame(width: 500, height: 500)
                    .blur(radius: perfBlur(130))
                    .offset(x: -100, y: -200)
            }
        }
        // Keep the glow stack as native transparent views. Flattening these
        // oversized blurred discs into a Metal layer can leave a faint boxed
        // edge visible behind the weather UI on some iPadOS renderers.
        // Opacity animation is used instead of scaleEffect: scaling blurred
        // layers forces the compositor to recomposite every frame (~60fps),
        // whereas opacity is a single alpha-multiply on the cached textures.
        .opacity(breathe ? 1.0 : 0.90)
        .animation(.easeInOut(duration: (hotSunny ? 18 : 14) / animSpeed).repeatForever(autoreverses: true), value: breathe)
        .ignoresSafeArea()
    }

    private var accentLightColor: Color {
        switch mood {
        case .storm:  return Color(red: 0.20, green: 0.10, blue: 0.50)
        case .wet:    return Color(red: 0.30, green: 0.50, blue: 0.70)
        case .snow:   return Color(red: 0.60, green: 0.80, blue: 1.0)
        case .fog:    return Color(red: 0.80, green: 0.82, blue: 0.80)
        default:      return .cyan
        }
    }

    private var accentLightOpacity: Double {
        switch mood {
        case .wet, .fog, .snow: return 0.14
        case .storm:            return 0.10
        default:                return hotSunny ? 0.04 : 0.09
        }
    }

    // MARK: - Star Field (Clear/PartlyCloudy Night)

    private var starField: some View {
        Canvas { context, size in
            for i in 0..<100 {
                let d = Double(i)
                let x = (sin(d * 127.1) * 0.5 + 0.5) * Double(size.width)
                let y = (sin(d * 311.7) * 0.5 + 0.5) * Double(size.height) * 0.74
                let r = 0.5 + (sin(d * 74.3) * 0.5 + 0.5) * 1.4
                let a = max(0.08, 0.16 + (sin(d * 193.1) * 0.5 + 0.5) * 0.52)
                context.fill(
                    Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)),
                    with: .color(.white.opacity(a))
                )
            }
            let moonX = Double(size.width) * 0.76
            let moonY = Double(size.height) * 0.13
            context.fill(
                Path(ellipseIn: CGRect(x: moonX - 22, y: moonY - 22, width: 44, height: 44)),
                with: .color(.white.opacity(0.92))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: moonX - 68, y: moonY - 68, width: 136, height: 136)),
                with: .color(.white.opacity(0.08))
            )

            // Sandbox override: carve a phase terminator into the moon disc by
            // sliding a sky-coloured shadow disc across it.
            if moonCycleOverride >= 0 {
                let illumination = (1 - cos(moonCycleOverride * 2 * .pi)) / 2  // 0=new … 1=full
                let waxing = moonCycleOverride < 0.5
                let shift = illumination * 44 * (waxing ? -1 : 1)
                context.fill(
                    Path(ellipseIn: CGRect(x: moonX - 22 + shift, y: moonY - 22, width: 44, height: 44)),
                    with: .color(Color(red: 0.02, green: 0.03, blue: 0.12).opacity(0.97))
                )
            }
        }
        .blur(radius: 0.5)
        .ignoresSafeArea()
    }

    // MARK: - Sun Disk Layer

    /// Sky-wash tint only. The sun disc/corona itself is owned entirely by
    /// `SunHaloOpticsLayer` (bloom + sharp core + rings, drawn at the same
    /// anchor point below) — this used to duplicate its own Corona+Core here,
    /// stacking two independent sun renders on the identical position for no
    /// visual gain and extra render cost.
    private var sunDiskLayer: some View {
        RadialGradient(
            colors: [
                Color(red: 1.0, green: 0.85, blue: 0.4).opacity(0.15),
                .clear
            ],
            center: UnitPoint(x: 0.84, y: 0.16),
            startRadius: 0,
            endRadius: 900
        )
        .ignoresSafeArea()
    }

    // MARK: - Air Mass Layer

    private var airMassLayer: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 8.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate * animSpeed
                let bands = max(2, min(6, Int(2 + atmosphere.cloudCover * 5)))
                let speed = 1.2 + windSpeed * 0.022
                // Scroll parallax: bands drift a fraction of the scroll offset so the
                // background reads as sitting behind the foreground cards rather than
                // glued to them. Reads `scrollTracker.value` directly inside this
                // already-running Canvas clock — no new SwiftUI observation/re-render.
                let parallaxY = scrollTracker.value * 0.18

                for index in 0..<bands {
                    let width = size.width * (0.82 + CGFloat(index) * 0.14)
                    let height = size.height * (0.14 + CGFloat(index % 3) * 0.032)
                    let x = (CGFloat(time * (speed + Double(index) * 0.20)) + CGFloat(index * 211))
                        .truncatingRemainder(dividingBy: size.width + width) - width
                    let y = size.height * (0.10 + CGFloat(index) * 0.13) + parallaxY
                    let opacity = hotSunny ? 0.028 : 0.028 + atmosphere.cloudCover * 0.09
                    let cx = x + width / 2
                    let cy = y + height / 2
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: width, height: height)),
                        with: .radialGradient(
                            Gradient(colors: [.white.opacity(opacity * 2.8), .white.opacity(0)]),
                            center: CGPoint(x: cx, y: cy),
                            startRadius: 0,
                            endRadius: max(width, height) / 2
                        )
                    )

                    if !hotSunny && atmosphere.cloudCover > 0.3 {
                        let shadowOpacity = 0.030 + atmosphere.cloudCover * 0.030
                        let shadowRect = CGRect(x: x + width * 0.08, y: y + height * 0.70,
                                               width: width * 0.84, height: height * 0.50)
                        context.fill(
                            Path(ellipseIn: shadowRect),
                            with: .radialGradient(
                                Gradient(colors: [.black.opacity(shadowOpacity * 2.0), .black.opacity(0)]),
                                center: CGPoint(x: shadowRect.midX, y: shadowRect.midY),
                                startRadius: 0,
                                endRadius: max(shadowRect.width, shadowRect.height) / 2
                            )
                        )
                    }
                }

                if hotSunny {
                    for index in 0..<3 {
                        let y = size.height * (0.60 + CGFloat(index) * 0.10) + parallaxY
                        let rect = CGRect(x: -size.width * 0.12, y: y, width: size.width * 1.24, height: 78)
                        let bandOpacity = 0.028 - Double(index) * 0.005
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: 55),
                            with: .linearGradient(
                                Gradient(colors: [
                                    Color(red: 1.0, green: 0.78, blue: 0.40).opacity(0),
                                    Color(red: 1.0, green: 0.78, blue: 0.40).opacity(bandOpacity * 2.0),
                                    Color(red: 1.0, green: 0.78, blue: 0.40).opacity(0)
                                ]),
                                startPoint: CGPoint(x: rect.minX, y: rect.midY),
                                endPoint: CGPoint(x: rect.maxX, y: rect.midY)
                            )
                        )
                    }
                }
            }
        }
        .padding(-60)
        .ignoresSafeArea()
    }

    // MARK: - Mood Layer

    @ViewBuilder
    private var moodLayer: some View {
        switch mood {
        case .clear:
            if hotSunny {
                HotSunnyLayer(drift: drift, windIntensity: windIntensity)
            } else {
                // Dawn/sunset/night "clear" used to render nothing but the flat
                // gradient — real clear skies still carry thin, sparse high
                // cirrus. A very low cover keeps it a texture, not a cloud deck.
                VolumetricCloudLayer(cloudCover: 0.14,
                                     windSpeed: windSpeed, timeOfDay: timeOfDay, scattered: true,
                                     scrollTracker: scrollTracker)
            }
        case .partlyCloudy:
            if hotSunny {
                HotSunnyLayer(drift: drift, windIntensity: windIntensity)
            } else {
                VolumetricCloudLayer(cloudCover: max(0.32, atmosphere.cloudCover),
                                     windSpeed: windSpeed, timeOfDay: timeOfDay, scattered: true,
                                     scrollTracker: scrollTracker)
            }
        case .cloudy:
            VolumetricCloudLayer(cloudCover: max(0.6, atmosphere.cloudCover),
                                 windSpeed: windSpeed, timeOfDay: timeOfDay,
                                 scrollTracker: scrollTracker)
        case .wet:
            RainSceneLayer(windSpeed: windSpeed, rainSignal: atmosphere.rainSignal, glassIntensity: rainGlassIntensity,
                           scrollTracker: scrollTracker)
        case .storm:
            LightningStormLayer(scrollTracker: scrollTracker)
            RainSceneLayer(windSpeed: max(windSpeed, 35), rainSignal: .high, glassIntensity: 0.88,
                           scrollTracker: scrollTracker)
        case .fog:
            DriftingFogLayer(windSpeed: windSpeed, scrollTracker: scrollTracker)
        case .snow:
            RealisticSnowLayer(windSpeed: windSpeed, scrollTracker: scrollTracker)
        }
    }

    private var rainGlassIntensity: Double {
        switch atmosphere.rainSignal {
        case .low:      return 0.42
        case .moderate: return 0.64
        case .high:     return 0.86
        }
    }

    // MARK: - Depth Overlay

    private var depthOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .white.opacity(hotSunny ? 0.060 : 0.040),
                    .clear,
                    depthMidColor,
                    .black.opacity(baseDarkness)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [.clear, .black.opacity(mood == .storm ? 0.60 : (hotSunny ? 0.18 : 0.30))],
                center: .center,
                startRadius: 110,
                endRadius: 640
            )
        }
        .ignoresSafeArea()
    }

    private var depthMidColor: Color {
        switch mood {
        case .storm: return Color(red: 0.10, green: 0.04, blue: 0.22).opacity(0.30)
        case .wet:   return Color(red: 0.04, green: 0.12, blue: 0.24).opacity(0.20)
        default:     return Color(red: 0.97, green: 0.58, blue: 0.22).opacity(hotSunny ? 0.18 : 0.0)
        }
    }

    private var baseDarkness: Double {
        let weather: Double
        switch mood {
        case .clear:        weather = hotSunny ? 0.02 : 0.06
        case .partlyCloudy: weather = hotSunny ? 0.04 : 0.10
        case .cloudy:       weather = 0.16
        case .wet:          weather = 0.22
        case .storm:        weather = 0.38
        case .fog:          weather = 0.08
        case .snow:         weather = 0.10
        }
        return min(0.66, weather + timeOfDay.darkness)
    }
}

// MARK: - Hot Sunny Layer

private struct HotSunnyLayer: View {
    let drift: Bool
    let windIntensity: Double

    @Environment(\.sandboxAnimationSpeed) private var animSpeed

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.88, blue: 0.46).opacity(0.18),
                    .clear,
                    Color(red: 1.0, green: 0.50, blue: 0.16).opacity(0.12)
                ],
                startPoint: drift ? .topLeading : .top,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)

            TimelineView(.periodic(from: .now, by: 1.0 / 8.0)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate * animSpeed
                    for index in 0..<4 {
                        let y = size.height * (0.55 + CGFloat(index) * 0.075)
                        let phase = CGFloat(time * 0.36 + Double(index) * 1.7)
                        var path = Path()
                        path.move(to: CGPoint(x: -40, y: y))
                        for step in 0...10 {
                            let x = size.width * CGFloat(step) / 10
                            let shimmer = sin(CGFloat(step) * 1.28 + phase) * (2.2 + CGFloat(windIntensity) * 4.5)
                            path.addLine(to: CGPoint(x: x, y: y + shimmer))
                        }
                        context.stroke(
                            path,
                            with: .color(Color(red: 1.0, green: 0.88, blue: 0.54).opacity(0.038 - Double(index) * 0.004)),
                            style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
            }
            .blur(radius: 1.0)
        }
        .ignoresSafeArea()
    }
}
#endif
