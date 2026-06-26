# Praeventus Development Guide

**Praeventus** is a privacy-first, zero-cost, science-grade weather app for anywhere in the world. Built entirely as a Swift Playgrounds app with no Mac, Xcode, or paid Apple Developer account required.

## Project Overview

### Core Principles
- **Global**: Search any city on Earth or use approximate location
- **Private by design**: Location uses `kCLLocationAccuracyReduced`, optional Cloudflare Worker proxy, on-device NLP analysis, no account/key/tracking
- **Scientific & free**: Data from Open-Meteo (ECMWF/national models)

### Target Platform
- **Primary**: Swift Playgrounds on iPad (iOS 17+)
- **Secondary**: macOS 14+ CLI for headless testing
- **UI Framework**: SwiftUI
- **Language**: Swift (version 6.0)

## Repository Structure

```
Praeventus/
├── README.md                          # User-facing project overview
├── CLAUDE.md                          # This file
├── .gitignore
├── Praeventus.swiftpm/                # Main Swift Package
│   ├── Package.swift                  # Swift Package manifest (iOS app + macOS CLI)
│   ├── App.swift                      # App entry point (branched: UI vs CLI)
│   ├── en.lproj/Localizable.strings   # English localization
│   ├── tr.lproj/Localizable.strings   # Turkish localization
│   │
│   ├── [Data Layer - Pure Foundation]
│   ├── WeatherEndpoint.swift          # API endpoint definitions
│   ├── OpenMeteoModels.swift          # Decodable models for Open-Meteo JSON
│   ├── OpenMeteoClient.swift          # HTTP client (geocoding + forecast)
│   ├── WeatherMapping.swift           # Maps API response → WeatherData
│   ├── WeatherData.swift              # Core domain model (no SwiftUI)
│   ├── LocalizedStringCompat.swift    # Localization utilities
│   ├── StorySentiment.swift           # NLP sentiment analysis
│   │
│   ├── [Domain & State Management]
│   ├── AtmosphericEngine.swift        # Weather state → visual representation
│   ├── AstronomicalEngine.swift       # Sun/moon position & visibility calcs
│   ├── WeatherNarrativeEngine.swift   # Scenario-aware narrative generation
│   ├── WeatherStore.swift             # @Observable state container
│   ├── WeatherCondition+Palette.swift # WMO code mapping + palette
│   │
│   ├── [Activity System]
│   ├── Activity.swift                 # Activity suitability models
│   ├── ActivityAnalysisEngine.swift   # Maps weather → activity scores
│   │
│   ├── [Location]
│   ├── LocationProvider.swift         # Core Location wrapper
│   │
│   ├── [Search MVVM]
│   ├── SearchViewModel.swift          # City search + autocomplete
│   │
│   ├── [UI Layer]
│   ├── PraeventusRootView.swift       # Root container view
│   ├── HomeView.swift                 # Main weather display
│   ├── LocationSearchView.swift       # City search modal
│   ├── WeatherChartsView.swift        # Charts visualization
│   ├── WeatherLabView.swift           # Detailed metrics display
│   ├── SettingsView.swift             # App preferences
│   ├── CitySearchBar.swift            # Search input bar
│   ├── SearchSuggestionsView.swift    # Autocomplete dropdown
│   ├── AtmosphereBackgroundView.swift # Weather animation layer
│   ├── WeatherEffectLayers.swift      # Particle/gradient effects
│   ├── SunHaloOpticsLayer.swift       # Sun halo visual effect
│   └── GlassComponents.swift          # Reusable glass morphism UI
│
└── worker/                            # Cloudflare Worker (privacy proxy)
    ├── README.md
    ├── wrangler.toml
    └── src/index.js
```

## Architecture

### Data Flow

