# Praeventus — Technical Reference

**Praeventus** is a high-fidelity, privacy-first atmospheric prediction system distributed as a Swift Playgrounds app. It requires no Mac, no Xcode, no paid Apple Developer account, no API key, and no account of any kind. All intelligence runs on-device against freely available, institutionally-grade numerical weather prediction (NWP) data.

---

## System Philosophy

### High-Level Prediction via NWP Fusion

All forecast and geocoding requests are routed through a Cloudflare Worker (`CloudflareWeatherProvider`), which fetches raw output from three independent global NWP models in a single round-trip and returns them in one JSON envelope. The device receives all three model responses, fuses them on-device via `WeatherFusion`, and presents a single synthetic forecast to the user. No direct calls to upstream weather APIs are made from the device.

The three models in the fusion set are:

| Model | Operator | Resolution | License | Strengths |
|-------|----------|------------|---------|-----------|
| **ECMWF IFS 0.25°** | European Centre for Medium-Range Weather Forecasts | ~25 km | CC-BY-4.0 | Global skill leader; best medium-range |
| **GFS Global** | NOAA / US National Centers for Environmental Prediction | ~13 km | Public Domain | Best North American coverage; open data pioneer |
| **ICON Global** | Deutscher Wetterdienst (Germany) | ~13 km | Open Data | Strong European and global coverage; open license |
| **METAR** | aviationweather.gov / NOAA | Station-level | Public Domain | Ground-truth surface pressure and wind overlay |

Blending these three models via the on-device `WeatherFusion` engine produces a single synthetic forecast that is statistically more accurate than any single model. This is the same principle used by professional forecasters when they run ensemble model chains.

### Privacy by Architecture

Every piece of personally sensitive information (location, usage patterns, device state) is treated as hostile to third parties by default:

- Location is acquired at `kCLLocationAccuracyReduced` (~500–1000 m), then truncated to 4 decimal places (~11 m) before leaving the device — meaning the API never sees sub-kilometre coordinates.
- Sentiment analysis of weather text uses Apple's on-device `NaturalLanguage` framework; no text leaves the device.
- Sensor calibration (barometric pressure offset) uses `CMAltimeter` — the reading stays local.
- Forecast responses are cached on-device; no user identifier is ever attached to a request.
- All requests route through a dedicated Cloudflare Worker — the device IP never reaches any upstream weather provider.

### Zero Cost, Zero Lock-In

Every external dependency is either a first-party Apple framework or a free, no-key-required open service:

- **Cloudflare Workers**: Free tier; the Worker fans out to ECMWF/GFS/ICON (via Open-Meteo) and METAR (aviationweather.gov) in parallel, caches responses in Workers KV (45-min TTL). The `/narrative` endpoint uses Workers AI (also free tier) for on-demand meteorological text generation.
- **ECMWF IFS data** (CC-BY-4.0, since Oct 2025): Free for commercial use; no account required.
- **GFS / METAR data** (NOAA, Public Domain): Open data; no account required.
- **ICON data** (DWD, Open Data): Open data; no account required.
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
│   ├── OpenMeteoModels.swift           # Decodable structs used by CloudflareWeatherProvider
│   ├── CloudflareWeatherProvider.swift # Single-round-trip fetch from Cloudflare Worker
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
└── worker/                             # Cloudflare Worker — sole upstream relay
    ├── README.md                       # Worker URL, KV namespace, deployment notes
    ├── wrangler.toml
    └── src/index.js                    # Routes /forecast, /search, and /narrative; fans out to 3 NWP models + METAR + Workers AI
```

---

## Architecture

### Data Flow

```
User Input
  │
  ├─ Search query ──→ CloudflareWeatherProvider.search() ──→ GeocodingResult[]
  │                                                                 │
  │                                                                 ▼
  └─ Saved/detected location ──→ CloudflareWeatherProvider.forecast()
                                 (single round-trip; Worker returns
                                  ECMWF + GFS + ICON in one envelope)
                                         │
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

AI narrative path (per forecast refresh):
  WeatherData + DailyRange ──→ CloudflareWeatherProvider.narrative()
  (anonymous weather values only; no coordinates sent)
         │
         ▼
  Worker /narrative ──→ Workers AI (Llama 3.3 70B)
         │
         ▼
  weatherNarrative: String ──→ HomeView.narrativeCard
