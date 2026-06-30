// Praeventus Weather Worker v4
// Routes: /forecast (ECMWF + ICON + METAR), /search, /narrative, /nowcast

const METNORWAY_BASE  = "https://api.met.no/weatherapi/locationforecast/2.0/complete";
const NOWCAST_BASE    = "https://api.met.no/weatherapi/nowcast/2.0/complete";
const BRIGHTSKY_BASE  = "https://api.brightsky.dev/weather";
// CRITICAL — Nominatim Usage Policy: max 1 request/second per IP.
// All traffic from this Worker shares a single outbound IP, so every
// /search call counts toward that shared quota.  To stay compliant,
// search results are cached in KV (see handleSearch).  Do NOT remove
// caching or send multiple concurrent Nominatim requests per user action.
// Policy: https://operations.osmfoundation.org/policies/nominatim/
const NOMINATIM_GEO   = "https://nominatim.openstreetmap.org/search";
const METAR_BASE      = "https://aviationweather.gov/api/data/metar";
const AIRPORT_BASE    = "https://aviationweather.gov/api/data/airport";

const USER_AGENT = "Praeventus/1.0 (Contact: mehmetgezoglu@icloud.com)";

function metarWMO(wxString, skyCover) {
  if (!wxString && !skyCover) return 0;
  const wx = (wxString || "").toUpperCase();
  if (wx.includes("TS"))  return 95;
  if (wx.includes("SN") || wx.includes("SG") || wx.includes("IC")) return 71;
  if (wx.includes("FZ"))  return 66;
  if (wx.includes("RA") || wx.includes("DZ")) return 61;
  if (wx.includes("SH"))  return 80;
  if (wx.includes("FG") || wx.includes("BR") || wx.includes("HZ")) return 45;
  const cover = (skyCover || [])
    .map(s => s.skyCover || s.cover || "").join(",").toUpperCase();
  if (cover.includes("OVC")) return 3;
  if (cover.includes("BKN")) return 2;
  if (cover.includes("SCT") || cover.includes("FEW")) return 1;
  return 0;
}

function inHgToHPa(v) { return v ? Math.round(v * 33.8639 * 10) / 10 : null; }
function ktsToKmh(v)  { return v ? Math.round(v * 1.852  * 10) / 10 : null; }
function smToMetres(v){ if (v == null) return null; const n = parseFloat(v); return isNaN(n) ? null : Math.round(n * 1609.34); }

// Canadian Wind Chill Index (T ≤ 10 °C, wind ≥ 5 km/h) and
// NWS Rothfusz Heat Index (T ≥ 27 °C, humidity ≥ 40 %).
// Falls back to actual temperature for the temperate middle range.
function apparentTemp(tempC, humidity, windKmh) {
  if (tempC <= 10 && windKmh >= 5) {
    const v = Math.pow(windKmh, 0.16);
    return Math.round((13.12 + 0.6215 * tempC - 11.37 * v + 0.3965 * tempC * v) * 10) / 10;
  }
  if (tempC >= 27 && humidity >= 40) {
    const T = tempC * 9 / 5 + 32;
    const R = humidity;
    const hi = -42.379 + 2.04901523 * T + 10.14333127 * R
               - 0.22475541 * T * R - 6.83783e-3 * T * T
               - 5.481717e-2 * R * R + 1.22874e-3 * T * T * R
               + 8.5282e-4 * T * R * R - 1.99e-6 * T * T * R * R;
    return Math.round(((hi - 32) * 5 / 9) * 10) / 10;
  }
  return tempC;
}

// Circular (vector) mean of compass bearings — correct across the 0°/360° seam.
function circularMeanDir(dirs) {
  const valid = dirs.filter(d => d != null);
  if (!valid.length) return null;
  const rads = valid.map(d => d * Math.PI / 180);
  const s = rads.reduce((sum, r) => sum + Math.sin(r), 0);
  const c = rads.reduce((sum, r) => sum + Math.cos(r), 0);
  if (s === 0 && c === 0) return valid[0];
  const mean = Math.atan2(s, c) * 180 / Math.PI;
  return Math.round(((mean % 360) + 360) % 360);
}

async function nearestICAO(lat, lon) {
  const delta = 2.0;
  const url = `${AIRPORT_BASE}?bbox=${lon-delta},${lat-delta},${lon+delta},${lat+delta}&format=json`;
  try {
    const res = await fetch(url, {
      signal: AbortSignal.timeout(4000),
      headers: { "User-Agent": USER_AGENT }
    });
    if (!res.ok) return null;
    const airports = await res.json();
    if (!airports?.length) return null;
    let best = null, bestDist = Infinity;
    for (const ap of airports) {
      const d = Math.hypot(
        parseFloat(ap.latitude  || ap.lat || 0) - lat,
        parseFloat(ap.longitude || ap.lon || 0) - lon
      );
      if (d < bestDist) { bestDist = d; best = ap; }
    }
    return best ? (best.icaoId || best.stationIdentifier || best.id || null) : null;
  } catch (err) { console.warn("nearestICAO failed:", err); return null; }
}

