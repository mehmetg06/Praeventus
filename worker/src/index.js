// Praeventus Weather Worker v3
// Routes: /forecast (ECMWF + GFS + ICON + METAR), /search, /narrative, /nowcast

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
function smToMetres(v){ return v ? Math.round(v * 1609.34)           : null; }

async function nearestICAO(lat, lon) {
  const delta = 2.0;
  const url = `${AIRPORT_BASE}?bbox=${lon-delta},${lat-delta},${lon+delta},${lat+delta}&format=json`;
  try {
    const res = await fetch(url, {
      signal: AbortSignal.timeout(8000),
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
  } catch { return null; }
}

async function fetchMETAR(icao) {
  if (!icao) return null;
  try {
    const res = await fetch(
      `${METAR_BASE}?ids=${icao}&format=json&taf=false`,
      { signal: AbortSignal.timeout(8000),
        headers: { "User-Agent": USER_AGENT } }
    );
    if (!res.ok) return null;
    const data = await res.json();
    return Array.isArray(data) && data.length > 0 ? data[0] : null;
  } catch { return null; }
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
    wind_gusts_10m: [], uv_index: [], weather_code: []
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

    const next1 = w.data.next_1_hours;
    const next6 = w.data.next_6_hours;

    if (next1) {
      precip_prob = next1.details?.probability_of_precipitation ?? 0;
      weather_symbol = next1.summary?.symbol_code ?? "";
    } else if (next6) {
      precip_prob = next6.details?.probability_of_precipitation ?? 0;
      weather_symbol = next6.summary?.symbol_code ?? "";
    }

    const weather_code = mapMetNoWMO(weather_symbol);
    const wind_speed = (d.wind_speed || 0) * 3.6;
    const wind_gusts = (d.wind_speed_of_gust || d.wind_speed || 0) * 3.6;

    if (!current || Math.abs(tDate - now) < Math.abs(new Date(current.time) - now)) {
      current = {
        time,
        temperature_2m: d.air_temperature,
        apparent_temperature: d.air_temperature,
        relative_humidity_2m: d.relative_humidity,
        surface_pressure: d.air_pressure_at_sea_level,
        pressure_msl: d.air_pressure_at_sea_level,
        wind_speed_10m: wind_speed,
        wind_direction_10m: d.wind_from_direction,
        wind_gusts_10m: wind_gusts,
        uv_index: d.ultraviolet_index_clear_sky || 0,
        dew_point_2m: d.dew_point_temperature || d.air_temperature,
        visibility: d.visibility || 10000,
        precipitation_probability: precip_prob,
        weather_code: weather_code
      };
    }

    hourly.time.push(time);
    hourly.temperature_2m.push(d.air_temperature);
    hourly.apparent_temperature.push(d.air_temperature);
    hourly.relative_humidity_2m.push(d.relative_humidity);
    hourly.precipitation_probability.push(precip_prob);
    hourly.wind_speed_10m.push(wind_speed);
    hourly.wind_direction_10m.push(d.wind_from_direction);
    hourly.wind_gusts_10m.push(wind_gusts);
    hourly.uv_index.push(d.ultraviolet_index_clear_sky || 0);
    hourly.weather_code.push(weather_code);

    const dayKey = time.split('T')[0];
    if (!dailyMap[dayKey]) {
      dailyMap[dayKey] = {
        minT: d.air_temperature, maxT: d.air_temperature,
        maxPrecipProb: precip_prob, codes: [weather_code]
      };
    } else {
      if (d.air_temperature < dailyMap[dayKey].minT) dailyMap[dayKey].minT = d.air_temperature;
      if (d.air_temperature > dailyMap[dayKey].maxT) dailyMap[dayKey].maxT = d.air_temperature;
      if (precip_prob > dailyMap[dayKey].maxPrecipProb) dailyMap[dayKey].maxPrecipProb = precip_prob;
      dailyMap[dayKey].codes.push(weather_code);
    }
  }

  const daily = {
    time: [], temperature_2m_max: [], temperature_2m_min: [],
    precipitation_probability_max: [], weather_code: [], sunrise: [], sunset: []
  };

  for (const day of Object.keys(dailyMap)) {
    daily.time.push(day);
    daily.temperature_2m_max.push(dailyMap[day].maxT);
    daily.temperature_2m_min.push(dailyMap[day].minT);
    daily.precipitation_probability_max.push(dailyMap[day].maxPrecipProb);

    const codes = dailyMap[day].codes;
    const counts = {};
    let maxCode = codes[0]; let maxCount = 0;
    for (const c of codes) {
      counts[c] = (counts[c] || 0) + 1;
      if (counts[c] > maxCount) { maxCount = counts[c]; maxCode = c; }
    }
    daily.weather_code.push(maxCode);
    daily.sunrise.push(day + "T06:00:00Z");
    daily.sunset.push(day + "T18:00:00Z");
  }

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
    wind_gusts_10m: [], uv_index: [], weather_code: []
  };
  const dailyMap = {};

  let current = null;
  const now = new Date();

  for (const w of data.weather) {
    const time = w.timestamp;
    const tDate = new Date(time);

    const weather_code = mapBrightSkyWMO(w.condition);
    const precip_prob = w.precipitation_probability || 0;

    if (!current || Math.abs(tDate - now) < Math.abs(new Date(current.time) - now)) {
      current = {
        time,
        temperature_2m: w.temperature,
        apparent_temperature: w.temperature,
        relative_humidity_2m: w.relative_humidity,
        surface_pressure: w.pressure_msl,
        pressure_msl: w.pressure_msl,
        wind_speed_10m: w.wind_speed,
        wind_direction_10m: w.wind_direction,
        wind_gusts_10m: w.wind_gust_speed || w.wind_speed,
        uv_index: 0,
        dew_point_2m: w.dew_point,
        visibility: w.visibility,
        precipitation_probability: precip_prob,
        weather_code: weather_code
      };
    }

    hourly.time.push(time);
    hourly.temperature_2m.push(w.temperature);
    hourly.apparent_temperature.push(w.temperature);
    hourly.relative_humidity_2m.push(w.relative_humidity);
    hourly.precipitation_probability.push(precip_prob);
    hourly.wind_speed_10m.push(w.wind_speed);
    hourly.wind_direction_10m.push(w.wind_direction);
    hourly.wind_gusts_10m.push(w.wind_gust_speed || w.wind_speed);
    hourly.uv_index.push(0);
    hourly.weather_code.push(weather_code);

    const dayKey = time.split('T')[0];
    if (!dailyMap[dayKey]) {
      dailyMap[dayKey] = {
        minT: w.temperature, maxT: w.temperature,
        maxPrecipProb: precip_prob, codes: [weather_code]
      };
    } else {
      if (w.temperature < dailyMap[dayKey].minT) dailyMap[dayKey].minT = w.temperature;
      if (w.temperature > dailyMap[dayKey].maxT) dailyMap[dayKey].maxT = w.temperature;
      if (precip_prob > dailyMap[dayKey].maxPrecipProb) dailyMap[dayKey].maxPrecipProb = precip_prob;
      dailyMap[dayKey].codes.push(weather_code);
    }
  }

  const daily = {
    time: [], temperature_2m_max: [], temperature_2m_min: [],
    precipitation_probability_max: [], weather_code: [], sunrise: [], sunset: []
  };

  for (const day of Object.keys(dailyMap)) {
    daily.time.push(day);
    daily.temperature_2m_max.push(dailyMap[day].maxT);
    daily.temperature_2m_min.push(dailyMap[day].minT);
    daily.precipitation_probability_max.push(dailyMap[day].maxPrecipProb);

    const codes = dailyMap[day].codes;
    const counts = {};
    let maxCode = codes[0]; let maxCount = 0;
    for (const c of codes) {
      counts[c] = (counts[c] || 0) + 1;
      if (counts[c] > maxCount) { maxCount = counts[c]; maxCode = c; }
    }
    daily.weather_code.push(maxCode);
    daily.sunrise.push(day + "T06:00:00Z");
    daily.sunset.push(day + "T18:00:00Z");
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
  if (metar.wdir != null) c.wind_direction_10m = parseFloat(metar.wdir);
  const wgst = ktsToKmh(metar.wgst);
  if (wgst != null) c.wind_gusts_10m = wgst;
  const vis = smToMetres(metar.visib);
  if (vis != null) c.visibility = vis;
  const wmo = metarWMO(metar.wxString, metar.skyCondition || metar.sky_condition);
  if (wmo > 0) c.weather_code = wmo;
  return forecast;
}

async function cacheGet(env, key) {
  try {
    if (!env?.PRAEVENTUS_CACHE) return null;
    const val = await env.PRAEVENTUS_CACHE.get(key);
    return val ? JSON.parse(val) : null;
  } catch { return null; }
}

async function cachePut(env, key, value, ttl) {
  try {
    if (!env?.PRAEVENTUS_CACHE) return;
    await env.PRAEVENTUS_CACHE.put(key, JSON.stringify(value), {
      expirationTtl: ttl
    });
  } catch {}
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin":  "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
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

  const latR = Math.round(lat * 100) / 100;
  const lonR = Math.round(lon * 100) / 100;
  const cacheKey = `forecast_v2_${latR}_${lonR}`;

  const cached = await cacheGet(env, cacheKey);
  if (cached) return jsonResponse({ ...cached, _cached: true });

  const [ecmwf, brightsky, icao] = await Promise.allSettled([
    fetchMETNorway(latR, lonR),
    fetchBrightSky(latR, lonR),
    nearestICAO(latR, lonR),
  ]);

  const models = {};
  if (ecmwf.status === "fulfilled" && ecmwf.value) {
    models.ecmwf_ifs025 = ecmwf.value;
    models.gfs_global   = ecmwf.value;
  }
  if (brightsky.status === "fulfilled" && brightsky.value) {
    models.icon_global  = brightsky.value;
  }

  if (Object.keys(models).length === 0)
    return jsonResponse({ error: "tüm modeller başarısız" }, 503);

  let metar = null;
  if (icao.status === "fulfilled" && icao.value)
    metar = await fetchMETAR(icao.value);

  for (const key of Object.keys(models))
    models[key] = overlayMETAR(models[key], metar);

  const result = {
    models,
    metar_station: icao.status === "fulfilled" ? icao.value : null,
    metar_raw: metar ? {
      temp: metar.temp, dewp: metar.dewp, wspd: metar.wspd,
      wdir: metar.wdir, altim: metar.altim, visib: metar.visib,
      wxString: metar.wxString,
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

async function handleNarrative(url, env) {
  const lang       = url.searchParams.get("lang") || "tr";
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
  } catch (err) { narrative = String(err); }

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

  // 2-decimal precision matches the privacy-truncation done on the Swift side.
  const latR = Math.round(lat * 100) / 100;
  const lonR = Math.round(lon * 100) / 100;

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
    return jsonResponse({ error: String(err), radarCoverage: false, minutecast: [] }, 503);
  }
}

async function handleSearch(url, env) {
  const q    = url.searchParams.get("q") || "";
  const count = url.searchParams.get("count") || "5";
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
    return jsonResponse({ error: "geocoding başarısız" }, 503);
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS")
      return new Response(null, { headers: corsHeaders() });
    if (url.pathname === "/forecast")  return handleForecast(url, env);
    if (url.pathname === "/search")    return handleSearch(url, env);
    if (url.pathname === "/narrative") return handleNarrative(url, env);
    if (url.pathname === "/nowcast")   return handleNowcast(url, env);
    return jsonResponse({
      status: "Praeventus Weather Worker v3",
      routes: [
        "/forecast?lat=&lon=",
        "/search?q=&lang=",
        "/narrative?lang=&temp=&weather_code=",
        "/nowcast?lat=&lon="
      ]
    });
  }
};