```

### Platform Layers

| Layer | Files | Imports | Platforms |
|-------|-------|---------|-----------|
| **Data** | OpenMeteoModels, CloudflareWeatherProvider, WeatherModel, WeatherFusion, ForecastCache, WeatherMapping, WeatherData, LocalizedStringCompat, StorySentiment | Foundation only | iOS, macOS, Linux |
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

#### `OpenMeteoModels.swift`
Decodable structs used by `CloudflareWeatherProvider` to decode the `ForecastResponse` and `GeocodingResult` shapes that the Cloudflare Worker returns. Notable details:

- `ForecastResponse.Current` holds all instantaneous fields (temperature_2m, apparent_temperature, relative_humidity_2m, surface_pressure, pressure_msl, wind_speed_10m, wind_direction_10m, wind_gusts_10m, uv_index, dew_point_2m, visibility, precipitation_probability, weather_code). Every field is `Double?` or `Int?` — partial responses are tolerated.
- `ForecastResponse.Hourly` holds parallel arrays (one value per hour); arrays are optional-typed to survive partial responses.
- `ForecastResponse.Daily` holds daily aggregates including `sunrise`/`sunset` as ISO-8601 strings.
- `GeocodingResponse` / `GeocodingResult` model the geocoding search results.

The shared `JSONDecoder` in `CloudflareWeatherProvider` is configured with `.convertFromString(positiveInfinity:negativeInfinity:nan:)` to handle the rare NaN/Infinity values emitted for some parameters in extreme grid cells.

---

#### `CloudflareWeatherProvider.swift`
Pure-Foundation HTTP client that is the **sole** upstream networking layer. All forecast, geocoding, and narrative requests go through the Cloudflare Worker at `WeatherSettings.cloudflareWorkerURL` — no direct calls to upstream weather APIs are made from the device.

**Forecast** (`forecast(latitude:longitude:)`):
- Sends a single GET to `<workerURL>/forecast?lat=…&lon=…`.
- Decodes the Worker's JSON envelope (`{ models: { ecmwf_ifs025, gfs_global, icon_global }, metar_station, generated_at }`).
- Maps the `models` dictionary to `[WeatherModel: ForecastResponse]` — the exact shape `WeatherFusion.fuse()` expects.
- Throws `WeatherClientError.noResults` if no recognised model keys are present.

**AI Narrative** (`narrative(temp:feelsLike:humidity:windSpeed:windDir:weatherCode:tempMax:tempMin:precipProb:uvIndex:visibility:pressure:lang:)`):
- Sends anonymous weather parameters to `<workerURL>/narrative` — no coordinates, no location, no user identifier.
- Visibility is converted from metres to km before sending (÷ 1000).
- Decodes `NarrativeResponse { narrative: String }`.
- Returns an empty string on any network or decoding error so the UI can hide the card gracefully.
- Called by `HomeView.startNarrativeFetch()` on every `store.forecastID` change.

**Geocoding** (`search(_:count:)`):
- Forwards to `<workerURL>/search?q=…&count=…&lang=…`.
- Passes the locale's language code for localised city names.

All paths use a 15-second timeout, a privacy User-Agent, and coordinate trimming to 4 decimal places (~11 m).

---

#### `WeatherModel.swift`
Enum of the four NWP model identifiers. The `apiValue` strings match the keys in the Worker's `models` JSON dictionary.

| Case | API value | Label |
|------|-----------|-------|
| `.bestMatch` | `best_match` | Best Match |
| `.ecmwf` | `ecmwf_ifs025` | ECMWF |
| `.gfs` | `gfs_global` | GFS |
| `.icon` | `icon_global` | ICON |

`WeatherModel.fusionSet` is `[.ecmwf, .gfs, .icon]` — the three models the Worker always returns and that `WeatherFusion` blends.

`WeatherSettings` holds:
- `multiModelEnabled` (UserDefaults, default `true`) — informational flag; fusion always runs since the Worker always delivers three models.
- `sensorCalibrationEnabled` (UserDefaults, default `false`) — whether to apply the iPad barometer offset.
- `cloudflareWorkerURL` — the compiled-in Worker base URL.

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

**`HourlyPoint`** (Identifiable, Equatable): `date`, `hour` (0–23), `temperature`, `precipitationProbability`, `condition`, `uvIndex`, `windSpeed`, `windDirection`, `windGustSpeed`, `humidity`, `dewPoint`, `visibility`.

**`DailyRange`** (Identifiable, Equatable): `date`, `min`, `max`, `feelsLikeMin`, `feelsLikeMax`, `uvIndexMax`, `windSpeedMax`, `windDirection`, `windGustMax`, `precipitationAmount`, `condition`, `sunrise: Date?`, `sunset: Date?`. Computed `mean` property. Used by the 7-day forecast card and heatwave detector.

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

**`weatherCode: Int`** (computed): Derives a representative WMO code from the `condition` enum (e.g. `.rain` → `61`, `.storm` → `95`). Used when passing the weather state to the Worker's `/narrative` endpoint so the AI receives a standard numeric code rather than an app-internal enum name.

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

### Cloudflare Worker

---

#### `worker/src/index.js`
The production Cloudflare Worker that serves as the **sole** upstream relay. All Swift network calls go to this Worker; no device ever contacts Open-Meteo or aviationweather.gov directly.

**Deployment**: `https://praeventus-weather.mehmetgezoglu.workers.dev`  
**KV namespace**: `PRAEVENTUS_CACHE`  
**Cache TTL**: 2700 s (45 min) for `/forecast`; 1800 s (30 min) for `/narrative`  
**Deployed via**: Cloudflare dashboard (no wrangler CLI — project is developed exclusively on iPad).  
**Bindings required**: `PRAEVENTUS_CACHE` (Workers KV), `AI` (Workers AI)

