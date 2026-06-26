#if canImport(SwiftUI)
import SwiftUI

/// Prominent health/safety card surfacing `ThermalPredictionEngine` output:
/// heatwave alerts, the current hour's thermal/Foehn risk, UV time-to-burn and
/// the best outdoor windows. Rendered in the app's frosted `VisionGlassCard`.
struct HealthInsightsCard: View {
    let insights: HealthInsights

    var body: some View {
        VisionGlassCard(cornerRadius: 28) {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let alert = insights.heatwaveAlert {
                    heatwaveBanner(alert)
                }

                riskRow

                divider
                uvRow

                divider
                bestHoursRow
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 14, weight: .semibold))
            Text(String(localized: "health.heading", defaultValue: "HEALTH INSIGHTS"))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.4)
            Spacer()
        }
        .foregroundStyle(.white.opacity(0.56))
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 0.5)
    }

    // MARK: - Heatwave alert (critical accent)

    private func heatwaveBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "thermometer.sun.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.32, blue: 0.18), Color(red: 1.0, green: 0.58, blue: 0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "health.heatwave", defaultValue: "HEATWAVE ALERT"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.3))
                Text(text)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(red: 1.0, green: 0.36, blue: 0.18).opacity(0.16))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(red: 1.0, green: 0.45, blue: 0.22).opacity(0.45), lineWidth: 0.75)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Current hour risk + Foehn

    private var riskRow: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(riskColor.opacity(0.16))
                    .frame(width: 38, height: 38)
                Image(systemName: riskSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(riskColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(riskTitle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    if insights.isFoehnActive {
                        Label(
                            String(localized: "health.foehn", defaultValue: "Foehn"),
                            systemImage: "wind"
                        )
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.6, blue: 0.3))
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(Color(red: 1.0, green: 0.6, blue: 0.3).opacity(0.16))
                        .clipShape(Capsule())
                    }
                }
                Text(insights.currentRiskWarning)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - UV time-to-burn

    private var uvRow: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(uvColor.opacity(0.16))
                    .frame(width: 38, height: 38)
                Image(systemName: "sun.max.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(uvColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "health.uv.title", defaultValue: "Time to sunburn"))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(String(
                    format: String(localized: "health.uv.subtitle", defaultValue: "Skin type %lld · SPF %lld"),
                    insights.skinType.rawValue, insights.spf
                ))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.52))
            }

            Spacer(minLength: 0)

            Text(burnTimeText)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(uvColor)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(uvColor.opacity(0.16))
                .clipShape(Capsule())
        }
    }

    // MARK: - Best hours outside

    private var bestHoursRow: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.16))
                    .frame(width: 38, height: 38)
                Image(systemName: "figure.walk.motion")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "health.bestHours", defaultValue: "Best hours outside"))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(insights.bestHours)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Derived presentation

    private var riskColor: Color {
        switch insights.currentRiskLevel {
        case .safe: return .green
        case .caution: return .orange
        case .extremeDanger: return .red
        }
    }

    private var riskSymbol: String {
        if insights.riskKind == .cold {
            switch insights.currentRiskLevel {
            case .safe: return "checkmark.shield.fill"
            case .caution: return "thermometer.snowflake"
            case .extremeDanger: return "snowflake"
            }
        }
        switch insights.currentRiskLevel {
        case .safe: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .extremeDanger: return "exclamationmark.octagon.fill"
        }
    }

    private var riskTitle: String {
        if insights.riskKind == .cold {
            switch insights.currentRiskLevel {
            case .safe: return String(localized: "health.risk.cold.safe", defaultValue: "Low cold risk")
            case .caution: return String(localized: "health.risk.cold.caution", defaultValue: "Severe cold")
            case .extremeDanger: return String(localized: "health.risk.cold.danger", defaultValue: "Frostbite & hypothermia risk")
            }
        }
        switch insights.currentRiskLevel {
        case .safe: return String(localized: "health.risk.safe", defaultValue: "Low thermal risk")
        case .caution: return String(localized: "health.risk.caution", defaultValue: "Moderate heat stress")
        case .extremeDanger: return String(localized: "health.risk.danger", defaultValue: "Extreme heat danger")
        }
    }

    private var uvColor: Color {
        guard insights.hasBurnRisk else { return .green }
        switch insights.minutesToBurn {
        case ..<15: return .red
        case 15..<30: return .orange
        default: return .yellow
        }
    }

    /// Human-friendly burn time: a safe state when there is no UV, otherwise
    /// minutes, rolling up into hours once the window is long.
    private var burnTimeText: String {
        guard insights.hasBurnRisk else {
            return String(localized: "health.uv.safe", defaultValue: "No risk")
        }
        let minutes = insights.minutesToBurn
        if minutes < 60 {
            return String(format: String(localized: "health.uv.min", defaultValue: "%lld min"), minutes)
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return String(format: String(localized: "health.uv.hour", defaultValue: "%lld h"), hours)
        }
        return String(format: String(localized: "health.uv.hourMin", defaultValue: "%lld h %lld min"), hours, remainder)
    }
}
#endif
