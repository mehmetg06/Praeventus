# Praeventus

A privacy-first, zero-cost, science-grade weather app for **anywhere in the
world** — built entirely as a Swift Playgrounds app (no Mac, no Xcode, no paid
Apple Developer account required).

## Principles

- **Global.** Search any city on Earth, or use your approximate location.
- **Private by design.**
  - Location uses `kCLLocationAccuracyReduced` (and is rounded again in-app), so
    the app only ever knows your rough area — never a sharp fix.
  - All requests go through a Cloudflare Worker — your device IP never reaches
    any weather provider.
  - Forecast summaries are analyzed **on-device** with Apple's `NaturalLanguage`
    framework — nothing is sent to any LLM or cloud service.
  - No account, no API key, no tracking.
- **Scientific & free.** Data comes from three independent global NWP models,
  blended on-device for higher accuracy than any single model alone. All data
  sources are public domain or CC-BY-4.0.

## Architecture

```
CLLocationManager (reduced accuracy)
City search ─────────────────────────────┐
                                         ▼
                             CloudflareWeatherProvider
                                         │ HTTPS
                                         ▼
                          praeventus-weather.mehmetgezoglu.workers.dev
                               ┌─────────┼──────────┐
                               ▼         ▼           ▼
                            ECMWF      GFS         ICON       + METAR overlay
                                  (Open-Meteo · Workers KV cache · 45 min TTL)
                                         │
                              [WorkerEnvelope JSON]
                                         │
                               WeatherFusion.fuse()
                               (inverse-spread weighted blend, on-device)
                                         │
                         WeatherData → AtmosphericEngine → SwiftUI
```

## Weather data pipeline

The Cloudflare Worker fans out to three global NWP models in parallel — ECMWF
IFS 0.25° (Europe), GFS (NOAA, USA), and ICON (DWD, Germany) — and returns all
three forecasts in a single JSON envelope. The app blends them on-device:
models that agree closely are weighted heavily; outliers contribute less. The
result is statistically more accurate than any single model, at no extra cost.

METAR observations from aviationweather.gov are overlaid on each response to
provide real-time surface pressure and wind from nearby reporting stations.

| Model | Operator | License |
|-------|----------|---------|
| ECMWF IFS 0.25° | ECMWF | CC-BY-4.0 |
| GFS Global | NOAA, USA | Public Domain |
| ICON Global | DWD, Germany | Open Data |
| METAR | aviationweather.gov | Public Domain |

No API keys required for any of these.

## Layer overview

| Layer | Key files |
|-------|-----------|
| Data (pure Foundation) | `CloudflareWeatherProvider`, `OpenMeteoModels`, `WeatherFusion`, `WeatherMapping`, `WeatherData` |
| Domain / engines | `AtmosphericEngine`, `ThermalPredictionEngine`, `AstronomicalEngine`, `WeatherStore` |
| Location | `LocationProvider` |
| UI (iOS only) | `HomeView`, `WeatherLabView`, `WeatherChartsView`, `AtmosphereBackgroundView` + effect layers |
| Localization | `en.lproj/Localizable.strings`, `tr.lproj/Localizable.strings` |
| Worker | [`worker/src/index.js`](worker/src/index.js) |

## Running it

1. Open `Praeventus.swiftpm` in **Swift Playgrounds** (iPad or Mac).
2. In **App Settings → Capabilities**, add **Core Location When in Use** and a
   usage description (e.g. *"Praeventus uses your approximate location to show
   local weather."*). This is the only manual setup step.
3. Run. Search a city or tap **Use my location**.

## Verifying the data layer without an iPad

The networking/decoding/mapping layer is pure Foundation, so on a machine with a
Swift toolchain you can run it headless:

```bash
cd Praeventus.swiftpm
swift run        # geocodes a city, fetches a forecast via the Worker, prints the mapped model
```
