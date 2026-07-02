#if canImport(SwiftUI)
import SwiftUI

// MARK: - Deterministic Hash

/// 1024-entry pre-computed table: fractional part of sin(n*12.9898+78.233)*43758.5453.
/// Eliminates per-frame sin() calls — wHash becomes an O(1) array lookup.
private let hashLookup: [Double] = (0..<1024).map { n in
    let x = sin(Double(n) * 12.9898 + 78.233) * 43758.5453
    return x - x.rounded(.down)
}

/// Stable pseudo-random value in 0..<1 for a given seed. Lets Canvas redraws
/// keep particle identity frame-to-frame without storing per-particle state.
@inline(__always)
fileprivate func wHash(_ n: Int) -> Double {
    hashLookup[abs(n) % 1024]
}

// Gradient allocated once; `drawBead` scales opacity via GraphicsContext.opacity instead of
// creating a new Gradient(stops:) on every bead every frame. The rim-shadow that used to be a
// separate offset ellipse draw is now baked into the gradient's outer stops (see drawBead).
private let beadBodyGradient = Gradient(stops: [
    .init(color: .white.opacity(0.02), location: 0.0),
    .init(color: .white.opacity(0.10), location: 0.55),
    .init(color: .black.opacity(0.16), location: 0.80),
    .init(color: .white.opacity(0.40), location: 0.94),
    .init(color: .white.opacity(0.0),  location: 1.0)
])

/// Renders a single water bead: a body gradient with the refraction shadow baked
/// into its outer stops, plus a crisp specular highlight. Two fills instead of the
/// previous three (a separate offset shadow ellipse was folded into the gradient) —
/// the single biggest per-frame draw-call cost in the wet/storm scene, so trimming it
/// buys headroom for the bigger, brighter beads below.
fileprivate func drawBead(_ context: GraphicsContext, center: CGPoint, radius r: CGFloat, alpha: Double) {
    let a = min(1.0, max(0.0, alpha))
    // Copy context and set opacity once; all draws below inherit the scale factor,
    // avoiding per-call alpha multiplication in every color literal.
    var ctx = context
    ctx.opacity = a
    let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)

    // Body: reuses pre-allocated file-level gradient; no heap allocation per bead.
    ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
        beadBodyGradient, center: center, startRadius: 0, endRadius: r))

    // Specular highlight, upper-left like a single overhead light source.
    let hr = r * 0.40
    let hRect = CGRect(x: center.x - r * 0.34 - hr / 2,
                       y: center.y - r * 0.40 - hr / 2,
                       width: hr, height: hr)
    ctx.fill(Path(ellipseIn: hRect), with: .color(.white.opacity(0.62)))
}

// MARK: - Rain Scene (falling streaks + lens droplets, one render pass)

/// The full close-range rain scene: depth-layered falling streaks (far drizzle,
/// bright near streaks, drifting mist, ground splashes) plus a field of glass
/// lens droplets ("the signature Apple Weather close-up effect"), drawn in a
/// single `TimelineView`/`Canvas` pass. Previously these were two independently
/// clocked layers (`VolumetricRainLayer` + `RaindropGlassLayer`) — merging them
/// removes one full render-loop subscription from `.wet`/`.storm` scenes without
/// changing what's on screen.
struct RainSceneLayer: View {
    let windSpeed: Double
    let rainSignal: AtmosphericRisk
    let glassIntensity: Double     // 0...1, lens-droplet density/brightness
    /// See `ScrollOffsetTracker` — rain is the nearest weather layer, so it
    /// parallaxes the most.
    @ObservedObject var scrollTracker: ScrollOffsetTracker = ScrollOffsetTracker()

    @Environment(\.sandboxAnimationSpeed) private var animSpeed

