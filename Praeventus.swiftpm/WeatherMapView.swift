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

    private var workerURL: String { WeatherSettings.cloudflareWorkerURL }

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
            }
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

    private func refreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(300))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.5)) { overlayAlpha = 0.15 }
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }
            lastRefresh = Date()
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
            alpha: overlayAlpha
        )
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject {
        private var activeLayers: Set<MapOverlayLayer> = []
        private var overlayByLayer: [MapOverlayLayer: WorkerTileOverlay] = [:]
        var currentAlpha: Double = 1.0

        func apply(
            mapView: MKMapView,
            workerURL: String,
            enabledLayers: Set<MapOverlayLayer>,
            alpha: Double
        ) {
            currentAlpha = alpha

            let toAdd    = enabledLayers.subtracting(activeLayers)
            let toRemove = activeLayers.subtracting(enabledLayers)

            for layer in toRemove {
                if let ov = overlayByLayer.removeValue(forKey: layer) {
                    mapView.removeOverlay(ov)
                }
            }

            for layer in toAdd {
                let ov = WorkerTileOverlay(workerURL: workerURL, layer: layer)
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

/// Routes tile requests through the Cloudflare Worker so upstream tile servers
/// never see the device IP, and KV caching throttles request volume.
final class WorkerTileOverlay: MKTileOverlay, @unchecked Sendable {
    let layer: MapOverlayLayer
    private let workerBase: String

    init(workerURL: String, layer: MapOverlayLayer) {
        self.layer      = layer
        self.workerBase = workerURL
        super.init(urlTemplate: nil)
        canReplaceMapContent = false
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let str = "\(workerBase)\(layer.tilePathSuffix)?z=\(path.z)&x=\(path.x)&y=\(path.y)"
        return URL(string: str) ?? URL(string: workerBase)!
    }
}
#endif

#endif
