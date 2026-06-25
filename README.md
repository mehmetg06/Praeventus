# Praeventus

A privacy-first, zero-cost, science-grade weather app for **anywhere in the
world** — built entirely as a Swift Playgrounds app (no Mac, no Xcode, no paid
Apple Developer account required).

## Principles

- **Global.** Search any city on Earth, or use your approximate location.
- **Private by design.**
  - Location uses `kCLLocationAccuracyReduced` (and is rounded again in-app), so
    the app only ever knows your rough area — never a sharp fix.
  - An optional [Cloudflare Worker proxy](worker/) hides your IP from the
    weather servers.
  - Forecast summaries are analyzed **on-device** with Apple's `NaturalLanguage`
    framework — nothing is sent to any LLM or cloud service.
  - No account, no API key, no tracking.
- **Scientific & free.** Data comes from [Open-Meteo](https://open-meteo.com)
  (ECMWF / national models), which needs no key.

## Architecture

```
CLLocationManager (reduced accuracy)  ─┐
City search (Open-Meteo geocoding)  ───┤→ OpenMeteoClient ─→ [Cloudflare Worker]
                                                                     │
                                                          api.open-meteo.com
                                                                     │
              ForecastResponse → WeatherData → AtmosphericEngine → SwiftUI
                                                  │
                                   Swift Charts + on-device sentiment
```

| Layer | Files |
|-------|-------|
| Data (pure Foundation) | `WeatherEndpoint`, `OpenMeteoModels`, `OpenMeteoClient`, `WeatherMapping`, `WeatherData` |
| Domain / state | `AtmosphericEngine`, `WeatherStore`, `StorySentiment` |
| Location | `LocationProvider` |
| UI | `PraeventusRootView`, `HomeView`, `LocationSearchView`, `WeatherChartsView`, `WeatherLabView`, `SettingsView`, atmosphere/effect layers |
| Localization | `Localizable.xcstrings` (English + Turkish) |
| Privacy proxy | [`worker/`](worker/) (Cloudflare Worker) |

## Running it

1. Open `Praeventus.swiftpm` in **Swift Playgrounds** (iPad or Mac).
2. In **App Settings → Capabilities**, add **Core Location When in Use** and a
   usage description (e.g. *"Praeventus uses your approximate location to show
   local weather."*). This is the only manual setup step.
3. Run. Search a city or tap **Use my location**.
4. (Optional) Deploy the [privacy proxy](worker/) and paste its URL into
   **Settings → Data Source / Privacy Proxy**.

## Verifying the data layer without an iPad

The networking/decoding/mapping layer is pure Foundation, so on a machine with a
Swift toolchain you can run it headless:

```bash
cd Praeventus.swiftpm
swift run        # geocodes a city, fetches a forecast, prints the mapped model
```