    private var intensity: Double {
        switch rainSignal {
        case .low:      return 0.30
        case .moderate: return 0.56
        case .high:     return 0.82
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate * animSpeed
                context.translateBy(x: 0, y: scrollTracker.value * 0.22)
                drawFallingRain(context, size: size, time: time)
                drawGlassBeads(context, size: size, time: time)
            }
        }
        .ignoresSafeArea()
    }

    private func drawFallingRain(_ context: GraphicsContext, size: CGSize, time: Double) {
        let tilt = CGFloat(4 + windSpeed * 0.14)
        let groundY = size.height * 0.90

        // Far layer — short, faint, slow. Opacity roughly 2-3x the original range
        // so distant drizzle actually reads instead of being nearly invisible.
        let bgCount = Int(14 + intensity * 22)
        for i in 0..<bgCount {
            let seed = Double(i * 97 + 13)
            let x = CGFloat(seed.truncatingRemainder(dividingBy: 881)) / 881 * size.width
            let speed = 16 + windSpeed * 0.12 + seed.truncatingRemainder(dividingBy: 6)
            let y = CGFloat(time * speed + seed * 7).truncatingRemainder(dividingBy: size.height + 100) - 50
            let length = CGFloat(9 + intensity * 9)
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x - tilt * 0.6, y: y + length))
            context.stroke(path, with: .color(.white.opacity(0.045 + intensity * 0.045)), lineWidth: 0.34)
        }

        // Near layer — a soft trailing halo pass plus a bright tapered core pass, so
        // each streak reads as a falling drop with visual mass, not a thin flat line.
        let fgCount = Int(8 + intensity * 16)
        let haloOpacity = 0.05 + intensity * 0.05
        let coreGradient = Gradient(colors: [.white.opacity(0.0),
                                             .white.opacity(0.11 + intensity * 0.11),
                                             .white.opacity(0.0)])
        for i in 0..<fgCount {
            let seed = Double(i * 53 + 71)
            let x = CGFloat(seed.truncatingRemainder(dividingBy: 773)) / 773 * size.width
            let speed = 34 + windSpeed * 0.24 + seed.truncatingRemainder(dividingBy: 8)
            let length = CGFloat(30 + intensity * 34)
            let y = CGFloat(time * speed + seed * 11).truncatingRemainder(dividingBy: size.height + 160) - 85
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x - tilt, y: y + length))
            context.stroke(path, with: .color(.white.opacity(haloOpacity)),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            let streak = GraphicsContext.Shading.linearGradient(
                coreGradient,
                startPoint: CGPoint(x: x, y: y),
                endPoint: CGPoint(x: x - tilt, y: y + length)
            )
            context.stroke(path, with: streak,
                           style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
        }

        // Drifting mist bands.
        for m in 0..<3 {
            let my = size.height * (0.48 + Double(m) * 0.15)
            let mist = CGRect(x: -size.width * 0.10, y: my, width: size.width * 1.20, height: 92)
            context.fill(Path(roundedRect: mist, cornerRadius: 52),
                         with: .color(.white.opacity(0.028 + intensity * 0.018 - Double(m) * 0.004)))
        }

        // Impact splashes — tiny rings flickering on the wet ground.
        let splashCount = Int(6 + intensity * 12)
        for i in 0..<splashCount {
            let seed = Double(i * 131 + 29)
            let cadence = 0.5 + seed.truncatingRemainder(dividingBy: 4) * 0.2
            let local = (time / cadence + seed).truncatingRemainder(dividingBy: 1.0)
            guard local < 0.4 else { continue }
            let life = local / 0.4               // 0...1 expansion
            let sx = CGFloat(seed.truncatingRemainder(dividingBy: 997)) / 997 * size.width
            let sy = groundY + CGFloat(seed.truncatingRemainder(dividingBy: 7)) * (size.height * 0.012)
            let rr = CGFloat(1 + life * 9)
            let ringRect = CGRect(x: sx - rr, y: sy - rr * 0.35, width: rr * 2, height: rr * 0.7)
            context.stroke(Path(ellipseIn: ringRect),
                           with: .color(.white.opacity((1 - life) * 0.16 * (0.5 + intensity))),
                           lineWidth: 0.8)
        }

        // Wet ground sheen.
        let gnd = CGRect(x: 0, y: size.height * 0.88, width: size.width, height: size.height * 0.12)
        context.fill(Path(gnd), with: .color(Color(red: 0.45, green: 0.65, blue: 0.82).opacity(0.026 + intensity * 0.018)))
    }

    private func drawGlassBeads(_ context: GraphicsContext, size: CGSize, time t: Double) {
        let windTilt = CGFloat(min(windSpeed / 90.0, 1.0))

        // Resting condensation beads — mostly static, gently breathing. Slightly
        // larger/brighter than before now that each bead costs one less draw call.
        let restCount = Int(34 + glassIntensity * 30)
        for i in 0..<restCount {
            let x = CGFloat(wHash(i * 2 + 1)) * size.width
            let y = CGFloat(wHash(i * 2 + 7)) * size.height
            let baseR = CGFloat(1.6 + wHash(i * 3 + 5) * (2.6 + glassIntensity * 4.0))
            let breath = 0.82 + 0.18 * sin(t * 0.5 + Double(i) * 1.3)
            let r = baseR * CGFloat(breath)
            drawBead(context, center: CGPoint(x: x, y: y), radius: r, alpha: 0.62 + glassIntensity * 0.35)
        }

        // Runners — beads heavy enough to overcome surface tension and slide.
        let runnerCount = Int(2 + glassIntensity * 6)
        for i in 0..<runnerCount {
            let lane = CGFloat(wHash(i * 5 + 3))
            let period = 3.4 + wHash(i * 5 + 9) * 5.2
            let phase = wHash(i * 5 + 11)
            let cycle = ((t / period) + phase).truncatingRemainder(dividingBy: 1.0)

            let startY = CGFloat(wHash(i * 5 + 13)) * size.height * 0.22
            let travel = size.height - startY
            // Ease-in so the bead lingers, then accelerates downward.
            let eased = CGFloat(cycle * cycle * (3 - 2 * cycle))
            let headY = startY + travel * eased
            let wobble = sin(t * 1.4 + Double(i) * 2.1) * 5
            let headX = lane * size.width + CGFloat(wobble) + windTilt * eased * 26
            let headR = CGFloat(2.8 + glassIntensity * 3.6 + wHash(i * 5 + 17) * 2.2)

            // Tapering trail of residue beads left in the wake.
            let segs = 11
            for s in 1...segs {
                let f = CGFloat(s) / CGFloat(segs)
                let ty = headY - f * (headY - startY)
                let tr = headR * (1 - f) * 0.62
                if tr > 0.35 {
                    let tx = headX - windTilt * (headY - ty) * 0.22
                    drawBead(context, center: CGPoint(x: tx, y: ty), radius: tr, alpha: (1 - Double(f)) * 0.5)
                }
            }
            drawBead(context, center: CGPoint(x: headX, y: headY), radius: headR, alpha: 0.95)
        }
    }
}

