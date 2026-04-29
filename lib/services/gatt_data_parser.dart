// ══════════════════════════════════════════════════════════════
// GATT Data Parser
// Maps standard Bluetooth SIG UUIDs to human-readable parsed values.
// Used in the Inspector tab to show meaningful values alongside raw hex.
// ══════════════════════════════════════════════════════════════

class GattDataParser {
  GattDataParser._();

  /// Returns a human-readable string for well-known GATT characteristics.
  /// Returns null if the UUID is not a known characteristic.
  static String? parse(String uuid, List<int> bytes) {
    if (bytes.isEmpty) return null;

    final shortUuid = _toShortUuid(uuid);

    switch (shortUuid) {
      // Battery Level — 1 byte, 0–100 %
      case '2a19':
        final pct = bytes[0].clamp(0, 100);
        return '$pct% Battery';

      // Heart Rate Measurement — complex
      case '2a37':
        return _parseHeartRate(bytes);

      // Device Name
      case '2a00':
        return _utf8(bytes);

      // Appearance
      case '2a01':
        return _parseAppearance(bytes);

      // Manufacturer Name String
      case '2a29':
        return _utf8(bytes);

      // Model Number String
      case '2a24':
        return _utf8(bytes);

      // Serial Number String
      case '2a25':
        return _utf8(bytes);

      // Hardware Revision String
      case '2a27':
        return _utf8(bytes);

      // Firmware Revision String
      case '2a26':
        return _utf8(bytes);

      // Software Revision String
      case '2a28':
        return _utf8(bytes);

      // System ID
      case '2a23':
        return '0x${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':')}';

      // Temperature Measurement (IEEE-11073)
      case '2a1c':
      case '2a6e': // Temperature (simple)
        return _parseTemperature(bytes);

      // Tx Power Level — 1 signed byte, dBm
      case '2a07':
        final dbm = bytes[0].toSigned(8);
        return '$dbm dBm TX Power';

      // Connection Interval (in 1.25ms units)
      case '2a04':
        if (bytes.length >= 4) {
          final minInterval =
              ((bytes[1] << 8) | bytes[0]) * 1.25;
          final maxInterval =
              ((bytes[3] << 8) | bytes[2]) * 1.25;
          return 'Interval: ${minInterval.toStringAsFixed(2)}–${maxInterval.toStringAsFixed(2)} ms';
        }
        return null;

      // Body Sensor Location
      case '2a38':
        const locations = ['Other', 'Chest', 'Wrist', 'Finger', 'Hand', 'Ear Lobe', 'Foot'];
        final loc = bytes[0];
        return loc < locations.length ? locations[loc] : 'Location: $loc';

      // Alert Level
      case '2a06':
        const levels = ['No Alert', 'Mild Alert', 'High Alert'];
        return bytes[0] < levels.length ? levels[bytes[0]] : null;

      // Blood Pressure Measurement — simplified
      case '2a35':
        if (bytes.length >= 7) {
          final systolic = bytes[1];
          final diastolic = bytes[3];
          return '$systolic/$diastolic mmHg';
        }
        return null;

      // Glucose Measurement — simplified
      case '2a18':
        if (bytes.length >= 4) {
          final val = (bytes[3] << 8) | bytes[2];
          return '${val / 100.0} mmol/L';
        }
        return null;

      default:
        return null;
    }
  }

  // ── Service UUID names ─────────────────────────────────────

  static String? serviceName(String uuid) {
    final s = _toShortUuid(uuid);
    const names = {
      '1800': 'Generic Access',
      '1801': 'Generic Attribute',
      '180a': 'Device Information',
      '180f': 'Battery Service',
      '180d': 'Heart Rate',
      '1810': 'Blood Pressure',
      '1802': 'Immediate Alert',
      '1803': 'Link Loss',
      '1804': 'Tx Power',
      '1809': 'Health Thermometer',
      '181c': 'User Data',
      '181a': 'Environmental Sensing',
      '1816': 'Cycling Speed and Cadence',
      '1818': 'Cycling Power',
      '1814': 'Running Speed and Cadence',
      '1812': 'Human Interface Device',
      '181e': 'Bond Management',
      '181f': 'Continuous Glucose Monitoring',
      '1826': 'Fitness Machine',
    };
    return names[s];
  }

  static String? characteristicName(String uuid) {
    final s = _toShortUuid(uuid);
    const names = {
      '2a00': 'Device Name',
      '2a01': 'Appearance',
      '2a19': 'Battery Level',
      '2a29': 'Manufacturer Name',
      '2a24': 'Model Number',
      '2a25': 'Serial Number',
      '2a27': 'Hardware Revision',
      '2a26': 'Firmware Revision',
      '2a28': 'Software Revision',
      '2a23': 'System ID',
      '2a37': 'Heart Rate Measurement',
      '2a38': 'Body Sensor Location',
      '2a35': 'Blood Pressure',
      '2a07': 'Tx Power Level',
      '2a04': 'Peripheral Preferred Connection Parameters',
      '2a06': 'Alert Level',
      '2a1c': 'Temperature Measurement',
      '2a6e': 'Temperature',
      '2a18': 'Glucose Measurement',
    };
    return names[s];
  }

  // ── Helpers ────────────────────────────────────────────────

  static String _toShortUuid(String uuid) {
    final cleaned = uuid.toLowerCase().replaceAll('-', '');
    // 16-bit short form: 0000xxxx0000100080000805f9b34fb
    if (cleaned.length == 32) {
      return cleaned.substring(4, 8);
    }
    // Already short
    if (cleaned.length == 4) return cleaned;
    // Full custom 128-bit UUID — return as-is
    return cleaned;
  }

  static String _utf8(List<int> bytes) {
    try {
      return String.fromCharCodes(bytes);
    } catch (_) {
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    }
  }

  static String? _parseHeartRate(List<int> bytes) {
    if (bytes.isEmpty) return null;
    final flags = bytes[0];
    final is16bit = (flags & 0x01) != 0;
    int bpm;
    if (is16bit && bytes.length >= 3) {
      bpm = (bytes[2] << 8) | bytes[1];
    } else if (bytes.length >= 2) {
      bpm = bytes[1];
    } else {
      return null;
    }
    return '$bpm BPM';
  }

  static String? _parseAppearance(List<int> bytes) {
    if (bytes.length < 2) return null;
    final value = (bytes[1] << 8) | bytes[0];
    const appearances = {
      0: 'Unknown',
      64: 'Phone',
      128: 'Computer',
      192: 'Watch',
      193: 'Sports Watch',
      256: 'Clock',
      320: 'Display',
      384: 'Remote Control',
      448: 'Eye Glasses',
      512: 'Tag',
      576: 'Keyring',
      640: 'Media Player',
      704: 'Barcode Scanner',
      768: 'Thermometer',
      832: 'Heart Rate Sensor',
      896: 'Blood Pressure',
      960: 'HID Generic',
      961: 'Keyboard',
      962: 'Mouse',
      963: 'Joystick',
      964: 'Gamepad',
      1088: 'Glucose Meter',
      1152: 'Running Walking Sensor',
      1216: 'Cycling',
    };
    return appearances[value] ?? 'Appearance: 0x${value.toRadixString(16).padLeft(4, '0')}';
  }

  static String? _parseTemperature(List<int> bytes) {
    if (bytes.length < 2) return null;
    try {
      final raw = (bytes[1] << 8) | bytes[0];
      final temp = raw / 100.0;
      return '${temp.toStringAsFixed(1)} °C';
    } catch (_) {
      return null;
    }
  }
}
