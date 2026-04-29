import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// Centralised BLE permission handling for production.
///
/// Android permission matrix:
///   API 18–22  : No runtime permissions needed (declared in manifest)
///   API 23–30  : ACCESS_FINE_LOCATION (BLE scan requirement)
///   API 31–32  : BLUETOOTH_SCAN + BLUETOOTH_CONNECT
///   API 33+    : BLUETOOTH_SCAN (neverForLocation) + BLUETOOTH_CONNECT
///
/// iOS: handled automatically by CoreBluetooth via Info.plist keys.
///   NSBluetoothAlwaysUsageDescription is required for the App Store.
class PermissionService {
  PermissionService._();

  // ── Public API ──────────────────────────────────────────────────

  /// Returns true when every permission needed for BLE is already granted,
  /// WITHOUT prompting the user. Safe to call at launch.
  static Future<bool> areAllAlreadyGranted() async {
    if (!Platform.isAndroid) return true; // iOS managed by system dialogs
    for (final p in _requiredPermissions) {
      final status = await p.status;
      if (status != PermissionStatus.granted &&
          status != PermissionStatus.limited) {
        return false;
      }
    }
    return true;
  }

  /// Requests all required permissions and returns true if all are granted.
  /// Shows the system permission dialog to the user.
  static Future<bool> areAllGranted() async {
    if (!Platform.isAndroid) return true;
    final perms = await _requiredPermissions.request();
    return perms.values.every(
      (s) => s == PermissionStatus.granted || s == PermissionStatus.limited,
    );
  }

  /// Ordered list of permissions to request one-by-one in the onboarding UI.
  static List<Permission> get orderedOnboardingPermissions {
    if (!Platform.isAndroid) return [];
    final sdk = androidSdkInt;
    if (sdk >= 31) {
      return [Permission.bluetoothScan, Permission.bluetoothConnect];
    } else {
      return [Permission.locationWhenInUse];
    }
  }

  /// Opens the app's system settings page (for permanently denied permissions).
  static Future<void> openSettings() => openAppSettings();

  // ── Internal helpers ────────────────────────────────────────────

  static List<Permission> get _requiredPermissions {
    if (!Platform.isAndroid) return [];
    final sdk = androidSdkInt;
    if (sdk >= 31) {
      // Android 12+ — no location needed for pure BLE with neverForLocation flag
      return [Permission.bluetoothScan, Permission.bluetoothConnect];
    } else {
      // Android 6–11 — location required by the OS to run BLE scans
      return [Permission.locationWhenInUse];
    }
  }

  /// Parses the Android API level from Platform.operatingSystemVersion.
  /// Example string: "Android 13 (API 33)"
  static int get androidSdkInt {
    try {
      final ver = Platform.operatingSystemVersion;
      final match = RegExp(r'API (\d+)').firstMatch(ver);
      if (match != null) return int.tryParse(match.group(1)!) ?? 31;
    } catch (_) {}
    return 31; // Conservative default: assume modern Android
  }

  // ── UI helpers (used in onboarding) ────────────────────────────

  /// Human-readable label for the permission card in onboarding.
  static String labelFor(Permission p) {
    if (p == Permission.bluetoothScan) return 'Bluetooth Scan';
    if (p == Permission.bluetoothConnect) return 'Bluetooth Connect';
    if (p == Permission.bluetoothAdvertise) return 'Bluetooth Advertise';
    if (p == Permission.location ||
        p == Permission.locationWhenInUse ||
        p == Permission.locationAlways) {
      return 'Location (BLE scan)';
    }
    return 'System Permission';
  }

  /// Detailed description for the permission card in onboarding.
  static String descriptionFor(Permission p) {
    if (p == Permission.bluetoothScan) {
      return 'Needed to discover nearby BLE devices.\n'
          'We never use this to determine your location.';
    }
    if (p == Permission.bluetoothConnect) {
      return 'Required to establish connections, read characteristics,\n'
          'and send commands to paired devices.';
    }
    if (p == Permission.location || p == Permission.locationWhenInUse) {
      return 'Android requires location permission to scan for BLE devices\n'
          'on older OS versions. Your location is never stored or shared.';
    }
    return 'Required for BLE functionality.';
  }

  /// Returns true if any permission is permanently denied (user tapped "Never ask again").
  static Future<bool> anyPermanentlyDenied() async {
    if (!Platform.isAndroid) return false;
    for (final p in _requiredPermissions) {
      if (await p.isPermanentlyDenied) return true;
    }
    return false;
  }
}
