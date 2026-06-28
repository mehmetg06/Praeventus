# Praeventus — Technical Reference

**Praeventus** is a high-fidelity, privacy-first atmospheric prediction system distributed as a Swift Playgrounds app. It requires no Mac, no Xcode, no paid Apple Developer account, no API key, and no account of any kind. All intelligence runs on-device against freely available, institutionally-grade numerical weather prediction (NWP) data.

---

## System Philosophy

### High-Level Prediction via NWP Fusion

Praeventus does not consume a proprietary "weather API" that hides its data sources behind a commercial paywall. Instead it queries Open-Meteo — a fully open-source, self-hostable weather service that exposes raw output from the world's leading NWP models — and blends three independent global models on the device before presenting any result to the user.

The three models in the default fusion set are:

| Model | Operator | Resolution | Strengths |
|-------|----------|------------|-----------|
| **ECMWF IFS 0.25°** | European Centre for Medium-Range Weather Forecasts | ~25 km | Global skill leader; best medium-range |
| **GFS Global** | NOAA / US National Centers for Environmental Prediction | ~13 km | Best North American coverage; open data pioneer |
| **ICON Global** | Deutscher Wetterdienst (Germany) | ~13 km | Strong European and global coverage; open license |

Blending these three models via the on-device `WeatherFusion` engine produces a single synthetic forecast that is statistically more accurate than any single model. This is the same principle used by professional forecasters when they run ensemble model chains.

### Privacy by Architecture

Every piece of personally sensitive information (location, usage patterns, device state) is treated as hostile to third parties by default:

- Location is acquired at `kCLLocationAccuracyReduced` (~500–1000 m), then truncated to 4 decimal places (~11 m) before leaving the device — meaning the API never sees sub-kilometre coordinates.
- Sentiment analysis of weather text uses Apple's on-device `NaturalLanguage` framework; no text leaves the device.
- Sensor calibration (barometric pressure offset) uses `CMAltimeter` — the reading stays local.
- Forecast responses are cached on-device; no user identifier is ever attached to a request.
- An optional Cloudflare Worker proxy is available so even the server never sees the device IP.

### Zero Cost, Zero Lock-In

Every external dependency is either a first-party Apple framework or a free, no-key-required open API:

- **Open-Meteo**: AGPL-licensed, fully open source, no account required.
- **ECMWF/GFS/ICON data**: Published under open data agreements.
- **SF Symbols**: Bundled with iOS.
- **NaturalLanguage, CoreMotion, CoreLocation, Swift Charts**: Apple platform SDKs.

### Realistic but Efficient UI

The visual design targets physical realism — sun halo optics derived from actual solar geometry, particle layers tied to real atmospheric state — while staying within a budget a 2019 iPad can sustain at 60 fps. Heavy blurs and ultra-thin materials are used deliberately (not gratuitously), and every rendering decision is tunable through the developer sandbox without touching code.

---

## Repository Structure

```
Praeventus/
├── README.md
├── CLAUDE.md                           # This file
├── .gitignore
├── Praeventus.swiftpm/                 # Main Swift Package
│   ├── Package.swift                   # iOS app + macOS CLI dual-target manifest
│   ├── App.swift                       # Platform-branched entry point
│   ├── en.lproj/Localizable.strings    # English strings (legacy .strings format)
│   ├── tr.lproj/Localizable.strings    # Turkish strings
│   │
│   ├── ── Data Layer (pure Foundation — compiles on Linux) ──
│   ├── WeatherEndpoint.swift           # URL construction for Open-Meteo APIs
│   ├── OpenMeteoModels.swift           # Decodable structs mirroring Open-Meteo JSON
│   ├── OpenMeteoClient.swift           # Async HTTP client; concurrent multi-model fetch
│   ├── WeatherModel.swift              # NWP model enum + UserDefaults feature flags
│   ├── WeatherFusion.swift             # On-device inverse-spread model fusion engine
│   ├── ForecastCache.swift             # Disk-based forecast cache (1-hour TTL)
│   ├── WeatherMapping.swift            # WMO code decoder + API response → domain model
│   ├── WeatherData.swift               # Core immutable snapshot + TimeOfDay enum
│   ├── LocalizedStringCompat.swift     # Localization shim for Foundation-only targets
│   ├── StorySentiment.swift            # On-device NLP severity classification
│   │
│   ├── ── Domain Layer (Foundation + CoreMotion) ──
│   ├── AtmosphericEngine.swift         # Multi-variable stability / instability scorer
│   ├── AstronomicalEngine.swift        # Solar altitude, sunrise/sunset, moon phase
│   ├── MeteorologicalExpertSystem.swift # Expert-system narrative matrix (Turkish)
│   ├── WeatherNarrativeEngine.swift    # Bridge: AtmosphericEngine → ExpertSystem
│   ├── ThermalPredictionEngine.swift   # Heat index, wind chill, UV/Fitzpatrick engine
│   ├── HealthInsights.swift            # Composite thermal/UV result bundle
│   ├── SensorCalibration.swift         # CMAltimeter pressure calibration (iOS-only)
│   ├── WeatherStore.swift              # @MainActor state container + sandbox
│   │
│   ├── ── Activity System ──
│   ├── Activity.swift                  # Activity constraint models
│   ├── ActivityAnalysisEngine.swift    # Weather → suitability scorer
│   │
│   ├── ── Location & Search ──
│   ├── LocationProvider.swift          # CLLocationManager wrapper (reduced accuracy)
│   ├── SearchViewModel.swift           # Debounced city autocomplete MVVM
│   │
│   ├── ── UI Layer (SwiftUI, iOS only) ──
│   ├── WeatherCondition+Palette.swift  # Condition → 3-stop color palette
│   ├── SandboxEnvironment.swift        # SwiftUI EnvironmentKey overrides for Lab
│   ├── PraeventusRootView.swift        # Root container + navigation state
│   ├── HomeView.swift                  # Primary weather display
│   ├── LocationSearchView.swift        # City search modal
│   ├── WeatherChartsView.swift         # Swift Charts: hourly + daily visualizations
│   ├── WeatherLabView.swift            # Developer/advanced metrics sandbox
│   ├── SettingsView.swift              # App preferences + proxy configuration
│   ├── CitySearchBar.swift             # Search input component
│   ├── SearchSuggestionsView.swift     # Autocomplete dropdown
│   ├── AtmosphereBackgroundView.swift  # Layered animated weather background
│   ├── WeatherEffectLayers.swift       # Particle systems (rain, snow, wind, clouds)
│   ├── SunHaloOpticsLayer.swift        # Physically-derived sun halo renderer
│   ├── GlassComponents.swift           # Reusable glass-morphism containers
│   └── HealthInsightsCard.swift        # Health/UV card component
│
└── worker/                             # Cloudflare Worker privacy proxy
    ├── README.md
    ├── wrangler.toml
    └── src/index.js
```