**Routes**:
- `GET /forecast?lat=…&lon=…` — fans out to ECMWF IFS 0.25°, GFS Global, and ICON Global in parallel via Open-Meteo, overlays the nearest METAR observation from aviationweather.gov, and returns one `WorkerEnvelope` JSON: `{ models: { ecmwf_ifs025, gfs_global, icon_global }, metar_station, metar_raw, generated_at }`. Responses are cached in Workers KV for 2700 s.
- `GET /search?q=…&count=…&lang=…` — proxies geocoding queries to Open-Meteo's geocoding endpoint and returns `GeocodingResult[]`.
- `GET /narrative?lang=&temp=&feels=&humidity=&wind=&wind_dir=&weather_code=&temp_max=&temp_min=&precip_prob=&uv=&visibility=&pressure=` — generates a 3-sentence meteorological interpretation using Workers AI (`@cf/meta/llama-3.3-70b-instruct-fp8-fast`). No coordinates are ever sent; only anonymous numeric weather values. Cache key is bucketed by language, WMO code, temperature (±5°C), and UV index (±2 units) to maximise cache reuse across nearby conditions. Cached for 1800 s. Falls back to a safe placeholder string on any AI error.

**CORS**: All routes include `Access-Control-Allow-Origin` headers for browser-based testing.

**`/narrative` implementation details**:
- `buildWeatherSummary(params, lang)` formats the raw query-string numbers into a readable paragraph (in Turkish or English) that the LLM uses as its user prompt.
- `windDirectionLabel(deg, lang)` converts a bearing to an 8-point compass label in both languages.
- `wmoCondition(code, lang)` maps the WMO code integer to a condition word (e.g. `95 → "Fırtınalı"` / `"Thunderstorm"`).
- The system prompt instructs the LLM to synthesise the parameters (not describe them individually), avoid markdown and emoji, and write exactly 3 sentences.
- The response is extracted from `choices[0].message.content || choices[0].message.reasoning_content || response` to tolerate structural variations in the Workers AI output.

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

**`forecastID: UUID`**: Published on every `applyForecast()` call (cache hit, network refresh, or location switch). `HomeView` observes this with `.onChange(of: store.forecastID)` to trigger a narrative fetch. Using an ID rather than `phase` or city name is necessary because the phase can stay `.loaded` across location changes and the city is empty for GPS locations.

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
`@Observable` (or `ObservableObject`-compatible) class that debounces the text-field input and calls `CloudflareWeatherProvider.search()`. Manages the query string and result array as published properties consumed by `LocationSearchView` and `SearchSuggestionsView`.

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
Primary display screen. Non-scrolling `topBar` contains `AtmosphereOrb` + city/time header + `CitySearchBar`. The scrollable content area (`loadedContent`) layers (in order, top to bottom):

1. `AtmosphereBackgroundView` — full-bleed animated background (behind the scroll view).
2. **Temperature hero** — large thin numeral (110 pt), condition label, feels-like. Also shows: model fusion badge (ECMWF · GFS · ICON chips with agreement %) when `store.fusionConfidence` is set; a stale-data pill (`home.stale`) when `store.isStale` is true.
3. **Story card** — `atmosphere.story` from `MeteorologicalExpertSystem` (deterministic Turkish/English narrative, always present). Severity icon from `StorySentiment` drives the heading icon.
4. **AI narrative card** — 3-sentence meteorological commentary from the Worker's `/narrative` endpoint. Shows a loading spinner (`fetchingNarrativeCard`) while the network call is in flight, then the text (`narrativeCard`). Hidden when empty, on error, or if the response contains markdown (`**`), the word "Analyze", or exceeds 600 characters. Cleared and re-fetched on every `store.forecastID` change.
5. **Atmospheric Signals card** (`atmosphericSignalsCard`) — "ATMOSPHERE" heading. Three color-coded chips (storm risk, rain signal, visibility level) sourced directly from `AtmosphericState`; two animated progress bars for instability and cloud cover. Surfaces `AtmosphericEngine` outputs that were previously only visible in the Lab.
6. `HealthInsightsCard` — thermal/UV health panel.
7. **Rotating metric card** — Instagram-story-style single-metric display with a `MetricProgressBar` above cycling through 9 parameters (humidity, pressure, wind, UV, dew point, wind gust, direction, visibility, rain probability). Tap left/right to navigate; auto-advances every 6 s. `MetricProgressBar` is an isolated private struct so its `@State` timer animation never invalidates `HomeView`'s body.
8. **Activity suitability card** — top 3 recommended activities with suitability level badges.
9. **Astronomical card** (`AstronomicalCard` private struct) — `SunArcView` Canvas arc + moon panel (illumination bar + percentage) + altitude panel (color-coded label and value).
10. **Hourly strip** — 6-slot compact row showing time, condition symbol, temperature, rain probability. Falls back to a synthetic diurnal approximation when `store.hourly` is empty.
11. **7-Day Forecast card** (`dailyForecastCard`) — shown when `!store.daily.isEmpty`. Each row: abbreviated day name, condition icon, precipitation amount (shown when > 0.5 mm), a temperature range bar with a cold→warm `LinearGradient`, and min/max values.
12. `WeatherChartsView` — Swift Charts (only when `canImport(Charts)`).

