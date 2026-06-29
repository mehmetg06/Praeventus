// Praeventus Weather Worker v3
// Aşama 1: METAR gözlem + Open-Meteo fallback
// Aşama 2: NASA IMERG uydu yağış gözlemi (/precipitation)

const OPEN_METEO_BASE = "https://api.open-meteo.com/v1/forecast";
const OPEN_METEO_GEO  = "https://geocoding-api.open-meteo.com/v1/search";
const METAR_BASE      = "https://aviationweather.gov/api/data/metar";
const AIRPORT_BASE    = "https://aviationweather.gov/api/data/airport";

const CURRENT_FIELDS = [
  "temperature_2m", "apparent_temperature", "relative_humidity_2m",
  "surface_pressure", "pressure_msl", "wind_speed_10m",
  "wind_direction_10m", "wind_gusts_10m", "uv_index",
  "dew_point_2m", "visibility", "precipitation_probability", "weather_code"
].join(",");

const HOURLY_FIELDS = [
  "temperature_2m", "apparent_temperature", "relative_humidity_2m",
  "precipitation_probability", "wind_speed_10m", "wind_direction_10m",
  "wind_gusts_10m", "uv_index", "weather_code"
].join(",");

const DAILY_FIELDS = [
  "temperature_2m_max", "temperature_2m_min",
  "precipitation_probability_max", "weather_code", "sunrise", "sunset"
].join(",");

const FORECAST_PARAMS =
  `current=${CURRENT_FIELDS}` +
  `&hourly=${HOURLY_FIELDS}` +
  `&daily=${DAILY_FIELDS}` +
  `&timezone=auto&forecast_days=7&wind_speed_unit=kmh`;

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
      headers: { "User-Agent": "Praeventus/1.0" }
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
        headers: { "User-Agent": "Praeventus/1.0" } }
    );
    if (!res.ok) return null;
    const data = await res.json();
    return Array.isArray(data) && data.length > 0 ? data[0] : null;
  } catch { return null; }
}

async function fetchOpenMeteo(lat, lon, model) {
  const modelParam = model ? `&models=${model}` : "";
  const url = `${OPEN_METEO_BASE}?latitude=${lat}&longitude=${lon}&${FORECAST_PARAMS}${modelParam}`;
  const res = await fetch(url, {
    signal: AbortSignal.timeout(12000),
    headers: { "User-Agent": "Praeventus/1.0" }
  });
  if (!res.ok) throw new Error(`OpenMeteo ${res.status}`);
  return res.json();
}