---

## Architecture

### Data Flow

```
User Input
  │
  ├─ Search query ──→ OpenMeteoClient.search() ──→ GeocodingResult[]
  │                                                       │
  │                                                       ▼
  └─ Saved/detected location ──→ OpenMeteoClient.forecast() × [ECMWF, GFS, ICON]
                                         │ (concurrent TaskGroup)
                                         ▼
                                   WeatherFusion.fuse()
                                   (inverse-spread weighted blend)
                                         │
                              ┌──────────┴────────────┐
                              │ ForecastResponse       │ FusionConfidence
                              │ (synthetic single)     │ (agreement %, spread)
                              └──────────┬────────────┘
                                         ▼
                                  WeatherMapping.map()
                                  (WMO codes, hourly window, safe array access)
                                         │
                              ┌──────────┼──────────────┐
                              ▼          ▼               ▼
                          WeatherData  [HourlyPoint]  [DailyRange]
                              │
                    ┌─────────┼────────────────────────────────┐
                    ▼         ▼                                 ▼
            AtmosphericEngine  ThermalPredictionEngine    AstronomicalEngine
            (instability,      (heat index, wind chill,   (solar altitude,
             cloud cover,       Fitzpatrick UV, Foehn,     moon phase,
             storm score,       heatwave detection,        sunrise/sunset)
             mood)              best outdoor hours)
                    │                   │
                    ▼                   ▼
         MeteorologicalExpertSystem   HealthInsights
         (AtmosphericDynamics         (composite result bundle)
          → Turkish narrative)
                    │
                    ▼
             WeatherStore (@MainActor)
             (publishes to SwiftUI)
                    │
                    ▼
          SwiftUI view hierarchy
          (HomeView, WeatherLabView, charts, background, health card)

Optional NLP severity:
  AtmosphericState.story ──→ StorySentiment.severity() ──→ WeatherSeverity

Optional sensor calibration (iOS):
  WeatherData.pressure ──→ SensorCalibration.calibrate() ──→ adjusted WeatherData

Offline path:
  ForecastCache.load() ──→ paint instantly ──→ network refresh in background
```

### Platform Layers

| Layer | Files | Imports | Platforms |
|-------|-------|---------|-----------|
| **Data** | WeatherEndpoint, OpenMeteoModels, OpenMeteoClient, WeatherModel, WeatherFusion, ForecastCache, WeatherMapping, WeatherData, LocalizedStringCompat, StorySentiment | Foundation only | iOS, macOS, Linux |
| **Domain** | AtmosphericEngine, AstronomicalEngine, MeteorologicalExpertSystem, WeatherNarrativeEngine, ThermalPredictionEngine, HealthInsights | Foundation (+ SwiftUI guard for Atmospheric) | iOS, macOS |
| **Sensor** | SensorCalibration | CoreMotion (stub for others) | iOS (no-op elsewhere) |
| **State** | WeatherStore, Activity, ActivityAnalysisEngine | Foundation + SwiftUI | iOS |
| **Location** | LocationProvider | CoreLocation | iOS, macOS |
| **Search** | SearchViewModel | Foundation | iOS |
| **UI** | All *View.swift, GlassComponents, SandboxEnvironment | SwiftUI | iOS only |

**Key invariant**: every file outside the UI layer has zero `import SwiftUI`. This allows the entire data + domain stack to be exercised headlessly on any CI machine.

---

## File-by-File Technical Reference

### Data Layer

---

#### `WeatherEndpoint.swift`
Constructs typed `URL` values for the two Open-Meteo endpoints:

- **Forecast endpoint**: `https://api.open-meteo.com/v1/forecast` — accepts latitude, longitude, field lists for `current`, `hourly`, and `daily`, timezone auto-detect, 7-day window, kmh wind units, and an optional `models=` parameter for NWP model selection.
- **Geocoding endpoint**: `https://geocoding-api.open-meteo.com/v1/search` — accepts a city name query, result count, format, and locale-aware language code.

When a Cloudflare Worker proxy URL is configured, the same query parameters are sent to the proxy's base URL instead.

---

#### `OpenMeteoModels.swift`
Decodable structs that mirror the exact JSON schema Open-Meteo returns. Notable details:

- `ForecastResponse.Current` holds all instantaneous fields (temperature_2m, apparent_temperature, relative_humidity_2m, surface_pressure, pressure_msl, wind_speed_10m, wind_direction_10m, wind_gusts_10m, uv_index, dew_point_2m, visibility, precipitation_probability, weather_code). Every field is `Double?` or `Int?` — Open-Meteo can omit any field.
- `ForecastResponse.Hourly` holds parallel arrays (one value per hour); arrays are also optional-typed to survive partial responses.
- `ForecastResponse.Daily` holds daily aggregates including `sunrise`/`sunset` as ISO-8601 strings.
- `GeocodingResponse` / `GeocodingResult` model the geocoding endpoint.

The shared `JSONDecoder` is configured with `.convertFromString(positiveInfinity:negativeInfinity:nan:)` to handle the rare NaN/Infinity values Open-Meteo emits for some parameters in extreme grid cells.

---

#### `OpenMeteoClient.swift`
Pure-Foundation HTTP client. Two modes:

**Single-model fetch** (`forecast(latitude:longitude:model:)`):
- Builds URLQueryItem lists explicitly (current, hourly, daily field sets, timezone, forecast_days, wind_speed_unit).
- Appends `models=<apiValue>` only for non-`bestMatch` requests (omitting the parameter lets Open-Meteo select its blended default and avoids changing the JSON key suffixes, keeping the decoder unchanged).
- 15-second timeout from `URLSession.shared`.