**Private subcomponents defined in this file**:
- `AtmosphereOrb` — circular glass orb (`.ultraThinMaterial`, radial gradient, shadow) containing the current weather SF Symbol. Placed in the non-scrolling header.
- `AstronomicalCard` — private struct wrapping `SunArcView`, moon illumination panel, and sun altitude panel into a single glass card.
- `SunArcView` — `Canvas`-based arc rendering. Draws a dashed background semicircle, an orange→yellow progress arc proportional to elapsed daylight, a dashed horizon line, sunrise/sunset endpoint dots, and a glowing sun disc at the current arc position.
- `MetricProgressBar` — isolated private struct with a `task(id: currentIndex)` that drives a 6-second linear fill animation and calls `onAdvance()` when done. Kept separate from `HomeView` so its `@State progress` changes never trigger the parent body.
- `HourlyStripPoint` — lightweight private struct with a `synthetic(from:atmosphere:)` factory for the fallback hourly display.
- `MetricItem` — private data bag (icon, title, value, description, accent color) for rotating metric cards.

**Narrative fetch lifecycle**: `startNarrativeFetch()` is triggered by `.onChange(of: store.forecastID)` (covers all forecast arrivals including GPS launches) and by `.onAppear` (covers re-navigation to tab). The `.onChange(of: store.phase)` watcher clears the narrative when a new `.loading` phase begins, so stale text from a previous location is never shown briefly during a location switch.

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
- Coordinates truncated to 4 decimal places (~11 m) in `CloudflareWeatherProvider.trimmed(_:)` before inclusion in any URL.
- Cache key at 2 decimal places (~1 km) — the saved location is never more precise than needed.
- `UserDefaults` stores the last city name + coarse coordinates. No device ID, no timestamp.

### Network
- All requests go to the Cloudflare Worker over HTTPS; the device never contacts upstream weather APIs directly.
- The Worker's IP is what upstream services see — the device IP is never exposed to them.
- User-Agent is a generic `Praeventus/1.0 (privacy-weather)` — no device identifier, no OS version, no app version beyond the major.
- The `/narrative` request sends only anonymous numeric weather values (temperature, humidity, WMO code, etc.) — no coordinates, no location name, no user identifier.

### On-Device Computation
- `NLTagger` sentiment analysis: text never leaves the device.
- `CMAltimeter` barometric calibration: sensor reading never leaves the device.
- `AstronomicalEngine`: pure arithmetic, no network.
- `ThermalPredictionEngine`: pure arithmetic, no network, no ML model file.
- `MeteorologicalExpertSystem`: deterministic pattern match, no network.
- The `MeteorologicalExpertSystem` Turkish narrative (the "story card") is fully on-device. The Workers AI narrative (the second card in `HomeView`) is the one place weather values leave the device — but only as anonymous numeric parameters, never as location or identity.

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
This exercises the full data + domain stack: geocoding via the Cloudflare Worker → multi-model response → fusion → mapping → atmospheric engine → narrative engine → thermal engine.

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
2. Ensure the Cloudflare Worker includes the field in its upstream request to Open-Meteo.
3. Add the field to `WeatherData`.
4. Map it in `WeatherMapping.map()` / `hourlyPoints()` / `dailyRanges()`.
5. Add a localized key to both strings files.
6. Display in `WeatherLabView` and wherever relevant.

### Adding a New NWP Model
1. Add a new case to `WeatherModel` with the correct `apiValue` matching the key the Worker uses in its `models` envelope.
2. Add its `displayName` localization key.
3. If it should join the fusion set, add it to `WeatherModel.fusionSet`.
4. Update the Cloudflare Worker to fetch and return the new model under that key.
5. No changes to `WeatherFusion` or `CloudflareWeatherProvider` are needed — both are model-agnostic.

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
The Cloudflare Worker may relay `NaN` or `Infinity` values from upstream NWP models for certain fields in extreme grid cells (e.g., UV index at polar night). `CloudflareWeatherProvider`'s `JSONDecoder` is configured with `.convertFromString(positiveInfinity:negativeInfinity:nan:)`, and `WeatherMapping` uses `safe(_:at:or:)` with typed defaults on every array access. `WeatherFusion.fusedDouble(_:)` filters out non-finite values via `.filter { $0.isFinite }` before any arithmetic.