async function fetchMETAR(icao) {
  if (!icao) return null;
  try {
    const res = await fetch(
      `${METAR_BASE}?ids=${icao}&format=json&taf=false`,
      { signal: AbortSignal.timeout(4000),
        headers: { "User-Agent": USER_AGENT } }
    );
    if (!res.ok) return null;
    const data = await res.json();
    return Array.isArray(data) && data.length > 0 ? data[0] : null;
  } catch (err) { console.warn("fetchMETAR failed:", err); return null; }
}

async function fetchMETARForCoord(lat, lon) {
  const icao = await nearestICAO(lat, lon);
  if (!icao) return { icao: null, metar: null };
  const metar = await fetchMETAR(icao);
  return { icao, metar };
}

function mapMetNoWMO(symbol) {
  if (!symbol) return 0;
  const s = symbol.split('_')[0];
  const map = {
    clearsky: 0, fair: 1, partlycloudy: 2, cloudy: 3,
    lightrainshowers: 80, rainshowers: 81, heavyrainshowers: 82,
    lightrainshowersandthunder: 95, rainshowersandthunder: 95, heavyrainshowersandthunder: 95,
    sleetshowers: 68, heavysleetshowers: 68, sleetshowersandthunder: 95, heavysleetshowersandthunder: 95,
    snowshowers: 85, heavysnowshowers: 86, snowshowersandthunder: 95, heavysnowshowersandthunder: 95,
    lightrain: 61, rain: 63, heavyrain: 65, lightrainandthunder: 95, rainandthunder: 95, heavyrainandthunder: 95,
    lightsleet: 68, sleet: 68, heavysleet: 68, lightsleetandthunder: 95, sleetandthunder: 95, heavysleetandthunder: 95,
    lightsnow: 71, snow: 73, heavysnow: 75, lightsnowandthunder: 95, snowandthunder: 95, heavysnowandthunder: 95,
    fog: 45
  };
  return map[s] || 0;
}

function mapBrightSkyWMO(condition) {
  const map = {
    dry: 0, fog: 45, rain: 61, sleet: 68, snow: 71, hail: 89, thunderstorm: 95
  };
  return map[condition] || 0;
}

