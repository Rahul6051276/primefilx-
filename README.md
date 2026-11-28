# 🎬 PrimeFlix - Modern Streaming App (Mobile & Android TV)

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Media3%20ExoPlayer-00A8E1?style=for-the-badge&logo=android&logoColor=white" alt="Media3 ExoPlayer" />
  <img src="https://img.shields.io/badge/Android%20TV-Compatible-green?style=for-the-badge&logo=android" alt="Android TV" />
  <img src="https://img.shields.io/badge/TMDB-API%20Integrated-01d277?style=for-the-badge&logo=themoviedatabase" alt="TMDB" />
  <img src="https://img.shields.io/badge/Xtream%20IPTV-Supported-00A8E1?style=for-the-badge&logo=xtream" alt="Xtream IPTV" />
</p>

A high-performance **Prime Blue (`#00A8E1`)** streaming application built with **Flutter** and **Kotlin (Media3 / ExoPlayer)**, designed seamlessly for both **Android Mobile** and **Android TV / Google TV** with complete **Remote (D-Pad)** support.

---

## 🌟 Key Features

### 🚀 Dual-Source Streaming Architecture
- **Xtream Codes IPTV Integration:** Connects directly to Xtream IPTV servers with fast streaming JSON parsing and automatic **Hindi Audio / Hindi Dubbed** priority.
- **Stremio & Cloud Addons Support:** Parallel multi-server stream resolution (`Cloud Server 1`, `Cloud Server 2`, `HD Streamers`) with live in-player source switching.

### 🍿 Curated Catalogs & 200+ Collections
- **5-Slide Auto-Sliding Hero Banner:** Showcases the latest releases across **Bollywood**, **South**, **Hollywood**, **Hindi Web Series**, and **Global Web Series** with instant `Watch Now` playback.
- **5-Tab Bottom Navigation:** Quick access to **Home**, **Movies**, **Web Series**, **My List**, and **Settings**.
- **All Movies & All Web Series Hubs (200+ Titles):** Unified grids combining **Bollywood, Hollywood, and South** catalogs with **Popular** & **Latest** filters and infinite scroll.
- **Smart Content Cleaning:** Strictly filters out TV daily soaps, talk shows, and reality TV from Web Series lists so only genuine OTT series appear.

### 🎥 Native Media3 Cinema Player (`CinemaPlayerActivity`)
- **Prime Blue HUD & Controls:** Custom native landscape player matching the PrimeFlix theme.
- **200% Audio Boost:** Built-in `LoudnessEnhancer` (`100%` to `200%`) plus vertical swipe volume boost and brightness gestures.
- **Live Sources Drawer:** Switch between 20+ IPTV and cloud servers mid-playback with Hindi/Multi-Audio & resolution badges (`1080p`, `4K`, `HDR10`).
- **Advanced Playback Controls:**
  - `15s` Rewind / Fast-Forward (double-tap or HUD buttons).
  - Audio Track & Subtitle / Video Quality selector.
  - Aspect Ratio switcher: `Fit`, `Crop / Zoom` (camera-cutout edge-to-edge), and `Fill`.
  - Playback Speed (`0.75x` – `2.0x`), Picture Modes (`HW Original`), and Screen Lock.

### 📺 Cross-Platform (Mobile & Android TV)
- **Android TV / Google TV Remote Friendly:** Full D-Pad navigation (`Up`, `Down`, `Left`, `Right`, `Center/OK`, `Back`) with landscape orientation protection.
- **Instant Local Caching:** Saves watchlist (`My List`), TMDB key, and Gist URL locally via `SharedPreferences`.

---

## 📂 Project Structure

```text
mobile_version/
├── lib/
│   ├── internal_player.dart                 # Flutter-to-Native CinemaPlayer bridge
│   ├── screens/
│   │   ├── mobile_home_screen.dart          # 5-Slide Banner, Home Rows & 5-Tab Navigation
│   │   ├── catalog_collection_screen.dart   # 200+ All Movies & Web Series (Popular/Latest)
│   │   ├── my_list_screen.dart              # Saved Watchlist / Bookmarks
│   │   ├── search_screen.dart               # Instant TMDB Multi-Search
│   │   └── settings_screen.dart             # Gist URL, TMDB Key & Player Preferences
│   ├── services/
│   │   ├── app_settings_service.dart        # Local configuration & preferences storage
│   │   ├── catalog_service.dart             # Catalog parsers
│   │   ├── native_cinema_player.dart        # Native MethodChannel wrapper
│   │   ├── stream_service.dart              # IPTV & Stremio provider loader
│   │   ├── tmdb_service.dart                # TMDB discover & metadata queries
│   │   └── xtream_service.dart              # Xtream IPTV VOD & Series resolver
│   └── widgets/
│       └── mobile_stream_modal.dart         # Details, Episode Picker & Watch Now Modal
├── android/
│   └── app/
│       ├── build.gradle                     # Android SDK & Media3 dependencies
│       └── src/main/
│           ├── AndroidManifest.xml          # Landscape CinemaPlayer & Cleartext HTTP config
│           └── kotlin/com/primeflix/app/
│               ├── MainActivity.kt          # com.primeflix/player MethodChannel handler
│               └── CinemaPlayerActivity.kt  # Native Media3/ExoPlayer Cinema Player
└── pubspec.yaml                             # Flutter dependencies
```

---

## 🛠️ Build Instructions

```bash
git clone [https://github.com/Rahul6051276/primefilx-.git](https://github.com/Rahul6051276/primefilx-.git)
cd primefilx-/mobile_version
flutter clean
flutter pub get
flutter build apk --release
```

---

## ⚙️ Remote GitHub Gist Configuration (Example Format)

Server providers (Cloud Addons and Xtream IPTV accounts) are dynamically loaded from your private GitHub Gist Raw URL configured inside the **Settings** tab. Use the following sample structure:

```json
{
  "active_providers": [
    {
      "name": "Cloud Stream Server (Example)",
      "type": "stremio",
      "url": "[https://your-cloud-addon.example.com/manifest.json](https://your-cloud-addon.example.com/manifest.json)"
    },
    {
      "name": "IPTV Server (Example)",
      "type": "xtream",
      "xc_host": "[http://your-iptv-host.example.com](http://your-iptv-host.example.com)",
      "xc_username": "YOUR_USERNAME",
      "xc_password": "YOUR_PASSWORD"
    }
  ]
}
```
