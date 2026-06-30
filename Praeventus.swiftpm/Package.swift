// swift-tools-version: 6.0

import PackageDescription
#if canImport(AppleProductTypes)
import AppleProductTypes
#endif

let sources = [
    "App.swift",
    // Data layer (pure Foundation — also builds on Linux)
    "OpenMeteoModels.swift",
    "CloudflareWeatherProvider.swift",
    "WeatherModel.swift",
    "WeatherMapping.swift",
    "WeatherFusion.swift",
    "ForecastCache.swift",
    "WeatherData.swift",
    "LocalizedStringCompat.swift",
    "StorySentiment.swift",
    // Domain + state
    "AtmosphericEngine.swift",
    "AstronomicalEngine.swift",
    "MinutecastEngine.swift",
    "StormSensorEngine.swift",
    "WeatherNarrativeEngine.swift",
    "MeteorologicalExpertSystem.swift",
    "ThermalPredictionEngine.swift",
    "HealthInsights.swift",
    "SensorCalibration.swift",
    "WeatherStore.swift",
    // Activity system
    "Activity.swift",
    "ActivityAnalysisEngine.swift",
    // Location
    "LocationProvider.swift",
    // Search MVVM
    "SearchViewModel.swift",
    // METAR domain model
    "MetarSnapshot.swift",
    // UI
    "WeatherCondition+Palette.swift",
    "WeatherMapView.swift",
    "AviationMetarCard.swift",
    "SandboxEnvironment.swift",
    "PraeventusRootView.swift",
    "AtmosphereBackgroundView.swift",
    "WeatherEffectLayers.swift",
    "SunHaloOpticsLayer.swift",
    "GlassComponents.swift",
    "HealthInsightsCard.swift",
    "CitySearchBar.swift",
    "SearchSuggestionsView.swift",
    "HomeView.swift",
    "LocationSearchView.swift",
    "WeatherChartsView.swift",
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
    defaultLocalization: "en",
    platforms: supportedPlatforms,
    products: packageProducts,
    targets: [
        .executableTarget(
            name: "AppModule",
            path: ".",
            sources: sources,
            resources: [
                // Legacy .strings catalogs (en/tr). Swift Playgrounds on iPad
                // cannot run xcstringstool, so a String Catalog (.xcstrings)
                // fails to build there ("stat(/xcstringstool): No such file").
                .process("en.lproj/Localizable.strings"),
                .process("tr.lproj/Localizable.strings")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)