async function fetchMETNorway(lat, lon) {
  const url = `${METNORWAY_BASE}?lat=${lat}&lon=${lon}`;
  const res = await fetch(url, {
    signal: AbortSignal.timeout(12000),
    headers: { "User-Agent": USER_AGENT }
  });
  if (!res.ok) throw new Error(`MetNorway ${res.status}`);
  const data = await res.json();

  const hourly = {
    time: [], temperature_2m: [], apparent_temperature: [], relative_humidity_2m: [],
    precipitation_probability: [], wind_speed_10m: [], wind_direction_10m: [],
    wind_gusts_10m: [], uv_index: [], weather_code: [],
    dew_point_2m: [], visibility: []
  };

  let current = null;
  const now = new Date();
  let dailyMap = {};

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
    const wind_speed  = (d.wind_speed || 0) * 3.6;
    const wind_gusts  = (d.wind_speed_of_gust ?? d.wind_speed ?? 0) * 3.6;
    const uv          = d.ultraviolet_index_clear_sky ?? 0;
    const humidity    = d.relative_humidity ?? 60;
    const dew_point   = d.dew_point_temperature ?? d.air_temperature;
    const visibility  = d.visibility ?? 10000;
    const wind_dir    = d.wind_from_direction != null ? Math.round(d.wind_from_direction) : null;

    if (!current || Math.abs(tDate.getTime() - now.getTime()) < Math.abs(new Date(current.time).getTime() - now.getTime())) {
      current = {
        time,
        temperature_2m:           d.air_temperature,
        apparent_temperature:     apparentTemp(d.air_temperature, humidity, wind_speed),
        relative_humidity_2m:     humidity,
        surface_pressure:         d.air_pressure_at_sea_level,
        pressure_msl:             d.air_pressure_at_sea_level,
        wind_speed_10m:           wind_speed,
        wind_direction_10m:       wind_dir,
        wind_gusts_10m:           wind_gusts,
        uv_index:                 uv,
        dew_point_2m:             dew_point,
        visibility:               visibility,
        precipitation_probability: precip_prob,
        weather_code:             weather_code
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

    const dayKey = time.split('T')[0];
    if (!dailyMap[dayKey]) {
      dailyMap[dayKey] = {
        minT: d.air_temperature, maxT: d.air_temperature,
        maxPrecipProb: precip_prob, codes: [weather_code],
        maxUV: uv, maxWind: wind_speed, maxGust: wind_gusts,
        windDirs: wind_dir != null ? [wind_dir] : [],
        precipSum: precip_amount
      };
    } else {
      if (d.air_temperature < dailyMap[dayKey].minT) dailyMap[dayKey].minT = d.air_temperature;
      if (d.air_temperature > dailyMap[dayKey].maxT) dailyMap[dayKey].maxT = d.air_temperature;
      if (precip_prob > dailyMap[dayKey].maxPrecipProb) dailyMap[dayKey].maxPrecipProb = precip_prob;
      dailyMap[dayKey].codes.push(weather_code);
      if (uv > dailyMap[dayKey].maxUV) dailyMap[dayKey].maxUV = uv;
      if (wind_speed > dailyMap[dayKey].maxWind) dailyMap[dayKey].maxWind = wind_speed;
      if (wind_gusts > dailyMap[dayKey].maxGust) dailyMap[dayKey].maxGust = wind_gusts;
      if (wind_dir != null) dailyMap[dayKey].windDirs.push(wind_dir);
      dailyMap[dayKey].precipSum += precip_amount;
    }
  }

  const daily = {
    time: [], temperature_2m_max: [], temperature_2m_min: [],
    apparent_temperature_max: [], apparent_temperature_min: [],
    precipitation_probability_max: [], precipitation_sum: [],
    weather_code: [], sunrise: [], sunset: [],
    uv_index_max: [], wind_speed_10m_max: [],
    wind_direction_10m_dominant: [], wind_gusts_10m_max: []
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
    daily.uv_index_max.push(dm.maxUV);
    daily.wind_speed_10m_max.push(dm.maxWind);
    daily.wind_direction_10m_dominant.push(circularMeanDir(dm.windDirs));
    daily.wind_gusts_10m_max.push(dm.maxGust);

    const codes = dm.codes;
    const counts = {};
    let maxCode = codes[0]; let maxCount = 0;
    for (const c of codes) {
      counts[c] = (counts[c] || 0) + 1;
      if (counts[c] > maxCount) { maxCount = counts[c]; maxCode = c; }
    }
    daily.weather_code.push(maxCode);
    daily.sunrise.push(null);
    daily.sunset.push(null);
  }

  if (!current) return null;
  return { latitude: lat, longitude: lon, current, hourly, daily };
}

async function fetchBrightSky(lat, lon) {
  const today = new Date();
  const start = today.toISOString().split('T')[0];
  const endDay = new Date(today.getTime() + 7 * 24 * 60 * 60 * 1000);
  const end = endDay.toISOString().split('T')[0];

  const url = `${BRIGHTSKY_BASE}?lat=${lat}&lon=${lon}&date=${start}&last_date=${end}`;
  const res = await fetch(url, {
    signal: AbortSignal.timeout(12000),
    headers: { "User-Agent": USER_AGENT }
  });
  if (!res.ok) throw new Error(`BrightSky ${res.status}`);
  const data = await res.json();

  if (!data.weather || data.weather.length === 0) throw new Error("No data");

  const hourly = {
    time: [], temperature_2m: [], apparent_temperature: [], relative_humidity_2m: [],
    precipitation_probability: [], wind_speed_10m: [], wind_direction_10m: [],
    wind_gusts_10m: [], uv_index: [], weather_code: [],
    dew_point_2m: [], visibility: []
  };
  const dailyMap = {};

  let current = null;
  const now = new Date();

  for (const w of data.weather) {
    const time = w.timestamp;
    const tDate = new Date(time);

    const weather_code   = mapBrightSkyWMO(w.condition);
    const precip_prob    = w.precipitation_probability ?? 0;
    const precip_amount  = w.precipitation ?? 0;
    const humidity       = w.relative_humidity ?? 60;
    const wind_speed     = w.wind_speed ?? 0;
    const wind_gusts     = w.wind_gust_speed ?? wind_speed;
    const wind_dir       = w.wind_direction != null ? Math.round(w.wind_direction) : null;
    const dew_point      = w.dew_point ?? null;
    const visibility     = w.visibility ?? null;

    if (!current || Math.abs(tDate.getTime() - now.getTime()) < Math.abs(new Date(current.time).getTime() - now.getTime())) {
      current = {
        time,
        temperature_2m:            w.temperature,
        apparent_temperature:      apparentTemp(w.temperature, humidity, wind_speed),
        relative_humidity_2m:      humidity,
        surface_pressure:          w.pressure_msl,
        pressure_msl:              w.pressure_msl,
        wind_speed_10m:            wind_speed,
        wind_direction_10m:        wind_dir,
        wind_gusts_10m:            wind_gusts,
        uv_index:                  0,
        dew_point_2m:              dew_point,
        visibility:                visibility,
        precipitation_probability: precip_prob,
        weather_code:              weather_code
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

    const dayKey = time.split('T')[0];
    if (!dailyMap[dayKey]) {
      dailyMap[dayKey] = {
        minT: w.temperature, maxT: w.temperature,
        maxPrecipProb: precip_prob, codes: [weather_code],
        maxWind: wind_speed, maxGust: wind_gusts,
        windDirs: wind_dir != null ? [wind_dir] : [],
        precipSum: precip_amount
      };
    } else {
      if (w.temperature < dailyMap[dayKey].minT) dailyMap[dayKey].minT = w.temperature;
      if (w.temperature > dailyMap[dayKey].maxT) dailyMap[dayKey].maxT = w.temperature;
      if (precip_prob > dailyMap[dayKey].maxPrecipProb) dailyMap[dayKey].maxPrecipProb = precip_prob;
      dailyMap[dayKey].codes.push(weather_code);
      if (wind_speed > dailyMap[dayKey].maxWind) dailyMap[dayKey].maxWind = wind_speed;
      if (wind_gusts > dailyMap[dayKey].maxGust) dailyMap[dayKey].maxGust = wind_gusts;
      if (wind_dir != null) dailyMap[dayKey].windDirs.push(wind_dir);
      dailyMap[dayKey].precipSum += precip_amount;
    }
  }

  const daily = {
    time: [], temperature_2m_max: [], temperature_2m_min: [],
    apparent_temperature_max: [], apparent_temperature_min: [],
    precipitation_probability_max: [], precipitation_sum: [],
    weather_code: [], sunrise: [], sunset: [],
    uv_index_max: [], wind_speed_10m_max: [],
    wind_direction_10m_dominant: [], wind_gusts_10m_max: []
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
    daily.uv_index_max.push(0);
    daily.wind_speed_10m_max.push(dm.maxWind);
    daily.wind_direction_10m_dominant.push(circularMeanDir(dm.windDirs));
    daily.wind_gusts_10m_max.push(dm.maxGust);

    const codes = dm.codes;
    const counts = {};
    let maxCode = codes[0]; let maxCount = 0;
    for (const c of codes) {
      counts[c] = (counts[c] || 0) + 1;
      if (counts[c] > maxCount) { maxCount = counts[c]; maxCode = c; }
    }
    daily.weather_code.push(maxCode);
    daily.sunrise.push(null);
    daily.sunset.push(null);
  }

  return { latitude: lat, longitude: lon, current, hourly, daily };
}

function overlayMETAR(forecast, metar) {
  if (!metar || !forecast?.current) return forecast;
  const c = forecast.current;
  if (metar.temp != null) c.temperature_2m = parseFloat(metar.temp);
  if (metar.dewp != null) {
    const T = c.temperature_2m, Td = parseFloat(metar.dewp);
    c.dew_point_2m = Td;
    const magnus = (t) => Math.exp((17.625 * t) / (243.04 + t));
    c.relative_humidity_2m = Math.min(100, Math.max(0, Math.round(100 * (magnus(Td) / magnus(T)))));
  }
  const hpa = inHgToHPa(metar.altim);
  if (hpa) { c.surface_pressure = hpa; c.pressure_msl = hpa; }
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

async function cacheGet(env, key) {
  try {
    if (!env?.PRAEVENTUS_CACHE) return null;
    const val = await env.PRAEVENTUS_CACHE.get(key);
    return val ? JSON.parse(val) : null;
  } catch (err) { console.warn("cacheGet failed:", key, err); return null; }
}

async function cachePut(env, key, value, ttl) {
  try {
    if (!env?.PRAEVENTUS_CACHE) return;
    await env.PRAEVENTUS_CACHE.put(key, JSON.stringify(value), {
      expirationTtl: ttl
    });
  } catch (err) { console.warn("cachePut failed:", key, err); }
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin":  "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "X-Content-Type-Options": "nosniff",
  };
}

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders() }
  });
}

