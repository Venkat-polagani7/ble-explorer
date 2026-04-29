import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════════════
// BLE LOG SERVICE – Shared singleton across all tabs
// Collects timestamped, tagged log entries for the Logs tab
// ══════════════════════════════════════════════════════════════

enum BleLogLevel { debug, info, success, warning, error }

class BleLogEntry {
  final DateTime timestamp;
  final BleLogLevel level;
  final String tag;
  final String message;

  BleLogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
  });

  String get timeStr {
    final t = timestamp;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
  }

  Color get levelColor {
    switch (level) {
      case BleLogLevel.debug:
        return const Color(0xFF6B7280);
      case BleLogLevel.info:
        return const Color(0xFF3B82F6);
      case BleLogLevel.success:
        return const Color(0xFF10B981);
      case BleLogLevel.warning:
        return const Color(0xFFF59E0B);
      case BleLogLevel.error:
        return const Color(0xFFEF4444);
    }
  }

  String get levelLabel {
    switch (level) {
      case BleLogLevel.debug:
        return 'DBG';
      case BleLogLevel.info:
        return 'INF';
      case BleLogLevel.success:
        return 'OK ';
      case BleLogLevel.warning:
        return 'WRN';
      case BleLogLevel.error:
        return 'ERR';
    }
  }
}

class BleLogService extends ChangeNotifier {
  final List<BleLogEntry> _entries = [];
  List<BleLogEntry> get entries => List.unmodifiable(_entries);

  static const int _maxEntries = 2000;

  void log(
    String message, {
    BleLogLevel level = BleLogLevel.info,
    String tag = 'BLE',
  }) {
    _entries.add(BleLogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
    ));
    // Trim to avoid unbounded growth
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    notifyListeners();
  }

  void debug(String msg, {String tag = 'BLE'}) =>
      log(msg, level: BleLogLevel.debug, tag: tag);
  void info(String msg, {String tag = 'BLE'}) =>
      log(msg, level: BleLogLevel.info, tag: tag);
  void success(String msg, {String tag = 'BLE'}) =>
      log(msg, level: BleLogLevel.success, tag: tag);
  void warning(String msg, {String tag = 'BLE'}) =>
      log(msg, level: BleLogLevel.warning, tag: tag);
  void error(String msg, {String tag = 'BLE'}) =>
      log(msg, level: BleLogLevel.error, tag: tag);

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  List<BleLogEntry> filter({
    BleLogLevel? level,
    String? tag,
    String? query,
  }) {
    return _entries.where((e) {
      if (level != null && e.level != level) return false;
      if (tag != null && tag.isNotEmpty && !e.tag.contains(tag)) return false;
      if (query != null && query.isNotEmpty) {
        final q = query.toLowerCase();
        if (!e.message.toLowerCase().contains(q) &&
            !e.tag.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }
}