// MARK: - Lightning Storm

/// Convective storm: slow purple cloud-glow pulses with realistic forked
/// lightning bolts. Strikes are time-driven so the flash envelope and bolt
/// shape stay perfectly in sync each frame.
struct LightningStormLayer: View {
    @State private var strikeTime: Double = -100
    @State private var strikeSeed: Int = 1
    /// See `ScrollOffsetTracker` — the cloud base the bolt hangs from
    /// parallaxes with the rest of the mid-distance storm scene.
    @ObservedObject var scrollTracker: ScrollOffsetTracker = ScrollOffsetTracker()

    var body: some View {
        // Ambient charged-cloud glow now lives solely in AtmosphereBackgroundView's
        // `lightField` (storm branch) — this layer used to draw its own duplicate
        // pair of large blurred circles in the same screen region, doubling the
        // blur/compositing cost for no visual gain. This layer now only draws the
        // flash/bolt, which is the part unique to it.
        //
        // Throttled to 30 Hz instead of `.animation` (native refresh rate,
        // up to 120 Hz on ProMotion): the bolt only needs to look crisp for
        // its ~0.4 s lifetime, and most of the time `flash` is near zero —
        // redrawing the Canvas every display frame for that idle stretch
        // was pure wasted CPU/GPU work (and a contributor to device heating
        // during sustained storm conditions).
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let dt = now - strikeTime
            let flash = flashEnvelope(dt)

            Canvas { context, size in
                // Whole-sky flash illuminating the clouds — kept screen-fixed
                // (not translated) so it always fully covers the viewport.
                if flash > 0.001 {
                    context.fill(Path(CGRect(origin: .zero, size: size)),
                                 with: .color(.white.opacity(flash * 0.16)))
                }

                // Bolt + origin bloom parallax with the mid-distance storm scene —
                // isolated to a translated copy of the context so the full-sky
                // flash fill above stays untouched.
                var boltContext = context
                boltContext.translateBy(x: 0, y: scrollTracker.value * 0.16)

                if flash > 0.001 {
                    // Bright bloom where the bolt originates.
                    let originX = CGFloat(wHash(strikeSeed * 1000 + 1)) * size.width
                    let bloom = CGRect(x: originX - 220, y: -180, width: 440, height: 440)
                    boltContext.fill(Path(ellipseIn: bloom),
                                 with: .radialGradient(
                                    Gradient(colors: [Color(red: 0.8, green: 0.85, blue: 1.0).opacity(flash * 0.5), .clear]),
                                    center: CGPoint(x: originX, y: 40), startRadius: 0, endRadius: 240))
                }

                // The bolt itself, drawn for a brief lifetime after the strike.
                if dt >= 0 && dt < 0.42 {
                    let bolt = boltPath(seed: strikeSeed, size: size)
                    let boltAlpha = max(0.0, 1.0 - dt / 0.42) * (0.55 + flash)

                    // Outer glow — thick low-opacity stroke behind bolt path, same visual as blur without GPU filter.
                    boltContext.stroke(bolt,
                                   with: .color(Color(red: 0.66, green: 0.78, blue: 1.0).opacity(min(1, boltAlpha) * 0.18)),
                                   style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round))
                    // Mid halo.
                    boltContext.stroke(bolt,
                                   with: .color(.white.opacity(min(1, boltAlpha) * 0.35)),
                                   style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    // Hot core.
                    boltContext.stroke(bolt,
                                   with: .color(.white.opacity(min(1, boltAlpha))),
                                   style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
            }
            .blendMode(.screen)
        }
        .ignoresSafeArea()
        .onAppear {
            scheduleStrike()
        }
    }

    /// Two-stage decaying flash: a sharp leader followed by a softer return stroke.
    private func flashEnvelope(_ dt: Double) -> Double {
        guard dt >= 0 else { return 0 }
        let a = exp(-dt * 9.0)
        let b = dt > 0.16 ? exp(-(dt - 0.16) * 13.0) * 0.7 : 0
        return min(1.0, a + b)
    }

    /// A jagged main channel from the top to a ground point, plus a couple of
    /// shorter forks branching off. Deterministic in `seed` so it is stable
    /// for the bolt's whole lifetime.
    private func boltPath(seed: Int, size: CGSize) -> Path {
        var path = Path()
        var k = seed * 1000
        func rnd() -> Double { k += 1; return wHash(k) }

        let topX = CGFloat(0.22 + rnd() * 0.56) * size.width
        var pt = CGPoint(x: topX, y: 0)
        path.move(to: pt)

        let groundY = CGFloat(0.62 + rnd() * 0.16) * size.height
        let segs = 12 + Int(rnd() * 6)
        var points: [CGPoint] = [pt]
        for s in 0..<segs {
            let prog = CGFloat(s + 1) / CGFloat(segs)
            let ny = groundY * prog
            let nx = pt.x + CGFloat(rnd() - 0.5) * size.width * 0.13
            pt = CGPoint(x: nx, y: ny)
            path.addLine(to: pt)
            points.append(pt)
        }

        let forkCount = 1 + Int(rnd() * 2)
        for _ in 0..<forkCount {
            let startIdx = max(1, min(points.count - 2, Int(rnd() * Double(points.count - 2)) + 1))
            var fpt = points[startIdx]
            path.move(to: fpt)
            let fsegs = 3 + Int(rnd() * 4)
            let dir: CGFloat = rnd() > 0.5 ? 1 : -1
            for _ in 0..<fsegs {
                fpt = CGPoint(x: fpt.x + dir * size.width * CGFloat(0.02 + rnd() * 0.05),
                              y: fpt.y + size.height * CGFloat(0.03 + rnd() * 0.05))
                path.addLine(to: fpt)
            }
        }
        return path
    }

    private func scheduleStrike() {
        let delay = Double.random(in: 2.4...6.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            strikeSeed = Int.random(in: 1...100_000)
            strikeTime = Date().timeIntervalSinceReferenceDate
            scheduleStrike()
        }
    }
}

// MARK: - Realistic Snow

/// Three depth bands of snow: tiny crisp far flakes, mid flakes, and large
/// soft out-of-focus foreground flakes. Each sways on a sine path and drifts
/// with the wind, over a luminous accumulation glow.
struct RealisticSnowLayer: View {
    let windSpeed: Double
    /// See `ScrollOffsetTracker` — the near flake band parallaxes the most.
    @ObservedObject var scrollTracker: ScrollOffsetTracker = ScrollOffsetTracker()
    @State private var glow = false

