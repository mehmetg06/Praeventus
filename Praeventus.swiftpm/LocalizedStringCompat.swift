import Foundation

extension String {
    /// Compatibility initializer for Linux/headless SwiftPM builds where the
    /// Apple SDK `String(localized:defaultValue:)` overload is unavailable.
    init(localized key: String, defaultValue: String) {
        let localizationBundle: Bundle
        #if SWIFT_PACKAGE
        if let module = Bundle(identifier: "com.mehmetg06.praeventus") {
            localizationBundle = module
        } else {
            localizationBundle = Bundle.main
        }
        #else
        localizationBundle = Bundle.main
        #endif

        let value = NSLocalizedString(key, tableName: nil, bundle: localizationBundle, value: defaultValue, comment: "")
        self = value == key ? defaultValue : value
    }
}
