# Praeventus Privacy Proxy (Cloudflare Worker)

A tiny, free, stateless pass-through proxy that hides the user's IP from the
weather upstreams. The app talks only to this Worker; the Worker talks to
Open-Meteo. Open-Meteo therefore sees a Cloudflare datacenter IP, never the
user's device.

## What it does

- Routes by path:
  - `GET /v1/forecast?...` → `https://api.open-meteo.com/v1/forecast`
  - `GET /v1/search?...` → `https://geocoding-api.open-meteo.com/v1/search`
- Rebuilds the request with a **clean header set**, dropping every
  identity/location/fingerprint header (`X-Forwarded-For`, `CF-Connecting-IP`,
  `CF-IPCountry`, `True-Client-IP`, `Referer`, `Cookie`, …) and replacing
  `User-Agent` with a generic value.
- Adds permissive CORS and a 5-minute edge cache.

## Deploy (free tier — 100k requests/day)

```bash
cd worker
npm i -g wrangler        # or: npx wrangler ...
wrangler login
wrangler deploy
```

Wrangler prints a URL like `https://praeventus.<your-subdomain>.workers.dev`.

## Point the app at it

Set that URL as the proxy base in **either** place:

- App at runtime: **Settings tab → Data source / proxy URL**, or
- Compile-time default: `WeatherEndpoint.defaultProxyBaseURL` in
  `Praeventus.swiftpm/WeatherEndpoint.swift`.

Leave it empty to call Open-Meteo directly (the app still works; you just lose
the IP-anonymization layer).

## Recommended hardening: Transform Rule

The Worker already drops `CF-Connecting-IP` from the request it *builds*. For
defense in depth, also add a dashboard Transform Rule so Cloudflare never
attaches it on the outbound hop:

1. Cloudflare Dashboard → your domain/Worker → **Rules → Transform Rules →
   Modify Request Header**.
2. Action: **Remove** header `cf-connecting-ip` (and optionally
   `x-forwarded-for`).
3. Deploy.

## Quick test

```bash
# Forecast
curl "https://praeventus.<your-subdomain>.workers.dev/v1/forecast?latitude=41.01&longitude=28.98&current=temperature_2m&timezone=auto"

# City search
curl "https://praeventus.<your-subdomain>.workers.dev/v1/search?name=Tokyo&count=5"
```

Both should return Open-Meteo JSON. The response carries no echo of your client
IP.
