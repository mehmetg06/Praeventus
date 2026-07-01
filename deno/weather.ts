// Weather aggregation handlers — the core fusion logic, ported verbatim from
// the Cloudflare Worker (v4). The backend fans out to MET Norway (ECMWF/GFS),
// Bright Sky (ICON) and aviationweather.gov (METAR), normalises everything into
// the Open-Meteo-shaped envelope the Swift `WeatherFusion` expects, and overlays
// the nearest-station METAR onto the current conditions.
//
// Only the cache (Deno KV) and the AI narrative (aiProvider) differ from the
// original Worker; the meteorological math is unchanged.

import {
  apparentTemp,
  buildWeatherSummary,
  circularMeanDir,
  ktsToKmh,
  mapBrightSkyWMO,
  mapMetNoWMO,
  metarAltimToHPa,
  metarWMO,
  narrativeSystemPrompt,
  normalizeLang,
  smToMetres,
  USER_AGENT,
} from "./util.ts";
import tzlookup from "tz-lookup";
import { sunriseSunsetISO } from "./astro.ts";
import {
  cacheGet,
  cachePut,
  jsonResponseWithCache,
  snapGrid,
  SOFT_TTL,
  TTL,
  withSWR,
} from "./cache.ts";
import { jsonResponse } from "./util.ts";
import { anyProviderConfigured, generateNarrative } from "./aiProvider.ts";

const METNORWAY_BASE = "https://api.met.no/weatherapi/locationforecast/2.0/complete";
const NOWCAST_BASE = "https://api.met.no/weatherapi/nowcast/2.0/complete";
const BRIGHTSKY_BASE = "https://api.brightsky.dev/weather";
// CRITICAL — Nominatim Usage Policy: max 1 request/second per IP. All traffic
// from this backend shares a single outbound IP, so every /search call counts
// toward that shared quota. Search results are cached in Deno KV (see
// handleSearch). Do NOT remove caching or send concurrent Nominatim requests.
// Policy: https://operations.osmfoundation.org/policies/nominatim/
const NOMINATIM_GEO = "https://nominatim.openstreetmap.org/search";
const METAR_BASE = "https://aviationweather.gov/api/data/metar";

// deno-lint-ignore no-explicit-any
type Json = any;

interface ForecastModel {
  latitude: number;
  longitude: number;
  timezone: string | null;
  current: Json;
  hourly: Json;
  daily: Json;
}

// A model is only useful if it carries a real temperature signal. Upstream
// providers occasionally return a timeseries with null `air_temperature` /
// `temperature` (missing station data, partial coverage). Blending such a model
// silently renders as 0° everywhere with a misleading "100% agreement", so we
// backfill the current slot from the nearest finite hourly reading and drop the
// model outright when no hourly temperature is finite.
function ensureCurrentTemperature(model: ForecastModel | null): ForecastModel | null {
  if (!model || !model.current) return null;
  const cur = model.current;
  if (!Number.isFinite(cur.temperature_2m)) {
    const fallback = (model.hourly?.temperature_2m ?? []).find((t: Json) => Number.isFinite(t));
    if (fallback == null) return null;
    cur.temperature_2m = fallback;
  }
  return model;
}

function timezoneForCoord(lat: number, lon: number): string | null {
  try {
    return tzlookup(lat, lon);
  } catch {
    return null;
  }
}