**Multi-model concurrent fetch** (`forecast(latitude:longitude:models:)`):
- Spawns one `Task` per model inside a `withTaskGroup`.
- Uses `try?` per task — a model that returns an HTTP error or decode failure is silently dropped from the result dictionary.
- Throws `WeatherClientError.noResults` only when every model in the set fails; otherwise returns a partial dictionary that `WeatherFusion` handles gracefully.

**Geocoding** (`search(_:count:)`):
- Passes the locale's language code so the API returns localized city names.

Coordinates are formatted to 4 decimal places (~11 m precision), deliberately coarser than the device's actual location resolution, as a privacy measure.

---

#### `WeatherModel.swift`
Enum of the four selectable NWP models:

| Case | API value | Label |
|------|-----------|-------|
| `.bestMatch` | *(omitted)* | Best Match |
| `.ecmwf` | `ecmwf_ifs025` | ECMWF |
| `.gfs` | `gfs_global` | GFS |
| `.icon` | `icon_global` | ICON |

`WeatherModel.fusionSet` is `[.ecmwf, .gfs, .icon]` — the three independent global NWP models fetched concurrently when multi-model fusion is on.

`WeatherSettings` reads two UserDefaults-backed flags:
- `praeventus.multiModelEnabled` (default `true`) — whether to fetch and fuse three models.
- `praeventus.sensorCalibrationEnabled` (default `false`) — whether to apply the iPad barometer offset.

---

#### `WeatherFusion.swift`
The on-device NWP ensemble fusion engine. Accepts a `[WeatherModel: ForecastResponse]` dictionary and produces one synthetic `ForecastResponse` plus a `FusionConfidence` value. No training data, no historical ground truth, no ML inference — purely statistical combination of the live model outputs.

**Algorithm: Inverse-Spread Weighted Mean** (`fusedDouble(_:)`):

```
mean = average of all present values
deviation[i] = |value[i] - mean|
ε = max(deviations) × 0.25 + 1e-6    (ε scales with spread so it's never trivially dominant)
weight[i] = 1 / (deviation[i] + ε)
result = Σ(value[i] × weight[i]) / Σ(weight[i])
```

Effect: values that cluster near the consensus are weighted heavily; outliers (models that disagree strongly with the others) contribute less. This is the on-device equivalent of the bias-correction confidence weighting a server-side ML pipeline would apply.

**Wind Direction** (`fusedDirection(_:)`): Compass bearings cannot be averaged arithmetically across the 0°/360° seam. The engine converts each bearing to a unit vector (sin/cos), sums the components, and takes `atan2(sin_sum, cos_sum)`. This is the correct circular mean.

**Weather Code** (`fusedCode(_:)`): Majority vote; ties break toward the highest (most severe) WMO code. This ensures that when models disagree between "partly cloudy" and "rain", the result is not quietly downgraded.

**Hourly/Daily Alignment**: Each model's time series may start or end at different hours. The engine uses the longest series as the reference timeline, builds a `[timestamp: index]` lookup map for every other model, and gathers the value from each model for each timestamp slot. Models that do not have a given timestamp contribute `nil` and are excluded from that slot's blend.

**Confidence Scoring** (`FusionConfidence`):
- `temperatureSpreadC`: max(current_temps) - min(current_temps) across models.
- `agreement`: `max(0, 1 - spread / 8)`. An 8 °C disagreement collapses agreement to 0; perfect consensus is 1.
- Surfaced in the Lab view as an honest uncertainty signal.

---

#### `ForecastCache.swift`
Disk-based cache stored in the platform's caches directory. Key is `forecast_<lat>_<lon>.json` where lat/lon are formatted to 2 decimal places (~1 km), deliberately coarse to match the app's location privacy stance and to reuse cached data for nearby launches.

- **TTL**: 1 hour. Entries older than 1 hour are shown in the UI with an "isStale" flag but are not deleted.
- **Atomic writes**: `Data.write(to:options:.atomic)` prevents a corrupt cache entry from a crash mid-write.
- **NaN/Infinity**: Uses the same non-conforming float encoding strategy as the network decoder so cached model responses survive round-trips.
- **Pure Foundation**: No UIKit or SwiftUI imports; exercisable on Linux CI.

---

#### `WeatherMapping.swift`
Translates raw `ForecastResponse` JSON into the app's typed domain model. Also defines `HourlyPoint`, `DailyRange`, and `MappedForecast`.

**WMO Code Mapping** (`condition(forWMOCode:)`):

| WMO codes | Condition |
|-----------|-----------|
| 0 | `.clear` |
| 1, 2 | `.partlyCloudy` |
| 3 | `.cloudy` |
| 45, 48 | `.fog` |
| 51–67 (drizzle + rain + freezing rain) | `.rain` |
| 71–77 (snowfall + ice grains) | `.snow` |
| 80–82 (rain showers) | `.rain` |
| 85, 86 (snow showers) | `.snow` |
| 95–99 (thunderstorms) | `.storm` |

**Hourly alignment**: `nowIndex(in:currentTime:)` finds the slice of the 168-hour series (7 days × 24 h) that starts closest to "now". It tries an exact ISO-8601 timestamp match first, then an hour-prefix match (since Open-Meteo rounds `current.time` to the hour), then falls back to the first entry whose parsed date is ≥ the current system time.

**Safe array access**: Open-Meteo returns parallel nullable arrays whose lengths can vary. Every field read uses `safe(_:at:or:)` which bounds-checks and unwraps optionals, returning a typed default on any failure — preventing crashes from partially delivered responses.

---

#### `WeatherData.swift`
The core immutable weather snapshot. Foundation-only (no SwiftUI).

Fields: `city`, `country`, `temperature`, `feelsLike`, `condition`, `humidity`, `pressure`, `windSpeed`, `windDirection`, `windGustSpeed`, `uvIndex`, `dewPoint`, `visibility`, `rainProbability`, `hour`.

**`TimeOfDay` enum**: Maps the `hour` field into four bands that drive both the visual atmosphere and narrative text:

| Band | Hours | Darkness | Warmth | Coolness |
|------|-------|----------|--------|----------|
| `.dawn` | 5–8 | 0.08 | 0.16 | 0.12 |
| `.day` | 9–16 | 0.00 | 0.08 | 0.00 |
| `.sunset` | 17–20 | 0.16 | 0.30 | 0.04 |
| `.night` | 21–4 | 0.48 | 0.00 | 0.28 |