```
User Input ─┐
            ├─→ LocationProvider (kCLLocationAccuracyReduced)
            │
City Search ├─→ OpenMeteoClient ──┬→ [Optional Cloudflare Worker]
            │                      │
            └──────────────────────┴→ api.open-meteo.com

Response (JSON) ──→ OpenMeteoModels (Decodable) 
                   ──→ WeatherMapping.map()
                   ──→ WeatherData (core model)
                   ──→ AtmosphericEngine (visual state)
                   ──→ WeatherStore (@Observable)
                   ──→ SwiftUI (HomeView, WeatherLabView, etc.)

Optional Sentiment Analysis:
  WeatherData.story ──→ StorySentiment.analyze() ──→ sentiment tag
```

### Layered Architecture

| Layer | Responsibility | Files | Platform |
|-------|---|---|---|
| **Data** | HTTP, JSON decoding, API mapping | WeatherEndpoint, OpenMeteoModels, OpenMeteoClient, WeatherMapping, WeatherData | Pure Foundation (iOS + macOS + Linux) |
| **Domain** | Business logic, state, computations | AtmosphericEngine, AstronomicalEngine, WeatherNarrativeEngine, WeatherStore, StorySentiment, ActivityAnalysisEngine | Pure Foundation (iOS + macOS) |
| **Location** | Device location services | LocationProvider | iOS + macOS (requires Core Location) |
| **Search** | City autocomplete | SearchViewModel | Pure Foundation |
| **UI** | Visual rendering, interactions | All *View.swift, GlassComponents | SwiftUI (iOS only) |
| **Localization** | String resources | Localizable.strings (en, tr) | All platforms |

**Key principle**: Data + Domain layers use **zero SwiftUI imports**. This allows the entire data layer to compile and run on Linux/macOS CLI for headless testing.

## Code Conventions

### Swift Style
- **Language mode**: Swift 6.0 (strict concurrency)
- **Naming**: camelCase for variables/functions, PascalCase for types
- **Access control**: Use `private`/`fileprivate` by default; mark public APIs with `@Observable`, `Codable`, etc.
- **Comments**: One-liner only; explain *why*, not *what*. Avoid referencing task IDs or future hypotheticals.
- **No over-engineering**: Three similar lines beats premature abstraction. Don't design for hypothetical future use cases.

### Foundation Patterns
- **Async/await**: Preferred over callbacks. Use `async throws` for fallible operations.
- **Codable**: Use explicit `CodingKeys` when JSON field names differ from Swift identifiers.
- **Error handling**: Define custom error types (e.g., `OpenMeteoError`). Only catch at system boundaries (network, persistence).
- **Optional handling**: Prefer `guard let` / `if let` over forced unwrapping. Use `?` for optional chaining.

