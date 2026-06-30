function mod(value: number, divisor: number): number {
  return ((value % divisor) + divisor) % divisor;
}

function rad(degrees: number): number {
  return (degrees * Math.PI) / 180;
}

function deg(radians: number): number {
  return (radians * 180) / Math.PI;
}

function julianDay(dateKey: string): number | null {
  const parts = dateKey.split("-");
  if (parts.length !== 3) return null;
  const y0 = Number(parts[0]);
  let m = Number(parts[1]);
  const d = Number(parts[2]);
  if (!Number.isFinite(y0) || !Number.isFinite(m) || !Number.isFinite(d)) return null;

  let y = y0;
  if (m <= 2) {
    y -= 1;
    m += 12;
  }

  const A = Math.floor(y / 100);
  const B = 2 - A + Math.floor(A / 4);
  return (
    Math.floor(365.25 * (y + 4716)) +
    Math.floor(30.6001 * (m + 1)) +
    d +
    B -
    1524.5
  );
}

function calc(JDx: number): { eqTime: number; decl: number } {
  const t = (JDx - 2451545.0) / 36525;
  const L0 = mod(280.46646 + t * (36000.76983 + 0.0003032 * t), 360);
  const M = 357.52911 + t * (35999.05029 - 0.0001537 * t);
  const e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
  const C = Math.sin(rad(M)) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
    Math.sin(rad(2 * M)) * (0.019993 - 0.000101 * t) +
    Math.sin(rad(3 * M)) * 0.000289;
  const trueLong = L0 + C;
  const lambda = trueLong - 0.00569 - 0.00478 * Math.sin(rad(125.04 - 1934.136 * t));
  const obliq0 = 23 +
    (26 +
        ((21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60)) /
      60;
  const obliqCorr = obliq0 + 0.00256 * Math.cos(rad(125.04 - 1934.136 * t));
  const decl = Math.asin(Math.sin(rad(obliqCorr)) * Math.sin(rad(lambda)));
  const y2 = Math.tan(rad(obliqCorr / 2)) ** 2;
  const eqTime = 4 *
    deg(
      y2 * Math.sin(2 * rad(L0)) -
        2 * e * Math.sin(rad(M)) +
        4 * e * y2 * Math.sin(rad(M)) * Math.cos(2 * rad(L0)) -
        0.5 * y2 * y2 * Math.sin(4 * rad(L0)) -
        1.25 * e * e * Math.sin(2 * rad(M)),
    );
  return { eqTime, decl };
}

function eventMinutes(
  JD: number,
  lat: number,
  lon: number,
  isSunrise: boolean,
): number | null {
  const { eqTime, decl } = calc(JD);
  const cosH = Math.cos(rad(90.833)) / (Math.cos(rad(lat)) * Math.cos(decl)) -
    Math.tan(rad(lat)) * Math.tan(decl);
  if (cosH > 1 || cosH < -1) return null;
  const HAdeg = deg(Math.acos(cosH));
  return isSunrise ? 720 - 4 * (lon + HAdeg) - eqTime : 720 - 4 * (lon - HAdeg) - eqTime;
}

function eventISO(
  dateKey: string,
  minute: number | null,
): string | null {
  if (minute == null) return null;
  const [y, m, d] = dateKey.split("-").map((part) => Number(part));
  if (![y, m, d].every(Number.isFinite)) return null;
  const base = Date.UTC(y, m - 1, d, 0, 0, 0);
  return new Date(base + Math.round(minute * 60) * 1000).toISOString();
}

export function sunriseSunsetISO(
  dateKey: string,
  lat: number,
  lon: number,
): { sunrise: string | null; sunset: string | null } {
  const JD = julianDay(dateKey);
  if (JD == null) return { sunrise: null, sunset: null };

  const sunrise0 = eventMinutes(JD, lat, lon, true);
  const sunset0 = eventMinutes(JD, lat, lon, false);

  const sunrise1 = sunrise0 == null ? null : eventMinutes(JD + sunrise0 / 1440, lat, lon, true);
  const sunset1 = sunset0 == null ? null : eventMinutes(JD + sunset0 / 1440, lat, lon, false);

  return {
    sunrise: eventISO(dateKey, sunrise1),
    sunset: eventISO(dateKey, sunset1),
  };
}
