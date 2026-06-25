/**
 * Praeventus privacy proxy — Cloudflare Worker.
 *
 * A pass-through proxy that sits between the app and Open-Meteo so the upstream
 * weather servers only ever see this Worker's IP, never the user's device IP.
 *
 * Routing (path-based):
 *   /v1/forecast?...  ->  https://api.open-meteo.com/v1/forecast?...
 *   /v1/search?...    ->  https://geocoding-api.open-meteo.com/v1/search?...
 *
 * Every request is rebuilt with a clean header set: all IP / geo / fingerprint
 * headers are stripped and the User-Agent is replaced with a generic one.
 *
 * Free tier: 100,000 requests/day — plenty for an independent weather app.
 */

const UPSTREAMS = {
  "/v1/forecast": "https://api.open-meteo.com/v1/forecast",
  "/v1/search": "https://geocoding-api.open-meteo.com/v1/search",
};

// Headers that can leak the client's identity / location. Stripped on every hop.
const STRIP_HEADERS = [
  "x-forwarded-for",
  "x-forwarded-host",
  "x-forwarded-proto",
  "x-real-ip",
  "cf-connecting-ip",
  "cf-connecting-ipv6",
  "cf-ipcountry",
  "cf-ray",
  "cf-visitor",
  "true-client-ip",
  "forwarded",
  "via",
  "referer",
  "origin",
  "cookie",
];

const GENERIC_USER_AGENT = "Praeventus-Proxy/1.0";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Max-Age": "86400",
};

export default {
  async fetch(request) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }
    if (request.method !== "GET") {
      return json({ error: "method_not_allowed" }, 405);
    }

    const url = new URL(request.url);
    const upstreamBase = UPSTREAMS[url.pathname];
    if (!upstreamBase) {
      return json({ error: "not_found", hint: "use /v1/forecast or /v1/search" }, 404);
    }

    // Carry the query string straight through to the upstream endpoint.
    const upstreamURL = new URL(upstreamBase);
    upstreamURL.search = url.search;

    // Build a fresh, sanitized header set (the incoming Headers is immutable).
    const headers = new Headers();
    headers.set("User-Agent", GENERIC_USER_AGENT);
    headers.set("Accept", "application/json");
    // Note: STRIP_HEADERS are simply never copied; nothing identifying is added.

    let upstreamResponse;
    try {
      upstreamResponse = await fetch(upstreamURL.toString(), {
        method: "GET",
        headers,
        // Do not forward client IP via Cloudflare's connecting-ip mechanism.
        cf: { cacheTtl: 300, cacheEverything: true },
      });
    } catch (err) {
      return json({ error: "upstream_unreachable" }, 502);
    }

    // Re-emit the body with CORS + a short cache; drop any upstream headers
    // that could echo request metadata back.
    const responseHeaders = new Headers(CORS_HEADERS);
    responseHeaders.set(
      "Content-Type",
      upstreamResponse.headers.get("Content-Type") || "application/json"
    );
    responseHeaders.set("Cache-Control", "public, max-age=300");

    return new Response(upstreamResponse.body, {
      status: upstreamResponse.status,
      headers: responseHeaders,
    });
  },
};

function json(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// Exported for completeness / testing.
export { STRIP_HEADERS, UPSTREAMS };