### No Pressure History
`MeteorologicalExpertSystem`'s barometric tendency is inferred, not measured, because the app does not store a rolling pressure buffer. The inference is based on current pressure deviation, rain probability gradient, and instability scalars — not on a historical 3-hour differential. This is a deliberate trade-off: it avoids persisting time-series state at the cost of some forecasting accuracy in rapidly changing conditions.

### NaturalLanguage Turkish Support
`NLTagger`'s `.sentimentScore` has limited language coverage; Turkish may return 0 (indeterminate). The `StorySentiment` engine treats a 0 score as "no signal", falling back entirely to the engine-derived severity. The NL path can only raise severity, never lower it, so behaviour is always correct.

### Worker Deployment
- **No wrangler CLI on iPad**: The Worker (`worker/src/index.js`) is deployed manually via the Cloudflare dashboard. `wrangler.toml` is kept for documentation purposes but `wrangler deploy` is not run in CI or from the iPad development environment.

### Workers AI Binding
The `/narrative` endpoint uses the `env.AI` binding (Workers AI). This binding must be added to the Worker in the Cloudflare dashboard under **Settings → Bindings → Add binding → AI**. Without it `env.AI` is `undefined` and narrative calls return the fallback placeholder. The free Workers AI quota (10,000 neurons/day) is ample for a personal weather app.

### AI Narrative Privacy
The `/narrative` endpoint sends only anonymous numeric weather values (temperature, humidity, wind speed, WMO code, UV index, etc.) — never coordinates, location name, city, or any user identifier. The text generated by the LLM is cached on the Worker by weather-state bucket, not by user or session.

---

## Session Log

### 2026-06-29 — Cloudflare Worker as First-Class Data Source

**Branch**: `claude/cloudflare-weather-provider-pgx9p7`

#### What changed

**New file — `CloudflareWeatherProvider.swift`** (Data Layer, pure Foundation)

A new networking struct that replaces `OpenMeteoClient` for forecast and search requests when the Cloudflare data source is active. Key design points:

- `forecast(latitude:longitude:)` sends a single GET to `<baseURL>/forecast?latitude=…&longitude=…` and decodes the worker's JSON envelope (`{ models: { ecmwf_ifs025, gfs_global, icon_global }, metar_station, generated_at }`).
- The `models` dictionary is mapped to `[WeatherModel: ForecastResponse]` — exactly the shape `WeatherFusion.fuse()` already expects, so WeatherFusion needed zero changes.
- `search(_:count:)` forwards geocoding queries to `<baseURL>/search` using the same query-item shape as `OpenMeteoClient.search()`.
- Uses the same 15 s timeout, privacy User-Agent, and non-conforming-float decoder configuration as the existing client.
- Coordinate trimming to 4 decimal places preserved (≈ 11 m privacy radius).
- Throws `WeatherClientError.noResults` when the worker's models dict maps to zero recognised `WeatherModel` cases.

**`WeatherModel.swift` — `WeatherSettings` extended**

Added inside the `WeatherSettings` namespace:

- `enum DataSource: String` with cases `.cloudflare` (default) and `.openMeteo`. Backed by `UserDefaults` key `praeventus.dataSource`.
- `static var dataSource: DataSource` — get/set computed property over that key.
- `static let cloudflareWorkerURL` — the compiled-in worker URL (`https://praeventus-weather.mehmetgezoglu.workers.dev`).

The default is `.cloudflare`, meaning all fresh installs route through the Worker without any user configuration.

**`WeatherStore.swift` — `fetchForecast` restructured**

The private method now has three paths instead of two:

1. `dataSource == .cloudflare` → instantiates `CloudflareWeatherProvider` and calls `cf.forecast(...)`. The response is always multi-model and goes directly into `WeatherFusion.fuse()`.
2. `dataSource == .openMeteo` + `multiModelEnabled` → existing concurrent ECMWF/GFS/ICON fetch via `OpenMeteoClient`.
3. `dataSource == .openMeteo` + single-model → existing single-model path (returns without fusion).

`OpenMeteoClient` is kept intact and still used for the Open-Meteo path.

**`SearchViewModel.swift` — `fetchSuggestions` updated**

The `client.search(query)` call is now conditional:
- `dataSource == .cloudflare` → `CloudflareWeatherProvider(baseURL: …).search(query)`.
- Otherwise → existing `client.search(query)` via `OpenMeteoClient`.

**`Package.swift`** — `"CloudflareWeatherProvider.swift"` added to the sources array between `OpenMeteoClient.swift` and `WeatherModel.swift`.

**Localizable.strings** (both `en.lproj` and `tr.lproj`) — two new keys added:
- `"source.cloudflare"` = `"Cloudflare Worker"` / `"Cloudflare Worker"`
- `"source.openMeteo"` = `"Open-Meteo"` / `"Open-Meteo"`

#### Files with zero changes (as required)
`WeatherFusion.swift`, `WeatherMapping.swift`, `OpenMeteoClient.swift`, all UI layer files.