// Current UTC offset (seconds) for an IANA timezone, DST-aware. Computes the
// difference between wall-clock time in `tz` and UTC for the current instant.
function utcOffsetSeconds(tz: string | null): number | null {
  if (!tz) return null;
  try {
    const now = new Date();
    // Drop milliseconds so the difference below is a whole number of seconds
    // (formatToParts truncates the wall clock to whole seconds).
    now.setMilliseconds(0);
    const dtf = new Intl.DateTimeFormat("en-US", {
      timeZone: tz,
      hour12: false,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
    const parts: Record<string, number> = {};
    for (const p of dtf.formatToParts(now)) {
      if (p.type !== "literal") parts[p.type] = parseInt(p.value, 10);
    }
    // Intl can emit hour "24" at midnight; normalise to 0.
    const hour = parts.hour === 24 ? 0 : parts.hour;
    const asUTC = Date.UTC(
      parts.year,
      parts.month - 1,
      parts.day,
      hour,
      parts.minute,
      parts.second,
    );
    return Math.round((asUTC - now.getTime()) / 1000);
  } catch {
    return null;
  }
}

// --- METAR ------------------------------------------------------------------

async function nearestICAO(lat: number, lon: number): Promise<string | null> {
  const delta = 2.0;
  // Query the METAR endpoint by bbox instead of the airport endpoint: the
  // airport endpoint returns HTTP 204 (empty) for bbox queries, and the METAR
  // endpoint also guarantees the station is actively publishing observations.
  // aviationweather.gov expects bbox as minLat,minLon,maxLat,maxLon (lat first).
  const url = `${METAR_BASE}?bbox=${lat - delta},${lon - delta},${lat + delta},${
    lon + delta
  }&format=json&taf=false`;
  console.warn(`nearestICAO: querying ${url}`);
  try {
    const res = await fetch(url, {
      signal: AbortSignal.timeout(4000),
      headers: { "User-Agent": USER_AGENT },
    });
    if (!res.ok) {
      console.warn(`nearestICAO station query failed: HTTP ${res.status} for ${url}`);
      return null;
    }
    const stations = await res.json();
    if (!Array.isArray(stations) || stations.length === 0) {
      console.warn(`nearestICAO: no reporting stations in bbox for lat=${lat} lon=${lon}`);
      return null;
    }
    let best: Json = null;
    let bestDist = Infinity;
    for (const st of stations) {
      const d = Math.hypot(
        parseFloat(st.lat ?? st.latitude ?? 0) - lat,
        parseFloat(st.lon ?? st.longitude ?? 0) - lon,
      );
      if (d < bestDist) {
        bestDist = d;
        best = st;
      }
    }
    const icao = best ? (best.icaoId || best.stationIdentifier || best.id || null) : null;
    if (!icao) {
      console.warn(`nearestICAO: nearest station had no ICAO id (${JSON.stringify(best)})`);
    } else {
      console.warn(
        `nearestICAO: selected ${icao} at lat=${best.lat} lon=${best.lon} (dist=${
          bestDist.toFixed(3)
        }) from ${stations.length} stations`,
      );
    }
    return icao;
  } catch (err) {
    console.warn("nearestICAO failed:", err);
    return null;
  }
}

async function fetchMETAR(icao: string | null): Promise<Json> {
  if (!icao) return null;
  try {
    const res = await fetch(
      `${METAR_BASE}?ids=${icao}&format=json&taf=false`,
      { signal: AbortSignal.timeout(4000), headers: { "User-Agent": USER_AGENT } },
    );
    if (!res.ok) {
      console.warn(`fetchMETAR failed: HTTP ${res.status} for ICAO ${icao}`);
      return null;
    }
    const data = await res.json();
    if (!Array.isArray(data) || data.length === 0) {
      console.warn(`fetchMETAR: empty METAR response for ICAO ${icao}`);
      return null;
    }
    return data[0];
  } catch (err) {
    console.warn("fetchMETAR failed:", err);
    return null;
  }
}

async function fetchMETARForCoord(
  lat: number,
  lon: number,
): Promise<{ icao: string | null; metar: Json }> {
  const icao = await nearestICAO(lat, lon);
  if (!icao) return { icao: null, metar: null };
  const metar = await fetchMETAR(icao);
  return { icao, metar };
}

// --- MET Norway (ECMWF/GFS) -------------------------------------------------

async function fetchMETNorway(lat: number, lon: number): Promise<ForecastModel | null> {
  const url = `${METNORWAY_BASE}?lat=${lat}&lon=${lon}`;
  const res = await fetch(url, {
    signal: AbortSignal.timeout(12000),
    headers: { "User-Agent": USER_AGENT },
  });
  if (!res.ok) throw new Error(`MetNorway ${res.status}`);
  const data = await res.json();

  const hourly: Json = {
    time: [],
    temperature_2m: [],
    apparent_temperature: [],
    relative_humidity_2m: [],
    precipitation_probability: [],
    wind_speed_10m: [],
    wind_direction_10m: [],
    wind_gusts_10m: [],
    uv_index: [],
    weather_code: [],
    dew_point_2m: [],
    visibility: [],
  };

  let current: Json = null;
  const now = new Date();
  const dailyMap: Json = {};

  if (!data.properties || !data.properties.timeseries) return null;

  for (const w of data.properties.timeseries) {
    const time = w.time;
    const tDate = new Date(time);
    const d = w.data.instant.details;

    let precip_prob = 0;
    let weather_symbol = "";
    let precip_amount = 0;

    const next1 = w.data.next_1_hours;
    const next6 = w.data.next_6_hours;

    if (next1) {
      precip_prob = next1.details?.probability_of_precipitation ?? 0;
      weather_symbol = next1.summary?.symbol_code ?? "";
      precip_amount = next1.details?.precipitation_amount ?? 0;
    } else if (next6) {
      precip_prob = next6.details?.probability_of_precipitation ?? 0;
      weather_symbol = next6.summary?.symbol_code ?? "";
      precip_amount = next6.details?.precipitation_amount ?? 0;
    }

    const weather_code = mapMetNoWMO(weather_symbol);
    const wind_speed = (d.wind_speed || 0) * 3.6;
    const wind_gusts = (d.wind_speed_of_gust ?? d.wind_speed ?? 0) * 3.6;
    const uv = d.ultraviolet_index_clear_sky ?? 0;
    const humidity = d.relative_humidity ?? 60;
    const dew_point = d.dew_point_temperature ?? d.air_temperature;
    const visibility = d.visibility ?? 10000;
    const wind_dir = d.wind_from_direction != null ? Math.round(d.wind_from_direction) : null;

    if (
      !current ||
      Math.abs(tDate.getTime() - now.getTime()) <
        Math.abs(new Date(current.time).getTime() - now.getTime())
    ) {
      current = {
        time,
        temperature_2m: d.air_temperature,
        apparent_temperature: apparentTemp(d.air_temperature, humidity, wind_speed),
        relative_humidity_2m: humidity,
        surface_pressure: d.air_pressure_at_sea_level,
        pressure_msl: d.air_pressure_at_sea_level,
        wind_speed_10m: wind_speed,
        wind_direction_10m: wind_dir,
        wind_gusts_10m: wind_gusts,
        uv_index: uv,
        dew_point_2m: dew_point,
        visibility: visibility,
        precipitation_probability: precip_prob,
        weather_code: weather_code,
      };
    }

    hourly.time.push(time);
    hourly.temperature_2m.push(d.air_temperature);
    hourly.apparent_temperature.push(apparentTemp(d.air_temperature, humidity, wind_speed));
    hourly.relative_humidity_2m.push(humidity);
    hourly.precipitation_probability.push(precip_prob);
    hourly.wind_speed_10m.push(wind_speed);
    hourly.wind_direction_10m.push(wind_dir);
    hourly.wind_gusts_10m.push(wind_gusts);
    hourly.uv_index.push(uv);
    hourly.weather_code.push(weather_code);
    hourly.dew_point_2m.push(dew_point);
    hourly.visibility.push(visibility);

    const dayKey = time.split("T")[0];
    if (!dailyMap[dayKey]) {
      dailyMap[dayKey] = {
        minT: d.air_temperature,
        maxT: d.air_temperature,
        maxPrecipProb: precip_prob,
        codes: [weather_code],
        maxUV: uv,
        maxWind: wind_speed,
        maxGust: wind_gusts,
        windDirs: wind_dir != null ? [wind_dir] : [],
        precipSum: precip_amount,
      };
    } else {
      if (d.air_temperature < dailyMap[dayKey].minT) dailyMap[dayKey].minT = d.air_temperature;
      if (d.air_temperature > dailyMap[dayKey].maxT) dailyMap[dayKey].maxT = d.air_temperature;
      if (precip_prob > dailyMap[dayKey].maxPrecipProb) {
        dailyMap[dayKey].maxPrecipProb = precip_prob;
      }
      dailyMap[dayKey].codes.push(weather_code);
      if (uv > dailyMap[dayKey].maxUV) dailyMap[dayKey].maxUV = uv;
      if (wind_speed > dailyMap[dayKey].maxWind) dailyMap[dayKey].maxWind = wind_speed;
      if (wind_gusts > dailyMap[dayKey].maxGust) dailyMap[dayKey].maxGust = wind_gusts;
      if (wind_dir != null) dailyMap[dayKey].windDirs.push(wind_dir);
      dailyMap[dayKey].precipSum += precip_amount;
    }
  }

  const daily = buildDaily(dailyMap, true, lat, lon);

  if (!current) return null;
  return ensureCurrentTemperature({
    latitude: lat,
    longitude: lon,
    timezone: timezoneForCoord(lat, lon),
    current,
    hourly,
    daily,
  });
}

// --- Bright Sky (ICON) ------------------------------------------------------

async function fetchBrightSky(lat: number, lon: number): Promise<ForecastModel | null> {
  const today = new Date();
  const start = today.toISOString().split("T")[0];
  const endDay = new Date(today.getTime() + 7 * 24 * 60 * 60 * 1000);
  const end = endDay.toISOString().split("T")[0];

  const url = `${BRIGHTSKY_BASE}?lat=${lat}&lon=${lon}&date=${start}&last_date=${end}`;
  const res = await fetch(url, {
    signal: AbortSignal.timeout(12000),
    headers: { "User-Agent": USER_AGENT },
  });
  if (!res.ok) throw new Error(`BrightSky ${res.status}`);
  const data = await res.json();

  if (!data.weather || data.weather.length === 0) throw new Error("No data");

  const hourly: Json = {
    time: [],
    temperature_2m: [],
    apparent_temperature: [],
    relative_humidity_2m: [],
    precipitation_probability: [],
    wind_speed_10m: [],
    wind_direction_10m: [],
    wind_gusts_10m: [],
    uv_index: [],
    weather_code: [],
    dew_point_2m: [],
    visibility: [],
  };
  const dailyMap: Json = {};

  let current: Json = null;
  const now = new Date();

  for (const w of data.weather) {
    const time = w.timestamp;
    const tDate = new Date(time);

    const weather_code = mapBrightSkyWMO(w.condition);
    const precip_prob = w.precipitation_probability ?? 0;
    const precip_amount = w.precipitation ?? 0;
    const humidity = w.relative_humidity ?? 60;
    const wind_speed = w.wind_speed ?? 0;
    const wind_gusts = w.wind_gust_speed ?? wind_speed;
    const wind_dir = w.wind_direction != null ? Math.round(w.wind_direction) : null;
    const dew_point = w.dew_point ?? null;
    const visibility = w.visibility ?? null;

    if (
      !current ||
      Math.abs(tDate.getTime() - now.getTime()) <
        Math.abs(new Date(current.time).getTime() - now.getTime())
    ) {
      current = {
        time,
        temperature_2m: w.temperature,
        apparent_temperature: apparentTemp(w.temperature, humidity, wind_speed),
        relative_humidity_2m: humidity,
        surface_pressure: w.pressure_msl,
        pressure_msl: w.pressure_msl,
        wind_speed_10m: wind_speed,
        wind_direction_10m: wind_dir,
        wind_gusts_10m: wind_gusts,
        uv_index: 0,
        dew_point_2m: dew_point,
        visibility: visibility,
        precipitation_probability: precip_prob,
        weather_code: weather_code,
      };
    }

    hourly.time.push(time);
    hourly.temperature_2m.push(w.temperature);
    hourly.apparent_temperature.push(apparentTemp(w.temperature, humidity, wind_speed));
    hourly.relative_humidity_2m.push(humidity);
    hourly.precipitation_probability.push(precip_prob);
    hourly.wind_speed_10m.push(wind_speed);
    hourly.wind_direction_10m.push(wind_dir);
    hourly.wind_gusts_10m.push(wind_gusts);
    hourly.uv_index.push(0);
    hourly.weather_code.push(weather_code);
    hourly.dew_point_2m.push(dew_point);
    hourly.visibility.push(visibility);

    const dayKey = time.split("T")[0];
    if (!dailyMap[dayKey]) {
      dailyMap[dayKey] = {
        minT: w.temperature,
        maxT: w.temperature,
        maxPrecipProb: precip_prob,
        codes: [weather_code],
        maxUV: 0,
        maxWind: wind_speed,
        maxGust: wind_gusts,
        windDirs: wind_dir != null ? [wind_dir] : [],
        precipSum: precip_amount,
      };
    } else {
      if (w.temperature < dailyMap[dayKey].minT) dailyMap[dayKey].minT = w.temperature;
      if (w.temperature > dailyMap[dayKey].maxT) dailyMap[dayKey].maxT = w.temperature;
      if (precip_prob > dailyMap[dayKey].maxPrecipProb) {
        dailyMap[dayKey].maxPrecipProb = precip_prob;
      }
      dailyMap[dayKey].codes.push(weather_code);
      if (wind_speed > dailyMap[dayKey].maxWind) dailyMap[dayKey].maxWind = wind_speed;
      if (wind_gusts > dailyMap[dayKey].maxGust) dailyMap[dayKey].maxGust = wind_gusts;
      if (wind_dir != null) dailyMap[dayKey].windDirs.push(wind_dir);
      dailyMap[dayKey].precipSum += precip_amount;
    }
  }

  const daily = buildDaily(dailyMap, false, lat, lon);
  return ensureCurrentTemperature({
    latitude: lat,
    longitude: lon,
    timezone: timezoneForCoord(lat, lon),
    current,
    hourly,
    daily,
  });
}

// Shared daily-aggregate builder. `withUV` controls whether UV maxima come from
// the source (MET Norway) or are forced to 0 (Bright Sky has no UV).
function buildDaily(dailyMap: Json, withUV: boolean, lat: number, lon: number): Json {
  const daily: Json = {
    time: [],
    temperature_2m_max: [],
    temperature_2m_min: [],
    apparent_temperature_max: [],
    apparent_temperature_min: [],
    precipitation_probability_max: [],
    precipitation_sum: [],
    weather_code: [],
    sunrise: [],
    sunset: [],
    uv_index_max: [],
    wind_speed_10m_max: [],
    wind_direction_10m_dominant: [],
    wind_gusts_10m_max: [],
  };

  for (const day of Object.keys(dailyMap)) {
    const dm = dailyMap[day];
    daily.time.push(day);
    daily.temperature_2m_max.push(dm.maxT);
    daily.temperature_2m_min.push(dm.minT);
    daily.apparent_temperature_max.push(apparentTemp(dm.maxT, 60, dm.maxWind));
    daily.apparent_temperature_min.push(apparentTemp(dm.minT, 70, dm.maxWind));
    daily.precipitation_probability_max.push(dm.maxPrecipProb);
    daily.precipitation_sum.push(Math.round(dm.precipSum * 10) / 10);
    daily.uv_index_max.push(withUV ? dm.maxUV : 0);
    daily.wind_speed_10m_max.push(dm.maxWind);
    daily.wind_direction_10m_dominant.push(circularMeanDir(dm.windDirs));
    daily.wind_gusts_10m_max.push(dm.maxGust);

    const codes = dm.codes;
    const counts: Record<number, number> = {};
    let maxCode = codes[0];
    let maxCount = 0;
    for (const c of codes) {
      counts[c] = (counts[c] || 0) + 1;
      if (counts[c] > maxCount) {
        maxCount = counts[c];
        maxCode = c;
      }
    }
    daily.weather_code.push(maxCode);
    const ss = sunriseSunsetISO(day, lat, lon);
    daily.sunrise.push(ss.sunrise);
    daily.sunset.push(ss.sunset);
  }
  return daily;
}

// aviationweather.gov's METAR JSON fields are usually numeric but can carry
// non-numeric strings (e.g. wdir: "VRB" for variable wind) — coerce to a
// finite number or null so downstream Double? decoding never throws.
function metarNum(v: Json): number | null {
  if (v == null) return null;
  const n = typeof v === "number" ? v : parseFloat(v);
  return Number.isFinite(n) ? n : null;
}

// `reportTime` decodes into a Swift `String?`. aviationweather.gov usually
// supplies it as a string, but the `obsTime` fallback is a Unix epoch
// *integer* — forwarding that number as-is would hit the same
// type-mismatch decode failure as the unsanitized "VRB" wdir bug. Always
// emit a string (or null).
function metarTimeISO(reportTime: Json, obsTime: Json): string | null {
  if (typeof reportTime === "string" && reportTime) return reportTime;
  if (typeof obsTime === "number" && Number.isFinite(obsTime)) {
    try {
      return new Date(obsTime * 1000).toISOString();
    } catch {
      return null;
    }
  }
  if (typeof obsTime === "string" && obsTime) return obsTime;
  return null;
}

function overlayMETAR(forecast: ForecastModel, metar: Json): ForecastModel {
  if (!metar || !forecast?.current) return forecast;
  const c = forecast.current;
  if (metar.temp != null) c.temperature_2m = parseFloat(metar.temp);
  if (metar.dewp != null) {
    const T = c.temperature_2m;
    const Td = parseFloat(metar.dewp);
    c.dew_point_2m = Td;
    const magnus = (t: number) => Math.exp((17.625 * t) / (243.04 + t));
    c.relative_humidity_2m = Math.min(
      100,
      Math.max(0, Math.round(100 * (magnus(Td) / magnus(T)))),
    );
  }
  const hpa = metarAltimToHPa(metar.altim, metar.rawOb);
  if (hpa) {
    c.surface_pressure = hpa;
    c.pressure_msl = hpa;
  }
  const wspd = ktsToKmh(metar.wspd);
  if (wspd != null) c.wind_speed_10m = wspd;
  if (metar.wdir != null) c.wind_direction_10m = Math.round(parseFloat(metar.wdir));
  const wgst = ktsToKmh(metar.wgst);
  if (wgst != null) c.wind_gusts_10m = wgst;
  const vis = smToMetres(metar.visib);
  if (vis != null) c.visibility = vis;
  const wmo = metarWMO(metar.wxString, metar.skyCondition || metar.sky_condition || metar.clouds);
  if (wmo > 0) c.weather_code = wmo;
  return forecast;
}

// --- Handlers ---------------------------------------------------------------

async function buildForecast(latR: number, lonR: number): Promise<Json> {
  const [ecmwf, brightsky, metarFetch] = await Promise.allSettled([
    fetchMETNorway(latR, lonR),
    fetchBrightSky(latR, lonR),
    fetchMETARForCoord(latR, lonR),
  ]);

  if (ecmwf.status === "rejected") console.warn("MET Norway fetch rejected:", ecmwf.reason);
  if (brightsky.status === "rejected") console.warn("Bright Sky fetch rejected:", brightsky.reason);
  if (metarFetch.status === "rejected") console.warn("METAR fetch rejected:", metarFetch.reason);

  const models: Json = {};
  if (ecmwf.status === "fulfilled" && ecmwf.value) models.ecmwf_ifs025 = ecmwf.value;
  if (brightsky.status === "fulfilled" && brightsky.value) models.icon_global = brightsky.value;

  if (Object.keys(models).length === 0) throw new Error("all models failed");

  const mr = metarFetch.status === "fulfilled" ? metarFetch.value : { icao: null, metar: null };
  const metar = mr.metar;
  const icaoId = mr.icao;

  for (const key of Object.keys(models)) models[key] = overlayMETAR(models[key], metar);

  const skyCoverLayers = (metar?.skyCondition || metar?.sky_condition || metar?.clouds || [])
    .map((layer: Json) => ({
      skyCover: layer.skyCover ?? layer.cover ?? null,
      // cloudBase decodes into a Swift `Int?` client-side — coerce the same way
      // as the other numeric METAR fields so a non-numeric value here can't
      // throw and fail the whole envelope decode (same failure mode as wdir).
      cloudBase: (() => {
        const n = metarNum(layer.cloudBase ?? layer.base ?? null);
        return n != null ? Math.round(n) : null;
      })(),
    }));

  const visibRaw = metar?.visib ?? null;
  const visibNum = visibRaw != null ? parseFloat(visibRaw) : null;

  const timezone = timezoneForCoord(latR, lonR);

  return {
    models,
    timezone,
    utc_offset_seconds: utcOffsetSeconds(timezone),
    metar_station: icaoId,
    metar_raw: metar
      ? {
        temp: metarNum(metar.temp),
        dewp: metarNum(metar.dewp),
        wspd: metarNum(metar.wspd),
        wgst: metarNum(metar.wgst),
        // wdir is "VRB" (string) from aviationweather.gov when wind is
        // variable — must be sanitized or the Swift Double? decode throws
        // and the whole envelope decode fails, silently hiding the METAR card.
        wdir: metarNum(metar.wdir),
        altim: metarNum(metar.altim),
        visib: visibNum != null && isNaN(visibNum) ? null : visibNum,
        wxString: metar.wxString ?? null,
        skyCondition: skyCoverLayers,
        rawOb: metar.rawOb ?? null,
        reportTime: metarTimeISO(metar.reportTime, metar.obsTime),
      }
      : null,
    generated_at: new Date().toISOString(),
  };
}

export async function handleForecast(url: URL): Promise<Response> {
  const lat = parseFloat(url.searchParams.get("lat") || "");
  const lon = parseFloat(url.searchParams.get("lon") || "");
  if (isNaN(lat) || isNaN(lon)) return jsonResponse({ error: "lat ve lon gerekli" }, 400);
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
    return jsonResponse({ error: "lat/lon aralık dışı" }, 400);
  }
  if (Math.abs(lat) < 1e-6 && Math.abs(lon) < 1e-6) {
    return jsonResponse({ error: "0,0 (null island) geçerli bir konum değil" }, 400);
  }

  // Snap to the cache grid (~0.1 deg) so neighbouring requests share an entry.
  const latR = snapGrid(lat);
  const lonR = snapGrid(lon);
  const key: Deno.KvKey = ["forecast", "v4", latR, lonR];

  try {
    const { value, cached } = await withSWR(
      key,
      SOFT_TTL.forecast,
      TTL.forecast,
      () => buildForecast(latR, lonR),
    );
    return jsonResponseWithCache(value, cached);
  } catch (err) {
    console.error("handleForecast failed:", err);
    return jsonResponse({ error: "tüm modeller başarısız" }, 503);
  }
}

export async function handleNarrative(url: URL): Promise<Response> {
  const lang = normalizeLang(url.searchParams.get("lang"));
  const code = parseInt(url.searchParams.get("weather_code") || "0", 10);
  const temp = parseFloat(url.searchParams.get("temp") || "20");
  const uv = parseFloat(url.searchParams.get("uv") || "0");
  const tempBucket = Math.round(temp / 5) * 5;
  const uvBucket = Math.round(uv / 2) * 2;
  const key: Deno.KvKey = ["narrative", lang, code, tempBucket, uvBucket];

  const cached = await cacheGet<{ narrative: string; lang: string }>(key);
  if (cached) return jsonResponse({ ...cached, cached: true });

  const fallback = lang === "tr" ? "Hava durumu yükleniyor..." : "Loading weather summary...";
  // PRIVACY: only abstracted numeric weather values are sent to the AI provider.
  const weatherSummary = buildWeatherSummary(url.searchParams, lang);
  let narrative = fallback;

  if (anyProviderConfigured()) {
    try {
      const text = await generateNarrative(narrativeSystemPrompt(lang), weatherSummary);
      if (text) narrative = text;
    } catch (err) {
      console.error("AI narrative generation failed:", err);
      narrative = fallback;
    }
  }

  const result = { narrative, cached: false, lang };
  if (narrative !== fallback) await cachePut(key, { narrative, lang }, TTL.narrative);
  return jsonResponse(result);
}

async function buildNowcast(latR: number, lonR: number): Promise<Json> {
  const res = await fetch(`${NOWCAST_BASE}?lat=${latR}&lon=${lonR}`, {
    signal: AbortSignal.timeout(10000),
    headers: { "User-Agent": USER_AGENT },
  });

  // MET Norway returns 422 when the coordinate is outside radar coverage.
  if (res.status === 422) {
    const tz = timezoneForCoord(latR, lonR);
    return {
      radarCoverage: false,
      minutecast: [],
      timezone: tz,
      utc_offset_seconds: utcOffsetSeconds(tz),
    };
  }
  if (!res.ok) throw new Error(`MET Nowcast ${res.status}`);

  const data = await res.json();
  if (!data.properties?.timeseries?.length) {
    const tz = timezoneForCoord(latR, lonR);
    return {
      radarCoverage: false,
      minutecast: [],
      timezone: tz,
      utc_offset_seconds: utcOffsetSeconds(tz),
    };
  }

  const minutecast = data.properties.timeseries.map((entry: Json) => {
    const d = entry.data?.instant?.details || {};
    const next = entry.data?.next_1_hours?.details || {};
    return {
      time: entry.time,
      precipitationRate: d.precipitation_rate ?? 0,
      precipitationAmount: next.precipitation_amount ?? 0,
      temperature: d.air_temperature ?? null,
      humidity: d.relative_humidity ?? null,
      windSpeed: (d.wind_speed ?? 0) * 3.6,
      windDirection: d.wind_from_direction ?? 0,
      windGust: (d.wind_speed_of_gust ?? d.wind_speed ?? 0) * 3.6,
      symbolCode: entry.data?.next_1_hours?.summary?.symbol_code ?? "",
    };
  });

  const timezone = timezoneForCoord(latR, lonR);

  return {
    minutecast,
    radarCoverage: true,
    timezone,
    utc_offset_seconds: utcOffsetSeconds(timezone),
    geometry: data.geometry ?? null,
    generated_at: new Date().toISOString(),
  };
}

export async function handleNowcast(url: URL): Promise<Response> {
  const lat = parseFloat(url.searchParams.get("lat") || "");
  const lon = parseFloat(url.searchParams.get("lon") || "");
  if (isNaN(lat) || isNaN(lon)) return jsonResponse({ error: "lat ve lon gerekli" }, 400);
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
    return jsonResponse({ error: "lat/lon aralık dışı" }, 400);
  }
  if (Math.abs(lat) < 1e-6 && Math.abs(lon) < 1e-6) {
    return jsonResponse({ error: "0,0 (null island) geçerli bir konum değil" }, 400);
  }

  const latR = snapGrid(lat);
  const lonR = snapGrid(lon);
  const key: Deno.KvKey = ["nowcast", latR, lonR];

  try {
    const { value, cached } = await withSWR(
      key,
      SOFT_TTL.nowcast,
      TTL.nowcast,
      () => buildNowcast(latR, lonR),
    );
    return jsonResponseWithCache(value, cached);
  } catch (err) {
    console.warn("handleNowcast failed:", err);
    return jsonResponse(
      { error: "nowcast unavailable", radarCoverage: false, minutecast: [] },
      503,
    );
  }
}

