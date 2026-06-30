# Praeventus Backend (Deno Deploy)

Privacy-first weather aggregator. The app talks only to this backend; upstreams (MET Norway, Bright
Sky, aviationweather.gov, Nominatim) see a Deno Deploy datacenter IP, never the user's device.

This replaces the former Cloudflare Worker. Routes and JSON shapes are identical, so the iOS client
only needs its base URL (`WeatherSettings.backendBaseURL`) changed.

## What it does

| Route                                       | Function                                                                            |
| ------------------------------------------- | ----------------------------------------------------------------------------------- |
| `GET /forecast?lat=&lon=`                   | MET Norway (ECMWF) + Bright Sky (ICON) + METAR overlay, fused into one envelope |
| `GET /search?q=&lang=&count=`               | Nominatim (OpenStreetMap) geocoding                                                 |
| `GET /narrative?lang=&temp=&...`            | AI weather commentary — **anonymous numeric values only**                           |
| `GET /nowcast?lat=&lon=`                    | MET Norway radar nowcast (Scandinavia coverage)                                     |
| `GET /tile/{nexrad,satellite,dwd}?z=&x=&y=` | radar/satellite tile proxy                                                          |

## File structure

```
deno/
├── main.ts          # Deno.serve entrypoint: routing, CORS, rate limit
├── cache.ts         # Deno KV: grid rounding, TTL, write-dedup, stale-while-revalidate, rate limit
├── aiProvider.ts    # Groq (primary) -> Gemini (fallback) chain; extensible
├── weather.ts       # MET Norway + Bright Sky + METAR fusion + search/narrative/nowcast handlers
├── tiles.ts         # radar/satellite tile proxy (binary KV cache)
├── util.ts          # unit conversions, WMO maps, CORS, JSON helpers, AI summary builder
└── deno.json        # tasks + fmt/lint config
```

## Cache (Deno KV)

- **Grid rounding:** coordinates are snapped to a ~0.1° grid (`CACHE_GRID`) so neighbouring requests
  share a cache entry. Full-precision keys gave ~0% hits.
- **TTL:** forecast 12 min, nowcast 5 min, narrative 30 min, search 30 days (via `expireIn`).
- **Write dedup:** an unchanged value is not re-written, keeping daily KV write volume low.
- **Stale-while-revalidate:** stale forecast/nowcast data is served instantly and refreshed in the
  background.

Deno KV is auto-provisioned on Deno Deploy — no binding/config needed. Locally it is backed by
SQLite.

## AI narrative

Workers AI is gone. `aiProvider.ts` runs an ordered provider chain:

1. **Groq** — `llama-3.3-70b-versatile`, OpenAI-compatible API (`https://api.groq.com/openai/v1`).
2. **Gemini** — `gemini-2.5-flash-lite`. Used automatically when Groq returns 429 (rate limit) or
   404 (model not found), or on network failure.

Adding a third provider = append another `AIProvider` to `providers`.

**Privacy:** only the abstracted weather summary (temperature, humidity, pressure trend, wind —
numeric values) is ever sent. Coordinates, IP, and any device/user identifier are never sent. When
no provider key is configured, a static loading string is returned and the UI hides the card.

## Environment variables

| Variable         | Required    | Description                                      |
| ---------------- | ----------- | ------------------------------------------------ |
| `GROQ_API_KEY`   | recommended | Primary AI provider (Groq)                       |
| `GEMINI_API_KEY` | recommended | Fallback AI provider (Gemini)                    |
| `CACHE_GRID`     | optional    | Cache grid resolution in degrees (default `0.1`) |

## Run locally

```bash
cd deno
deno task dev      # http://localhost:8000
# with AI keys:
GROQ_API_KEY=... GEMINI_API_KEY=... deno task start
```

```bash
curl "http://localhost:8000/forecast?lat=41.01&lon=28.98"
curl "http://localhost:8000/search?q=Tokyo&count=5"
curl "http://localhost:8000/narrative?lang=en&temp=24&humidity=70&wind=12&weather_code=3"
```

## Deploy (Deno Deploy)

1. Create a project at <https://dash.deno.com>, link this repo, set entrypoint to `deno/main.ts`.
2. Add env vars `GROQ_API_KEY` and `GEMINI_API_KEY` in the project settings.
3. Deploy. Deno Deploy prints a URL like `https://praeventus.deno.dev`.
4. Set that URL as `WeatherSettings.backendBaseURL` in `Praeventus.swiftpm/WeatherModel.swift`.

Or via CLI:

```bash
deno install -gArf jsr:@deno/deployctl
deployctl deploy --project=praeventus --entrypoint=deno/main.ts
```