async function handleForecast(url, env) {
  const lat = parseFloat(url.searchParams.get("lat") || "");
  const lon = parseFloat(url.searchParams.get("lon") || "");
  if (isNaN(lat) || isNaN(lon))
    return jsonResponse({ error: "lat ve lon gerekli" }, 400);
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180)
    return jsonResponse({ error: "lat/lon aralık dışı" }, 400);

  const latR = Math.round(lat * 10000) / 10000;
  const lonR = Math.round(lon * 10000) / 10000;
  const cacheKey = `forecast_v4_${latR}_${lonR}`;

  const cached = await cacheGet(env, cacheKey);
  if (cached) return jsonResponse({ ...cached, _cached: true });

  const [ecmwf, brightsky, metarFetch] = await Promise.allSettled([
    fetchMETNorway(latR, lonR),
    fetchBrightSky(latR, lonR),
    fetchMETARForCoord(latR, lonR),
  ]);

  if (ecmwf.status === "rejected") console.warn("MET Norway fetch rejected:", ecmwf.reason);
  if (brightsky.status === "rejected") console.warn("Bright Sky fetch rejected:", brightsky.reason);
  if (metarFetch.status === "rejected") console.warn("METAR fetch rejected:", metarFetch.reason);

  const models = {};
  if (ecmwf.status === "fulfilled" && ecmwf.value) {
    models.ecmwf_ifs025 = ecmwf.value;
  }
  if (brightsky.status === "fulfilled" && brightsky.value) {
    models.icon_global  = brightsky.value;
  }

  if (Object.keys(models).length === 0)
    return jsonResponse({ error: "tüm modeller başarısız" }, 503);

  const mr     = metarFetch.status === "fulfilled" ? metarFetch.value : { icao: null, metar: null };
  const metar  = mr.metar;
  const icaoId = mr.icao;

  for (const key of Object.keys(models))
    models[key] = overlayMETAR(models[key], metar);

  const skyCoverLayers = (metar?.skyCondition || metar?.sky_condition || metar?.clouds || [])
    .map(layer => ({
      skyCover:  layer.skyCover  ?? layer.cover ?? null,
      cloudBase: layer.cloudBase ?? layer.base  ?? null,
    }));

  const visibRaw = metar?.visib ?? null;
  const visibNum = visibRaw != null ? parseFloat(visibRaw) : null;

  const result = {
    models,
    metar_station: icaoId,
    metar_raw: metar ? {
      temp:         metar.temp,
      dewp:         metar.dewp,
      wspd:         metar.wspd,
      wgst:         metar.wgst ?? null,
      wdir:         metar.wdir,
      altim:        metar.altim,
      visib:        isNaN(visibNum) ? null : visibNum,
      wxString:     metar.wxString ?? null,
      skyCondition: skyCoverLayers,
      rawOb:        metar.rawOb ?? null,
      reportTime:   metar.reportTime ?? metar.obsTime ?? null,
    } : null,
    generated_at: new Date().toISOString(),
  };

  await cachePut(env, cacheKey, result, 2700);
  return jsonResponse(result);
}