// --- Alerts (NWS + MeteoAlarm + GDACS) --------------------------------------
//
// Combined, coordinate-bearing official weather/disaster alert feed. This is
// deliberately a SINGLE global cache entry (see handleAlerts) rather than a
// per-coordinate one: every client shares the same upstream fetch, so the
// request volume against NWS/MeteoAlarm/GDACS stays constant regardless of
// how many devices are polling the backend.
//
// Only alerts a coordinate could be extracted for are returned — anything
// without a resolvable lat/lon is dropped so the client never has to fall
// back to Nominatim (which would blow the 1 req/sec quota, see handleSearch).

const NWS_ALERTS_URL = "https://api.weather.gov/alerts/active";
const GDACS_RSS_URL = "https://www.gdacs.org/xml/rss.xml";
// Aggregated pan-European CAP feed (all countries in one document).
const METEOALARM_ATOM_URL = "https://feeds.meteoalarm.org/feeds/meteoalarm-legacy-atom-europe";

type AlertSource = "NWS" | "MeteoAlarm" | "GDACS";

interface NormalizedAlert {
  id: string;
  title: string;
  severity: string; // "extreme" | "severe" | "moderate" | "minor" | "unknown"
  area: string;
  country: string | null;
  latitude: number;
  longitude: number;
  source: AlertSource;
  onset: string | null;
  expires: string | null;
}

