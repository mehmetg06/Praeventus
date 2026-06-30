// Praeventus backend — Deno Deploy entrypoint.
//
// Drop-in replacement for the Cloudflare Worker. Same routes and JSON shapes,
// so the iOS client only needs its base URL changed. Cache is Deno KV; AI
// narrative is the Groq -> Gemini provider chain (see aiProvider.ts).
//
// Routes:
//   GET /forecast?lat=&lon=        ECMWF + GFS + ICON + METAR fusion
//   GET /search?q=&lang=&count=    Nominatim geocoding
//   GET /narrative?lang=&temp=&... AI weather commentary (anonymous values only)
//   GET /nowcast?lat=&lon=         MET Norway radar nowcast
//   GET /tile/{nexrad,satellite,dwd}?z=&x=&y=   radar/satellite tile proxy

import { corsHeaders, jsonResponse } from "./util.ts";
import { checkRateLimit } from "./cache.ts";
import { handleForecast, handleNarrative, handleNowcast, handleSearch } from "./weather.ts";
import { handleTileDwd, handleTileNexrad, handleTileSatellite } from "./tiles.ts";

function clientIP(request: Request): string {
  const xff = request.headers.get("x-forwarded-for");
  if (xff) return xff.split(",")[0].trim();
  return request.headers.get("x-real-ip") || "unknown";
}

export async function handler(request: Request): Promise<Response> {
  const url = new URL(request.url);

  if (request.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders() });
  }
  if (request.method !== "GET") {
    return new Response(null, { status: 405, headers: corsHeaders() });
  }

  if (await checkRateLimit(clientIP(request), url.pathname)) {
    return jsonResponse({ error: "rate limit exceeded" }, 429);
  }

  switch (url.pathname) {
    case "/forecast":
      return handleForecast(url);
    case "/search":
      return handleSearch(url);
    case "/narrative":
      return handleNarrative(url);
    case "/nowcast":
      return handleNowcast(url);
    case "/tile/nexrad":
      return handleTileNexrad(url);
    case "/tile/satellite":
      return handleTileSatellite(url);
    case "/tile/dwd":
      return handleTileDwd(url);
    default:
      return new Response(null, { status: 404, headers: corsHeaders() });
  }
}

if (import.meta.main) {
  Deno.serve(handler);
}