const WMO_TR = {
  0: "Açık", 1: "Az bulutlu", 2: "Az bulutlu", 3: "Bulutlu",
  45: "Sisli", 48: "Sisli",
  51: "Çisenti", 53: "Çisenti", 55: "Çisenti",
  61: "Yağmurlu", 63: "Yağmurlu", 65: "Yağmurlu",
  71: "Karlı",   73: "Karlı",   75: "Karlı",
  80: "Sağanak", 81: "Sağanak", 82: "Sağanak",
  95: "Fırtınalı"
};
const WMO_EN = {
  0: "Clear", 1: "Partly cloudy", 2: "Partly cloudy", 3: "Overcast",
  45: "Foggy", 48: "Foggy",
  51: "Drizzle", 53: "Drizzle", 55: "Drizzle",
  61: "Rainy", 63: "Rainy", 65: "Rainy",
  71: "Snowy",  73: "Snowy",  75: "Snowy",
  80: "Showers", 81: "Showers", 82: "Showers",
  95: "Thunderstorm"
};

function wmoCondition(code, lang) {
  return (lang === "tr" ? WMO_TR[code] : WMO_EN[code])
      ?? (lang === "tr" ? "Değişken" : "Variable");
}

function windDirectionLabel(deg, lang) {
  const d = ((deg % 360) + 360) % 360;
  if (d <= 22 || d >= 338) return lang === "tr" ? "Kuzey"      : "North";
  if (d <= 67)              return lang === "tr" ? "Kuzeydoğu"  : "Northeast";
  if (d <= 112)             return lang === "tr" ? "Doğu"       : "East";
  if (d <= 157)             return lang === "tr" ? "Güneydoğu"  : "Southeast";
  if (d <= 202)             return lang === "tr" ? "Güney"      : "South";
  if (d <= 247)             return lang === "tr" ? "Güneybatı"  : "Southwest";
  if (d <= 292)             return lang === "tr" ? "Batı"       : "West";
  return lang === "tr" ? "Kuzeybatı" : "Northwest";
}

function buildWeatherSummary(params, lang) {
  const temp     = parseFloat(params.get("temp")         || "20");
  const feels    = parseFloat(params.get("feels")        || String(temp));
  const humidity = parseFloat(params.get("humidity")     || "60");
  const wind     = parseFloat(params.get("wind")         || "0");
  const windDeg  = parseFloat(params.get("wind_dir")     || "0");
  const code     = parseInt(  params.get("weather_code") || "0", 10);
  const precip   = parseFloat(params.get("precip_prob")  || "0");
  const tempMax  = parseFloat(params.get("temp_max")     || String(temp));
  const tempMin  = parseFloat(params.get("temp_min")     || String(temp));
  const uv       = parseFloat(params.get("uv")           || "0");
  const vis      = parseFloat(params.get("visibility")   || "10");
  const pressure = parseFloat(params.get("pressure")     || "1013");
  const cond     = wmoCondition(code, lang);
  const windDir  = windDirectionLabel(windDeg, lang);

  if (lang === "tr") {
    const uvLabel = uv >= 8 ? "çok yüksek" : uv >= 6 ? "yüksek" : uv >= 3 ? "orta" : "düşük";
    return `Sıcaklık ${temp}°C (hissedilen ${feels}°C), gün boyu ${tempMin}-${tempMax}°C arası.\n` +
           `Nem %${humidity}, rüzgar ${wind} km/s ${windDir} yönünden.\n` +
           `UV indeksi ${uv} (${uvLabel}), görüş mesafesi ${vis} km.\n` +
           `Basınç ${pressure} hPa, yağış ihtimali %${precip}. ${cond}.`;
  } else {
    const uvLabel = uv >= 8 ? "very high" : uv >= 6 ? "high" : uv >= 3 ? "moderate" : "low";
    return `Temperature ${temp}°C (feels like ${feels}°C), daily range ${tempMin}-${tempMax}°C.\n` +
           `Humidity ${humidity}%, wind ${wind} km/h from the ${windDir}.\n` +
           `UV index ${uv} (${uvLabel}), visibility ${vis} km.\n` +
           `Pressure ${pressure} hPa, precipitation probability ${precip}%. ${cond}.`;
  }
}

const ALLOWED_LANGS = new Set(["tr", "en", "de", "fr", "es", "it", "pt", "nl", "ja", "ko", "zh"]);

