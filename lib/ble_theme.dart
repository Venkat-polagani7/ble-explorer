import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ══════════════════════════════════════════════════════════════
// SHARED THEME
// ══════════════════════════════════════════════════════════════
class BleTheme {
  BleTheme._();

  static const Color bg = Color(0xFF0A0E1A);
  static const Color surface = Color(0xFF111827);
  static const Color surfaceCard = Color(0xFF1C2333);
  static const Color surfaceBorder = Color(0xFF2A3347);
  static const Color accent = Color(0xFF3B82F6);
  static const Color accentSecondary = Color(0xFF8B5CF6);
  static const Color accentGreen = Color(0xFF10B981);
  static const Color accentRed = Color(0xFFEF4444);
  static const Color accentOrange = Color(0xFFF59E0B);
  static const Color textPrimary = Color(0xFFE2E8F0);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF4B5563);

  static TextStyle get mono => const TextStyle(
        fontFamily: 'monospace',
        color: textPrimary,
        fontSize: 12,
      );

  static BoxDecoration get cardDecoration => BoxDecoration(
        color: surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: surfaceBorder, width: 1),
      );

  /// Signal strength color: green → yellow → orange → red
  static Color rssiColor(int rssi) {
    if (rssi >= -60) return accentGreen;
    if (rssi >= -75) return accentOrange;
    if (rssi >= -90) return Colors.orange.shade700;
    return accentRed;
  }

  /// Number of bars (1–4) for RSSI
  static int rssiBars(int rssi) {
    if (rssi >= -60) return 4;
    if (rssi >= -70) return 3;
    if (rssi >= -80) return 2;
    return 1;
  }
}

// ══════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ══════════════════════════════════════════════════════════════

class RssiWidget extends StatelessWidget {
  final int rssi;
  const RssiWidget({super.key, required this.rssi});

  @override
  Widget build(BuildContext context) {
    final isInvalid = rssi == 127 || rssi > 0;
    final displayRssi = isInvalid ? 'N/A' : '$rssi dBm';
    final bars = isInvalid ? 0 : BleTheme.rssiBars(rssi);
    final color = isInvalid ? BleTheme.textMuted : BleTheme.rssiColor(rssi);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(4, (i) {
            final active = i < bars;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 5,
              height: 6.0 + i * 4,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: active ? color : BleTheme.surfaceBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
        const SizedBox(height: 2),
        Text(
          displayRssi,
          style: TextStyle(
            fontSize: 9,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class CopyChip extends StatefulWidget {
  final String value;
  final String? label;

  const CopyChip({super.key, required this.value, this.label});

  @override
  State<CopyChip> createState() => _CopyChipState();
}

class _CopyChipState extends State<CopyChip> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _copy,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _copied
              ? BleTheme.accentGreen.withValues(alpha: 0.15)
              : BleTheme.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _copied
                ? BleTheme.accentGreen
                : BleTheme.accent.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _copied ? Icons.check : Icons.copy_rounded,
              size: 12,
              color: _copied ? BleTheme.accentGreen : BleTheme.accent,
            ),
            if (widget.label != null) ...[
              const SizedBox(width: 4),
              Text(
                widget.label!,
                style: TextStyle(
                  fontSize: 11,
                  color: _copied ? BleTheme.accentGreen : BleTheme.accent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Animated button used throughout diagnostics tab
class AnimBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  final bool compact;

  const AnimBtn({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.4,
      duration: const Duration(milliseconds: 200),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
