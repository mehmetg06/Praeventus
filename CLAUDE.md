# Praeventus — Sistem Mimarisi El Kitabı

**Praeventus**, gizlilik odaklı, sıfır maliyetli ve yüksek sadakatli bir atmosferik tahmin sistemidir. Swift Playgrounds ekosistemi üzerinden dağıtılmak üzere tasarlanmıştır. "No Account, No API Key" (Hesap Yok, API Anahtarı Yok) kuralına mutlak suretle uyar. Sistem, doğrudan kurumsal seviyedeki Açık Veri (Open Data) sağlayıcılarından beslenir ve cihaz üzerinde harici bağımlılık yaratmadan çalışır.

---

## 1. Sistem Felsefesi ve Direct Aggregator Mimarisi

### Direct Aggregator (Doğrudan Toplayıcı) Yapısı
Proje, aracı ve kısıtlayıcı hava durumu API'lerini (ör. Open-Meteo) tamamen terk ederek **"Direct Aggregator"** mimarisine geçmiştir.
Tüm dış veri talepleri, Cloudflare Worker üzerinden doğrudan global ve kurumsal veri merkezlerine yönlendirilir. Worker, bu heterojen verileri toplayıp, Swift uygulamasının beklediği standart "ikili model" (ECMWF, ICON) yapısına dönüştürerek (mapping) cihaza tek bir JSON paketi halinde iletir. Bu sayede cihazdaki `WeatherFusion` motoru hiçbir kod değişikliği gerektirmeden çalışmaya devam eder.

Sistem, aşağıdaki bağımsız kaynakları eşzamanlı olarak sorgular ve birleştirir:

| Model / Veri | Veri Kaynağı | Lisans ve Ticari Uyum | Görevi ve Güçlü Yönü |
|--------------|--------------|-----------------------|----------------------|
| **ECMWF IFS 0.25°** | **MET Norway** (`api.met.no`) | CC-BY-4.0 / Public Domain | Global tahmin lideri. `User-Agent: Praeventus/1.0` başlığı zorunludur. |
| **ICON Global** | **Bright Sky** (`api.brightsky.dev`) | Open Data (DWD) | Yüksek çözünürlüklü Avrupa ve global kapsam. |
| **Nowcast (Radar)** | **MET Norway** (`api.met.no/weatherapi/nowcast`) | CC-BY-4.0 | Radar tabanlı anlık yağış tahmini (5 dk güncelleme). Sadece Kuzey Avrupa kapsama alanında aktiftir; dışında `radarCoverage: false` döner. |
| **METAR** | **aviationweather.gov** (NOAA) | Public Domain | İstasyon bazlı, yerel anlık gözlem verisi (yer doğrulaması). |
| **Geocoding** | **Nominatim** (OpenStreetMap) | ODbL / Open Data | Arama sorgularını koordinatlara çeviren açık veri servisi. |
| **AI Narrative** | **Cloudflare Workers AI** | Commercial-compliant (Free Tier) | `llama-3.3-70b-instruct-fp8-fast` ile uçta meteorolojik metin üretimi. |

### Privacy by Architecture (Mimari Seviyede Gizlilik)
Kullanıcıya ait hiçbir veri, işlenmek veya satılmak üzere dışarı çıkarılmaz:
- **Konum Truncation:** Lokasyon verisi cihazda `kCLLocationAccuracyReduced` ile alınır, `LocationProvider` tarafından 2 ondalık basamağa (~1.1 km) kırpılır ve Worker'a 4 ondalık basamak olarak gönderilir.
- **Anonim Ağ:** Cihaz IP'si hiçbir zaman veri sağlayıcılara ulaşmaz; tüm trafik Cloudflare Worker arkasında maskelenir.
- **On-Device NLP:** Hava durumu metninin duygu analizi, Apple'ın yerel `NaturalLanguage` framework'ü (NLTagger) ile cihaz üzerinde yapılır.
- **AI Narrative Mahremiyeti:** Cloudflare AI'a sadece anonim hava değerleri (sıcaklık, rüzgar vb.) gönderilir; koordinat veya kullanıcı tanımı asla iletilmez.
- **Baro Verileri:** `SensorCalibration` ve `StormSensorEngine` cihazın barometre okumasını tamamen cihaz üzerinde işler; hiçbir şey dışarı çıkmaz.