These scalar values are read directly by the background and effect rendering layers to tint gradients without any additional logic.

**`WeatherCondition` enum**: Seven values (`clear`, `partlyCloudy`, `cloudy`, `rain`, `storm`, `fog`, `snow`). Each carries a `symbolName` (SF Symbol) and a localized `displayName`.

---

#### `LocalizedStringCompat.swift`
Thin shim for using `String(localized:defaultValue:)` on targets that compile without a module bundle (macOS CLI). Ensures the same call site works across all platforms.

---

#### `StorySentiment.swift`
Combines two independent severity signals:

1. **Engine-derived severity**: `instability > 0.66` or `stormRiskIsHigh` → `.alert`; `instability > 0.40` → `.caution`; else → `.calm`. This is always computed, always reliable.
2. **NL sentiment score**: `NLTagger` with `.sentimentScore` scheme over the generated story text. Returns a value in [-1, 1]. Scores ≤ -0.5 force `.alert`; scores ≤ -0.2 upgrade `.calm` to `.caution`.

The NL signal can only raise severity, never lower it. This is intentional: Turkish text (the expert system's output language) may return 0 from `NLTagger` as "unsupported", which is correctly treated as "no signal" rather than "positive".

---

### Domain Layer

---

#### `AtmosphericEngine.swift`
A multi-variable atmospheric stability scorer. All inputs are normalized to [0, 1] before entering the weighted formulas.

**Input normalization**:
- `humidity = raw_humidity / 100`
- `rain = rain_probability / 100`
- `wind = wind_speed / 90` (90 km/h as the reference for severe wind)
- `pressureDeficit = (1013 - pressure) / 33` (low pressure → instability)
- `pressureExcess = (pressure - 1016) / 22` (high pressure → stability)
- `heat = (temperature - 18) / 22`
- `cold = (6 - temperature) / 18`

**Derived scalar fields**:

```swift
instability = rain×0.32 + humidity×0.24 + pressureDeficit×0.24
            + wind×0.16 + heat×humidity×0.14 - pressureExcess×0.18

cloudCover  = humidity×0.42 + rain×0.34 + pressureDeficit×0.18
            + wind×0.04 - pressureExcess×0.12

stormScore  = instability×0.50 + rain×0.18 + wind×0.18 + pressureDeficit×0.18

visibilityScore = humidity×0.38 + rain×0.28 + cold×0.20 - wind×0.16
```

**Condition resolution** (priority order, highest wins):
1. `cold > 0.50 && humidity > 0.62 && rain > 0.30` → `.snow`
2. `stormScore > 0.66` → `.storm`
3. `visibilityScore > 0.74 && wind < 0.35` → `.fog`
4. `rain > 0.52` → `.rain`
5. `cloudCover > 0.68` → `.cloudy`
6. `cloudCover > 0.36` → `.partlyCloudy`
7. Else: the WMO-decoded base condition

The resolved condition also maps to a `BackgroundMood` which drives the atmosphere rendering pipeline.

---

#### `AstronomicalEngine.swift`
Implements solar and lunar position calculations without any external library.

**Solar Altitude** (`sunAltitude(at:latitude:longitude:)`):

Uses the USNO/Meeus simplified solar position algorithm:
1. Compute Julian Day Number from the date components.
2. Mean anomaly `M` from J2000.0 epoch.
3. Equation of center `C` via three harmonic terms of sin(M).
4. True solar longitude from M + C.
5. Obliquity of the ecliptic (22.5° range over millennia; approximated as 23.44° minus a small secular drift term).
6. Right ascension `α` and declination `δ` from the solar longitude and obliquity.
7. Hour angle `H` from the local apparent solar time (UTC offset applied to avoid dependence on system wall-clock drift).
8. Altitude = `arcsin(sin(lat)·sin(δ) + cos(lat)·cos(δ)·cos(H))`.

Result is clamped to [-90°, 90°]. Used by `SunHaloOpticsLayer` to scale the sun disc and halo brightness in real time.

**Sunrise/Sunset** (`sunTiming(at:latitude:longitude:)`):

Uses the NOAA simplified algorithm:
1. Longitude-hour offset to convert to local time.
2. Approximate time of event (6h for rise, 18h for set).
3. Sun's mean anomaly → true longitude `L`.
4. Right ascension `RA` from `L`, quadrant-corrected.
5. Declination from `L`.
6. Local hour angle `H` from the zenith (90.833° to account for atmospheric refraction and solar disc radius).
7. cosH > 1 → polar night; cosH < -1 → midnight sun.
8. UT conversion back to wall-clock via longitude-hour.

**Moon Phase** (`moonPhase(at:)`):

Anchored to a known new moon (Unix timestamp 947182800 = January 6, 2000 UTC). Elapsed days modulo the synodic period (29.530588 days) gives a cycle position in [0, 1), which maps to the eight named phases. The `cyclePosition` property on each `MoonPhase` case is used by the sandbox's moon-override feature.

---

#### `ThermalPredictionEngine.swift`
A medical-grade thermal and UV hazard engine. No ML, no network. All formulas are from published scientific/regulatory sources.

**NWS Heat Index** (Rothfusz regression, converted to °C):

```
HI_F = -42.379 + 2.04901523T + 10.14333127R - 0.22475541TR
       - 0.00683783T² - 0.05481717R² + 0.00122874T²R
       + 0.00085282TR² - 0.00000199T²R²
```
where T is temperature in °F and R is relative humidity (0–100). Two correction terms handle very dry air and very humid air at moderate temperatures. The result is converted back to °C.

Only applied when `temperatureC >= 27`; below that the formula diverges from physical reality.

**Environment Canada Wind Chill Index**:

```
WC = 13.12 + 0.6215T - 11.37V^0.16 + 0.3965TV^0.16
```
where T is temperature in °C and V is wind speed in km/h. Only applied when `T ≤ 10` and `V > 4.8 km/h`.

**Foehn Wind Detection**:

A Foehn effect occurs when hot, dry, fast air drives dehydration instead of cooling. The engine detects this when `temperature > 36°C` AND `windSpeed > 15 km/h`, and adds a hazard score contribution instead of subtracting one:

```
Normal regime: score -= min(windSpeed × 0.8, 15)
Foehn regime:  score += min((windSpeed - 15) × 1.5 + 15, 45)
```

**Risk Bands**:

| Score range | Band |
|-------------|------|
| < 35 | `.safe` |
| 35–75 | `.caution` |
| ≥ 75 | `.extremeDanger` |

**Fitzpatrick UV Burn Calculator**:

Based on WHO reference (UV Index 3 = minimum erythema dose reference point):

```
safe_minutes = base_minutes_at_UV3 × (3 / uvIndex) × SPF
```

| Fitzpatrick Type | Baseline at UV 3 | Description |
|------------------|------------------|-------------|
| 1 | 10 min | Very fair, always burns |
| 2 | 15 min | Fair, burns easily |
| 3 | 20 min | Medium, sometimes burns |
| 4 | 30 min | Olive, rarely burns |
| 5 | 40 min | Brown, very rarely burns |
| 6 | 60 min | Deeply pigmented |

**Shadow Rule**: When solar elevation angle > 45°, a person's shadow is shorter than their height — the practical indication that UV is at or near daily peak. Triggers a localized Turkish warning.

**Optimal Outdoor Window Finder**: Scans a 24-hour hourly forecast, identifies continuous spans where `riskLevel == .safe` AND `uvIndex <= 3`, and formats them as a Turkish time-range recommendation.

**Heatwave Detection**: Returns a persistent Turkish alert when 3 or more consecutive days in the 7-day daily max array reach ≥ 35°C.

---

#### `MeteorologicalExpertSystem.swift`
The narrative engine. Translates quantitative atmospheric state into a single, internally-consistent Turkish paragraph.

**Stage 1 — `AtmosphericDynamics`** (computed from raw data):

- **ThermalRegime** (9 bands): `extremeCold` (≤−10°C apparent) through `extremeHeat` (≥41°C apparent). The `oppressive` band (≥32°C apparent + dew point ≥22°C) splits the hot regime to capture humidity-driven heat as distinct from dry heat.
- **PressureTendency** (inferred, not measured): Since the app has no 3-hour historical pressure buffer, the engine *infers* the tendency from:
  - Deviation of current pressure from the standard 1013.25 hPa baseline (ridge vs. trough signal).
  - Near-term precipitation probability gradient (ramping rain ↔ falling barometer).
  - Atmospheric instability scalar from `AtmosphericEngine`.
  - Storm score.
  - All scaled to a per-3-hour estimate, then divided by 3 for per-hour, and bucketed into five bands: `fallingFast`, `falling`, `steady`, `rising`, `risingFast`.
- **TemperatureGradient** (from the next 4-hour series):
  - `plunging` ≤ −2°C/h
  - `cooling` −2 to −0.6°C/h
  - `steady` ±0.6°C/h
  - `warming` 0.6 to 2°C/h
  - `surging` ≥ 2°C/h
  - `isAccelerating`: true when the second half of the 4-hour window changes faster than the first (trend gaining momentum).
- **WeatherHazard** (OptionSet, 10 flags): `heatStress`, `mugginess`, `dryHeat`, `windChill`, `frostbite`, `uvBurn`, `stormApproaching`, `gustWind`, `lowVisibility`, `deceptiveCooling`. Multiple hazards can be active simultaneously.
- `deceptiveCooling`: active when temperature is falling but apparent temperature ≥ 30°C and UV ≥ 6 during daytime. Warns users not to interpret the falling readout as genuine relief.

**Stage 2 — The Narrative Matrix**:

Each thermal regime has its own function. Within each function, the five-dimensional tuple `(NarrativePressure, NarrativeGradient, NarrativeRain, NarrativeWind, NarrativeHazard)` selects a specific narrative opening sentence. A shared `paragraph()` function then assembles the opening with shared "language bricks" — one phrase per dimension, always phrased consistently so they never contradict each other — plus an `advice()` call that selects the actionable recommendation from a priority-ordered match over all five dimensions.

The matrix is fully exhaustive without a generic `default`; every meaningful combination (and combinations without a specific match) is handled by the regime's fallback case. The same pair of variables (e.g., "heat" and "false cooling") that would produce contradictory sentences in a generative model here resolve to a single sentence that explicitly addresses the paradox.

---

#### `WeatherNarrativeEngine.swift`
Thin adapter between the SwiftUI-facing `AtmosphericState` (which carries coarse risk enums) and the Foundation-only `MeteorologicalExpertSystem` (which needs raw floating-point inputs). Converts `AtmosphericRisk` to a numeric storm score, then delegates entirely to `MeteorologicalExpertSystem.narrative(for:)`.

---

#### `HealthInsights.swift`
A value-type bundle (`struct HealthInsights`) that aggregates all thermal and UV outputs for the current snapshot:

- `heatwaveAlert`: multi-day alert string, or `nil`.
- `currentRiskLevel` / `currentRiskWarning`: the dominant risk (heat or cold, whichever is more severe — ties go to cold).
- `isFoehnActive`: whether the hot-dry-wind amplification path is active.
- `minutesToBurn`: unprotected skin exposure ceiling.
- `uvIndex`, `skinType`, `spf`: parameters used for the burn calculation.
- `bestHours`: recommended outdoor windows for today.
- `riskKind`: `.heat` or `.cold`, drives the card icon.

Three static sandbox presets — `forcedHeatstroke`, `forcedHypothermia`, `forcedExtremeUV` — provide extreme states for UI testing without needing real weather conditions.

---

#### `SensorCalibration.swift`
Uses `CMAltimeter.startRelativeAltitudeUpdates` to stream real-time barometric pressure from the iPad's physical sensor. The `calibrate(_:WeatherData)` method adds the difference between the sensor reading and the API-provided pressure, clamped to ±25 hPa (so a single bad sample cannot distort the snapshot).

Runs only on iOS/iPadOS (where `CoreMotion` is available); all other platforms use a no-op stub that returns the input unchanged. Must be started explicitly; `WeatherStore` calls `start()` only when `sensorCalibrationEnabled` is true.

---

#### `WeatherStore.swift`
`@MainActor` `ObservableObject`. The single source of truth for all live data and developer-sandbox state.

**Loading lifecycle** (`LoadPhase`):

```
.idle → .loading → .loaded
              ↓           ↘
          .failed      (cache: paint first, then refresh)
```

**Cache-first strategy**:
1. Check `ForecastCache` for an entry at the coarse coordinates.
2. If found: apply it immediately (user sees data in < 1 ms), set `isStale` based on TTL, set phase to `.loaded`.
3. Fire the async network fetch in parallel.
4. On success: overwrite with fresh data, save to cache, clear stale flag.
5. On failure with cached data: keep the cached data, mark `isStale = true`.
6. On failure with no cache: set phase to `.failed(message)`.

**Sensor calibration**: if enabled, the `SensorCalibration.calibrate()` pass runs after `WeatherMapping.map()` and before publishing.

**Developer sandbox** (all `@Published`, all in `WeatherLabView`):
- `animationSpeed` (0.1–2.0): particle/animation playback rate, injected via `SandboxEnvironment`.
- `performanceMode`: drops blur and ultra-thin materials, injected via environment.
- `showLayoutBounds`: red borders on major rendering layers.
- `moonPhaseOverride`: overrides the live astronomical calculation.
- `forcedHealthInsights`: pins the health card to a hand-built state for medical UI testing.

**Biome presets**: `applyBiome(...)` synthesizes fake 24-hour hourly and 7-day daily series from a single snapshot using a sinusoidal diurnal temperature wobble and a half-sine UV curve. This lets the heatwave detector, best-hours finder, and charts all respond to the chosen extreme environment (Death Valley, Antarctica, Sahara) without a real forecast fetch.

**`syntheticHourly` diurnal model**:
```
temp[h] = base_temp + sin(hour / 24 × 2π - π/2) × 2.5
uv[h]   = base_uv × max(0, sin((hour - 6) / 12 × π))
```
UV is zeroed overnight and rises/falls as a half-sine across the daylight window.

---

### Activity System

---

#### `Activity.swift`
Defines the activity model and constraint parameters (temperature range, max wind speed, max wind gust, min visibility, max UV index, boolean flags for rain/snow/fog/storm avoidance).

`ActivityStorage.loadActivities()` returns the full catalog of built-in activities.

---

#### `ActivityAnalysisEngine.swift`
Score-based suitability evaluator. Starts at 100 and deducts per-criterion penalties:

| Criterion | Deduction |
|-----------|-----------|
| Temperature out of range | −15 |
| Wind gust > activity max | −20 |
| Wind speed > activity max (no gust) | −10 |
| Visibility < activity min | −15 |
| UV > activity max | −10 |
| Rain (when `avoidRain`) | −25 |
| Snow (when `avoidSnow`) | −25 |
| Fog (when `avoidFog`) | −20 |
| Storm (when `avoidStorm`) | −30 |

Suitability bands: `excellent` ≥85, `good` 70–84, `fair` 55–69, `poor` 40–54, `unsuitable` <40.

---

### Location & Search

---

#### `LocationProvider.swift`
`CLLocationManager` wrapper requesting `kCLLocationAccuracyReduced`. Delivers a `CLLocationCoordinate2D` once, then stops updating (one-shot request model). Handles the `notDetermined` → request flow and `denied`/`restricted` error paths.

---

#### `SearchViewModel.swift`
`@Observable` (or `ObservableObject`-compatible) class that debounces the text-field input and calls `OpenMeteoClient.search()`. Manages the query string and result array as published properties consumed by `LocationSearchView` and `SearchSuggestionsView`.

---

### UI Layer

---

#### `WeatherCondition+Palette.swift`
Extends `WeatherCondition` with a `palette: [Color]` property — a 3-stop gradient array for each condition:

| Condition | Palette intent |
|-----------|---------------|
| `.clear` | Deep cobalt → sky blue → pale azure |
| `.partlyCloudy` | Navy → steel blue → light blue |
| `.cloudy` | Near-black → slate grey → silver-blue |
| `.rain` | Dark navy → storm blue → muted blue |
| `.storm` | Near-black → very dark purple → deep indigo |
| `.fog` | Dark grey → mid grey → near-white |
| `.snow` | Midnight blue → ice blue → near-white |

---

#### `SandboxEnvironment.swift`
Defines four `EnvironmentKey` types that propagate sandbox overrides through the entire SwiftUI view tree without threading parameters through every intermediate view:

- `performanceMode`: when `true`, `GlassComponents` drops `.ultraThinMaterial` blurs and the background drops expensive noise layers.
- `showLayoutBounds`: when `true`, a `LayoutBoundsModifier` draws a 1 px red border around every major rendering layer via the `.layoutBounds()` view extension.
- `sandboxAnimationSpeed`: multiplier applied to `TimelineView` and `withAnimation` durations in particle layers.
- `moonCycleOverride`: passes a `0…1` synodic cycle override to `SunHaloOpticsLayer` and the astronomical display; `-1` means "use live data".

---

#### `PraeventusRootView.swift`
The root `@State var store: WeatherStore` holder. Switches between `HomeView` and `LocationSearchView` (city search modal). Calls `store.restoreOrPrompt()` on appear to reload the last location.

---

#### `HomeView.swift`
Primary display screen. Layers:

1. `AtmosphereBackgroundView` — full-bleed animated background.
2. Current conditions section — temperature, feels-like, condition label, status text from `AtmosphericEngine`.
3. Narrative text (`atmosphere.story`) from `MeteorologicalExpertSystem`.
4. Hourly strip (Swift Charts horizontal scroll).
5. `HealthInsightsCard` — thermal/UV health panel.
6. 7-day daily forecast cards.
7. Toolbar: Lab button → `WeatherLabView`, Settings → `SettingsView`.

---

#### `WeatherLabView.swift`
Developer and advanced-user mode. Two sections:

**Instruments**: all 15+ meteorological parameters displayed with units, plus `FusionConfidence` (agreement %, temperature spread, participating model names), `AstronomicalAnalysis` (sun altitude, moon phase/brightness, daylight hours, sunrise/sunset times).

**Simulator** ("Ultimate Developer Sandbox"): interactive sliders for condition, temperature, humidity, pressure, wind, rain probability, time-of-day. Biome presets (tropics, desert, Arctic, high altitude, coastal). Medical stress-test buttons (heatstroke, hypothermia, extreme UV). Moon phase override picker. Animation speed slider. Performance mode and layout bounds toggles.

All sandbox changes propagate through `WeatherStore.update(...)` / `applyBiome(...)` / `forceHealthState(...)`, which publish through the normal SwiftUI state pipeline — the background, charts, health card, and narrative update live.

---

#### `WeatherChartsView.swift`
Swift Charts visualizations:
- **Hourly temperature strip**: `LineMark` + `AreaMark` over 24 `HourlyPoint`s. Area fill uses the condition palette.
- **Daily high/low band**: `RectangleMark` spanning `[min, max]` per `DailyRange`.
- **Precipitation probability**: `BarMark` or `LineMark` over hourly probability values.
- **Wind**: optional wind speed overlay on the hourly chart.

All charts use `ChartXAxis` / `ChartYAxis` with localized labels and the weather condition palette for gradient fills.

---

#### `AtmosphereBackgroundView.swift`
Layered background system driven by `AtmosphericState.backgroundMood`:

1. **Gradient layer**: 3-stop `LinearGradient` from `WeatherCondition.palette`, tinted by `TimeOfDay.darkness` / `warmth` / `coolness` scalars.
2. **Weather effect layer**: `WeatherEffectLayers` particle system.
3. **Sun halo layer**: `SunHaloOpticsLayer` (clear and partly cloudy only).
4. Conditional: noise texture overlay in performance mode.

Uses SwiftUI `Canvas` for particle drawing to avoid the per-view overhead of many small `Shape`s.

---

#### `WeatherEffectLayers.swift`
Particle and procedural effect systems:

- **Rain**: animated `Path` line segments with random offsets and a slight downward-right angle. Opacity and density tied to `AtmosphericState.rainSignal`.
- **Snow**: circular particles with slow drift and a sine-wave lateral wobble.
- **Cloud shapes**: procedural Bézier blobs positioned in layers; opacity from `cloudCover` scalar.
- **Wind flow lines**: gentle diagonal streaks for high-wind conditions.
- All particle systems read `sandboxAnimationSpeed` from the environment to run at the developer-set playback rate.

---

#### `SunHaloOpticsLayer.swift`
Renders a physically-motivated sun disc + diffraction halo using `AstronomicalEngine.sunAltitude`:

- **Disc radius**: scales with altitude (larger near horizon due to apparent angular size perception).
- **Halo rings**: two concentric radial gradients (inner glow and outer halo); radius and opacity drop as altitude decreases.
- **Night fade**: opacity → 0 below the horizon.
- **Moon override**: when `moonCycleOverride != -1`, reads the cycle position from the environment key to display a moon phase indicator instead.

---

#### `GlassComponents.swift`
Reusable glass-morphism containers:

- `GlassMorphismContainer`: background of `.ultraThinMaterial` + a subtle inner gradient. In `performanceMode`, the material is replaced with a plain translucent fill to avoid the GPU blur cost.
- `GlassCard`: fixed-corner-radius container using `GlassMorphismContainer` with padding and optional shadow.

---

#### `HealthInsightsCard.swift`
Displays the `HealthInsights` bundle on the home screen:

- Headline: current risk level icon + colour-coded banner (green/amber/red).
- Heatwave alert (if present): persistent multi-day warning.
- UV burn clock: countdown display of `minutesToBurn`.
- Foehn note (if active): "wind is not cooling you" explanation.
- Best hours: formatted outdoor window recommendation.
- Cold stress (if `riskKind == .cold`): frostbite / hypothermia warning.

---

## Physics & Algorithm Summary

| System | Method | Source / Standard |
|--------|--------|-------------------|
| Model fusion | Inverse-spread weighted mean | Statistical ensemble theory |
| Wind fusion | Circular (vector) mean | Directional statistics |
| Solar altitude | Meeus simplified + equation of center | USNO / Astronomical Algorithms |
| Sunrise/Sunset | NOAA simplified algorithm (zenith 90.833°) | NOAA Solar Calculator |
| Moon phase | Synodic period from known new moon epoch | Astronomical ephemeris |
| Heat index | NWS Rothfusz regression (3 Fahrenheit adjustments) | NWS / Steadman 1979 |
| Wind chill | Environment Canada 2001 formula | MSC / Environment Canada |
| Foehn hazard | Apparent temperature + wind threshold | Synoptic meteorology |
| Fitzpatrick burn time | WHO UV reference × SPF multiplier | WHO / CIE photobiology |
| Shadow rule | Solar elevation angle > 45° | WHO UV protection guidelines |
| Heatwave | 3+ consecutive days ≥35°C | WMO / national meteorological standards |
| Barometric inversion | Pressure deviation + rain gradient + instability | Synoptic meteorology |
| Temperature gradient | Linear regression over 4-hour series | Standard time-series derivative |
| Dew point | Magnus formula | August-Roche-Magnus approximation |
| Apparent temperature (felt) | Heat index when ≥27°C; wind chill when ≤10°C | Hybrid (NWS + MSC) |
| NLP sentiment | NLTagger `.sentimentScore`, engine baseline | Apple NaturalLanguage framework |
| Activity suitability | Weighted deduction scoring | Domain-specific heuristics |

---

## Developer Sandbox

The sandbox is accessed via **Weather Lab** (Lab button in `HomeView`). It provides:

| Feature | Mechanism |
|---------|-----------|
| Parameter sliders | `WeatherStore.update(...)` → full pipeline re-render |
| Biome presets | `WeatherStore.applyBiome(...)` → synthesizes hourly/daily series |
| Medical stress tests | `WeatherStore.forceHealthState(HealthInsights.forced*)` |
| Moon phase override | `WeatherStore.moonPhaseOverride` + environment key |
| Animation speed | `animationSpeed` → `sandboxAnimationSpeed` environment key |
| Performance mode | `performanceMode` → environment key → drops blurs |
| Layout bounds | `showLayoutBounds` → red borders on all major layers |
| Resume live | `WeatherStore.resumeLiveData()` → clears all overrides + re-fetches |

---

## Privacy Architecture

### Location
- `kCLLocationAccuracyReduced`: OS-level ~500–1000 m rounding before the app ever sees coordinates.
- Coordinates truncated to 4 decimal places (~11 m) in `OpenMeteoClient.trimmed(_:)` before inclusion in any URL.
- Cache key at 2 decimal places (~1 km) — the saved location is never more precise than needed.
- `UserDefaults` stores the last city name + coarse coordinates. No device ID, no timestamp.

### Network
- All Open-Meteo requests are HTTPS.
- Optional Cloudflare Worker proxy: the device's IP is exposed to the proxy, not to Open-Meteo. The worker forwards only the query string.
- User-Agent is a generic `Praeventus/1.0 (privacy-weather)` — no device identifier, no OS version, no app version beyond the major.

### On-Device Computation
- `NLTagger` sentiment analysis: text never leaves the device.
- `CMAltimeter` barometric calibration: sensor reading never leaves the device.
- `AstronomicalEngine`: pure arithmetic, no network.
- `ThermalPredictionEngine`: pure arithmetic, no network, no ML model file.
- `MeteorologicalExpertSystem`: deterministic pattern match, no network.

### Data Retention
- No user account. No telemetry. No analytics SDK.
- Forecast cache is stored in the platform's caches directory, which the OS may purge under storage pressure. It is never backed up to iCloud.
- All in-memory state is transient and not logged.

---

## Build Configuration

### `Package.swift`

- Swift language mode: **6.0** (strict concurrency).
- iOS target: `iOS 17.0+`, iPad only, portrait + landscape.
- macOS target: `macOS 14.0+`, CLI executable for headless verification.
- Resources: `en.lproj/Localizable.strings` and `tr.lproj/Localizable.strings` (legacy `.strings` format — the Swift Playgrounds on-device builder cannot run `xcstringstool`, which is required for the `.xcstrings` String Catalog format).

### Headless Verification (macOS/Linux)

```bash
cd Praeventus.swiftpm
swift run
```
This exercises the full data + domain stack: geocoding → multi-model fetch → fusion → mapping → atmospheric engine → narrative engine → thermal engine.

### iOS (Swift Playgrounds)

1. Open `Praeventus.swiftpm` in Swift Playgrounds on iPad.
2. Settings → Capabilities → **Core Location When in Use** (required for location).
3. Run. Search a city or tap **Use my location**.

---

## Development Workflow

### Branch Conventions
- `main` — stable
- `claude/description-suffix` — feature/fix branches (kebab-case)

### Commit Style
- Describe the *why*, not the *what*: `"Fix NaN decoding in forecast response"` not `"Fix issue"`.
- No co-author tags in production commit messages unless the toolchain inserts them automatically.

### Code Review Checklist
- [ ] Swift 6.0 concurrency: no force-unwrap in async contexts; all `@MainActor` boundaries explicit.
- [ ] Data/domain files: zero `import SwiftUI`.
- [ ] New files added to `Package.swift` `sources` array.
- [ ] New user-facing strings added to both `en.lproj/Localizable.strings` and `tr.lproj/Localizable.strings`.
- [ ] `swift run` completes without errors or warnings on macOS.
- [ ] No debugging `print` statements or commented-out code left in.

### Adding a New Weather Metric
1. Add the field to `OpenMeteoModels` (as `Double?` or `Int?`).
2. Request the field name in `OpenMeteoClient.forecast` query items.
3. Add the field to `WeatherData`.
4. Map it in `WeatherMapping.map()` / `hourlyPoints()` / `dailyRanges()`.
5. Add a localized key to both strings files.
6. Display in `WeatherLabView` and wherever relevant.

### Adding a New NWP Model
1. Add a new case to `WeatherModel` with the correct `apiValue` (Open-Meteo `models=` parameter).
2. Add its `displayName` localization key.
3. If it should join the fusion set, add it to `WeatherModel.fusionSet`.
4. No changes to `WeatherFusion` or `OpenMeteoClient` are needed — both are model-agnostic.

### Modifying the Expert System Narrative
1. Edit `MeteorologicalExpertSystem.swift`.
2. Extend or modify one of the regime functions (`hot()`, `cold()`, etc.) or shared phrase functions.
3. If adding a new hazard type: add a `WeatherHazard` flag, set it in `AtmosphericDynamics.from()`, add a `NarrativeHazard` case, add a `hazardPhrase()` case.
4. All output is Turkish; keep Turkish text consistent with the existing register and keep `advice()` case-exhaustive.

---

## Known Constraints

### Swift Playgrounds Limitations
- **No `xcstringstool`**: String Catalog (`.xcstrings`) requires `xcstringstool` at build time, which is unavailable on the iPad builder. Legacy `.strings` files in `.lproj` directories are used instead.
- **No `@Previewable`**: SwiftUI previews are not supported in the Swift Playgrounds target.
- **No test targets**: Swift Playgrounds apps cannot include `XCTest` targets. The headless macOS CLI serves as the integration test harness.

### Floating-Point Safety
Open-Meteo occasionally returns `NaN` or `Infinity` for certain fields in extreme grid cells (e.g., UV index at polar night). The `JSONDecoder` is configured with `.convertFromString(positiveInfinity:negativeInfinity:nan:)`, and `WeatherMapping` uses `safe(_:at:or:)` with typed defaults on every array access. `WeatherFusion.fusedDouble(_:)` filters out non-finite values via `.filter { $0.isFinite }` before any arithmetic.

### No Pressure History
`MeteorologicalExpertSystem`'s barometric tendency is inferred, not measured, because the app does not store a rolling pressure buffer. The inference is based on current pressure deviation, rain probability gradient, and instability scalars — not on a historical 3-hour differential. This is a deliberate trade-off: it avoids persisting time-series state at the cost of some forecasting accuracy in rapidly changing conditions.

### NaturalLanguage Turkish Support
`NLTagger`'s `.sentimentScore` has limited language coverage; Turkish may return 0 (indeterminate). The `StorySentiment` engine treats a 0 score as "no signal", falling back entirely to the engine-derived severity. The NL path can only raise severity, never lower it, so behaviour is always correct.

---

## Contact & Attribution

- **Weather data + models**: [Open-Meteo](https://open-meteo.com) (AGPL-3.0) — ECMWF, GFS, ICON data under respective open data agreements.
- **Icons**: SF Symbols (Apple, license: Apple SF Symbols License Agreement).
- **Privacy proxy**: [Cloudflare Workers](https://workers.cloudflare.com/) (free tier).
- **Maintainer**: [@mehmetg06](https://github.com/mehmetg06)

---

**Last updated**: 2026-06-28 | Full technical audit by Claude Code
