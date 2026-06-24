// swift-tools-version: 6.0

import PackageDescription
#if canImport(AppleProductTypes)
import AppleProductTypes
#endif

let sources = [
    "App.swift",
    "WeatherData.swift",
    "WeatherStore.swift",
    "PraeventusRootView.swift",
    "AtmosphereBackgroundView.swift",
    "GlassComponents.swift",
    "HomeView.swift",
    "WeatherLabView.swift",
    "SettingsView.swift"
]

#if canImport(AppleProductTypes)
let supportedPlatforms: [SupportedPlatform] = [.iOS("17.0")]
let packageProducts: [Product] = [
    .iOSApplication(
        name: "Praeventus",
        targets: ["AppModule"],
        bundleIdentifier: "com.mehmetg06.praeventus",
        teamIdentifier: "",
        displayVersion: "0.1",
        bundleVersion: "1",
        appIcon: .placeholder(icon: .cloud),
        accentColor: .presetColor(.blue),
        supportedDeviceFamilies: [.pad],
        supportedInterfaceOrientations: [.portrait, .landscapeLeft, .landscapeRight]
    )
]
#else
let supportedPlatforms: [SupportedPlatform] = [.macOS("14.0")]
let packageProducts: [Product] = [.executable(name: "Praeventus", targets: ["AppModule"])]
#endif

let package = Package(
    name: "Praeventus",
    platforms: supportedPlatforms,
    products: packageProducts,
    targets: [
        .executableTarget(
            name: "AppModule",
            path: ".",
            sources: sources
        )
    ],
    swiftLanguageModes: [.v6]
)
