# TrackLine (fastAndCar) — Proje Haritası

Projeye ara verip geri dönerken (ya da başka biri koda bakacaksa) "bu ekran
hangi dosyada, bu dosya ne işe yarıyor" sorusuna hızlı cevap vermek için.
Kod değiştikçe bu dosya da güncel tutulmalı — özellikle yeni bir ekran/tab
eklenince.

## 1. Açılış akışı

```
fastAndCarApp.swift          → uygulamanın girişi (WindowGroup, PersistenceController)
  └─ AppRootView.swift       → tek paylaşılan NavigationStack; sırayla:
       ├─ SplashView         → her açılışta kısa marka animasyonu (rota çizgisi + isim)
       ├─ OnboardingView     → sadece ilk kurulumda
       └─ MainTabBar + 5 sekme (AppTab.swift)
```

**Önemli mimari nokta:** Tüm ekranlar arası geçiş (`NavigationLink(value:)`)
`AppRootView`'daki TEK `NavigationStack`'ten yönetiliyor. Alt sekmelerin
kendi `NavigationStack`'i yok — sekme değişince `path` sıfırlanıyor
(`.onChange(of: selectedTab)`). Bunu bozmayın; sekmeler kendi
`NavigationStack`'ini açarsa "geri tuşuna basınca eski ekran duruyor" gibi
bug'lar geri gelir (bir kere yaşandı, bkz. git geçmişi).

## 2. 5 sekme — hangi ekran nerede

Sekme sırası (soldan sağa, `MainTabBar.swift`):
**Sürüşlerim → Rotalar → Ana Sayfa (ortada, vurgulu) → Garaj → Liderlik**

### 🕓 Sürüşlerim (`.trips`)
| Dosya | Tür | Ne işe yarar |
|---|---|---|
| `Features/Home/TripsListView.swift` | **Ekran** | Sürüş geçmişi listesi. Ayarlar ikonu da burada. |
| `Features/Home/Components/TripRowCard.swift` | Bileşen | Listedeki her sürüş satırı |
| `Features/Home/HomeViewModel.swift` | ViewModel | Bu ekranın verisi |

Bir sürüşe tıklayınca → **Trip Detail** (aşağıda, sekme dışı ekranlar).

### 🗺️ Rotalar (`.routes`)
| Dosya | Tür | Ne işe yarar |
|---|---|---|
| `Features/Routes/RoutesTabView.swift` | **Ekran** | Kendi kaydettiğin sürüşlerden oluşturduğun rotalar ("Rotalarım") |
| `Features/Routes/PickTripForRouteView.swift` | Sheet | "Sürüşten Rota Oluştur" → hangi sürüş, adım 1 |
| `Features/GlobalLeaderboard/CreateSegmentFlowView.swift` | Sheet | Adım 2: seçilen sürüşün başlangıç/bitiş aralığını seçip "Parkur" olarak kaydet |
| `Core/Leaderboard/LocalRoutesStore.swift` | Servis (yerel) | Bu sekmenin gerçek verisi — CloudKit kapalıyken bile çalışsın diye tamamen cihazda tutuluyor |

Not: Burada segment **arama** yok — "benim rotalarım" burası, "herkesin
parkurunu ara" Liderlik → Global kısmında.

### 📍 Ana Sayfa / Dashboard (`.dashboard`, ortadaki vurgulu buton)
| Dosya | Tür | Ne işe yarar |
|---|---|---|
| `Features/Home/DashboardView.swift` | **Ekran** | Tek ekran, iki hali var: boşta (harita + "Sürüşe Başla") ve kayıt sırasında (aynı ekran, buton "Sürüşü Bitir"e döner) |
| `Features/ActiveTrip/ActiveTripViewModel.swift` | ViewModel | Kayıt oturumunu yönetir: örnekleri toplar, canlı hız/mesafe/süre hesaplar |
| `Features/ActiveTrip/Components/LiveRouteMapView.swift` | Bileşen | Canlı harita + büyüyen rota çizgisi + (varsa) mor kesikli "hayalet rota" + tur talimatları |
| `Features/ActiveTrip/Components/LiveStatBadge.swift` | Bileşen | Hız/mesafe rozetleri |

