# Praeventus — Sistem Mimarisi El Kitabı

**Praeventus**, gizlilik odaklı, sıfır maliyetli ve yüksek sadakatli bir atmosferik tahmin sistemidir. Swift Playgrounds ekosistemi üzerinden dağıtılmak üzere tasarlanmıştır. "No Account, No API Key" (Hesap Yok, API Anahtarı Yok) kuralına mutlak suretle uyar. Sistem, doğrudan kurumsal seviyedeki Açık Veri (Open Data) sağlayıcılarından beslenir ve cihaz üzerinde harici bağımlılık yaratmadan çalışır.

---

## 1. Sistem Felsefesi ve Direct Aggregator Mimarisi

### Direct Aggregator (Doğrudan Toplayıcı) Yapısı
Proje, aracı ve kısıtlayıcı hava durumu API'lerini (ör. Open-Meteo) tamamen terk ederek **"Direct Aggregator"** mimarisine geçmiştir.
Tüm dış veri talepleri, Cloudflare Worker üzerinden doğrudan global ve kurumsal veri merkezlerine yönlendirilir. Worker, bu heterojen verileri toplayıp, Swift uygulamasının beklediği standart "üçlü model" (ECMWF, GFS, ICON) yapısına dönüştürerek (mapping) cihaza tek bir JSON paketi halinde iletir. Bu sayede cihazdaki `WeatherFusion` motoru hiçbir kod değişikliği gerektirmeden çalışmaya devam eder.

Sistem, aşağıdaki bağımsız kaynakları eşzamanlı olarak sorgular ve birleştirir:

| Model / Veri | Veri Kaynağı | Lisans ve Ticari Uyum | Görevi ve Güçlü Yönü |
|--------------|--------------|-----------------------|----------------------|
| **ECMWF & GFS** | **MET Norway** (`api.met.no`) | CC-BY-4.0 / Public Domain | Global tahmin liderleri. `User-Agent: Praeventus/1.0` başlığı zorunludur. |
| **ICON Global** | **Bright Sky** (`api.brightsky.dev`) | Open Data (DWD) | Yüksek çözünürlüklü Avrupa ve global kapsam. |
| **METAR** | **aviationweather.gov** (NOAA) | Public Domain | İstasyon bazlı, yerel anlık gözlem verisi (yer doğrulaması). |
| **Geocoding** | **Nominatim** (OpenStreetMap) | ODbL / Open Data | Arama sorgularını koordinatlara çeviren açık veri servisi. |
| **AI Narrative** | **Cloudflare Workers AI** | Commercial-compliant (Free Tier) | `llama-3.3-70b-instruct-fp8-fast` ile uçta meteorolojik metin üretimi. |

### Privacy by Architecture (Mimari Seviyede Gizlilik)
Kullanıcıya ait hiçbir veri, işlenmek veya satılmak üzere dışarı çıkarılmaz:
- **Konum Truncation:** Lokasyon verisi cihazda `kCLLocationAccuracyReduced` ile alınır ve 4 ondalık basamağa (~11 metre) kırpılarak Worker'a gönderilir.
- **Anonim Ağ:** Cihaz IP'si hiçbir zaman veri sağlayıcılara ulaşmaz; tüm trafik Cloudflare Worker arkasında maskelenir.
- **On-Device NLP:** Hava durumu metninin duygu analizi, Apple'ın yerel `NaturalLanguage` framework'ü (NLTagger) ile cihaz üzerinde yapılır.
- **AI Narrative Mahremiyeti:** Cloudflare AI'a sadece anonim hava değerleri (sıcaklık, rüzgar vb.) gönderilir; koordinat veya kullanıcı tanımı asla iletilmez.

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
  └─ 2. Tahmin (Forecast) ──→ CloudflareWorker.forecast()
                                │
                                ├─→ MET Norway (api.met.no)      ──→ ECMWF & GFS Verisi
                                ├─→ Bright Sky (api.brightsky.dev) ──→ ICON Verisi
                                └─→ NOAA (aviationweather.gov)     ──→ METAR (Anlık İstasyon)
                                │
                                ▼  [Worker, verileri normalize edip tek JSON paketine çevirir]
                                │