function normalizeSeverity(raw: string | null | undefined, source: AlertSource): string {
  const s = (raw || "").toLowerCase();
  if (source === "GDACS") {
    // GDACS uses a traffic-light alert level rather than CAP severity words.
    if (s === "red") return "extreme";
    if (s === "orange") return "severe";
    if (s === "green") return "minor";
    return "unknown";
  }
  if (s === "extreme" || s === "severe" || s === "moderate" || s === "minor") return s;
  return "unknown";
}

function polygonCentroid(ring: Json): { lat: number; lon: number } | null {
  if (!Array.isArray(ring) || ring.length === 0) return null;
  let sumLat = 0, sumLon = 0, n = 0;
  for (const pt of ring) {
    if (!Array.isArray(pt) || pt.length < 2) continue;
    const lon = pt[0], lat = pt[1]; // GeoJSON order is [lon, lat]
    if (!Number.isFinite(lon) || !Number.isFinite(lat)) continue;
    sumLon += lon;
    sumLat += lat;
    n++;
  }
  if (n === 0) return null;
  return { lat: sumLat / n, lon: sumLon / n };
}

// Extracts a representative point from a GeoJSON geometry. NWS alerts carry
// Point/Polygon/MultiPolygon geometries directly; county-wide alerts often
// have `geometry: null`, which we treat as "no coordinates" per the filtering
// rule rather than resolving it via an extra per-zone lookup request.
function geometryCentroid(geometry: Json): { lat: number; lon: number } | null {
  if (!geometry || !geometry.type) return null;
  try {
    if (geometry.type === "Point") {
      const [lon, lat] = geometry.coordinates ?? [];
      if (!Number.isFinite(lon) || !Number.isFinite(lat)) return null;
      return { lat, lon };
    }
    if (geometry.type === "Polygon") {
      return polygonCentroid(geometry.coordinates?.[0]);
    }
    if (geometry.type === "MultiPolygon") {
      return polygonCentroid(geometry.coordinates?.[0]?.[0]);
    }
  } catch (err) {
    console.warn("geometryCentroid failed:", err);
    return null;
  }
  return null;
}

