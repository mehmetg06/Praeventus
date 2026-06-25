#if canImport(SwiftUI)
import SwiftUI

/// Rounded iOS-native search bar with a leading magnifying-glass icon and a
/// trailing "use my location" button.
///
/// `isFocused` accepts a `FocusState<Bool>.Binding` from the parent so the
/// keyboard can be raised or dismissed programmatically (e.g. when the user
/// taps the idle-state CTA).
struct CitySearchBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    /// When true, replaces the magnifying glass with an activity indicator.
    var isSearching: Bool = false
    /// When true, replaces the location icon with an activity indicator.
    var isLocating: Bool = false
    var onLocationTap: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            leadingIcon
            searchField
            if !text.isEmpty { clearButton.transition(.scale.combined(with: .opacity)) }
            divider
            locationButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(background)
        .animation(.easeInOut(duration: 0.18), value: isFocused.wrappedValue)
        .animation(.easeInOut(duration: 0.14), value: text.isEmpty)
        .animation(.easeInOut(duration: 0.18), value: isSearching)
    }

    // MARK: - Subviews

    private var leadingIcon: some View {
        Group {
            if isSearching {
                ProgressView()
                    .tint(.white.opacity(0.65))
                    .scaleEffect(0.82)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(isFocused.wrappedValue ? 0.85 : 0.50))
            }
        }
        .frame(width: 20, height: 20)
    }

    private var searchField: some View {
        TextField(
            "",
            text: $text,
            prompt: Text("search.inline.placeholder")
                .foregroundStyle(.white.opacity(0.38))
        )
        .font(.system(size: 16, weight: .regular, design: .rounded))
        .foregroundStyle(.white)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .submitLabel(.search)
        .focused(isFocused)
    }

    private var clearButton: some View {
        Button(action: { text = "" }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.42))
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.20))
            .frame(width: 1, height: 18)
    }

    private var locationButton: some View {
        Button(action: onLocationTap) {
            Group {
                if isLocating {
                    ProgressView()
                        .tint(.cyan.opacity(0.90))
                        .scaleEffect(0.82)
                } else {
                    Image(systemName: "location.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.cyan.opacity(0.88))
                }
            }
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .disabled(isLocating)
        .animation(.easeInOut(duration: 0.18), value: isLocating)
    }

    // MARK: - Background

    private var background: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.white.opacity(0.09))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        .white.opacity(isFocused.wrappedValue ? 0.40 : 0.17),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(isFocused.wrappedValue ? 0.22 : 0.10), radius: 10, y: 4)
    }
}
#endif