[ Cihaz İçi İşleme (On-Device) ]
  │
  ▼
 WeatherFusion.fuse() ──→ İstatistiksel Model Birleştirme (Inverse-Spread Weighting)
  │
  ▼
 WeatherMapping.map() ──→ `WeatherData`, `HourlyPoint`, `DailyRange` (Domain Modelleri)
  │
  ├─→ AtmosphericEngine       ──→ Instability, Cloud Cover, Mood ve Fırtına Riski
  ├─→ ThermalPredictionEngine ──→ NWS Heat Index, Rüzgar Soğuğu, UV Yanma Riski (Fitzpatrick)
  └─→ AstronomicalEngine      ──→ Güneş Yüksekliği, Ay Evresi, Meeus Algoritmaları
  │
  ▼
 MeteorologicalExpertSystem ──→ Sayısal verilerden Türkçe Uzman Sistem Metni (On-Device)
  │
  └─→ (Opsiyonel) CloudflareWorker.narrative() ──→ Llama-3.3 70B üzerinden AI Meteorolojik Yorum
  │
  ▼
 WeatherStore (@MainActor) ──→ SwiftUI Arayüzüne Canlı Yayın
```

---

## 3. Repository Yapısı ve Modüller

Proje, katı bir `Domain-Driven Design` (DDD) mantığıyla şekillendirilmiştir. Veri, Etki Alanı (Domain) ve Arayüz (UI) katmanları birbirine sıkı sıkıya bağlı değildir.

### 3.1 Cloudflare Worker (`worker/src/index.js`)
Sistemin dış dünya ile iletişim kuran yegane bileşeni (Direct Aggregator).
- **`handleForecast`**: MET Norway ve Bright Sky'a eşzamanlı istek atar. Yanıtları Open-Meteo'nun eski JSON formatına (`ecmwf_ifs025`, `gfs_global`, `icon_global`) haritalar. Bu sayede Swift uygulaması değişmeden kalır. Eğer yakınlarda bir havalimanı varsa (Nominatim bounding box ile), NOAA'dan METAR verisini çekip anlık tahminin üzerine yazar (ground-truth overlay).
- **`handleSearch`**: Nominatim API'sine (`nominatim.openstreetmap.org/search`) yönlenir ve yanıtı standart geocoding dizisine çevirir.
- **`handleNarrative`**: Gelen sıcaklık, UV, rüzgar gibi anonim değerleri kullanarak Workers AI (`llama-3.3-70b-instruct-fp8-fast`) üzerinden 3 cümlelik bağlamsal meteoroloji metni üretir.

### 3.2 Data Layer (Swift Foundation)
Hiçbir UI bağımlılığı içermeyen, tamamen `Foundation` tabanlı katman.
- **`CloudflareWeatherProvider.swift`**: Sistemin tek ağ geçidi. Tüm HTTP isteklerini Worker'a yönlendirir. Zaman aşımı, hatalı yanıt ve User-Agent (`Praeventus/1.0`) kontrollerini üstlenir.
- **`WeatherFusion.swift`**: Worker'dan gelen 3 farklı NWP (Numerical Weather Prediction) modelini *Inverse-Spread Weighted Mean* algoritmasıyla cihaz üzerinde tek bir sentetik modele indirger. Modeller arası tutarsızlığı (spread) hesaplayarak `FusionConfidence` (Güvenilirlik) değeri üretir.
- **`WeatherMapping.swift`**: Ham JSON (ForecastResponse) verisini uygulamanın güvenli tip yapısına (`MappedForecast`, `HourlyPoint`, `DailyRange`) çevirir. Eksik dizileri tolere eder.
- **`ForecastCache.swift`**: Disk bazlı (1 saat TTL) önbellek mekanizması. Uygulamanın anında açılmasını sağlar.

### 3.3 Domain Layer (Fizik ve Matematik Motorları)
İş mantığının, meteorolojik standartların ve hesaplamaların barındığı merkez.
- **`AtmosphericEngine.swift`**: Sıcaklık, nem, rüzgar ve basınç açıklarını alarak [0,1] arasında kararsızlık (instability), bulutluluk ve fırtına skorları üretir.
- **`ThermalPredictionEngine.swift`**: NWS (National Weather Service) standartlarında Hissedilen Sıcaklık (Heat Index), Kanada standartlarında Rüzgar Soğuğu (Wind Chill) ve Fitzpatrick skalasına göre UV yanma sürelerini tıbbi standartlarda hesaplar. Foehn rüzgarı tespit algoritması içerir.
- **`AstronomicalEngine.swift`**: Herhangi bir dış kütüphane olmadan, Meeus ve NOAA algoritmalarıyla Güneş'in ufuk yüksekliğini, gün doğumu/batımını ve Ay evrelerini matematiksel olarak hesaplar.
- **`MeteorologicalExpertSystem.swift`**: Atmosferik dinamikleri okuyarak deterministik, Türkçe bir uzman meteoroloji raporu üretir.
- **`StorySentiment.swift`**: Üretilen hikaye üzerinde Apple `NaturalLanguage` (NLTagger) framework'ü ile duygu analizi yapar ve tehlike seviyesini (severity) günceller.

### 3.4 UI Layer (SwiftUI)
- **`WeatherStore.swift`**: `@MainActor` state yöneticisi. Cihaz hafızası ve ağ arasındaki önbellek (Cache-First) mantığını kurar. "Weather Lab" (Geliştirici Kum Havuzu) için gerekli tüm sentetik çevre (Biome) enjeksiyonlarını yönetir.
- **`HomeView.swift` & `WeatherChartsView.swift`**: Verileri son kullanıcıya sunan, Cam-Morfizm (Glass-morphism) ve fiziksel parçacık sistemleri (`WeatherEffectLayers.swift`, `SunHaloOpticsLayer.swift`) kullanan yüksek performanslı arayüzler. Optimizasyon amacıyla 60 FPS sınırını ihlal etmemek için ağır render işlemlerini (Canvas) kısıtlar.

---

## 4. Uygulama ve Geliştirme Standartları

1. **Katman İzolasyonu:** `Data` ve `Domain` katmanlarında kesinlikle `import SwiftUI` veya `UIKit` kullanılamaz. Kod, başsız (headless) olarak Linux/macOS ortamlarında test edilebilir olmalıdır.
2. **Swift 6.0 Concurrency:** Tüm asenkron işlemler `async/await` ile tasarlanmalı, `@MainActor` sınırları kesin ve güvenli bir şekilde belirlenmelidir. Force unwrap (`!`) kullanımı yasaktır.
3. **Kusursuz Türkçeleştirme:** Kullanıcının temel iletişim dili Türkçe olduğundan, `MeteorologicalExpertSystem`, AI promptları ve uygulama içi tüm lokalizasyonlar (.strings formatı) profesyonel ve hatasız bir Türkçe ile yazılmıştır. Yeni eklenen özellikler mutlaka `tr.lproj` içerisine eklenmelidir.
4. **Ticari Lisans Uyumu:** Projeye dahil edilecek her yeni API veya servis; mutlak suretle açık veri (Open Data), Public Domain veya ticari kullanıma izin veren CC-BY formatında olmalıdır. Anahtar (API Key) talep eden servislerin (örneğin eski OpenAQ denemesi) kullanımı proje kurallarına aykırıdır.

---

> *"Praeventus, hava durumunu göstermez; atmosferi hesaplar."*