async function fetchNWSAlerts(): Promise<NormalizedAlert[]> {
  const res = await fetch(NWS_ALERTS_URL, {
    signal: AbortSignal.timeout(10000),
    headers: { "User-Agent": USER_AGENT, "Accept": "application/geo+json" },
  });
  if (!res.ok) throw new Error(`NWS ${res.status}`);
  const data = await res.json();

  const out: NormalizedAlert[] = [];
  for (const feature of data.features ?? []) {
    try {
      const p = feature.properties ?? {};
      const center = geometryCentroid(feature.geometry);
      if (!center) continue; // KRİTİK: koordinatsız uyarı -> at
      out.push({
        id: `nws:${p.id ?? feature.id ?? crypto.randomUUID()}`,
        title: p.headline || p.event || "Weather Alert",
        severity: normalizeSeverity(p.severity, "NWS"),
        area: p.areaDesc || "",
        country: "US",
        latitude: center.lat,
        longitude: center.lon,
        source: "NWS",
        onset: p.onset ?? null,
        expires: p.expires ?? p.ends ?? null,
      });
    } catch (err) {
      console.warn("NWS alert parse failed:", err);
    }
  }
  return out;
}

// Minimal, dependency-free XML tag extractor for the RSS/Atom feeds below —
// Deno Deploy has no DOMParser, and pulling in a full XML parser for two
// well-known, stable feed shapes isn't worth the dependency.
function xmlTag(block: string, tag: string): string | null {
  const escaped = tag.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const re = new RegExp(`<${escaped}[^>]*>([\\s\\S]*?)<\\/${escaped}>`, "i");
  const m = block.match(re);
  if (!m) return null;
  return m[1].replace(/^<!\[CDATA\[/, "").replace(/\]\]>$/, "").trim();
}

