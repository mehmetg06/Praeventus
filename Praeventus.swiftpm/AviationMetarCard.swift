#if canImport(SwiftUI)
import SwiftUI

/// Live aeronautical observation card rendered in aviation monospaced style.
/// Data source: NOAA aviationweather.gov (Public Domain) via the backend.
struct AviationMetarCard: View {
    let metar: MetarSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading
            Divider().overlay(.white.opacity(0.12))
            mainGrid
            if let raw = metar.rawOb {
                rawObRow(raw)
            }
        }
        .padding(20)
        .background(ThinGlassShape(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(categoryColor.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Sub-views

    private var heading: some View {
        HStack(spacing: 10) {
            Image(systemName: "airplane.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(categoryColor)

            Text(String(localized: "metar.heading", defaultValue: "LIVE METAR"))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.56))

            Spacer()

            flightCategoryBadge
        }
    }

    private var flightCategoryBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(categoryColor)
                .frame(width: 7, height: 7)
            Text(metar.flightCategory.displayLabel)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(categoryColor)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(categoryColor.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(categoryColor.opacity(0.30), lineWidth: 0.5))
    }

    private var mainGrid: some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, alignment: .leading, spacing: 14) {
            // Station
            metarCell(
                label: String(localized: "metar.station", defaultValue: "STATION"),
                value: metar.station,
                icon: "antenna.radiowaves.left.and.right"
            )
            // Wind
            metarCell(
                label: String(localized: "metar.wind", defaultValue: "WIND"),
                value: metar.windString,
                icon: "wind"
            )
            // Altimeter
            metarCell(
                label: String(localized: "metar.altimeter", defaultValue: "ALTIMETER"),
                value: metar.altimeterString,
                icon: "gauge.with.dots.needle.bottom.50percent"
            )
            // Visibility
            metarCell(
                label: String(localized: "metar.visibility", defaultValue: "VISIBILITY"),
                value: metar.visibilityString,
                icon: "eye"
            )
            // Present weather (only if available)
            if let wx = metar.presentWeather, !wx.isEmpty {
                metarCell(
                    label: String(localized: "metar.wx", defaultValue: "WEATHER"),
                    value: wx,
                    icon: "cloud.bolt"
                )
            }
            // Ceiling
            if let ceil = metar.ceilingFt {
                metarCell(
                    label: String(localized: "metar.ceiling", defaultValue: "CEILING"),
                    value: "\(ceil) ft",
                    icon: "cloud"
                )
            }
        }
    }

    private func metarCell(label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(0.7)
            }
            .foregroundStyle(.white.opacity(0.44))

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func rawObRow(_ raw: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(String(localized: "metar.raw", defaultValue: "RAW"))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.35))
            Text(raw)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    // MARK: - Category colour

    private var categoryColor: Color {
        switch metar.flightCategory {
        case .vfr:  return Color(red: 0.22, green: 0.82, blue: 0.42)
        case .mvfr: return Color(red: 0.26, green: 0.60, blue: 1.00)
        case .ifr:  return Color(red: 0.95, green: 0.30, blue: 0.28)
        case .lifr: return Color(red: 0.68, green: 0.20, blue: 0.75)
        }
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        AviationMetarCard(metar: MetarSnapshot(
            station: "LTBA",
            observationTime: "2026-06-30T10:00:00Z",
            windSpeedKt: 12,
            windGustKt: 22,
            windDirection: 270,
            altimeterInHg: 29.92,
            visibilityMiles: 8.0,
            presentWeather: nil,
            ceilingFt: 4500,
            rawOb: "LTBA 301000Z 27012G22KT 8000 FEW045 BKN090 24/14 A2992 RMK AO2"
        ))
        .padding(22)
    }
}
#endif
#endif