### Zero Lock-In (Sıfır Bağımlılık)
Kod tabanında hiçbir API anahtarı, gizli token veya bağımlı SDK bulunmaz. Proje, tamamen "Keyless" ve ticari lisans uyumlu (CC-BY 4.0, Public Domain) kaynaklarla hayatta kalacak şekilde tasarlanmıştır.

---

## 2. Mimari Veri Akışı (Data Flow)

Sistemin veri akışı, birbirinden tamamen izole edilmiş üç katmanda gerçekleşir: İstemci (Swift), Aggregator (Worker), ve Kurumsal Kaynaklar.

```text
[ iOS / Swift İstemcisi ]
  │
  ├─ 1. Arama (Search) ─────→ CloudflareWorker.search()
  │                             └─→ Nominatim (OpenStreetMap) ──→ GeocodingResult[]
  │
  ├─ 2. Tahmin (Forecast) ──→ CloudflareWorker.forecast()
  │                             │
  │                             ├─→ MET Norway (locationforecast) ──→ ECMWF IFS 0.25° Verisi
  │                             ├─→ Bright Sky (api.brightsky.dev) ──→ ICON Verisi
  │                             └─→ NOAA (aviationweather.gov)     ──→ METAR (ground-truth overlay)
  │                             │
  │                             ▼  [Worker, verileri normalize edip tek JSON paketine çevirir]
  │
  ├─ 3. Nowcast (Radar) ────→ CloudflareWorker.nowcast()
  │                             └─→ MET Norway Nowcast API ──→ NowcastResponse (5 dk radar)
  │
  └─ 4. Narrative (AI) ─────→ CloudflareWorker.narrative()
                                └─→ Workers AI (llama-3.3-70b) ──→ 3 cümlelik meteoroloji metni

[ Cihaz İçi İşleme (On-Device) ]
  │
  ▼
 WeatherFusion.fuse() ──→ İstatistiksel Model Birleştirme (Inverse-Spread Weighting)
  │                         └─→ FusionConfidence (agreement%, temperatureSpreadC)
  ▼
 WeatherMapping.map() ──→ `WeatherData`, `HourlyPoint`, `DailyRange` (Domain Modelleri)
  │
  ├─→ AtmosphericEngine       ──→ Instability, Cloud Cover, Mood ve Fırtına Riski
  ├─→ ThermalPredictionEngine ──→ NWS Heat Index, Rüzgar Soğuğu, UV Yanma Riski (Fitzpatrick)
  ├─→ AstronomicalEngine      ──→ Güneş Yüksekliği, Ay Evresi, Meeus Algoritmaları
  ├─→ MinutecastEngine        ──→ Catmull-Rom Spline ile saatlik → dakika çözünürlüğü enterpolasyon
  ├─→ StormSensorEngine       ──→ CMAltimeter tabanlı hızlı basınç düşüşü tespiti (WMO kriterleri)
  ├─→ ActivityAnalysisEngine  ──→ 10 aktivite türü için hava durumu uygunluk skoru
  └─→ SensorCalibration       ──→ iPad barometre okumasıyla anlık basınç kalibrasyonu
  │
  ▼
 MeteorologicalExpertSystem ──→ Sayısal verilerden Türkçe Uzman Sistem Metni (On-Device)
  │  (WeatherNarrativeEngine adapter üzerinden)
  └─→ (Opsiyonel) CloudflareWorker.narrative() ──→ Llama-3.3 70B üzerinden AI Meteorolojik Yorum
  │
  ▼
 WeatherStore (@MainActor) ──→ SwiftUI Arayüzüne Canlı Yayın
```

---

## 3. Repository Yapısı