async function fetchGDACSAlerts(): Promise<NormalizedAlert[]> {
  const res = await fetch(GDACS_RSS_URL, {
    signal: AbortSignal.timeout(10000),
    headers: { "User-Agent": USER_AGENT },
  });
  if (!res.ok) throw new Error(`GDACS ${res.status}`);
  const xml = await res.text();

  const out: NormalizedAlert[] = [];
  const items = xml.match(/<item>[\s\S]*?<\/item>/g) ?? [];
  for (const item of items) {
    try {
      const title = xmlTag(item, "title");
      if (!title) continue;
      const geoBlock = item.match(/<geo:Point>[\s\S]*?<\/geo:Point>/i)?.[0] ?? item;
      const lat = parseFloat(xmlTag(geoBlock, "geo:lat") ?? "");
      const lon = parseFloat(xmlTag(geoBlock, "geo:long") ?? "");
      if (!Number.isFinite(lat) || !Number.isFinite(lon)) continue; // no coords -> drop
      const guid = xmlTag(item, "guid") || title;
      const country = xmlTag(item, "gdacs:country");
      const pubDate = xmlTag(item, "pubDate");
      let onset: string | null = null;
      if (pubDate) {
        const d = new Date(pubDate);
        onset = isNaN(d.getTime()) ? null : d.toISOString();
      }
      out.push({
        id: `gdacs:${guid}`,
        title,
        severity: normalizeSeverity(xmlTag(item, "gdacs:alertlevel"), "GDACS"),
        area: country || "",
        country,
        latitude: lat,
        longitude: lon,
        source: "GDACS",
        onset,
        expires: null,
      });
    } catch (err) {
      console.warn("GDACS item parse failed:", err);
    }
  }
  return out;
}