---

### 2026-06-29 — Remove Open-Meteo Client; Cloudflare Worker Is Sole Data Source

**Branch**: `claude/remove-open-meteo-xdbtkr`

#### What changed

**Deleted files**

- `OpenMeteoClient.swift` — removed entirely. `CloudflareWeatherProvider` is now the only HTTP client.
- `WeatherEndpoint.swift` — removed entirely. URL construction for direct Open-Meteo endpoints is no longer needed; all requests go through the Worker.

**`Package.swift`** — `"WeatherEndpoint.swift"` and `"OpenMeteoClient.swift"` removed from the sources array.

**`WeatherModel.swift`**

- `WeatherSettings.DataSource` enum removed (`.cloudflare` / `.openMeteo` distinction is gone).
- `WeatherSettings.dataSource` computed property removed.
- `WeatherSettings.cloudflareWorkerURL` retained — it is now the only routing constant.
- Updated doccomments to reflect Cloudflare Worker as the sole backend.

**`WeatherStore.swift`**

- `private let client: OpenMeteoClient` property removed.
- `init(client:)` parameter removed; `init()` is now the only initialiser.
- `fetchForecast` collapsed to a single path: always instantiates `CloudflareWeatherProvider` and calls `cf.forecast(...)`, then fuses via `WeatherFusion`.

**`SearchViewModel.swift`**

- `private let client: OpenMeteoClient` property removed; `init(client:)` → `init()`.
- `fetchSuggestions` always calls `CloudflareWeatherProvider(...).search(query)` — no branch.

**`LocationSearchView.swift`**

- `private let client = OpenMeteoClient()` removed.
- `runSearch()` creates a local `CloudflareWeatherProvider` inline.

**`App.swift` (macOS CLI)**

- Rewritten to use `CloudflareWeatherProvider` instead of `OpenMeteoClient`.
- Single fetch call returns all three models from the Worker; fusion and mapping follow as before.

**`WeatherMapping.swift`**

- `OpenMeteoClient.hourlyWindow` reference replaced with the literal `24`.
- `https://open-meteo.com/en/docs` URL comment removed from `condition(forWMOCode:)`.

**`SettingsView.swift`**

- Proxy URL section (TextField + Save button) removed — `WeatherEndpoint` is gone and the proxy UI served only the old direct-to-Open-Meteo path.
- `@State private var proxyURL` and `saveProxy()` removed.
- "About" data source label updated to `"Cloudflare Worker (ECMWF/GFS/ICON)"`.

**Localizable.strings** (both `en.lproj` and `tr.lproj`)

- `"source.cloudflare"` and `"source.openMeteo"` keys removed.
- `settings.proxy.footer` updated to remove the "call Open-Meteo directly" fallback reference.

#### Files with zero changes
`CloudflareWeatherProvider.swift`, `WeatherFusion.swift`, `OpenMeteoModels.swift`, all domain engine files, all remaining UI files (HomeView, WeatherLabView, charts, background, health card, etc.).

---

### 2026-06-29 — Cloudflare Worker Architecture Documentation Pass

**Branch**: `claude/docs-cloudflare-worker-arch-pmy6j2`

#### What changed

**Documentation only** — no Swift source files or worker code were modified.

**`README.md`**:
- Rewritten to reflect the Cloudflare Worker as the sole data relay (not an optional proxy).
- Architecture diagram updated to show Worker fan-out to ECMWF + GFS + ICON + METAR.
- "Weather data pipeline" section added explaining 3-model fusion in plain language.
- Data sources table with licenses added.
- Layer overview table updated (OpenMeteoClient removed).

**`CLAUDE.md`**:
- NWP model table updated with License column; METAR row added (aviationweather.gov, Public Domain).
- "Optional Cloudflare Worker proxy" privacy bullet replaced — the Worker is mandatory architecture.
- Zero Cost section updated with correct licenses: ECMWF CC-BY-4.0, GFS/METAR Public Domain (NOAA), ICON Open Data (DWD).
- Repository Structure: worker description updated to reflect sole-relay role.
- Worker section added to File-by-File Reference: URL, KV namespace, cache TTL, routes.
- `SearchViewModel.swift` description corrected (was still referencing `OpenMeteoClient.search()`).
- Known Constraints: Worker deployment note added (no wrangler CLI on iPad).
- Contact & Attribution: license references updated.

#### Commercial use compliance
All data sources are now public domain or CC-BY-4.0. ECMWF IFS moved to CC-BY-4.0 in October 2025, removing the previous AGPL constraint on derived works.

#### Files with zero changes
All Swift source files, `worker/src/index.js`, `Package.swift`.

---

### 2026-06-29 — Workers AI Narrative Endpoint

**Branch**: `claude/claude-md-docs-w8cwp5`

#### What changed

**`worker/src/index.js` — `/narrative` route added**