```
Praeventus/
├── CLAUDE.md                          # Bu dosya
├── README.md
├── worker/
│   ├── src/index.js                   # Cloudflare Worker v3 (Direct Aggregator)
│   └── wrangler.toml                  # Worker config (AI binding, deploy)
└── Praeventus.swiftpm/
    ├── Package.swift                  # Swift 6.0, iOS 17+, iPad only
    ├── en.lproj/Localizable.strings   # İngilizce lokalizasyon
    ├── tr.lproj/Localizable.strings   # Türkçe lokalizasyon
    └── *.swift                        # Tüm uygulama kaynak dosyaları
```

---

## 4. Modüller ve Dosyalar

Proje, katı bir `Domain-Driven Design` (DDD) mantığıyla şekillendirilmiştir. Veri, Etki Alanı (Domain) ve Arayüz (UI) katmanları birbirine sıkı sıkıya bağlı değildir.

### 4.1 Cloudflare Worker (`worker/src/index.js`)

Sistemin dış dünya ile iletişim kuran yegane bileşeni (Direct Aggregator). Mevcut sürüm: **v3**.

**Endpoint'ler:**

| Rota | İşlev |
|------|-------|
| `GET /forecast?lat=&lon=` | MET Norway + Bright Sky'ı paralel sorgular, METAR ile günceller. KV'de 45 dk. TTL ile önbellek. |
| `GET /search?q=&lang=&count=` | Nominatim'e yönlendirir. KV'de 30 gün TTL ile agresif önbellek (OSM politikası). |
| `GET /narrative?lang=&temp=&...` | Anonim parametre grubuyla Workers AI çağırır. KV'de 30 dk. TTL. |
| `GET /nowcast?lat=&lon=` | MET Norway Nowcast API. Kapsama dışında `radarCoverage: false` döner. KV'de 5 dk. TTL. |

**Önemli Worker detayları:**
- `PRAEVENTUS_CACHE` KV binding'i opsiyoneldir; yoksa önbelleksiz çalışır.
- Tüm isteklerde `User-Agent: Praeventus/1.0 (Contact: mehmetgezoglu@icloud.com)` başlığı gönderilir.
- `handleForecast`: Yanıtları `ecmwf_ifs025` (MET Norway) ve `icon_global` (Bright Sky) anahtarlı `models` nesnesi içinde döner.
- `overlayMETAR`: En yakın ICAO istasyonu bulunursa METAR okumaları anlık (current) verinin üzerine yazılır.
- Nominatim için max 1 req/sn politikası; KV önbellek bu limiti karşılamak için zorunludur, **asla kaldırılmamalı**.

**Dağıtım:**
```bash
npx wrangler deploy        # Production
npx wrangler dev           # Yerel geliştirme (http://localhost:8787)
```
Deploy sonrası `wrangler.toml`'a KV namespace eklenmeli. Worker URL'si (`WeatherSettings.cloudflareWorkerURL`) `WeatherModel.swift`'te sabit kodludur.

### 4.2 Data Layer (Swift Foundation)

`import SwiftUI` veya `UIKit` **yasaktır**. Bu katman Linux/macOS ortamında başsız (headless) derlenmeli ve test edilebilir olmalıdır.