// CAP polygon strings are whitespace-separated "lat,lon" pairs.
function centroidFromCapPolygon(s: string): { lat: number; lon: number } | null {
  const pairs = s.trim().split(/\s+/).map((pair) => pair.split(",").map(Number));
  const valid = pairs.filter((p) => p.length === 2 && p.every(Number.isFinite));
  if (valid.length === 0) return null;
  const sumLat = valid.reduce((acc, p) => acc + p[0], 0);
  const sumLon = valid.reduce((acc, p) => acc + p[1], 0);
  return { lat: sumLat / valid.length, lon: sumLon / valid.length };
}

async function fetchMeteoAlarmAlerts(): Promise<NormalizedAlert[]> {
  const res = await fetch(METEOALARM_ATOM_URL, {
    signal: AbortSignal.timeout(10000),
    headers: { "User-Agent": USER_AGENT },
  });
  if (!res.ok) throw new Error(`MeteoAlarm ${res.status}`);
  const xml = await res.text();

  const out: NormalizedAlert[] = [];
  const entries = xml.match(/<entry>[\s\S]*?<\/entry>/g) ?? [];
  for (const entry of entries) {
    try {
      const title = xmlTag(entry, "title");
      if (!title) continue;

      // The legacy Atom feed mostly carries country/region geocodes rather
      // than lat/lon. Only entries that happen to inline a georss:point or
      // cap:polygon resolve to coordinates; everything else is dropped per
      // the coordinates-only rule instead of issuing a follow-up fetch to
      // the full per-alert CAP document (which would multiply upstream
      // requests for a feed that's supposed to cost one fetch per refresh).
      let center: { lat: number; lon: number } | null = null;
      const point = xmlTag(entry, "georss:point");
      if (point) {
        const parts = point.split(/\s+/).map(Number);
        if (parts.length === 2 && parts.every(Number.isFinite)) {
          center = { lat: parts[0], lon: parts[1] };
        }
      }
      if (!center) {
        const polygon = xmlTag(entry, "cap:polygon") || xmlTag(entry, "georss:polygon");
        if (polygon) center = centroidFromCapPolygon(polygon);
      }
      if (!center) continue;

      const id = xmlTag(entry, "id") || title;
      const summary = xmlTag(entry, "summary") || xmlTag(entry, "cap:event") || title;
      out.push({
        id: `meteoalarm:${id}`,
        title: summary,
        severity: normalizeSeverity(xmlTag(entry, "cap:severity"), "MeteoAlarm"),
        area: xmlTag(entry, "cap:areaDesc") || "",
        country: xmlTag(entry, "cap:country"),
        latitude: center.lat,
        longitude: center.lon,
        source: "MeteoAlarm",
        onset: xmlTag(entry, "updated"),
        expires: xmlTag(entry, "cap:expires"),
      });
    } catch (err) {
      console.warn("MeteoAlarm entry parse failed:", err);
    }
  }
  return out;
}