    @Environment(\.sandboxAnimationSpeed) private var animSpeed
    @Environment(\.performanceMode) private var performanceMode

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.72, green: 0.86, blue: 1.0).opacity(glow ? 0.18 : 0.08))
                .frame(width: 620, height: 620)
                .blur(radius: performanceMode ? 0 : 145)
                .offset(x: 70, y: -130)

            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
                Canvas { context, size in
                    context.translateBy(x: 0, y: scrollTracker.value * 0.18)
                    let time = timeline.date.timeIntervalSinceReferenceDate * animSpeed
                    let wind = windSpeed * 0.05

                    flakeBand(context, size: size, time: time, wind: wind,
                              count: Int(46 + min(windSpeed / 100, 1) * 18),
                              seedBase: 0, sizeRange: 0.6...1.6, speed: 2.2,
                              opacity: 0.40, sway: 8, blurBig: false)

                    flakeBand(context, size: size, time: time, wind: wind * 1.3,
                              count: 26, seedBase: 5000, sizeRange: 1.6...3.2, speed: 3.6,
                              opacity: 0.55, sway: 16, blurBig: false)

                    flakeBand(context, size: size, time: time, wind: wind * 1.7,
                              count: 9, seedBase: 9000, sizeRange: 4.0...8.0, speed: 5.4,
                              opacity: 0.42, sway: 26, blurBig: true)

                    let snowBase = CGRect(x: 0, y: size.height * 0.93, width: size.width, height: size.height * 0.07)
                    context.fill(Path(snowBase), with: .color(.white.opacity(0.08)))
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) { glow = true }
        }
        .ignoresSafeArea()
    }

    private func flakeBand(_ context: GraphicsContext, size: CGSize, time: Double, wind: Double,
                           count: Int, seedBase: Int, sizeRange: ClosedRange<Double>,
                           speed: Double, opacity: Double, sway: Double, blurBig: Bool) {
        let bigFlakeGradient = Gradient(colors: [.white.opacity(opacity), .white.opacity(0)])
        for i in 0..<count {
            let seed = seedBase + i * 61 + 19
            let baseX = CGFloat(wHash(seed)) * size.width
            let driftX = CGFloat(time * wind).truncatingRemainder(dividingBy: size.width + 80)
            let swayX = CGFloat(sin(time * (0.6 + wHash(seed + 1) * 0.8) + Double(i)) * sway)
            let x = (baseX + driftX + swayX).truncatingRemainder(dividingBy: size.width + 80) - 40
            let fall = speed + wHash(seed + 2) * speed * 0.7
            let y = CGFloat(time * fall + Double(seed) * 1.7).truncatingRemainder(dividingBy: size.height + 60) - 30
            let sz = CGFloat(sizeRange.lowerBound + wHash(seed + 3) * (sizeRange.upperBound - sizeRange.lowerBound))

            let rect = CGRect(x: x - sz / 2, y: y - sz / 2, width: sz, height: sz)
            if blurBig {
                // Soft, defocused foreground flake.
                context.fill(Path(ellipseIn: rect.insetBy(dx: -sz * 0.6, dy: -sz * 0.6)),
                             with: .radialGradient(
                                bigFlakeGradient,
                                center: CGPoint(x: x, y: y), startRadius: 0, endRadius: sz * 1.4))
            } else {
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
            }
        }
    }
}

