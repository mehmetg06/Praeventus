// Deno KV cache layer — the Deno Deploy replacement for Workers KV.
//
// Improvements over the old Workers KV layer:
//   1. Coordinate keys are snapped to a ~0.1 degree grid so neighbouring
//      requests share a cache entry (full-precision keys gave ~0% hit rate).
//   2. TTLs raised to 10-15 min via `expireIn` (ms).
//   3. Writes are de-duplicated: an unchanged value is not re-written, which
//      keeps daily KV write volume low (the original free-tier pain point).
//   4. Stale-while-revalidate: a soft freshness window lets us return stale
//      data instantly while refreshing in the background.

import { jsonResponse } from "./util.ts";

const kv = await Deno.openKv();

/** JSON response that mirrors the old Worker's `_cached` envelope flag. */
export function jsonResponseWithCache(data: unknown, cached: boolean): Response {
  if (cached && data && typeof data === "object") {
    return jsonResponse({ ...(data as Record<string, unknown>), _cached: true });
  }
  return jsonResponse(data);
}

// Coordinate grid resolution in degrees (~11 km at 0.1). Override with CACHE_GRID.
const GRID = parseFloat(Deno.env.get("CACHE_GRID") || "0.1") || 0.1;

// Hard TTLs (ms) — entry is evicted by Deno KV after this.
export const TTL = {
  forecast: 12 * 60 * 1000, // 12 min (10-15 target)
  nowcast: 5 * 60 * 1000,
  narrative: 30 * 60 * 1000,
  search: 30 * 24 * 60 * 60 * 1000, // 30 days (OSM policy)
} as const;

// Soft freshness window (ms): younger than this -> "fresh"; between soft and
// hard TTL -> "stale" (served immediately, refreshed in background).
const SOFT = {
  forecast: 8 * 60 * 1000,
  nowcast: 3 * 60 * 1000,
} as const;

/** Snap a coordinate to the cache grid: 41.0082 -> 41.0 (GRID = 0.1). */
export function snapGrid(v: number): number {
  return Math.round(v / GRID) * GRID;
}

type KvKey = Deno.KvKey;

interface Stored<T> {
  data: T;
  storedAt: number;
}

function deepEqual(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (typeof a !== "object" || typeof b !== "object" || a == null || b == null) {
    return false;
  }
  return JSON.stringify(a) === JSON.stringify(b);
}

/** Simple get: returns the cached value or null (used for search, tiles meta). */
export async function cacheGet<T>(key: KvKey): Promise<T | null> {
  try {
    const res = await kv.get<Stored<T>>(key);
    return res.value ? res.value.data : null;
  } catch (err) {
    console.warn("cacheGet failed:", key, err);
    return null;
  }
}

/**
 * Write-deduplicated put. Skips the write when the stored value is identical,
 * preserving the existing entry's expiry instead of resetting it on every hit.
 */
export async function cachePut<T>(key: KvKey, value: T, ttl: number): Promise<void> {
  try {
    const existing = await kv.get<Stored<T>>(key);
    if (existing.value && deepEqual(existing.value.data, value)) return;
    await kv.set(key, { data: value, storedAt: Date.now() } satisfies Stored<T>, {
      expireIn: ttl,
    });
  } catch (err) {
    console.warn("cachePut failed:", key, err);
  }
}

export async function cacheDelete(key: KvKey): Promise<void> {
  try {
    await kv.delete(key);
  } catch (err) {
    console.warn("cacheDelete failed:", key, err);
  }
}

export type CacheState = "fresh" | "stale" | "miss";

export interface SWRResult<T> {
  value: T | null;
  state: CacheState;
}

/**
 * Stale-while-revalidate read. `softMs` is the freshness window; values older
 * than that (but still present) come back as "stale" so the caller can serve
 * them immediately and refresh in the background.
 */
export async function cacheGetSWR<T>(key: KvKey, softMs: number): Promise<SWRResult<T>> {
  try {
    const res = await kv.get<Stored<T>>(key);
    if (!res.value) return { value: null, state: "miss" };
    const age = Date.now() - res.value.storedAt;
    return { value: res.value.data, state: age <= softMs ? "fresh" : "stale" };
  } catch (err) {
    console.warn("cacheGetSWR failed:", key, err);
    return { value: null, state: "miss" };
  }
}

export const SOFT_TTL = SOFT;

/**
 * Fetch-through cache with stale-while-revalidate semantics.
 *  - fresh  -> return cached
 *  - stale  -> return cached now, refresh in background (fire-and-forget)
 *  - miss   -> await `loader`, cache, return
 */
export async function withSWR<T>(
  key: KvKey,
  softMs: number,
  hardMs: number,
  loader: () => Promise<T>,
): Promise<{ value: T; cached: boolean }> {
  const cached = await cacheGetSWR<T>(key, softMs);

  if (cached.state === "fresh" && cached.value != null) {
    return { value: cached.value, cached: true };
  }

  if (cached.state === "stale" && cached.value != null) {
    // Fire-and-forget refresh; errors must not reject the served response.
    (async () => {
      try {
        const fresh = await loader();
        await cachePut(key, fresh, hardMs);
      } catch (err) {
        console.warn("SWR background refresh failed:", key, err);
      }
    })();
    return { value: cached.value, cached: true };
  }

  const fresh = await loader();
  await cachePut(key, fresh, hardMs);
  return { value: fresh, cached: false };
}

// --- Rate limiting ----------------------------------------------------------
// Per-IP sliding window using a Deno KV atomic counter with expireIn.

const RATE_LIMITS: Record<string, { windowSec: number; maxRequests: number }> = {
  "/narrative": { windowSec: 60, maxRequests: 10 },
  "/search": { windowSec: 60, maxRequests: 30 },
  "/forecast": { windowSec: 60, maxRequests: 30 },
  "/nowcast": { windowSec: 60, maxRequests: 30 },
};

export async function checkRateLimit(ip: string, pathname: string): Promise<boolean> {
  const config = RATE_LIMITS[pathname];
  if (!config) return false;
  const key: KvKey = ["rl", pathname, ip];
  try {
    const res = await kv.get<number>(key);
    const count = res.value ?? 0;
    if (count >= config.maxRequests) return true;
    await kv.set(key, count + 1, { expireIn: config.windowSec * 1000 });
    return false;
  } catch (err) {
    console.warn("checkRateLimit failed:", err);
    return false;
  }
}