Bir "Parkur"u "Bu Rotayı Sür" ile aktive edince buraya otomatik geçiliyor ve
kayıt otomatik başlıyor (`AppRootView.followSegment`).

### 🚗 Garaj (`.garage`)
| Dosya | Tür | Ne işe yarar |
|---|---|---|
| `Features/Garage/GarageView.swift` | **Ekran** | Araç listesi |
| `Features/Garage/Components/CarCard.swift` | Bileşen | Listedeki her araç kartı |
| `Features/Garage/AddCarView.swift` | Sheet | Araç ekleme formu (marka/model/yıl/beygir/yakıt/km + foto) |
| `Features/Garage/PhotoCropView.swift` | Sheet | Araç fotoğrafını kırpma/yakınlaştırma (Share Card'ın 9:16 kadrajına göre) |

### 🏆 Liderlik (`.community`)
| Dosya | Tür | Ne işe yarar |
|---|---|---|
| `Features/Community/CommunityView.swift` | **Ekran** | Global / Crew arası segmented control (iç sekme) |
| `Features/GlobalLeaderboard/GlobalLeaderboardListView.swift` | Alt-ekran (Global) | Yakınımdakiler + Oluşturduklarım + Parkur Ara |
| `Features/GlobalLeaderboard/SegmentDetailView.swift` | Alt-ekran | Bir parkurun rota önizlemesi + sıralama tablosu + "Bu Rotayı Sür" |
| `Features/GlobalLeaderboard/Components/SegmentRow.swift`, `SegmentEffortRow.swift` | Bileşen | Liste satırları |
| `Features/Community/Crew/CrewHomeView.swift` | Alt-ekran (Crew) | Benim ekiplerim (oluşturulan/katılınan) + yeni ekip oluştur |
| `Features/Community/Crew/CreateCrewView.swift` | Sheet | Yeni Crew oluşturma |
| `Features/Community/Crew/CrewDetailView.swift` | Alt-ekran | Üye listesi + kişisel-en-iyi sıralaması + son sürüşler |
| `Features/Community/Crew/CloudSharingSheet.swift` | Sheet | Sistemin kendi davet ekranı (CKShare, Mesajlar/Mail/link kopyala) |
| `Features/Community/Crew/Components/CrewRow.swift`, `CrewDriveSummaryRow.swift` | Bileşen | Liste satırları |

⚠️ **Global Liderlik ve Crew şu an UI'da kapalı** — bkz. §6.

## 3. Sekme dışı ekranlar / akışlar

| Dosya | Tür | Ne işe yarar |
|---|---|---|
| `Features/Splash/SplashView.swift` | Ekran | Her açılışta kısa marka girişi (rota çizgisi + "Drive Tracker: TrackLine" + geliştirici notu) |
| `Features/Onboarding/OnboardingView.swift` + `OnboardingViewModel.swift` | Ekran | İlk kurulum, tek ekran |
| `Features/TripDetail/TripDetailView.swift` | **Ekran** | Sürüşe tıklayınca açılan detay: F1-tarzı rota, hız haritası, playback, sürüş skoru, istatistik grid'i, düzenlenebilir zaman çizelgesi |
| `Features/TripDetail/TripDetailViewModel.swift` | ViewModel | Bu ekranın verisi + playback imleci |
| `Features/TripDetail/Components/*.swift` | Bileşen | `DrivingScoreCard`, `PlaybackBar`, `RouteCanvas` (asıl rota çizici, her yerde reuse ediliyor), `RouteEndpointLabels`, `RouteInspectorOverlay` (rotaya dokununca en yakın örneği bul), `RouteMapBackdrop`, `StatTileGrid`, `TimelineList` |
| `Features/Share/ShareCardView.swift` | Sheet | Render edilen paylaşım kartının önizlemesi + native paylaş sayfası |
| `Features/Share/ShareCardRenderer.swift` | Servis | Sürüşü sabit 360×640 bir paylaşım kartına (UIImage) çeviriyor |
| `Features/Share/InstagramStorySharer.swift` | Servis | "Instagram Stories'e paylaş" native paylaşım sayfasının bir seçeneği olarak |
| `Features/Settings/SettingsView.swift` | Ekran (sheet) | İzin durumu, mesafe birimi, versiyon — **Sürüşlerim** sekmesindeki ikondan açılıyor |
| `Features/Settings/SettingsViewModel.swift` | ViewModel | — |
| `Features/Settings/LanguagePickerView.swift` | Ekran (sheet) | Sistem/Türkçe/English dil seçimi |
| `Features/Leaderboard/NicknamePromptView.swift` | Sheet | CloudKit'e ilk kez bir şey gönderirken (parkur/crew oluştururken) takma ad sorma. Klasör adı eski "Leaderboard" kalmış, kafa karıştırmasın. |

## 4. `Core/` — ekran değil, alttaki servis/model katmanı

| Alt klasör | İçerik |
|---|---|
| `Core/Persistence/` | `Trip.swift` (SwiftData modeli, örnekler JSON blob olarak tutulur), `Car.swift`, `PersistenceController.swift` (tek paylaşılan SwiftData container) |
| `Core/Location/` | `LocationManager` (CLLocationManager sarmalayıcısı), `LocationSample`, `LocationSmoothing` (GPS jitter filtresi), `PlaceNameResolver` (ters coğrafi kodlama), `TripAutoDetector` (durma tespiti) |
| `Core/Analytics/` | `TripStatsCalculator` (ham örneklerden istatistik), `DrivingScoreCalculator` (sürüş skoru) |
| `Core/Geometry/` | `RouteProjector`, `GeoMapProjector`, `FittedRegion`, `GeoMath` — GPS koordinatlarını ekrana/haritaya doğru şekilde oturtan matematik |
| `Core/Leaderboard/` | Parkur (Segment) sistemi: `Segment`, `SegmentEffort`, `SegmentMatcher`, `SegmentAutoMatcher`, `CloudKitSegmentService`, `Geohash`, `AntiCheat`, `RouteGuidance` + `RouteGuidanceTracker` (basit metin tabanlı yön talimatları), `LocalRoutesStore` (Rotalar sekmesinin yerel verisi), `MyCreatedSegmentsStore`, `NicknameStore`, `RoutePolylinePoint` |
| `Core/Crew/` | `Crew`, `CrewMembership`, `CrewDriveSummary`, `CrewZoneRef`, `MyCrewsStore`, `CloudKitCrewService` (CKShare tabanlı grup sistemi) |
| `Core/AppLanguage.swift` | Ayarlar > Dil override sistemi |
| `Core/FeatureFlags.swift` | §6'daki kapalı özellik anahtarları |
| `Core/LocalNotifier.swift` | Yerel bildirimler (parkur eşleşti, crew daveti kabul edildi) |

## 5. `DesignSystem/` — ortak görsel dil

`Colors.swift` (palet + hız→renk ısı haritası), `GlassCard.swift` (cam
kart), `PrimaryGlassButton.swift` (tek buton dili), `Typography.swift`,
`Haptics.swift`, `RouteMotifShape.swift` (onboarding/splash'teki dekoratif
rota çizgisi).

## 6. Şu an kapalı ama kodu tamamlanmış özellikler

`Core/FeatureFlags.swift` → `globalLeaderboardEnabled` ve `crewEnabled`
şu an `false`. Kod tamamen yazılmış ve çalışıyor ama **ücretli Apple
Developer Program hesabı** olmadan CloudKit/Push entitlement alınamıyor.
Hesap açılınca bu iki flag `true` yapılıp Liderlik sekmesi tam
aktif olacak.

## 7. Test/debug kısayolları

Simülatörde PhotosPicker gibi dokunmatik akışlar otomatikleştirilemediği
için, `-uiTestAutoX` şeklinde launch argument'ları var (`AppRootView.swift`
ve ilgili ekranlarda `#if DEBUG` bloklarında ara): örn.
`-uiTestAutoStartTrip`, `-uiTestAutoEnd`, `-uiTestAutoOpenTrip`,
`-uiTestAutoShare`, `-uiTestAutoGarage`, `-uiTestAutoAddCar`,
`-uiTestAutoCropTest`, `-uiTestAutoRoutes`, `-uiTestGuidanceFromLastTrip`,
`-uiTestSetLanguage`. Bunlar `xcodebuild` ile build alıp simülatöre
`xcrun simctl launch ... -uiTestAutoX` şeklinde verilerek ilgili akışı
otomatik tetiklemek için.