// MARK: - Volumetric Clouds

/// Billowy parallax clouds built from clusters of soft puffs (bright crowns,
/// shadowed undersides) drifting at speeds that scale with wind. `scattered`
/// gives sparse fair-weather cumulus; otherwise a fuller overcast deck.
struct VolumetricCloudLayer: View {
    let cloudCover: Double
    let windSpeed: Double
    let timeOfDay: TimeOfDay
    var scattered: Bool = false
    /// See `ScrollOffsetTracker` — clouds parallax slower than `airMassLayer`
    /// since they read as sitting further back.
    @ObservedObject var scrollTracker: ScrollOffsetTracker = ScrollOffsetTracker()

    @Environment(\.sandboxAnimationSpeed) private var animSpeed
    @Environment(\.performanceMode) private var performanceMode

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate * animSpeed
                let rows = scattered ? 4 : 6
                let speedBase = 0.5 + windSpeed * 0.022
                let parallaxY = Double(scrollTracker.value) * 0.10

                for row in 0..<rows {
                    let yFrac = (scattered ? 0.08 : 0.02) + Double(row) * (scattered ? 0.17 : 0.135)
                    let cloudsInRow = scattered ? 2 : 3
                    let rowSpeed = speedBase * (0.55 + Double(row) * 0.20)
                    let scale = 0.65 + Double(row) * 0.13

                    for c in 0..<cloudsInRow {
                        let seed = row * 31 + c * 7 + 3
                        let spacing = Double(size.width) / Double(cloudsInRow)
                        let baseX = Double(c) * spacing + wHash(seed) * spacing
                        let span = Double(size.width) + 460
                        let x = (baseX + t * rowSpeed + Double(row) * 120).truncatingRemainder(dividingBy: span) - 230
                        let y = Double(size.height) * yFrac + parallaxY
                        drawCloud(context, center: CGPoint(x: x, y: y),
                                  scale: scale, cover: cloudCover, seed: seed, tod: timeOfDay)
                    }
                }

