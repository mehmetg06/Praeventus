#if canImport(SwiftUI)
import SwiftUI
#if canImport(MapKit)
import MapKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Overlay layer options

enum MapOverlayLayer: String, CaseIterable, Hashable, Identifiable {
    case nexrad    = "NEXRAD"
    case satellite = "IR SAT"
    case dwd       = "DWD"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nexrad:    return String(localized: "map.layer.nexrad",    defaultValue: "NEXRAD Radar")
        case .satellite: return String(localized: "map.layer.satellite", defaultValue: "IR Satellite")
        case .dwd:       return String(localized: "map.layer.dwd",       defaultValue: "DWD Radar")
        }
    }

    var icon: String {
        switch self {
        case .nexrad:    return "dot.radiowaves.up.forward"
        case .satellite: return "globe.americas.fill"
        case .dwd:       return "cloud.rain.fill"
        }
    }

    var tilePathSuffix: String {
        switch self {
        case .nexrad:    return "/tile/nexrad"
        case .satellite: return "/tile/satellite"
        case .dwd:       return "/tile/dwd"
        }
    }

    /// Base alpha for the tile overlay renderer.
    var defaultAlpha: CGFloat {
        switch self {
        case .nexrad:    return 0.72
        case .satellite: return 0.65
        case .dwd:       return 0.68
        }
    }
}

// MARK: - WeatherMapView

struct WeatherMapView: View {
    @ObservedObject var store: WeatherStore
    @State private var enabledLayers: Set<MapOverlayLayer> = [.nexrad]
    @State private var overlayAlpha: Double = 1.0
    @State private var lastRefresh: Date = Date()
    /// Bumped every 5 minutes by `refreshLoop()`. Forces `RadarMapContainer`
    /// to rebuild its tile overlays (see `Coordinator.apply`) so the "Live"
    /// label is actually backed by a re-fetched tile, not just a cosmetic
    /// opacity fade — see that function's doc comment for why this exists.
    @State private var refreshToken: Int = 0

    private var workerURL: String { WeatherSettings.backendBaseURL }

    var body: some View {
        ZStack(alignment: .bottom) {
            mapContent.ignoresSafeArea(edges: .top)

            layerControls
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .task {
            await refreshLoop()
        }
    }

    // MARK: - Map

    @ViewBuilder
    private var mapContent: some View {
        #if canImport(UIKit) && canImport(MapKit)
        RadarMapContainer(
            workerURL: workerURL,
            enabledLayers: enabledLayers,
            overlayAlpha: overlayAlpha,
            centreCoordinate: store.location.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            },
            refreshToken: refreshToken
        )
        #else
        ZStack {
            Color(white: 0.08).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "map.fill")
                    .font(.system(size: 44, weight: .thin))
                    .foregroundStyle(.white.opacity(0.4))
                Text(String(localized: "map.unavailable", defaultValue: "Map requires iOS/iPadOS"))
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        #endif
    }

    // MARK: - Layer control panel

    private var layerControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(overlayAlpha > 0.5 ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(overlayAlpha > 0.5
                     ? String(localized: "map.live", defaultValue: "Live")
                     : String(localized: "map.updating", defaultValue: "Updating…"))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
                Text(refreshLabel)
                    .font(.system(size: 10, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.42))
            }

            HStack(spacing: 8) {
                ForEach(MapOverlayLayer.allCases) { layer in
                    layerChip(layer)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.90))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func layerChip(_ layer: MapOverlayLayer) -> some View {
        let isOn = enabledLayers.contains(layer)
        return Button {
            if isOn { enabledLayers.remove(layer) } else { enabledLayers.insert(layer) }
        } label: {
            Label(layer.rawValue, systemImage: layer.icon)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isOn ? .black : .white.opacity(0.65))
                .padding(.vertical, 7)
                .padding(.horizontal, 12)
                .background(isOn ? Color.white : Color.white.opacity(0.12))
                .clipShape(Capsule())
                .animation(.easeInOut(duration: 0.18), value: isOn)
        }
    }

    private var refreshLabel: String {
        let interval = Int(-lastRefresh.timeIntervalSinceNow)
        if interval < 60 { return String(localized: "map.justNow", defaultValue: "just now") }
        return "\(interval / 60)m ago"
    }

    // MARK: - Auto-refresh (5-minute KV TTL cycle)

    /// Runs every 5 minutes to match the backend's tile TTL (`deno/cache.ts`).
    /// Previously this only faded `overlayAlpha` and bumped `lastRefresh` (the
    /// "Live"/"Xm ago" label) — it never asked MapKit to re-fetch a tile, so
    /// the same radar/satellite imagery from the initial load stayed on
    /// screen indefinitely while the UI's green dot and label implied it was
    /// current. Bumping `refreshToken` now forces `Coordinator.apply` to
    /// rebuild every active overlay with a fresh cache-busting query param.
    private func refreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(300))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.5)) { overlayAlpha = 0.15 }
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }
            lastRefresh = Date()
            refreshToken += 1
            withAnimation(.easeIn(duration: 0.5)) { overlayAlpha = 1.0 }
        }
    }
}

