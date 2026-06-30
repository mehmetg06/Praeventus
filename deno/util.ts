// Shared helpers for the Praeventus backend: unit conversions, WMO code maps,
// CORS, JSON responses, and the anonymous weather-summary builder for the AI
// narrative. Pure functions — no I/O, no platform bindings.

export const USER_AGENT = "Praeventus/1.0 (Contact: mehmetgezoglu@icloud.com)";

// --- Unit conversions -------------------------------------------------------

export function inHgToHPa(v: number | null | undefined): number | null {
  return v ? Math.round(v * 33.8639 * 10) / 10 : null;
}

export function ktsToKmh(v: number | null | undefined): number | null {
  return v ? Math.round(v * 1.852 * 10) / 10 : null;
}

export function smToMetres(v: string | number | null | undefined): number | null {
  if (v == null) return null;
  const n = parseFloat(String(v));
  return isNaN(n) ? null : Math.round(n * 1609.34);
}

// Canadian Wind Chill Index (T <= 10 C, wind >= 5 km/h) and NWS Rothfusz Heat
// Index (T >= 27 C, humidity >= 40 %). Falls back to actual temperature for the
// temperate middle range.
export function apparentTemp(tempC: number, humidity: number, windKmh: number): number {
  if (tempC <= 10 && windKmh >= 5) {
    const v = Math.pow(windKmh, 0.16);
    return Math.round((13.12 + 0.6215 * tempC - 11.37 * v + 0.3965 * tempC * v) * 10) / 10;
  }
  if (tempC >= 27 && humidity >= 40) {
    const T = tempC * 9 / 5 + 32;
    const R = humidity;
    const hi = -42.379 + 2.04901523 * T + 10.14333127 * R -
      0.22475541 * T * R - 6.83783e-3 * T * T -
      5.481717e-2 * R * R + 1.22874e-3 * T * T * R +
      8.5282e-4 * T * R * R - 1.99e-6 * T * T * R * R;
    return Math.round(((hi - 32) * 5 / 9) * 10) / 10;
  }
  return tempC;
}

// Circular (vector) mean of compass bearings — correct across the 0/360 seam.
export function circularMeanDir(dirs: Array<number | null>): number | null {
  const valid = dirs.filter((d): d is number => d != null);
  if (!valid.length) return null;
  const rads = valid.map((d) => d * Math.PI / 180);
  const s = rads.reduce((sum, r) => sum + Math.sin(r), 0);
  const c = rads.reduce((sum, r) => sum + Math.cos(r), 0);
  if (s === 0 && c === 0) return valid[0];
  const mean = Math.atan2(s, c) * 180 / Math.PI;
  return Math.round(((mean % 360) + 360) % 360);
}

// --- WMO weather-code maps --------------------------------------------------

export function metarWMO(
  wxString: string | null | undefined,
  skyCover: Array<{ skyCover?: string; cover?: string }> | null | undefined,
): number {
  if (!wxString && !skyCover) return 0;
  const wx = (wxString || "").toUpperCase();
  if (wx.includes("TS")) return 95;
  if (wx.includes("SN") || wx.includes("SG") || wx.includes("IC")) return 71;
  if (wx.includes("FZ")) return 66;
  if (wx.includes("RA") || wx.includes("DZ")) return 61;
  if (wx.includes("SH")) return 80;
  if (wx.includes("FG") || wx.includes("BR") || wx.includes("HZ")) return 45;
  const cover = (skyCover || [])
    .map((s) => s.skyCover || s.cover || "").join(",").toUpperCase();
  if (cover.includes("OVC")) return 3;
  if (cover.includes("BKN")) return 2;
  if (cover.includes("SCT") || cover.includes("FEW")) return 1;
  return 0;
}

export function mapMetNoWMO(symbol: string | null | undefined): number {
  if (!symbol) return 0;
  const s = symbol.split("_")[0];
  const map: Record<string, number> = {
    clearsky: 0,
    fair: 1,
    partlycloudy: 2,
    cloudy: 3,
    lightrainshowers: 80,
    rainshowers: 81,
    heavyrainshowers: 82,
    lightrainshowersandthunder: 95,
    rainshowersandthunder: 95,
    heavyrainshowersandthunder: 95,
    sleetshowers: 68,
    heavysleetshowers: 68,
    sleetshowersandthunder: 95,
    heavysleetshowersandthunder: 95,
    snowshowers: 85,
    heavysnowshowers: 86,
    snowshowersandthunder: 95,
    heavysnowshowersandthunder: 95,
    lightrain: 61,
    rain: 63,
    heavyrain: 65,
    lightrainandthunder: 95,
    rainandthunder: 95,
    heavyrainandthunder: 95,
    lightsleet: 68,
    sleet: 68,
    heavysleet: 68,
    lightsleetandthunder: 95,
    sleetandthunder: 95,
    heavysleetandthunder: 95,
    lightsnow: 71,
    snow: 73,
    heavysnow: 75,
    lightsnowandthunder: 95,
    snowandthunder: 95,
    heavysnowandthunder: 95,
    fog: 45,
  };
  return map[s] || 0;
}

export function mapBrightSkyWMO(condition: string | null | undefined): number {
  const map: Record<string, number> = {
    dry: 0,
    fog: 45,
    rain: 61,
    sleet: 68,
    snow: 71,
    hail: 89,
    thunderstorm: 95,
  };
  return condition ? (map[condition] || 0) : 0;
}

// --- HTTP helpers -----------------------------------------------------------

export function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "X-Content-Type-Options": "nosniff",
  };
}

export function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...corsHeaders() },
  });
}

