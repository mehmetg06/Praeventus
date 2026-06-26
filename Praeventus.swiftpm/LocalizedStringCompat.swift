import Foundation

extension String {
    /// Compatibility initializer for Linux/headless SwiftPM builds where the
    /// Apple SDK `String(localized:defaultValue:)` overload is unavailable.
    init(localized key: String, defaultValue: String) {
        #if SWIFT_PACKAGE
        let localizationBundle = Bundle.module
        #else
        let localizationBundle = Bundle.main
        #endif

        let value = NSLocalizedString(key, tableName: nil, bundle: localizationBundle, value: defaultValue, comment: "")
        self = value == key ? defaultValue : value
    }
}