                // Low overcast deck welds the bases together.
                if !scattered {
                    let deck = CGRect(x: -size.width * 0.05, y: size.height * 0.74,
                                      width: size.width * 1.10, height: size.height * 0.34)
                    context.fill(Path(deck), with: .color(.white.opacity(cloudCover * 0.09)))
                }
            }
        }
        .ignoresSafeArea()
    }

    private func drawCloud(_ context: GraphicsContext, center: CGPoint,
                           scale: Double, cover: Double, seed: Int, tod: TimeOfDay) {
        let baseW = 150.0 * scale
        let puffCount = 7
        let crown = cloudTint(for: tod)
        // Raised from (0.08 + cover*0.18): at typical cover the puffs were
        // reading as a nearly invisible tint over the sky gradient instead
        // of a legible cloud shape.
        let topAlpha = 0.16 + cover * 0.30
        // Horizontal light bias standing in for sun azimuth (altitude alone doesn't
        // give a direction): low sun at dawn/sunset lights clouds from one side,
        // near-overhead day light is closer to top-down. Ties puff highlight and
        // underside shadow to a consistent light source instead of always
        // straight-down, the biggest single lever for reading as real cloud volume.
        let light = lightBias(for: tod)

        // Shadowed underside, offset opposite the light direction.
        let shadowRect = CGRect(x: center.x - CGFloat(baseW) * 0.95 + light * CGFloat(baseW) * 0.35,
                                y: center.y + CGFloat(baseW) * 0.06,
                                width: CGFloat(baseW) * 1.9, height: CGFloat(baseW) * 0.62)
        context.fill(Path(ellipseIn: shadowRect), with: .color(.black.opacity(cover * 0.10 + 0.04)))

        // Overlapping puffs, tallest in the middle to read as a cumulus crown.
        let puffGradient = Gradient(colors: [crown.opacity(topAlpha), crown.opacity(topAlpha * 0.62), crown.opacity(0)])
        for p in 0..<puffCount {
            let f = Double(p) / Double(puffCount - 1)          // 0...1 left -> right
            let lift = sin(f * .pi)                            // peak in the middle
            let px = center.x + CGFloat((f - 0.5) * baseW * 1.7)
            let py = center.y - CGFloat(lift * baseW * 0.30)
                + CGFloat((wHash(seed + p) - 0.5) * baseW * 0.18)
            let r = CGFloat(baseW * (0.30 + lift * 0.30 + wHash(seed + p * 3) * 0.12))
            let rect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
            // Highlight biased toward the light source so every puff's crown catches
            // sun from the same consistent angle, rather than a flat top-down glow.
            let highlightCenter = CGPoint(x: px - light * r * 0.45, y: py - r * 0.30)
            let shade = GraphicsContext.Shading.radialGradient(
                puffGradient,
                center: highlightCenter, startRadius: 0, endRadius: r)
            context.fill(Path(ellipseIn: rect), with: shade)
        }
    }

    private func lightBias(for tod: TimeOfDay) -> CGFloat {
        switch tod {
        case .dawn:   return -0.6   // low sun in the east — light from the left
        case .sunset: return 0.6    // low sun in the west — light from the right
        case .day:    return 0.15   // near-overhead, slight bias toward the anchored sun position
        case .night:  return 0.0    // flat, moonlit
        }
    }

    private func cloudTint(for tod: TimeOfDay) -> Color {
        switch tod {
        case .dawn:   return Color(red: 1.0, green: 0.93, blue: 0.88)
        case .day:    return .white
        case .sunset: return Color(red: 1.0, green: 0.90, blue: 0.82)
        case .night:  return Color(red: 0.82, green: 0.86, blue: 0.95)
        }
    }
}