Third route added to the Worker alongside `/forecast` and `/search`.

- `handleNarrative(url, env)`: reads weather parameters from the query string, builds a bilingual plain-text summary via `buildWeatherSummary()`, and calls `env.AI.run("@cf/meta/llama-3.3-70b-instruct-fp8-fast", ...)` with a strict system prompt (no markdown, no emoji, exactly 3 sentences, synthesise parameter interactions).
- `buildWeatherSummary(params, lang)`: formats `temp`, `feels`, `humidity`, `wind`, `wind_dir`, `weather_code`, `temp_max`, `temp_min`, `precip_prob`, `uv`, `visibility`, `pressure` into a readable paragraph in Turkish or English.
- `windDirectionLabel(deg, lang)`: converts a bearing to an 8-point compass label.
- `wmoCondition(code, lang)`: maps WMO integer to a localized condition word.
- Cache key: `narrative_<lang>_<code>_<tempBucket>_<uvBucket>` (5°C and 2-unit buckets to maximise hit rate). TTL: 1800 s.
- AI response extraction: `choices[0].message.content || choices[0].message.reasoning_content || response` to tolerate Workers AI output shape variations.
- Falls back to `"Hava durumu yükleniyor..."` / `"Loading weather summary..."` on any error without propagating the error to the client.
- The initial implementation (PR #58) used `@cf/thudm/glm-4-32b-0414` (GLM-4.7-Flash); PR #59 switched to `@cf/meta/llama-3.3-70b-instruct-fp8-fast` for better instruction-following and added stricter prompts. PR #63 enriched the parameter set to include wind direction, UV, visibility, and pressure.
- `metar_raw` field added to the `/forecast` response envelope (exposes the raw METAR values that were applied as overlays, for debugging).

**`CloudflareWeatherProvider.swift` — `narrative()` method added**

New method `narrative(temp:feelsLike:humidity:windSpeed:windDir:weatherCode:tempMax:tempMin:precipProb:uvIndex:visibility:pressure:lang:)`:
- Converts visibility from metres to km (÷1000) before sending.
- All errors silently return an empty string — the UI hides the card rather than showing an error.
- Decodes `NarrativeResponse { narrative: String }` (private struct, same file).

**`WeatherData.swift` — `weatherCode` computed property added**

Derives a representative WMO integer from the `condition` enum. No stored field — no migration needed. Used solely by `HomeView.startNarrativeFetch()` to pass a standard code to the Worker.

**`WeatherStore.swift` — `forecastID` property added**

`@Published private(set) var forecastID: UUID = UUID()`. Bumped on every `applyForecast()` call regardless of phase or city value, giving `HomeView` a reliable trigger for narrative fetches that works for GPS locations and cache-first loads.

**`HomeView.swift` — AI narrative card system**

- `@State private var weatherNarrative: String` and `@State private var isFetchingNarrative: Bool` drive the card visibility.
- `startNarrativeFetch()` fires on `.onChange(of: store.forecastID)` and on `.onAppear`.
- `.onChange(of: store.phase)` clears state when a new `.loading` begins.
- `fetchingNarrativeCard`: spinner shown while the network call is in flight.
- `narrativeCard`: plain text card; guarded against responses containing `**` (markdown), the word `"Analyze"` (leaked reasoning), or exceeding 600 characters.

**Localizable.strings** (both `en.lproj` and `tr.lproj`) — one new key:
- `"narrative.fetching"` = `"Fetching weather insight…"` / `"Hava durumu özeti alınıyor…"`

#### Files with zero changes
`WeatherFusion.swift`, `WeatherMapping.swift`, `OpenMeteoModels.swift`, `WeatherModel.swift`, `ForecastCache.swift`, all domain engine files, all other UI files.

---

### 2026-06-29 — Clear Weather Rendering Performance

**Branch**: `claude/weather-app-performance-08woth`

**`WeatherEffectLayers.swift`** — four targeted fixes to reduce GPU overhead on clear/sunny weather:
- `SunCameraBloom`, `OrbitalLensHalo`: animate `.opacity` only (not frame dimensions); SwiftUI was recalculating layout on every frame at 60 fps.
- `RadialSunStarburst`: replace 24 per-ray `.blur()` passes with a single `.blur(radius: 2.5)` at the enclosing `ZStack` (1 GPU compositing pass instead of 24); also remove pulse-driven length expansion so frame size is constant.
- `airMassLayer` `TimelineView`: drop update rate from 14 fps → 8 fps (cloud drift is imperceptibly smooth at either rate).
- `HotSunnyLayer`: drop shimmer `TimelineView` from 12 fps → 8 fps; reduce shimmer line count from 6 → 4.

**`AtmosphereBackgroundView.swift`** — `lightField` breathe animation: replace `.scaleEffect` with `.opacity`. Scaling a `ZStack` of large blurred circles forces the compositor to recomposite on every frame; opacity is a free alpha-multiply on cached textures.

#### Files with zero changes
All Swift source files other than `WeatherEffectLayers.swift` and `AtmosphereBackgroundView.swift`. No Worker changes.

---

### 2026-06-29 — Home Screen Feature Surfacing + Premium Glass UI

**Branch**: `claude/home-screen-feature-visibility-w0dool`

#### What changed

**`HomeView.swift`**:

- **Temperature hero expanded**: now shows a model fusion badge row (ECMWF · GFS · ICON Capsule chips + `agreement%` consensus label) sourced from `store.fusionConfidence`; and a stale-data `Label` pill when `store.isStale` is true.
- **New `atmosphericSignalsCard`**: "ATMOSPHERE" card placed between the AI narrative and `HealthInsightsCard`. Shows three chips (storm risk, rain signal, visibility) color-coded by `AtmosphericRisk` / `AtmosphericVisibility` level; two progress bars (instability %, cloud cover %). The color helpers (`riskLevelColor`, `visibilityLevelColor`, `instabilityAccentColor`) are private to this file.
- **New `dailyForecastCard`**: "7-DAY FORECAST" card placed between the hourly strip and `WeatherChartsView`. Each of the 7 `DailyRange` rows shows: day abbreviation (or "Today"), condition SF Symbol, precipitation amount label (hidden if ≤ 0.5 mm), temperature range bar (cold-to-warm `LinearGradient`, offset within global min–max), and min/max numerals.
- **`AtmosphereOrb`** private struct: glass-morphism circle with the current weather SF Symbol, placed in the non-scrolling top bar header.
- **`AstronomicalCard`**, **`SunArcView`**, **`MetricProgressBar`**, **`HourlyStripPoint`**, **`MetricItem`**: refactored into named private structs to isolate animation state and avoid unnecessary body re-renders.

**Localizable.strings** (both `en.lproj` and `tr.lproj`) — 9 new keys added:
- `"home.atmosphere.heading"`, `"home.stormRisk"`, `"home.rainSignal"`, `"home.instability"`, `"home.cloudCover"`, `"home.daily.heading"`, `"home.today"`, `"home.fusion.agreement"`, `"home.stale"`

#### Files with zero changes
`WeatherStore.swift`, `AtmosphericEngine.swift`, all data/domain layer files, `WeatherLabView.swift`, `SettingsView.swift`, Worker.

---

### 2026-06-29 — NASA IMERG / NASA POWER Precipitation: Added and Removed

**Branches**: `claude/imerg-precipitation-route-uv0luw` → `claude/nasa-power-precipitation-t1icpv` → `claude/satellite-precip-visibility-usydym` → `claude/satellite-precip-ui-debug-ihhbec` → `claude/remove-imerg-nasa-power-8hqeej`

**PRs #68–73 net effect: zero Swift files added or removed; zero worker routes remain.**

#### What was added (PRs #68–72)

- **Worker `/precipitation` route**: fetched 30-minute precipitation data from NASA GPM IMERG via OpenSearch→GeoJSON pipeline (PR #68), then switched to NASA POWER MERRA2 `PRECTOT` parameter (PR #69). Cached results for 25 minutes. Found nearest feature centroid within a bounding box.
- **`IMERGPrecipitation` struct** in `CloudflareWeatherProvider.swift`: decodable response model.
- **`satellitePrecipitation(latitude:longitude:)` async method** on `CloudflareWeatherProvider`: trimmed coordinates to 1 decimal place (city-level) before sending.
- **`satellitePrecip: IMERGPrecipitation?`** `@Published` property on `WeatherStore`; populated by a background `Task` fired after each network forecast refresh.
- **SATELLITE OBSERVATIONS card** in `WeatherLabView`: showed `mm/sa` label and "NASA GPM IMERG" sub-label when `satellitePrecip` was non-nil.

#### Why removed (PR #73)

NASA POWER MERRA2 returned `"no_satellite_coverage"` for the vast majority of global locations, making the feature unreliable as a general-purpose precipitation overlay. All code was cleanly reverted: Worker route, Swift struct, method, published property, background Task, and Lab card — leaving the codebase in the same file count as before.

---

## Contact & Attribution

- **Weather data + models** (via Cloudflare Worker → Open-Meteo + aviationweather.gov): ECMWF IFS data CC-BY-4.0; GFS and METAR data Public Domain (NOAA); ICON data Open Data (DWD). All free for commercial use; no account required.
- **AI narrative**: Cloudflare Workers AI, `@cf/meta/llama-3.3-70b-instruct-fp8-fast` (Meta Llama 3.3 70B, free tier).
- **Icons**: SF Symbols (Apple, license: Apple SF Symbols License Agreement).
- **Data relay**: [Cloudflare Workers](https://workers.cloudflare.com/) (free tier).
- **Maintainer**: [@mehmetg06](https://github.com/mehmetg06)

---

**Last updated**: 2026-06-29 | Home screen premium UI surfacing + performance + satellite precipitation (added and removed)