| Dosya | Görev |
|-------|-------|
| `OpenMeteoModels.swift` | `ForecastResponse`, `GeocodingResponse`, `GeocodingResult` — ağ veri sözleşmeleri |
| `WeatherModel.swift` | `WeatherModel` enum, `WeatherSettings` (UserDefaults feature flag'leri, Worker URL) |
| `CloudflareWeatherProvider.swift` | Tek ağ geçidi: `forecast()`, `nowcast()`, `narrative()`, `search()`. `User-Agent`, timeout, hata çevirimi. |
| `WeatherFusion.swift` | Çoklu NWP modelini *Inverse-Spread Weighted Mean* ile tek sentetik modele indirger. `FusionConfidence` üretir. Wind direction için circular mean kullanır. |
| `WeatherMapping.swift` | Ham `ForecastResponse` → `MappedForecast` (`WeatherData`, `HourlyPoint`, `DailyRange`). Eksik dizileri tolere eder. |
| `ForecastCache.swift` | Disk bazlı önbellek, 1 saat TTL. Cache-first yükleme stratejisi. |
| `WeatherData.swift` | `WeatherData`, `WeatherCondition`, `TimeOfDay` — temel domain veri modelleri |
| `StorySentiment.swift` | Apple `NaturalLanguage` (NLTagger) ile üretilen metin üzerinde duygu analizi ve tehlike seviyesi güncelleme |
| `LocalizedStringCompat.swift` | `String(localized:)` uyumluluk yardımcısı |

### 4.3 Domain Layer (Fizik ve Matematik Motorları)

İş mantığının, meteorolojik standartların ve hesaplamaların barındığı merkez. Tümü `Foundation`-only.

| Dosya | Görev |
|-------|-------|
| `AtmosphericEngine.swift` | Sıcaklık, nem, rüzgar ve basınç açıklarından [0,1] arasında kararsızlık, bulutluluk ve fırtına skoru üretir. `AtmosphericState` döner. |
| `ThermalPredictionEngine.swift` | NWS Heat Index, Kanada Wind Chill, Fitzpatrick UV yanma süresi (tıbbi standart). Foehn rüzgarı tespiti içerir. `ActivityRiskLevel` ve `ColdRiskLevel` döner. |
| `AstronomicalEngine.swift` | Meeus ve NOAA algoritmaları ile güneş yüksekliği, gün doğumu/batımı, ay evresi. Dış kütüphane yok. |
| `MeteorologicalExpertSystem.swift` | `AtmosphericDynamics` girişinden deterministik Türkçe uzman meteoroloji raporu üretir. |
| `WeatherNarrativeEngine.swift` | `AtmosphericState` → `AtmosphericDynamics` adapter'ı. `MeteorologicalExpertSystem`'i çağırır. SwiftUI gerektirdiğinden `#if canImport(SwiftUI)` guard'ı içerir. |
| `MinutecastEngine.swift` | Saatlik tahmin dizilerini Catmull-Rom kübik spline ile dakika çözünürlüğüne enterpolasyon yapar. WMO UV model formülü (Green et al., 1994). |
| `StormSensorEngine.swift` | `CMAltimeter` tabanlı `actor`. WMO hızlı derinleşme kriterlerine göre üç pencerede (90 dk/2 sa/3 sa) basınç düşüşü tarar. `AsyncStream<StormAlert>` döner. CoreMotion olmayan platformlarda stub. |
| `HealthInsights.swift` | `ThermalPredictionEngine` çıktısından hazır UI bundle'ı: heatwave alert, UV yanma süresi, best outdoor hours. |
| `SensorCalibration.swift` | `@MainActor` sınıfı. iPad barometresini (kPa→hPa dönüşüm) kullanarak model basıncını max ±25 hPa ile kalibre eder. CoreMotion olmayan platformlarda no-op. |
| `ActivityAnalysisEngine.swift` | 10 aktivite türü için ağırlıklı puan (0–100) ve uyarı üretir. `SuitabilityLevel` (unsuitable→excellent) döner. |
| `Activity.swift` | `Activity`, `ActivityType`, `ActivitySuitability`, `ActivityStorage` (UserDefaults). 10 varsayılan aktivite profili. |

### 4.4 State Layer

| Dosya | Görev |
|-------|-------|
| `WeatherStore.swift` | `@MainActor ObservableObject`. Cache-First yükleme stratejisi, lab simülasyonu, fırtına izleme, biome enjeksiyonu, medical stress test override'ları. `forecastID: UUID` her yüklemede değişir (narrative trigger). |
| `SearchViewModel.swift` | `@MainActor ObservableObject`. Debounced geocoding araması. |
| `LocationProvider.swift` | `@MainActor CLLocationManagerDelegate`. Tek seferlik, kaba konumlu (~1.1 km), `When In Use` yetki. |

### 4.5 UI Layer (SwiftUI)

| Dosya | Görev |
|-------|-------|
| `App.swift` | `@main`, `WeatherStore` ve `LocationProvider` environment enjeksiyonu |
| `PraeventusRootView.swift` | Ana navigasyon: tab bar (Home, Charts, Activities, Lab, Settings) |
| `HomeView.swift` | Ana hava durumu görünümü. Narratif, fırtına afişi, minutecast grafiği. |
| `WeatherChartsView.swift` | Saatlik ve günlük tahmin grafikleri |
| `WeatherLabView.swift` | Geliştirici sandbox: slider'lar, biome preset'ler, medical stress test'ler, fırtına önizleme, model güven göstergesi |
| `LocationSearchView.swift` | Şehir arama ve mevcut konum seçimi |
| `SettingsView.swift` | Multi-model fusion toggle, sensor calibration toggle, aktivite yönetimi, gizlilik etiketleri, attribution linkleri |
| `SandboxEnvironment.swift` | `EnvironmentKey`'ler: `performanceMode`, `showLayoutBounds`, `sandboxAnimationSpeed`, `moonCycleOverride` |
| `AtmosphereBackgroundView.swift` | Cam-morfizm arka plan katmanı |
| `WeatherEffectLayers.swift` | Fiziksel parçacık sistemi (yağmur, kar, sis vb.) |
| `SunHaloOpticsLayer.swift` | Güneş halo optiği efekti |
| `GlassComponents.swift` | Yeniden kullanılabilir cam-morfizm bileşenleri |
| `HealthInsightsCard.swift` | Sağlık içgörüleri UI kartı |
| `CitySearchBar.swift` | Arama çubuğu bileşeni |
| `SearchSuggestionsView.swift` | Geocoding önerileri listesi |
| `WeatherCondition+Palette.swift` | `WeatherCondition` için renk paleti uzantıları |

---

## 5. Temel Veri Modelleri

```swift
// Ağ katmanı veri sözleşmesi (OpenMeteoModels.swift)
ForecastResponse          // Worker'dan gelen JSON şekli (Open-Meteo formatı)
  └── Current             // Anlık veri noktası
  └── Hourly              // Paralel diziler (time[], temperature_2m[], ...)
  └── Daily               // Günlük min/max dizileri

// Domain modelleri (WeatherMapping çıktısı)
WeatherData               // Anlık hava durumu snapshotu
HourlyPoint               // Saatlik veri noktası
DailyRange                // Günlük min/max aralığı

// Minutecast
MinutePoint               // Dakika çözünürlüklü enterpolasyon çıktısı
NowcastPoint              // Worker /nowcast radar noktası (5 dk)
NowcastResponse           // { minutecast, radarCoverage, generated_at }

// Füzyon
FusionConfidence          // { agreement: 0…1, temperatureSpreadC, models: [String] }

// Fırtına sensörü
StormAlert                // { severity, pressureDropHPa, windowMinutes, triggeredAt }
StormSeverity             // .watch / .warning / .extreme (WMO kriterleri)
```

---

## 6. Worker JSON Envelope Formatı

`/forecast` yanıtı:
```json
{
  "models": {
    "ecmwf_ifs025": <ForecastResponse>,
    "icon_global":  <ForecastResponse>
  },
  "metar_station": "LTAC",
  "metar_raw": { "temp": 22, "dewp": 14, ... },
  "generated_at": "2026-06-30T12:00:00Z",
  "_cached": true
}
```

`/nowcast` yanıtı:
```json
{
  "minutecast": [{ "time": "...", "precipitationRate": 1.2, ... }],
  "radarCoverage": true,
  "geometry": { ... },
  "generated_at": "..."
}
```

---

## 7. Uygulama Platformu

- **Target:** iPad only (`supportedDeviceFamilies: [.pad]`)
- **Min iOS:** 17.0
- **Swift dil modu:** Swift 6.0 (`swiftLanguageModes: [.v6]`)
- **Dağıtım:** Swift Playgrounds (`.swiftpm` paketi)
- **macOS fallback:** `macOS("14.0")` — headless test ve CI için
- **Bundle ID:** `com.mehmetg06.praeventus`
- **Lokalizasyonlar:** `en.lproj/Localizable.strings`, `tr.lproj/Localizable.strings` (`.xcstrings` Swift Playgrounds'da desteklenmez)

---

## 8. Uygulama ve Geliştirme Standartları

### 8.1 Katman İzolasyonu (Zorunlu)
`Data` ve `Domain` katmanlarında kesinlikle `import SwiftUI` veya `UIKit` kullanılamaz. `WeatherNarrativeEngine.swift` istisnai olarak `#if canImport(SwiftUI)` guard'ı taşır ancak bu mevcut teknik borçtur, örnek alınmamalıdır.

### 8.2 Swift 6.0 Concurrency
- Tüm asenkron işlemler `async/await` ile tasarlanmalı.
- `@MainActor` sınırları kesin ve güvenli biçimde çizilmeli.
- `actor` izolasyonu: `StormSensorEngine` ve `SensorCalibration` doğru örnek.
- Force unwrap (`!`) kullanımı **yasaktır**.
- CoreMotion callback'leri gibi `nonisolated` protokol metodları `MainActor.assumeIsolated { }` ile ana aktöre geçiş yapmalı.

### 8.3 Kusursuz Türkçeleştirme
Kullanıcının temel iletişim dili Türkçe'dir:
- `MeteorologicalExpertSystem` ve AI promptları profesyonel Türkçe üretir.
- Yeni eklenen her `String(localized:)` anahtarı mutlaka hem `en.lproj` hem `tr.lproj` dosyasına eklenmeli.
- Worker'ın `WMO_TR` sözlüğü ve `windDirectionLabel` fonksiyonu da Türkçe çıktı üretir.

### 8.4 Ticari Lisans Uyumu
Projeye dahil edilecek her yeni API veya servis mutlaka Open Data, Public Domain veya CC-BY formatında olmalı. API Key talep eden servisler proje kurallarına aykırıdır.

### 8.5 Performans
- UI katmanı 60 FPS sınırını korumak için `Canvas` render işlemlerini kısıtlar.
- `WeatherLabView`'daki `performanceMode` toggle'ı blur/material'ları kaldırarak layout testini kolaylaştırır.
- `MinutecastEngine` O(n·60) karmaşıklığında; birden fazla çağrı yapılmamalı, sonuç önbelleğe alınmalı.

### 8.6 Gizlilik Katmanları (Değiştirilemez)
1. `LocationProvider`: `kCLLocationAccuracyReduced` + 2 ondalık yuvarlama (~1.1 km)
2. `CloudflareWeatherProvider.trimmed()`: 4 ondalık kesinlik (~11 m) — asla artırılmamalı
3. Worker: koordinatları upstream sağlayıcılara iletmez, sadece tahmini alır
4. `narrative()` endpoint'i: hiçbir zaman koordinat veya kimlik bilgisi almaz

---

## 9. Geliştirme İş Akışı

### Branch Stratejisi
- Ana geliştirme: `main`
- Feature branch'leri: `claude/<açıklama>` formatında (ör. `claude/claude-md-docs-3s20ei`)
- Her özellik ayrı PR ile birleştirilir

### Yeni Özellik Eklerken
1. `Data`/`Domain` layer'da SwiftUI import olmadığından emin ol
2. `String(localized:)` anahtarlarını her iki `.lproj` dosyasına ekle
3. `WeatherLabView`'da test edilebilirlik için sandbox override noktası düşün
4. `WeatherStore.swift`'te gerekirse yeni `@Published` property ekle

### Worker Değişiklikleri
1. `worker/src/index.js` düzenle
2. Yerel test: `npx wrangler dev`
3. Production deploy: `npx wrangler deploy`
4. KV binding (`PRAEVENTUS_CACHE`) mevcut değilse `wrangler.toml`'a ekle ve KV namespace oluştur

### Nominatim Rate Limit Uyumu (Kritik)
Worker'ın tüm istekleri tek bir outbound IP'den çıkar. Nominatim politikası max 1 req/sn. KV önbellek bu limiti karşılamak için zorunludur, `handleSearch`'ten **asla kaldırılmamalı** ve birden fazla eşzamanlı Nominatim isteği **asla gönderilmemeli**.

---

> *"Praeventus, hava durumunu göstermez; atmosferi hesaplar."*
