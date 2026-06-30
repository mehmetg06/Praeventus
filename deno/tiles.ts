// Tile proxy handlers — route radar / satellite tiles through the backend so
// the device IP never reaches upstream tile servers, with Deno KV caching to
// minimise their load. Ported from the Cloudflare Worker; binary tiles are
// stored in KV as Uint8Array instead of Workers KV ArrayBuffer.

import { corsHeaders, USER_AGENT } from "./util.ts";

const kv = await Deno.openKv();
const TILE_TTL = 5 * 60 * 1000; // 5 min

// Convert XYZ tile coordinates to an EPSG:3857 BBOX [west, south, east, north].
function tileToBbox3857(z: number, x: number, y: number): [number, number, number, number] {
  const R = 6378137;
  const n = 1 << z;
  const west = (x / n) * 2 * Math.PI * R - Math.PI * R;
  const east = ((x + 1) / n) * 2 * Math.PI * R - Math.PI * R;
  const latN = Math.atan(Math.sinh(Math.PI * (1 - 2 * y / n)));
  const latS = Math.atan(Math.sinh(Math.PI * (1 - 2 * (y + 1) / n)));
  const north = Math.log(Math.tan(Math.PI / 4 + latN / 2)) * R;
  const south = Math.log(Math.tan(Math.PI / 4 + latS / 2)) * R;
  return [Math.round(west), Math.round(south), Math.round(east), Math.round(north)];
}

async function tileCacheGet(key: Deno.KvKey): Promise<Uint8Array | null> {
  try {
    const res = await kv.get<Uint8Array>(key);
    return res.value && res.value.byteLength > 0 ? res.value : null;
  } catch (err) {
    console.warn("tileCacheGet failed:", key, err);
    return null;
  }
}

async function tileCachePut(key: Deno.KvKey, buffer: Uint8Array): Promise<void> {
  try {
    await kv.set(key, buffer, { expireIn: TILE_TTL });
  } catch (err) {
    console.warn("tileCachePut failed:", key, err);
  }
}

function tileResponse(buffer: Uint8Array, contentType: string): Response {
  return new Response(buffer as unknown as BodyInit, {
    status: 200,
    headers: {
      "Content-Type": contentType,
      "Cache-Control": "public, max-age=300",
      ...corsHeaders(),
    },
  });
}

function parseZXY(url: URL, maxZoom: number): { z: number; x: number; y: number } | null {
  const z = parseInt(url.searchParams.get("z") || "");
  const x = parseInt(url.searchParams.get("x") || "");
  const y = parseInt(url.searchParams.get("y") || "");
  if (isNaN(z) || isNaN(x) || isNaN(y)) return null;
  if (z < 0 || z > maxZoom) return null;
  const max = (1 << z) - 1; // tiles per axis at this zoom
  if (x < 0 || y < 0 || x > max || y > max) return null;
  return { z, x, y };
}

async function proxyTile(url: string, cacheKey: Deno.KvKey, timeoutMs: number): Promise<Response> {
  const cached = await tileCacheGet(cacheKey);
  if (cached) return tileResponse(cached, "image/png");
  try {
    const res = await fetch(url, {
      signal: AbortSignal.timeout(timeoutMs),
      headers: { "User-Agent": USER_AGENT },
    });
    if (!res.ok) return new Response(null, { status: 503, headers: corsHeaders() });
    const buffer = new Uint8Array(await res.arrayBuffer());
    await tileCachePut(cacheKey, buffer);
    return tileResponse(buffer, "image/png");
  } catch (err) {
    console.warn("proxyTile failed:", cacheKey, err);
    return new Response(null, { status: 503, headers: corsHeaders() });
  }
}

// IEM NEXRAD composite radar (Public Domain academic service).
export function handleTileNexrad(url: URL): Promise<Response> {
  const t = parseZXY(url, 10);
  if (!t) return Promise.resolve(new Response(null, { status: 400, headers: corsHeaders() }));
  const [west, south, east, north] = tileToBbox3857(t.z, t.x, t.y);
  const wmsUrl = `https://mesonet.agron.iastate.edu/cgi-bin/wms/nexrad/n0r.cgi` +
    `?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&FORMAT=image%2Fpng` +
    `&TRANSPARENT=true&LAYERS=nexrad-n0r-900913` +
    `&WIDTH=256&HEIGHT=256&SRS=EPSG%3A3857&BBOX=${west},${south},${east},${north}`;
  return proxyTile(wmsUrl, ["tile", "nexrad", t.z, t.x, t.y], 10000);
}

// NOAA GOES-East IR satellite tiles via NASA GIBS (Public Domain).
// GIBS WMTS uses {z}/{y}/{x} axis order (row-major).
export function handleTileSatellite(url: URL): Promise<Response> {
  const t = parseZXY(url, 9);
  if (!t) return Promise.resolve(new Response(null, { status: 400, headers: corsHeaders() }));
  const gibsUrl = `https://gibs.earthdata.nasa.gov/wmts/epsg3857/best` +
    `/GOES_East_IR_BrightnessTempColorized/default/default` +
    `/GoogleMapsCompatible_Level9/${t.z}/${t.y}/${t.x}.png`;
  return proxyTile(gibsUrl, ["tile", "sat", t.z, t.x, t.y], 12000);
}

// DWD precipitation radar WMS (CC BY 4.0, attribution required in UI).
export function handleTileDwd(url: URL): Promise<Response> {
  const t = parseZXY(url, 10);
  if (!t) return Promise.resolve(new Response(null, { status: 400, headers: corsHeaders() }));
  const [west, south, east, north] = tileToBbox3857(t.z, t.x, t.y);
  const dwdUrl = `https://maps.dwd.de/geoserver/dwd/wms` +
    `?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&FORMAT=image%2Fpng` +
    `&TRANSPARENT=true&LAYERS=dwd%3ANiederschlagsradar` +
    `&WIDTH=256&HEIGHT=256&SRS=EPSG%3A3857&BBOX=${west},${south},${east},${north}`;
  return proxyTile(dwdUrl, ["tile", "dwd", t.z, t.x, t.y], 10000);
}