async function handleNarrative(url, env) {
  const langRaw    = url.searchParams.get("lang") || "tr";
  const lang       = ALLOWED_LANGS.has(langRaw) ? langRaw : "en";
  const code       = parseInt(url.searchParams.get("weather_code") || "0", 10);
  const temp       = parseFloat(url.searchParams.get("temp") || "20");
  const uv         = parseFloat(url.searchParams.get("uv")   || "0");
  const tempBucket = Math.round(temp / 5) * 5;
  const uvBucket   = Math.round(uv / 2) * 2;
  const cacheKey   = `narrative_${lang}_${code}_${tempBucket}_${uvBucket}`;

  const cached = await cacheGet(env, cacheKey);
  if (cached) return jsonResponse({ ...cached, cached: true });

  const systemPrompt = lang === "tr"
    ? `Sen bir meteoroloji uzmanısın. Verilen hava parametrelerini birlikte değerlendirerek 3 kısa Türkçe cümle yaz. Parametreler birbirini nasıl etkiliyor? Örnek: yüksek nem + düşük rüzgar = boğucu his, yüksek UV + düşük nem = kuru ve yakıcı güneş, düşük basınç + artan rüzgar = hava bozulabilir. Sadece meteorolojik yorumu yaz. Düşünme adımlarını yazma. Emoji kullanma. Direkt başla.`
    : `You are a meteorologist. Evaluate all given weather parameters together and write 3 short sentences. How do the parameters interact? Examples: high humidity + low wind = muggy feeling, high UV + low humidity = dry and harsh sun, low pressure + increasing wind = weather may deteriorate. Write only the meteorological interpretation. No thinking steps. No emojis. Start directly.`;

  const weatherSummary = buildWeatherSummary(url.searchParams, lang);

  const fallback = lang === "tr" ? "Hava durumu yükleniyor..." : "Loading weather summary...";
  let narrative = fallback;

  try {
    const aiResp = await env.AI.run("@cf/meta/llama-3.3-70b-instruct-fp8-fast", {
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user",   content: weatherSummary }
      ],
      max_tokens: 400
    });
        const text = (aiResp?.choices?.[0]?.message?.content
               || aiResp?.choices?.[0]?.message?.reasoning_content
               || aiResp?.response
               || "").trim();
    if (text) narrative = text;
  } catch (err) {
    console.error("AI narrative generation failed:", err);
    narrative = fallback;
  }

  const result = { narrative, cached: false, lang };
  if (narrative !== fallback)
    await cachePut(env, cacheKey, { narrative, lang }, 1800);
  return jsonResponse(result);
}

// ---------------------------------------------------------------------------
// FAZ 1 — Nowcast (radar-based minute precipitation, MET Norway)
// Coverage: Norway + surrounding areas. Returns HTTP 200 with
// radarCoverage:false when the coordinate is outside the radar network.
// ---------------------------------------------------------------------------

async function handleNowcast(url, env) {
  const lat = parseFloat(url.searchParams.get("lat") || "");
  const lon = parseFloat(url.searchParams.get("lon") || "");
  if (isNaN(lat) || isNaN(lon))
    return jsonResponse({ error: "lat ve lon gerekli" }, 400);
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180)
    return jsonResponse({ error: "lat/lon aralık dışı" }, 400);

  // 4-decimal precision matches the privacy-truncation done on the Swift side.
  const latR = Math.round(lat * 10000) / 10000;
  const lonR = Math.round(lon * 10000) / 10000;

  // Nowcast updates every ~5 min → short TTL of 300 s.
  const cacheKey = `nowcast_${latR}_${lonR}`;
  const cached = await cacheGet(env, cacheKey);
  if (cached) return jsonResponse({ ...cached, _cached: true });

  try {
    const res = await fetch(
      `${NOWCAST_BASE}?lat=${latR}&lon=${lonR}`,
      {
        signal: AbortSignal.timeout(10000),
        headers: { "User-Agent": USER_AGENT }
      }
    );

    // MET Norway returns 422 when the coordinate is outside radar coverage.
    if (res.status === 422) {
      return jsonResponse({ radarCoverage: false, minutecast: [] }, 200);
    }
    if (!res.ok) throw new Error(`MET Nowcast ${res.status}`);

    const data = await res.json();
    if (!data.properties?.timeseries?.length) {
      return jsonResponse({ radarCoverage: false, minutecast: [] }, 200);
    }

    const minutecast = data.properties.timeseries.map(entry => {
      const d    = entry.data?.instant?.details            || {};
      const next = entry.data?.next_1_hours?.details       || {};
      return {
        time:                entry.time,
        precipitationRate:   d.precipitation_rate          ?? 0,   // mm/h, radar-derived
        precipitationAmount: next.precipitation_amount     ?? 0,   // mm expected in next hour
        temperature:         d.air_temperature             ?? null,
        humidity:            d.relative_humidity           ?? null,
        windSpeed:           (d.wind_speed                 ?? 0) * 3.6, // m/s → km/h
        windDirection:       d.wind_from_direction         ?? 0,
        windGust:            (d.wind_speed_of_gust ?? d.wind_speed ?? 0) * 3.6,
        symbolCode:          entry.data?.next_1_hours?.summary?.symbol_code ?? ""
      };
    });

    const result = {
      minutecast,
      radarCoverage: true,
      geometry:      data.geometry ?? null,
      generated_at:  new Date().toISOString()
    };

    await cachePut(env, cacheKey, result, 300);
    return jsonResponse(result);

  } catch (err) {
    return jsonResponse({ error: "nowcast unavailable", radarCoverage: false, minutecast: [] }, 503);
  }
}

