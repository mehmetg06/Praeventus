#if canImport(SwiftUI)
import SwiftUI

/// Frosted-glass dropdown shown beneath the search bar as the user types.
///
/// Each row displays the city name (primary) and the administrative region +
/// country as a dimmer subtitle — e.g. "Mérida" over "Yucatán, Mexico".
/// When `suggestions` is empty but `error` is set, a single informational row
/// is shown instead of an empty panel.
struct SearchSuggestionsView: View {
    let suggestions: [GeocodingResult]
    let error: String?
    var onSelect: (GeocodingResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if suggestions.isEmpty, let msg = error {
                emptyRow(msg)
            } else {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, result in
                    if index > 0 { rowDivider }
                    suggestionRow(result)
                }
            }
        }
        .padding(.vertical, 4)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.34), radius: 22, y: 10)
    }

    // MARK: - Rows

    private func suggestionRow(_ result: GeocodingResult) -> some View {
        Button(action: { onSelect(result) }) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !result.subtitle.isEmpty {
                        Text(result.subtitle)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.54))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(.white.opacity(0.30))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emptyRow(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.38))
            Text(message)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(0.52))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.09))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    // MARK: - Background

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.38))
        }
    }
}
#endif