function overlayMETAR(forecast, metar) {
  if (!metar || !forecast?.current) return forecast;
  const c = forecast.current;
  if (metar.temp != null) c.temperature_2m = parseFloat(metar.temp);
  if (metar.dewp != null) {
    const T = c.temperature_2m, Td = parseFloat(metar.dewp);
    c.dew_point_2m = Td;
    c.relative_humidity_2m = Math.min(100, Math.max(0, Math.round(100 - 5*(T-Td))));
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

  const latR = Math.round(lat * 10000) / 10000;
  const lonR = Math.round(lon * 10000) / 10000;
  const cacheKey = `forecast_${latR}_${lonR}`;

  const cached = await cacheGet(env, cacheKey);
  if (cached) return jsonResponse({ ...cached, _cached: true });

  const [ecmwf, gfs, icon, icao] = await Promise.allSettled([
    fetchOpenMeteo(latR, lonR, "ecmwf_ifs025"),
    fetchOpenMeteo(latR, lonR, "gfs_global"),
    fetchOpenMeteo(latR, lonR, "icon_global"),
    nearestICAO(latR, lonR),
  ]);

  const models = {};
  if (ecmwf.status === "fulfilled") models.ecmwf_ifs025 = ecmwf.value;
  if (gfs.status   === "fulfilled") models.gfs_global   = gfs.value;
  if (icon.status  === "fulfilled") models.icon_global  = icon.value;

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

// WMO code → localized condition string used in narrative summaries
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

async function handlePrecipitation(url, env) {
  const lat = parseFloat(url.searchParams.get("lat") || "");
  const lon = parseFloat(url.searchParams.get("lon") || "");
  if (isNaN(lat) || isNaN(lon))
    return jsonResponse({ error: "lat ve lon gerekli" }, 400);

  const latR = Math.round(lat * 10) / 10;
  const lonR = Math.round(lon * 10) / 10;
  const cacheKey = `precip_${latR}_${lonR}`;

  const cached = await cacheGet(env, cacheKey);
  if (cached) return jsonResponse({ ...cached, _cached: true });

  try {
    const now = new Date();
    const yesterday = new Date(now - 86400000);
    const fmt = d => d.toISOString().slice(0, 10).replace(/-/g, "");
    const startDate = fmt(yesterday);
    const endDate = fmt(now);

    // Try hourly MERRA2 endpoint first
    const powerUrl = `https://power.larc.nasa.gov/api/temporal/hourly/point` +
      `?parameters=PRECTOT` +
      `&community=RE` +
      `&longitude=${lonR}` +
      `&latitude=${latR}` +
      `&start=${startDate}` +
      `&end=${endDate}` +
      `&format=JSON` +
      `&time-standard=UTC`;

    const res = await fetch(powerUrl, {
      signal: AbortSignal.timeout(15000),
      headers: { "User-Agent": "Praeventus/1.0 (contact: weather@praeventus.app)" }
    });
    if (!res.ok) throw new Error(`NASA POWER ${res.status}`);

    const data = await res.json();
    const hourlyData = data?.properties?.parameter?.PRECTOT;

    // Collect valid hourly values — -999 is NASA POWER's fill value (no data)
    const validHourly = hourlyData
      ? Object.entries(hourlyData)
          .sort(([a], [b]) => a.localeCompare(b))
          .filter(([, v]) => v !== -999 && v >= 0)
      : [];

    if (validHourly.length > 0) {
      // Use most recent valid hour; average the last 3 valid readings for trend
      const latestEntry = validHourly[validHourly.length - 1];
      const last3 = validHourly.slice(-3);
      const avg3h = last3.reduce((a, [, v]) => a + v, 0) / last3.length;

      const result = {
        precipitation_mm_per_hr: latestEntry[1],
        precipitation_3h_avg: avg3h,
        latest_observation_time: latestEntry[0],
        unit: "mm/hr",
        data_source: "MERRA2 hourly",
        product: "NASA POWER MERRA2",
        source: "NASA POWER / MERRA2",
        license: "Public Domain",
        _cached: false
      };

      await cachePut(env, cacheKey, result, 2700);
      return jsonResponse(result);
    }

    // All hourly values were -999 → fall back to daily MERRA2 endpoint
    const dailyUrl = `https://power.larc.nasa.gov/api/temporal/daily/point` +
      `?parameters=PRECTOTCORR` +
      `&community=RE` +
      `&longitude=${lonR}` +
      `&latitude=${latR}` +
      `&start=${startDate}` +
      `&end=${endDate}` +
      `&format=JSON`;

    const dailyRes = await fetch(dailyUrl, {
      signal: AbortSignal.timeout(15000),
      headers: { "User-Agent": "Praeventus/1.0 (contact: weather@praeventus.app)" }
    });

    if (!dailyRes.ok) {
      return jsonResponse({
        error: "no_satellite_coverage",
        precipitation_mm_per_hr: null,
        product: "NASA POWER MERRA2",
        source: "NASA POWER / MERRA2"
      }, 503);
    }

    const dailyData = await dailyRes.json();
    const dailyParam = dailyData?.properties?.parameter?.PRECTOTCORR;

    const validDaily = dailyParam
      ? Object.entries(dailyParam)
          .sort(([a], [b]) => a.localeCompare(b))
          .filter(([, v]) => v !== -999 && v >= 0)
      : [];

    if (validDaily.length === 0) {
      return jsonResponse({
        error: "no_satellite_coverage",
        precipitation_mm_per_hr: null,
        product: "NASA POWER MERRA2",
        source: "NASA POWER / MERRA2"
      }, 503);
    }

    // Convert daily mm/day → mm/hr by dividing by 24
    const latestDaily = validDaily[validDaily.length - 1];
    const last3Daily = validDaily.slice(-3);
    const avg3d = last3Daily.reduce((a, [, v]) => a + v / 24, 0) / last3Daily.length;

    const result = {
      precipitation_mm_per_hr: latestDaily[1] / 24,
      precipitation_3h_avg: avg3d,
      latest_observation_time: latestDaily[0],
      unit: "mm/hr",
      data_source: "MERRA2 daily",
      product: "NASA POWER MERRA2",
      source: "NASA POWER / MERRA2",
      license: "Public Domain",
      _cached: false
    };

    await cachePut(env, cacheKey, result, 2700);
    return jsonResponse(result);

  } catch (err) {
    return jsonResponse({
      error: err.message,
      precipitation_mm_per_hr: null,
      product: "NASA POWER MERRA2",
      source: "NASA POWER / MERRA2"
    }, 503);
  }
}

async function handleSearch(url) {
  const q    = url.searchParams.get("q") || "";
  const count = url.searchParams.get("count") || "5";
  const lang  = url.searchParams.get("lang") || "tr";
  if (!q) return jsonResponse({ error: "q gerekli" }, 400);
  const geoUrl = `${OPEN_METEO_GEO}?name=${encodeURIComponent(q)}&count=${count}&language=${lang}&format=json`;
  const res = await fetch(geoUrl, {
    signal: AbortSignal.timeout(8000),
    headers: { "User-Agent": "Praeventus/1.0" }
  });
  if (!res.ok) return jsonResponse({ error: "geocoding başarısız" }, 503);
  return new Response(await res.text(), {
    headers: { "Content-Type": "application/json", ...corsHeaders() }
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS")
      return new Response(null, { headers: corsHeaders() });
    if (url.pathname === "/forecast")       return handleForecast(url, env);
    if (url.pathname === "/search")         return handleSearch(url);
    if (url.pathname === "/narrative")      return handleNarrative(url, env);
    if (url.pathname === "/precipitation")  return handlePrecipitation(url, env);
    return jsonResponse({
      status: "Praeventus Weather Worker v3",
      routes: [
        "/forecast?lat=&lon=",
        "/search?q=&lang=",
        "/narrative?lang=&temp=&weather_code=",
        "/precipitation?lat=&lon="
      ]
    });
  }
};