// --- AI narrative summary ---------------------------------------------------
// PRIVACY: this is the ONLY payload sent to any AI provider. It contains
// nothing but abstracted numeric weather values — never coordinates, IP, or
// any device/user identifier.

const ALLOWED_LANGS = new Set(["tr", "en", "de", "fr", "es", "it", "pt", "nl", "ja", "ko", "zh"]);

export function normalizeLang(raw: string | null): string {
  const lang = raw || "tr";
  return ALLOWED_LANGS.has(lang) ? lang : "en";
}

const WMO_TR: Record<number, string> = {
  0: "Açık",
  1: "Az bulutlu",
  2: "Az bulutlu",
  3: "Bulutlu",
  45: "Sisli",
  48: "Sisli",
  51: "Çisenti",
  53: "Çisenti",
  55: "Çisenti",
  61: "Yağmurlu",
  63: "Yağmurlu",
  65: "Yağmurlu",
  71: "Karlı",
  73: "Karlı",
  75: "Karlı",
  80: "Sağanak",
  81: "Sağanak",
  82: "Sağanak",
  95: "Fırtınalı",
};
const WMO_EN: Record<number, string> = {
  0: "Clear",
  1: "Partly cloudy",
  2: "Partly cloudy",
  3: "Overcast",
  45: "Foggy",
  48: "Foggy",
  51: "Drizzle",
  53: "Drizzle",
  55: "Drizzle",
  61: "Rainy",
  63: "Rainy",
  65: "Rainy",
  71: "Snowy",
  73: "Snowy",
  75: "Snowy",
  80: "Showers",
  81: "Showers",
  82: "Showers",
  95: "Thunderstorm",
};

function wmoCondition(code: number, lang: string): string {
  return (lang === "tr" ? WMO_TR[code] : WMO_EN[code]) ??
    (lang === "tr" ? "Değişken" : "Variable");
}

function windDirectionLabel(deg: number, lang: string): string {
  const d = ((deg % 360) + 360) % 360;
  if (d <= 22 || d >= 338) return lang === "tr" ? "Kuzey" : "North";
  if (d <= 67) return lang === "tr" ? "Kuzeydoğu" : "Northeast";
  if (d <= 112) return lang === "tr" ? "Doğu" : "East";
  if (d <= 157) return lang === "tr" ? "Güneydoğu" : "Southeast";
  if (d <= 202) return lang === "tr" ? "Güney" : "South";
  if (d <= 247) return lang === "tr" ? "Güneybatı" : "Southwest";
  if (d <= 292) return lang === "tr" ? "Batı" : "West";
  return lang === "tr" ? "Kuzeybatı" : "Northwest";
}

export function buildWeatherSummary(params: URLSearchParams, lang: string): string {
  const temp = parseFloat(params.get("temp") || "20");
  const feels = parseFloat(params.get("feels") || String(temp));
  const humidity = parseFloat(params.get("humidity") || "60");
  const wind = parseFloat(params.get("wind") || "0");
  const windDeg = parseFloat(params.get("wind_dir") || "0");
  const code = parseInt(params.get("weather_code") || "0", 10);
  const precip = parseFloat(params.get("precip_prob") || "0");
  const tempMax = parseFloat(params.get("temp_max") || String(temp));
  const tempMin = parseFloat(params.get("temp_min") || String(temp));
  const uv = parseFloat(params.get("uv") || "0");
  const vis = parseFloat(params.get("visibility") || "10");
  const pressure = parseFloat(params.get("pressure") || "1013");
  const cond = wmoCondition(code, lang);
  const windDir = windDirectionLabel(windDeg, lang);

  if (lang === "tr") {
    const uvLabel = uv >= 8 ? "çok yüksek" : uv >= 6 ? "yüksek" : uv >= 3 ? "orta" : "düşük";
    return `Sıcaklık ${temp}°C (hissedilen ${feels}°C), gün boyu ${tempMin}-${tempMax}°C arası.\n` +
      `Nem %${humidity}, rüzgar ${wind} km/s ${windDir} yönünden.\n` +
      `UV indeksi ${uv} (${uvLabel}), görüş mesafesi ${vis} km.\n` +
      `Basınç ${pressure} hPa, yağış ihtimali %${precip}. ${cond}.`;
  }
  const uvLabel = uv >= 8 ? "very high" : uv >= 6 ? "high" : uv >= 3 ? "moderate" : "low";
  return `Temperature ${temp}°C (feels like ${feels}°C), daily range ${tempMin}-${tempMax}°C.\n` +
    `Humidity ${humidity}%, wind ${wind} km/h from the ${windDir}.\n` +
    `UV index ${uv} (${uvLabel}), visibility ${vis} km.\n` +
    `Pressure ${pressure} hPa, precipitation probability ${precip}%. ${cond}.`;
}

export function narrativeSystemPrompt(lang: string): string {
  return lang === "tr"
    ? `Sen bir meteoroloji uzmanısın. Verilen hava parametrelerini birlikte değerlendirerek 3 kısa Türkçe cümle yaz. Parametreler birbirini nasıl etkiliyor? Örnek: yüksek nem + düşük rüzgar = boğucu his, yüksek UV + düşük nem = kuru ve yakıcı güneş, düşük basınç + artan rüzgar = hava bozulabilir. Sadece meteorolojik yorumu yaz. Düşünme adımlarını yazma. Emoji kullanma. Direkt başla.`
    : `You are a meteorologist. Evaluate all given weather parameters together and write 3 short sentences. How do the parameters interact? Examples: high humidity + low wind = muggy feeling, high UV + low humidity = dry and harsh sun, low pressure + increasing wind = weather may deteriorate. Write only the meteorological interpretation. No thinking steps. No emojis. Start directly.`;
}
