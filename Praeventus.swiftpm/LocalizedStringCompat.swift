import Foundation

extension String {
    /// Compatibility initializer for Linux/headless SwiftPM builds where the
    /// Apple SDK `String(localized:defaultValue:)` overload is unavailable.
    init(localized key: String, defaultValue: String) {
        let value = NSLocalizedString(key, tableName: nil, bundle: .module, value: defaultValue, comment: "")
        self = value == key ? defaultValue : value
    }
}
