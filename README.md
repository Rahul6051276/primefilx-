# 🎬 Primeflix - Modern Streaming App (Mobile & Android TV)

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Android%20TV-Compatible-green?style=for-the-badge&logo=android" alt="Android TV" />
  <img src="https://img.shields.io/badge/TMDB-API%20Integrated-01d277?style=for-the-badge&logo=themoviedatabase" alt="TMDB" />
  <img src="https://img.shields.io/badge/Xtream%20IPTV-Supported-blue?style=for-the-badge" alt="Xtream IPTV" />
</p>

A feature-rich, high-performance streaming application built with **Flutter**, designed seamlessly for both **Mobile Devices** and **Android TV / Google TV** with complete **Remote (D-Pad)** navigation.

---

## 🌟 Key Features

### 🚀 Dual-Source Streaming Architecture
- **Xtream Codes IPTV Integration:** Connects directly to Xtream IPTV server accounts with multi-server failover. Automatically prioritizes **Hindi Audio / Hindi Dubbed** audio streams.
- **Render Cloud API (TMDB-Embed-API):** Parallel scraping fallback powered by your custom backend on Render (`CastleTV`, `VaPlayer`, `Vidlink`, `HDHub4u`, `VegaMovies`).

### 📺 Cross-Platform (Mobile & Android TV)
- **Google TV / Android TV Remote Friendly:** Full D-Pad navigation (Up, Down, Left, Right, Center/OK) with interactive scale-up animations and glowing focus rings (`TvFocusable`).
- **Auto-Responsive Layout:**
  - **Mobile:** 3-column compact poster grid.
  - **Android TV:** 6-column native leanback layout.
- **Landscape Lock-Protection:** Automatically prevents TV displays from shrinking into vertical/portrait mode after video playback.

### 🎥 Custom Internal Video Player
- **Remote D-Pad Controls:**
  - `Center / OK`: Toggle Play / Pause.
  - `Left / Right Arrow`: 30-Second Rewind & Fast-Forward.
  - `Up / Down Arrow`: Show/Hide on-screen controls.
  - `Back Button`: Exit video player.
- **Player Choice Popup:** Choose between **In-App Player** and **External Player (VLC / MX Player)** with single-click remote access.
- **Advanced Player Features:**
  - Double-tap seek & on-screen HUD indicator.
  - Screen Lock functionality with top-layer touch priority.
  - Aspect ratio switcher: `FIT (16:9)`, `FILL (Stretch)`, and `CROP (Zoom / Notch-fill)`.
  - Mobile swipe gestures for brightness & volume adjustment.

### 🍿 Curated OTT Catalogs & Filters
- **Platform Hubs:** Dedicated catalogs for **Netflix, Disney+ Hotstar, Prime Video, ZEE5, and SonyLIV**.
- **Movies & Web Series Toggle:** Switch instantly between movies and series with remote-friendly tabs.
- **Smart Content Cleaning:**
  - 🚫 **No TV Daily Soaps:** Excludes StarPlus, Colors, Zee TV daily serials.
  - 🚫 **No Anime Pollution:** Strictly filters out Japanese animation and cartoons from platform lists.
  - ⭐ **Top Originals Only:** Curated directly from official OTT production networks.

### ⚡ Blazing Fast Launch & Local Caching
- **Instant Launch:** Caches catalogs locally with `SharedPreferences` to boot the home screen in **0.05 seconds** (no blank screens or grey placeholders).
- **Parallel Network Requests:** Utilizes concurrent `Future.wait` for lightning-fast catalog updates.

---

## ⚙️ Remote Gist Configuration Format

App credentials and server links are dynamically managed via **GitHub Gist**. Update your IPTV or backend scrapers without releasing a new APK:

mobile_version/
├── lib/
│   ├── internal_player.dart           # Custom Netflix-style player (TV Remote & gestures)
│   ├── screens/
│   │   ├── mobile_home_screen.dart    # Home Screen, Carousel, Horizontal Rows & TV Grids
│   │   ├── my_list_screen.dart        # Saved Bookmarks / Watchlist
│   │   └── search_screen.dart         # Instant TMDB search
│   ├── services/
│   │   ├── catalog_service.dart       # TMDB result parsers
│   │   ├── stream_service.dart        # Render cloud embed API connector
│   │   └── tmdb_service.dart          # TMDB discover queries & configuration
│   └── widgets/
│       └── mobile_stream_modal.dart   # Quality Selector Sheet & Player Choice Dialog
├── android/
│   └── app/
│       ├── build.gradle               # compileSdkVersion 34 configuration
│       └── src/main/AndroidManifest.xml # Android TV Leanback & Cleartext HTTP permissions
└── pubspec.yaml                       # Dependencies & packages

git clone https://github.com/Rahul6051276/primefilx-.git
cd primefilx-/mobile_version
flutter clean
flutter pub get
flutter build apk --releas

# Primeflix - Streaming App

## GitHub Gist Server Configuration (`TMDB API`)

Primeflix app mein servers (Stremio Addons aur Xtream IPTV) load karne ke liye GitHub Gist (`5b0a18b2cf69a99d1d3e06629fcbc70a`) ki `TMDB API` file mein niche diya gaya JSON structure hi use karna hai.

### Exact JSON Format (Copy & Paste)

```json
{
  "active_providers": [
    {
      "name": "PenguPlay (VegaMovies & VidLink)",
      "type": "stremio",
      "url": "[https://pengu.uk/%7B%22auth_token%22%3A%222UJkzYcs1DAE-kESrDyxt9r87LQZRf7NhRGi6lEC4Oc%22%7D/manifest.json](https://pengu.uk/%7B%22auth_token%22%3A%222UJkzYcs1DAE-kESrDyxt9r87LQZRf7NhRGi6lEC4Oc%22%7D/manifest.json)"
    },
    {
      "name": "Livebox Pro",
      "type": "xtream",
      "xc_host": "[http://livebox.pro](http://livebox.pro)",
      "xc_username": "YOUR_USERNAME",
      "xc_password": "YOUR_PASSWORD"
    }
  ]
}