// MARK: - UIKit / MapKit wrapper

#if canImport(UIKit) && canImport(MapKit)
import CoreLocation

struct RadarMapContainer: UIViewRepresentable {
    let workerURL: String
    let enabledLayers: Set<MapOverlayLayer>
    let overlayAlpha: Double
    let centreCoordinate: CLLocationCoordinate2D?
    let refreshToken: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType = .standard
        map.showsCompass = true
        map.showsScale = true
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.isPitchEnabled = false
        map.delegate = context.coordinator

        let centre = centreCoordinate ?? CLLocationCoordinate2D(latitude: 40, longitude: 28)
        map.setRegion(
            MKCoordinateRegion(center: centre,
                               span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)),
            animated: false
        )
        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.apply(
            mapView: uiView,
            workerURL: workerURL,
            enabledLayers: enabledLayers,
            alpha: overlayAlpha,
            refreshToken: refreshToken
        )
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject {
        private var activeLayers: Set<MapOverlayLayer> = []
        private var overlayByLayer: [MapOverlayLayer: WorkerTileOverlay] = [:]
        private var lastRefreshToken: Int?
        var currentAlpha: Double = 1.0

        func apply(
            mapView: MKMapView,
            workerURL: String,
            enabledLayers: Set<MapOverlayLayer>,
            alpha: Double,
            refreshToken: Int
        ) {
            currentAlpha = alpha

            // On a refresh tick (token changed), rebuild every active overlay
            // — not just the layer-set difference — so MapKit actually issues
            // a new tile request instead of reusing the overlay instance (and
            // its cached imagery) from the last add. `WorkerTileOverlay` bakes
            // `refreshToken` into the tile URL as a cache-buster.
            let didRefresh = lastRefreshToken != refreshToken
            lastRefreshToken = refreshToken

            let toAdd    = didRefresh ? enabledLayers : enabledLayers.subtracting(activeLayers)
            let toRemove = didRefresh ? activeLayers  : activeLayers.subtracting(enabledLayers)

            for layer in toRemove {
                if let ov = overlayByLayer.removeValue(forKey: layer) {
                    mapView.removeOverlay(ov)
                }
            }

            for layer in toAdd {
                let ov = WorkerTileOverlay(workerURL: workerURL, layer: layer, cacheBucket: refreshToken)
                ov.canReplaceMapContent = false
                mapView.addOverlay(ov, level: .aboveRoads)
                overlayByLayer[layer] = ov
            }

            activeLayers = enabledLayers

            // Propagate alpha to any renderer already created
            for ov in overlayByLayer.values {
                if let renderer = mapView.renderer(for: ov) as? MKTileOverlayRenderer {
                    renderer.alpha = CGFloat(alpha * Double(ov.layer.defaultAlpha))
                }
            }
        }
    }
}

// MKMapViewDelegate conformance — @preconcurrency lets an @MainActor class
// satisfy a pre-concurrency protocol without nonisolated boilerplate.
extension RadarMapContainer.Coordinator: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let tile = overlay as? WorkerTileOverlay else {
            return MKOverlayRenderer(overlay: overlay)
        }
        let renderer = MKTileOverlayRenderer(tileOverlay: tile)
        renderer.alpha = CGFloat(currentAlpha * Double(tile.layer.defaultAlpha))
        return renderer
    }
}

// MARK: - WorkerTileOverlay

/// Routes tile requests through the backend so upstream tile servers
/// never see the device IP, and KV caching throttles request volume.
final class WorkerTileOverlay: MKTileOverlay, @unchecked Sendable {
    let layer: MapOverlayLayer
    private let workerBase: String
    /// Cache-busting token (the map view's 5-minute `refreshToken`), so a new
    /// overlay generation actually re-requests tile imagery from the backend
    /// instead of reusing whatever MapKit/URLSession cached under the same URL.
    private let cacheBucket: Int

    init(workerURL: String, layer: MapOverlayLayer, cacheBucket: Int) {
        self.layer       = layer
        self.workerBase  = workerURL
        self.cacheBucket = cacheBucket
        super.init(urlTemplate: nil)
        canReplaceMapContent = false
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let str = "\(workerBase)\(layer.tilePathSuffix)?z=\(path.z)&x=\(path.x)&y=\(path.y)&t=\(cacheBucket)"
        if let url = URL(string: str) { return url }
        // MKTileOverlay requires a non-optional URL back, and `workerBase` is
        // a fixed, developer-configured backend base URL (never derived from
        // tile coordinates), so this is effectively unreachable — but avoid a
        // force-unwrap in favor of `URL(fileURLWithPath:)`, which cannot fail.
        // A file URL fetch simply 404s instead of crashing the app.
        return URL(fileURLWithPath: "/")
    }
}
#endif

#endif