async function buildAlerts(): Promise<Json> {
  const [nws, meteoAlarm, gdacs] = await Promise.allSettled([
    fetchNWSAlerts(),
    fetchMeteoAlarmAlerts(),
    fetchGDACSAlerts(),
  ]);

  const alerts: NormalizedAlert[] = [];
  if (nws.status === "fulfilled") alerts.push(...nws.value);
  else console.warn("NWS alerts fetch failed:", nws.reason);
  if (meteoAlarm.status === "fulfilled") alerts.push(...meteoAlarm.value);
  else console.warn("MeteoAlarm alerts fetch failed:", meteoAlarm.reason);
  if (gdacs.status === "fulfilled") alerts.push(...gdacs.value);
  else console.warn("GDACS alerts fetch failed:", gdacs.reason);

  return { alerts, generated_at: new Date().toISOString() };
}

export async function handleAlerts(_url: URL): Promise<Response> {
  // Single global key — deliberately NOT per-coordinate, so every client
  // shares one cached payload (see file header comment above).
  const key: Deno.KvKey = ["alerts", "v1"];

  try {
    const { value, cached } = await withSWR(
      key,
      SOFT_TTL.alerts,
      TTL.alerts,
      () => buildAlerts(),
    );
    return jsonResponseWithCache(value, cached);
  } catch (err) {
    console.error("handleAlerts failed:", err);
    return jsonResponse({ error: "alerts unavailable", alerts: [] }, 503);
  }
}

export async function handleSearch(url: URL): Promise<Response> {
  const q = (url.searchParams.get("q") || "").slice(0, 200);
  const countRaw = parseInt(url.searchParams.get("count") || "5", 10);
  const count = String(Math.max(1, Math.min(countRaw || 5, 10)));
  const lang = url.searchParams.get("lang") || "tr";
  if (!q) return jsonResponse({ error: "q gerekli" }, 400);

  const key: Deno.KvKey = ["search", lang, count, q];
  const cached = await cacheGet<Json>(key);
  if (cached) return jsonResponse({ ...cached, _cached: true });

  const geoUrl = `${NOMINATIM_GEO}?q=${
    encodeURIComponent(q)
  }&format=json&accept-language=${lang}&limit=${count}`;
  try {
    const res = await fetch(geoUrl, {
      signal: AbortSignal.timeout(8000),
      headers: { "User-Agent": USER_AGENT },
    });
    if (!res.ok) return jsonResponse({ error: "geocoding başarısız" }, 503);
    const data = await res.json();

    const results = data.map((item: Json) => ({
      id: parseInt(item.place_id, 10),
      name: item.name || item.display_name.split(",")[0],
      latitude: parseFloat(item.lat),
      longitude: parseFloat(item.lon),
      country: item.display_name.split(",").pop().trim(),
      admin1: "",
    }));
    const response = { results };
    await cachePut(key, response, TTL.search);
    return jsonResponse(response);
  } catch (e) {
    console.error("handleSearch geocoding failed:", e);
    return jsonResponse({ error: "geocoding başarısız" }, 503);
  }
}