async function handleSearch(url, env) {
  const q    = (url.searchParams.get("q") || "").slice(0, 200);
  const countRaw = parseInt(url.searchParams.get("count") || "5", 10);
  const count = String(Math.max(1, Math.min(countRaw || 5, 10)));
  const lang  = url.searchParams.get("lang") || "tr";
  if (!q) return jsonResponse({ error: "q gerekli" }, 400);

  const cacheKey = `search_${lang}_${count}_${encodeURIComponent(q)}`;
  const cached = await cacheGet(env, cacheKey);
  if (cached) return jsonResponse({ ...cached, _cached: true });

  const geoUrl = `${NOMINATIM_GEO}?q=${encodeURIComponent(q)}&format=json&accept-language=${lang}&limit=${count}`;
  try {
    const res = await fetch(geoUrl, {
      signal: AbortSignal.timeout(8000),
      headers: { "User-Agent": USER_AGENT }
    });
    if (!res.ok) return jsonResponse({ error: "geocoding başarısız" }, 503);
    const data = await res.json();

    const results = data.map(item => {
      return {
        id: parseInt(item.place_id, 10),
        name: item.name || item.display_name.split(',')[0],
        latitude: parseFloat(item.lat),
        longitude: parseFloat(item.lon),
        country: item.display_name.split(',').pop().trim(),
        admin1: ""
      };
    });
    const response = { results };
    // 30-day TTL: geocoding results are stable and OSM policy requires aggressive caching
    await cachePut(env, cacheKey, response, 2592000);
    return jsonResponse(response);
  } catch (e) {
    console.error("handleSearch geocoding failed:", e);
    return jsonResponse({ error: "geocoding başarısız" }, 503);
  }
}

// ---------------------------------------------------------------------------
// Tile proxy helpers — route radar / satellite tiles through Worker so device
// IP never reaches upstream tile servers and KV caching minimises their load.
// ---------------------------------------------------------------------------

// Convert XYZ tile coordinates to an EPSG:3857 BBOX [west, south, east, north].
function tileToBbox3857(z, x, y) {
  const R = 6378137;
  const n = 1 << z;
  const west  = (x       / n) * 2 * Math.PI * R - Math.PI * R;
  const east  = ((x + 1) / n) * 2 * Math.PI * R - Math.PI * R;
  const latN = Math.atan(Math.sinh(Math.PI * (1 - 2 * y       / n)));
  const latS = Math.atan(Math.sinh(Math.PI * (1 - 2 * (y + 1) / n)));
  const north = Math.log(Math.tan(Math.PI / 4 + latN / 2)) * R;
  const south = Math.log(Math.tan(Math.PI / 4 + latS / 2)) * R;
  return [
    Math.round(west),
    Math.round(south),
    Math.round(east),
    Math.round(north)
  ];
}

// Cache binary tile data (PNG/JPG) in KV as ArrayBuffer.
async function tileCacheGet(env, key) {
  try {
    if (!env?.PRAEVENTUS_CACHE) return null;
    return await env.PRAEVENTUS_CACHE.get(key, { type: "arrayBuffer" });
  } catch (err) { console.warn("tileCacheGet failed:", key, err); return null; }
}

async function tileCachePut(env, key, buffer, ttl) {
  try {
    if (!env?.PRAEVENTUS_CACHE) return;
    await env.PRAEVENTUS_CACHE.put(key, buffer, { expirationTtl: ttl });
  } catch (err) { console.warn("tileCachePut failed:", key, err); }
}

function tileResponse(buffer, contentType) {
  return new Response(buffer, {
    status: 200,
    headers: {
      "Content-Type": contentType,
      "Cache-Control": "public, max-age=300",
      ...corsHeaders()
    }
  });
}

// IEM NEXRAD composite radar (Public Domain academic service, graceful fallback).
// Docs: https://mesonet.agron.iastate.edu/ogc/
async function handleTileNexrad(url, env) {
  const z = parseInt(url.searchParams.get("z") || "");
  const x = parseInt(url.searchParams.get("x") || "");
  const y = parseInt(url.searchParams.get("y") || "");
  if (isNaN(z) || isNaN(x) || isNaN(y) || z > 10) {
    return new Response(null, { status: 400, headers: corsHeaders() });
  }

  const cacheKey = `tile_nexrad_${z}_${x}_${y}`;
  const cached = await tileCacheGet(env, cacheKey);
  if (cached && cached.byteLength > 0) return tileResponse(cached, "image/png");

  const [west, south, east, north] = tileToBbox3857(z, x, y);
  // nexrad-n0r-900913 is IEM's EPSG:3857 composite layer
  const wmsUrl =
    `https://mesonet.agron.iastate.edu/cgi-bin/wms/nexrad/n0r.cgi` +
    `?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&FORMAT=image%2Fpng` +
    `&TRANSPARENT=true&LAYERS=nexrad-n0r-900913` +
    `&WIDTH=256&HEIGHT=256&SRS=EPSG%3A3857&BBOX=${west},${south},${east},${north}`;

  try {
    const res = await fetch(wmsUrl, {
      signal: AbortSignal.timeout(10000),
      headers: { "User-Agent": USER_AGENT }
    });
    if (!res.ok) return new Response(null, { status: 503, headers: corsHeaders() });
    const buffer = await res.arrayBuffer();
    await tileCachePut(env, cacheKey, buffer, 300);
    return tileResponse(buffer, "image/png");
  } catch (err) {
    console.warn("handleTileNexrad failed:", err);
    return new Response(null, { status: 503, headers: corsHeaders() });
  }
}