### SwiftUI Patterns
- **@Observable**: Use for state containers (WeatherStore). Avoid `@State` for complex app state.
- **View composition**: Break into smaller views; name them `*View.swift` (e.g., `WeatherChartsView`).
- **Computed properties**: Use `.computed` for derived UI state (don't duplicate in @Observable).
- **Modifiers**: Chain logically: layout → background → effects → text formatting.
- **Previews**: Not used (Swift Playgrounds target doesn't support them easily).

### Localization
- **Strings file**: `en.lproj/Localizable.strings` (English) + `tr.lproj/Localizable.strings` (Turkish)
- **Key format**: Hierarchical with dots (e.g., `status.clear`, `story.rain`, `risk.high`)
- **In code**: Always use `String(localized: "key", defaultValue: "Fallback")` for both platforms
- **Tooling**: Legacy `.strings` format used (not `.xcstrings`), because Swift Playgrounds iPad can't run `xcstringstool`

## Key Components

### Data Layer

#### `WeatherEndpoint`
Defines Open-Meteo API endpoints for geocoding and forecast. Returns raw JSON structures.

#### `OpenMeteoModels`
Decodable structs that mirror Open-Meteo JSON schema:
- `SearchResults` (city autocomplete)
- `ForecastResponse` (hourly + daily weather)
- Nested models: `Hourly`, `Daily`, `CurrentWeather`

#### `OpenMeteoClient`
Main HTTP client. Methods:
- `search(_ query: String) async throws → [SearchResult]` — geocoding + autocomplete
- `forecast(latitude:longitude:proxy:) async throws → ForecastResponse` — weather data
- Supports optional `proxy` parameter for Cloudflare Worker URL

#### `WeatherMapping`
Pure function: `map(ForecastResponse, city:country:) → (weather: WeatherData, hourly: [WeatherData], daily: [WeatherData])`

Maps WMO weather codes → `WeatherCondition` enum. Computes derived metrics (feels-like, UV index categories, wind categories).

#### `WeatherData`
Core immutable model (no SwiftUI). Represents a snapshot of weather for one time period:
- Temperature, humidity, pressure, wind, visibility, dew point, UV index
- `WeatherCondition` enum (clear, partlyCloudy, cloudy, rain, storm, fog, snow)
- Computed properties: `timeOfDay`, `statusText`, `story`

#### `WeatherCondition`
Enum representing 7 meteorological conditions. Maps WMO codes in `WeatherMapping`:
- WMO 0 → clear
- WMO 1–4, 45–48 → partlyCloudy/cloudy/fog
- WMO 51–77 → rain/snow
- WMO 80–82, 85–86 → rain
- WMO 95–99 → storm

### Domain Layer

#### `WeatherStore` (@Observable)
Centralized app state:
- `currentWeather: WeatherData?` — current conditions
- `hourlyData: [WeatherData]` — next 24 hours
- `dailyData: [WeatherData]` — next 7 days
- `searchResults: [SearchResult]` — city autocomplete
- `isLoading: Bool`, `error: OpenMeteoError?`
- `selectedCity: SearchResult?` — currently viewed location
- `useProxyURL: String?` — optional Cloudflare Worker proxy

Methods:
- `func loadWeather(for city: SearchResult)` — fetches and maps data
- `func searchCities(query: String)` — autocomplete
- `func fetchLocation()` — uses LocationProvider for device location

#### `AtmosphericEngine`
Computes visual state from `WeatherData`:
- Maps condition + metrics → `AtmosphericState`
- Calculates storm risk, rain signal, visibility categories
- Determines background mood (clear → partlyCloudy → cloudy → wet → storm)
- Selects SF Symbols icon + status text

#### `AstronomicalEngine`
Computes sun/moon geometry for rendering:
- Solar altitude (elevation) — determines halo brightness
- Solar azimuth — halo angle
- Moon phase, visibility
- Used by `SunHaloOpticsLayer` for dynamic sun rendering

#### `WeatherNarrativeEngine`
Generates descriptive weather summaries:
- Takes `WeatherData` + activity context
- Produces English prose (e.g., "Pressure is balanced. Humidity is low.")
- Supports scenario-aware narratives (e.g., different text for outdoor vs. indoor activities)

#### `StorySentiment`
On-device NLP sentiment analysis:
- Uses Apple's `NaturalLanguage` framework
- Analyzes `WeatherData.story` text
- Returns sentiment tag (positive, neutral, negative)
- No cloud/LLM calls — purely local

#### `ActivityAnalysisEngine`
Maps weather metrics → activity suitability scores (0–100):
- `Activity` enum: hiking, running, cycling, outdoor_work, beach, photography, etc.
- Computes scores based on temperature, humidity, wind, UV, visibility
- Used to display "Recommended Activities" card

### Location & Search

#### `LocationProvider`
Wrapper around `CLLocationManager`:
- Requests `kCLLocationAccuracyReduced` (app-rounded; user location rounds further in-app)
- Handles privacy + permission prompts
- Returns `CLLocationCoordinate2D`

#### `SearchViewModel`
MVVM for city search:
- Debounces user input
- Calls `OpenMeteoClient.search()`
- Manages `@State` for query + results
- Used by `LocationSearchView`

### UI Layer

#### `PraeventusRootView`
Root container. Switches between:
- `HomeView` (main weather display)
- `LocationSearchView` (modal for picking a city)
- Holds `@State var store: WeatherStore`

#### `HomeView`
Main screen. Displays:
- Current conditions + status text
- Hourly chart (Swift Charts)
- Daily forecast cards
- "Lab" button → `WeatherLabView`
- "Settings" button → `SettingsView`

#### `WeatherLabView`
"Debug mode" / detailed metrics:
- All 15+ meteorological parameters (pressure, dew point, UV index, etc.)
- Atmospheric risk assessments (storm risk, rain probability)
- Activity suitability scores
- Accessible via "Lab" button

#### `WeatherChartsView`
Swift Charts visualizations:
- Hourly temperature + wind speed
- Daily high/low temperatures
- Precipitation probability

#### `SettingsView`
User preferences:
- Toggle for using device location vs. search
- Proxy URL input (for Cloudflare Worker)
- Language selection (English/Turkish)
- Data source attribution

#### `AtmosphereBackgroundView`
Animated background based on weather condition:
- Layers: gradient background + weather effects
- Clear → blue gradient with sun
- Cloudy → gray + cloud shapes
- Rain → darker clouds + rain particles
- Storm → dark red tones + lightning
- Uses `Canvas` + custom drawing

#### `WeatherEffectLayers`
Particle/gradient effects:
- Rain drops, snow flakes, wind flow visualization
- Cloud shape generation
- Opacity based on intensity metrics

#### `SunHaloOpticsLayer`
Sun rendering with realistic halo:
- Computes solar altitude from `AstronomicalEngine`
- Draws concentric circles (sun + outer halo)
- Brightness/size varies with altitude
- Fades at night

#### `GlassComponents`
Reusable glass morphism UI:
- `GlassMorphismContainer` — frosted glass background
- `GlassCard` — card-style container
- Used throughout for visual consistency

## Development Workflow

### Git & Branches
- **Main branch**: `main` (stable)
- **Feature branches**: Prefixed with `claude/` (e.g., `claude/add-activity-suitability`)
- **Branch naming**: kebab-case + descriptive suffix (e.g., `claude/fix-recurring-nan-errors`)
- **Commit messages**: Clear, concise; include why (not just what)
  - Good: "Fix NaN decoding in forecast response"
  - Bad: "Fix issue" or "Update files"
- **PR workflow**: Feature branch → PR to `main` → review → merge

### Making Changes

#### Adding a Feature
1. Create branch: `git checkout -b claude/feature-name-xxx`
2. Implement in `Praeventus.swiftpm/`
3. Update `Package.swift` sources array if adding new file
4. Update `Localizable.strings` (en + tr) if adding user-facing text
5. Test on iPad (Swift Playgrounds) and macOS CLI (`swift run`)
6. Commit: `git commit -m "Add feature: X"`
7. Push: `git push -u origin claude/feature-name-xxx`

#### Fixing a Bug
1. Create branch: `git checkout -b claude/fix-bug-name-xxx`
2. Fix in minimal scope (don't refactor surrounding code)
3. Run `swift run` to verify data layer
4. Commit: `git commit -m "Fix: issue description"`
5. Push + create PR

#### Code Review Checklist
- [ ] Follows Swift 6.0 concurrency rules (no force unwrap in async contexts)
- [ ] Data layer is pure Foundation (no SwiftUI imports in core files)
- [ ] Localization strings added (en + tr)
- [ ] `Package.swift` sources array updated if new files
- [ ] `swift run` completes without errors
- [ ] No commented-out code or debugging prints left
- [ ] Commit message is clear and descriptive

### Testing & Verification

#### Headless Testing (macOS/Linux)
```bash
cd Praeventus.swiftpm
swift run    # Exercises data layer: geocoding → forecast → mapping
```
Output shows:
- Geocoding result for "Tokyo"
- Current weather snapshot
- Hourly + daily point counts

#### iOS Testing
1. Open `Praeventus.swiftpm` in Swift Playgrounds (iPad)
2. Settings → Capabilities → Add **Core Location When in Use**
3. Run the app
4. Search a city or tap **Use my location**
5. Verify:
   - Current conditions display correctly
   - Charts render (hourly temp, daily range)
   - Status text matches condition
   - Background animation is smooth

#### Manual Testing Checklist
- [ ] City search autocomplete works
- [ ] Location permission prompt appears
- [ ] Current weather matches real-world conditions
- [ ] Charts display without crashes
- [ ] Settings (language, proxy URL) persist
- [ ] Lab view shows all metrics
- [ ] Activity suitability scores update
- [ ] UI smooth (no janky animations)

### Common Tasks

#### Add a New Weather Metric
1. Add field to `WeatherData` struct
2. Add decoding in `WeatherMapping.map()` from Open-Meteo response
3. Add localized string key to `Localizable.strings`
4. Display in `WeatherLabView` or relevant view

#### Add Localization (New Language)
1. Create `XX.lproj/Localizable.strings` (e.g., `fr.lproj/`)
2. Copy keys from `en.lproj/Localizable.strings`
3. Translate values
4. Update `Package.swift` `.process("XX.lproj/Localizable.strings")`
5. Test by changing device language in settings

#### Modify Weather Narrative
Edit `WeatherNarrativeEngine.swift`:
- Change scenario detection logic
- Update `WeatherData.story` computation in `WeatherData.swift`
- Add localized strings for new narrative variants

#### Update Cloudflare Worker Proxy
See `worker/README.md`. To use:
1. Deploy worker to Cloudflare
2. Copy URL
3. In app: Settings → Data Source / Privacy Proxy → paste URL
4. App will route requests through proxy

## Privacy & Security

### Location Privacy
- App requests `kCLLocationAccuracyReduced` (500m–1000m accuracy)
- Location rounded again in-app before sending to API
- User can toggle "Use my location" off; search cities manually instead

### Network Privacy
- All API calls to Open-Meteo are HTTPS
- Optional Cloudflare Worker proxy hides IP from weather servers
- No telemetry, tracking, or analytics

### Data Handling
- No user account, no API key required
- All data is transient (not persisted)
- App does not call external LLMs; sentiment analysis is on-device only
- No third-party SDKs (analytics, ads, etc.)

## Dependencies

### Built-in (No Third-Party)
- **Foundation**: URLSession, Codable, UserDefaults
- **SwiftUI**: For iOS app
- **Core Location**: For device location
- **NaturalLanguage**: For sentiment analysis
- **Swift Charts**: For data visualization
- **Combine**: For async coordination

### External
- **Open-Meteo API**: Free, no key required
- **Cloudflare Workers**: Optional, for privacy proxy

## CI/CD & Build

### Package.swift
- **Swift version**: 6.0
- **iOS target**: iOS 17.0+, iPad only
- **macOS target**: macOS 14.0+
- **Build modes**:
  - iOS: SwiftUI app + embedded resources
  - macOS: CLI executable for headless testing
- **Resources**: Localization strings (`.lproj` directories)

### Building Locally
```bash
# Swift Playgrounds (iPad) — done via GUI
# macOS CLI:
cd Praeventus.swiftpm
swift build
swift run
```

## Known Constraints & Workarounds

### Swift Playgrounds Limitations
- **No `xcstringstool`**: Can't use `.xcstrings` String Catalog on iPad
- **Workaround**: Legacy `.strings` files in `.lproj` directories

### Floating-Point Precision
- **Issue**: Open-Meteo sometimes returns NaN or Infinity for certain metrics
- **Solution**: `WeatherMapping` includes guards and fallback defaults
- **See**: Recent fix commit on `claude/recurring-error-osyiet`

### Async/Await Concurrency
- **Rule**: No force unwrap in async contexts; use `guard let` or optional chaining
- **Check**: `swift build` with `-strict-concurrency=complete` catches violations

## Performance Notes

- **Large datasets**: Hourly data can be 1000+ points; charts are paginated/windowed
- **Astronomy calculations**: Sun halo geometry is computed once per render cycle (not per frame)
- **Sentiment analysis**: NLP on narrative text is CPU-bound; run async to avoid UI freeze
- **Network**: Timeouts set to 15s; user sees error if forecast fetch fails

## Contact & Attribution

- **Weather data**: [Open-Meteo](https://open-meteo.com) — free, no API key
- **Icons**: SF Symbols (Apple)
- **Privacy proxy**: [Cloudflare Workers](https://workers.cloudflare.com/)
- **Maintainer**: [@mehmetg06](https://github.com/mehmetg06)

---

**Last updated**: 2026-06-26 | Generated by Claude Code analysis