// MARK: - Drifting Fog

/// Layered fog banks: soft drifting blobs that thicken toward the ground,
/// with a near-opaque base — the world dissolving into haze.
struct DriftingFogLayer: View {
    let windSpeed: Double
    /// See `ScrollOffsetTracker` — fog banks sit close to the viewer, so they
    /// parallax noticeably as the content scrolls past them.
    @ObservedObject var scrollTracker: ScrollOffsetTracker = ScrollOffsetTracker()

    @Environment(\.sandboxAnimationSpeed) private var animSpeed
    @Environment(\.performanceMode) private var performanceMode

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { timeline in
            Canvas { context, size in
                context.translateBy(x: 0, y: scrollTracker.value * 0.20)
                let t = timeline.date.timeIntervalSinceReferenceDate * animSpeed

                for layer in 0..<11 {
                    let yFrac = 0.08 + Double(layer) * 0.085
                    let speed = 0.6 + windSpeed * 0.012 + Double(layer) * 0.09
                    let density = 0.032 + (yFrac - 0.08) * 0.088
                    let blobs = 3
                    for b in 0..<blobs {
                        let seed = layer * 53 + b * 17 + 5
                        let w = Double(size.width) * (0.55 + wHash(seed) * 0.5)
                        let h = Double(size.height) * (0.07 + Double(layer % 2) * 0.04)
                        let span = Double(size.width) + w
                        let baseX = wHash(seed + 1) * Double(size.width)
                        let x = (baseX + t * speed + Double(layer * 90)).truncatingRemainder(dividingBy: span) - w * 0.5
                        let y = Double(size.height) * yFrac
                        let rect = CGRect(x: x, y: y, width: w, height: h)
                        context.fill(Path(ellipseIn: rect),
                                     with: .radialGradient(
                                        Gradient(colors: [.white.opacity(density), .white.opacity(0)]),
                                        center: CGPoint(x: x + w / 2, y: y + h / 2),
                                        startRadius: 0, endRadius: w / 2))
                    }
                }

                // Dense fog floor.
                let groundRect = CGRect(x: -size.width * 0.05, y: size.height * 0.70,
                                        width: size.width * 1.10, height: size.height * 0.30)
                context.fill(Path(groundRect), with: .color(.white.opacity(0.15)))
                let baseRect = CGRect(x: -size.width * 0.05, y: size.height * 0.86,
                                      width: size.width * 1.10, height: size.height * 0.14)
                context.fill(Path(baseRect), with: .color(.white.opacity(0.11)))
            }
        }
        .ignoresSafeArea()
    }
}
#endif
