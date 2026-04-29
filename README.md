# BLE Explorer

A professional BLE developer toolkit for Android & iOS — scan, inspect, diagnose, and log Bluetooth Low Energy devices.

---

## Features

| Tab | Description |
|-----|-------------|
| 📡 **Scanner** | nRF Connect-style device scanner with RSSI bars, advertisement data, name/RSSI filters |
| 🔬 **Inspector** | Connect → browse GATT services → Read / Write / Notify characteristics |
| 🏋 **Diagnostics** | Repeated connection attempts with retry logic, error classification, and XLSX export |
| 📋 **Logs** | Real-time colour-coded logs with search, level filter, copy-to-clipboard |

---

## Project Structure

```
lib/
├── main.dart                        ← Entry point + permission short-circuit
├── ble_theme.dart                   ← Shared colours, theme, CopyChip, RssiWidget
├── services/
│   ├── ble_log_service.dart         ← Shared live-log singleton
│   └── permission_service.dart      ← Android 12+ / legacy BLE permission helper
└── screens/
    ├── onboarding_screen.dart        ← Animated intro + per-step permission sheet
    ├── home_screen.dart              ← Main TabBar scaffold + BT adapter monitor
    └── tabs/
        ├── ble_scanner_tab.dart
        ├── ble_inspector_tab.dart
        ├── ble_diagnostics_tab.dart
        └── ble_log_tab.dart
```

---

## Setup

### 1. Prerequisites

- Flutter SDK ≥ 3.3.0
- Dart SDK ≥ 3.3.0
- Android Studio / Xcode

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Add Lottie animation (optional but recommended)

Download a BLE/radar Lottie JSON from [LottieFiles.com](https://lottiefiles.com) and place it at:

```
assets/lottie/ble_scan.json
```

If the file is missing, a built-in animated fallback (pulsing rings) is shown automatically.

### 4. Run

```bash
# Android
flutter run

# iOS (requires Mac + Xcode)
flutter run -d <ios_device>
```

---

## Android Permissions

Declared in `android/app/src/main/AndroidManifest.xml`:

| Permission | API Level | Purpose |
|-----------|-----------|---------|
| `BLUETOOTH_SCAN` + `neverForLocation` | 31+ | Discover nearby BLE devices without location |
| `BLUETOOTH_CONNECT` | 31+ | Connect to / communicate with BLE devices |
| `BLUETOOTH_ADVERTISE` | 31+ | Advertise as peripheral (future use) |
| `ACCESS_FINE_LOCATION` | ≤ 30 | Required for BLE scan on Android < 12 |
| `BLUETOOTH` / `BLUETOOTH_ADMIN` | ≤ 30 | Legacy BLE support |

Minimum SDK: **21** (Android 5.0)  
Target SDK: follows Flutter default (34+)

---

## iOS Permissions

Declared in `ios/Runner/Info.plist`:

- `NSBluetoothAlwaysUsageDescription` — required for App Store
- `NSBluetoothPeripheralUsageDescription` — legacy iOS 12
- `NSLocationWhenInUseUsageDescription` — BLE scan on iOS ≤ 12

---

## Onboarding Flow

```
App launch
    │
    ├─ All permissions already granted? ──YES──► HomeScreen (skip onboarding)
    │
    └─ NO ──► OnboardingScreen
                  │
                  └─ Tap "Get Started" ──► Permission bottom sheet
                         │  (step through each permission; user can skip each)
                         └─ Done ──► HomeScreen
```

---

## Diagnostics Export

The Diagnostics tab exports a `.xlsx` file with three sheets:

- **Attempts** — one row per connection attempt
- **Retry Details** — one row per retry within each attempt
- **Summary** — aggregate stats (success rate, error breakdown, durations)

---

## Key Dependencies

| Package | Version | Use |
|---------|---------|-----|
| `flutter_blue_plus` | ^1.32 | BLE scan / connect / GATT |
| `permission_handler` | ^11.3 | Runtime permissions |
| `lottie` | ^3.1 | Onboarding animation |
| `excel` | ^4.0 | XLSX report generation |
| `share_plus` | ^10.0 | Share XLSX via system sheet |
| `intl` | ^0.19 | Date formatting |

---

## Building for Release

### Android

```bash
flutter build apk --release
# or for Play Store:
flutter build appbundle --release
```

### iOS

```bash
flutter build ios --release
# then archive in Xcode
```

---

## License

MIT
