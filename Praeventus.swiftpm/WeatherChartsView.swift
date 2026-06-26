#if canImport(SwiftUI) && canImport(Charts)
import SwiftUI
import Charts

/// Scientific visualization of the live forecast.
///
/// - Hourly temperature as a smooth `LineMark`.
/// - Hourly precipitation probability as `BarMark` sharing the time axis.
/// - Daily min/max as an `AreaMark` band (the honest "spread" / uncertainty)
///   with a mean `LineMark` through it.
struct WeatherChartsView: View {
    let hourly: [HourlyPoint]
    let daily: [DailyRange]
    var tint: Color = .cyan

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !hourly.isEmpty {
                temperatureCard
                precipitationCard
            }
            if !daily.isEmpty {
                rangeCard
            }
            if hourly.isEmpty && daily.isEmpty {
                Text("charts.empty")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            }
        }
    }

    // MARK: - Cards

    private var temperatureCard: some View {
        chartCard(titleKey: "charts.temperature", symbol: "thermometer.medium") {
            Chart(hourly) { point in
                LineMark(
                    x: .value("time", point.date),
                    y: .value("temperature", point.temperature)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tint)

                AreaMark(
                    x: .value("time", point.date),
                    y: .value("temperature", point.temperature)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [tint.opacity(0.35), tint.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .chartYAxisLabel(String(localized: "charts.unit.celsius", defaultValue: "°C"))
            .frame(height: 170)
        }
    }

    private var precipitationCard: some View {
        chartCard(titleKey: "charts.precipitation", symbol: "umbrella") {
            Chart(hourly) { point in
                BarMark(
                    x: .value("time", point.date),
                    y: .value("probability", point.precipitationProbability)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.9), .cyan.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .chartYScale(domain: 0...100)
            .chartYAxisLabel("%")
            .frame(height: 150)
        }
    }

    private var rangeCard: some View {
        chartCard(titleKey: "charts.range", symbol: "chart.bar.doc.horizontal") {
            Chart(daily) { day in
                AreaMark(
                    x: .value("day", day.date, unit: .day),
                    yStart: .value("min", day.min),
                    yEnd: .value("max", day.max)
                )
                .foregroundStyle(tint.opacity(0.22))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("day", day.date, unit: .day),
                    y: .value("mean", day.mean)
                )
                .foregroundStyle(.white)
                .interpolationMethod(.catmullRom)
            }
            .chartYAxisLabel(String(localized: "charts.unit.celsius", defaultValue: "°C"))
            .frame(height: 170)
        }
    }

    // MARK: - Layout helper

    @ViewBuilder
    private func chartCard<Content: View>(
        titleKey: LocalizedStringKey,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .light))
                Text(titleKey)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.66))

            content()
                .foregroundStyle(.white)
                .tint(tint)
        }
        .padding(18)
        .background(ThinGlassShape(cornerRadius: 26))
    }
}
#endif