// NOAA GOES-East IR satellite tiles via NASA GIBS (Public Domain).
// GIBS WMTS uses {z}/{y}/{x} axis order (row-major).
// Service info: https://nasa.github.io/gibs/
async function handleTileSatellite(url, env) {
  const z = parseInt(url.searchParams.get("z") || "");
  const x = parseInt(url.searchParams.get("x") || "");
  const y = parseInt(url.searchParams.get("y") || "");
  if (isNaN(z) || isNaN(x) || isNaN(y) || z > 9) {
    return new Response(null, { status: 400, headers: corsHeaders() });
  }

  const cacheKey = `tile_sat_${z}_${x}_${y}`;
  const cached = await tileCacheGet(env, cacheKey);
  if (cached && cached.byteLength > 0) return tileResponse(cached, "image/png");

  // GIBS WMTS "default" time = most recent available image (~10 min latency)
  const gibsUrl =
    `https://gibs.earthdata.nasa.gov/wmts/epsg3857/best` +
    `/GOES_East_IR_BrightnessTempColorized/default/default` +
    `/GoogleMapsCompatible_Level9/${z}/${y}/${x}.png`;

  try {
    const res = await fetch(gibsUrl, {
      signal: AbortSignal.timeout(12000),
      headers: { "User-Agent": USER_AGENT }
    });
    if (!res.ok) return new Response(null, { status: 503, headers: corsHeaders() });
    const buffer = await res.arrayBuffer();
    await tileCachePut(env, cacheKey, buffer, 300);
    return tileResponse(buffer, "image/png");
  } catch (err) {
    console.warn("handleTileSatellite failed:", err);
    return new Response(null, { status: 503, headers: corsHeaders() });
  }
}

// DWD precipitation radar WMS (CC BY 4.0, attribution required in UI).
// WMS endpoint: https://maps.dwd.de/geoserver/dwd/wms
// Layer: dwd:Niederschlagsradar (current radar composite)
async function handleTileDwd(url, env) {
  const z = parseInt(url.searchParams.get("z") || "");
  const x = parseInt(url.searchParams.get("x") || "");
  const y = parseInt(url.searchParams.get("y") || "");
  if (isNaN(z) || isNaN(x) || isNaN(y) || z > 10) {
    return new Response(null, { status: 400, headers: corsHeaders() });
  }

  const cacheKey = `tile_dwd_${z}_${x}_${y}`;
  const cached = await tileCacheGet(env, cacheKey);
  if (cached && cached.byteLength > 0) return tileResponse(cached, "image/png");

  const [west, south, east, north] = tileToBbox3857(z, x, y);
  const dwdUrl =
    `https://maps.dwd.de/geoserver/dwd/wms` +
    `?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&FORMAT=image%2Fpng` +
    `&TRANSPARENT=true&LAYERS=dwd%3ANiederschlagsradar` +
    `&WIDTH=256&HEIGHT=256&SRS=EPSG%3A3857&BBOX=${west},${south},${east},${north}`;

  try {
    const res = await fetch(dwdUrl, {
      signal: AbortSignal.timeout(10000),
      headers: { "User-Agent": USER_AGENT }
    });
    if (!res.ok) return new Response(null, { status: 503, headers: corsHeaders() });
    const buffer = await res.arrayBuffer();
    await tileCachePut(env, cacheKey, buffer, 300);
    return tileResponse(buffer, "image/png");
  } catch (err) {
    console.warn("handleTileDwd failed:", err);
    return new Response(null, { status: 503, headers: corsHeaders() });
  }
}

// ---------------------------------------------------------------------------
// Rate limiting — per-IP sliding window stored in KV.
// /narrative is expensive (AI inference), so it gets a stricter budget.
// ---------------------------------------------------------------------------

const RATE_LIMITS = {
  "/narrative": { windowSec: 60, maxRequests: 10 },
  "/search":    { windowSec: 60, maxRequests: 30 },
  "/forecast":  { windowSec: 60, maxRequests: 30 },
  "/nowcast":   { windowSec: 60, maxRequests: 30 },
};

async function checkRateLimit(env, ip, pathname) {
  const config = RATE_LIMITS[pathname];
  if (!config || !env?.PRAEVENTUS_CACHE) return false;
  const key = `rl_${pathname}_${ip}`;
  try {
    const raw = await env.PRAEVENTUS_CACHE.get(key);
    const count = raw ? parseInt(raw, 10) : 0;
    if (count >= config.maxRequests) return true;
    await env.PRAEVENTUS_CACHE.put(key, String(count + 1), {
      expirationTtl: config.windowSec
    });
  } catch {}
  return false;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS")
      return new Response(null, { headers: corsHeaders() });

    // Only allow GET requests for all endpoints.
    if (request.method !== "GET")
      return new Response(null, { status: 405, headers: corsHeaders() });

    const ip = request.headers.get("CF-Connecting-IP") || "unknown";
    if (await checkRateLimit(env, ip, url.pathname)) {
      return jsonResponse({ error: "rate limit exceeded" }, 429);
    }

    if (url.pathname === "/forecast")       return handleForecast(url, env);
    if (url.pathname === "/search")         return handleSearch(url, env);
    if (url.pathname === "/narrative")      return handleNarrative(url, env);
    if (url.pathname === "/nowcast")        return handleNowcast(url, env);
    if (url.pathname === "/tile/nexrad")    return handleTileNexrad(url, env);
    if (url.pathname === "/tile/satellite") return handleTileSatellite(url, env);
    if (url.pathname === "/tile/dwd")       return handleTileDwd(url, env);
    return new Response(null, { status: 404, headers: corsHeaders() });
  }
};
