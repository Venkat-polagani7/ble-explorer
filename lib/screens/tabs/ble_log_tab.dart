import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ble_theme.dart';
import '../../services/ble_log_service.dart';

// ══════════════════════════════════════════════════════════════
// BLE LOG TAB – Real-time log viewer with filtering
// ══════════════════════════════════════════════════════════════

class BleLogTab extends StatefulWidget {
  final BleLogService logService;

  const BleLogTab({super.key, required this.logService});

  @override
  State<BleLogTab> createState() => _BleLogTabState();
}

class _BleLogTabState extends State<BleLogTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  String _searchQuery = '';
  BleLogLevel? _levelFilter;
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    widget.logService.addListener(_onNewLog);
  }

  void _onNewLog() {
    if (!mounted) return;
    setState(() {});
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    widget.logService.removeListener(_onNewLog);
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<BleLogEntry> get _filtered => widget.logService.filter(
        level: _levelFilter,
        query: _searchQuery,
      );

  String _exportText() {
    final entries = _filtered;
    final buf = StringBuffer();
    buf.writeln(
        '════════════════════════════════════════════════════════════');
    buf.writeln('BLE Explorer Log Export');
    buf.writeln('Exported: ${DateTime.now()}');
    buf.writeln('Entries: ${entries.length}');
    buf.writeln(
        '════════════════════════════════════════════════════════════');
    for (final e in entries) {
      buf.writeln(
          '[${e.timeStr}] [${e.levelLabel}] [${e.tag}] ${e.message}');
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final entries = _filtered;

    return Column(
      children: [
        // ── Toolbar ────────────────────────────────────────────
        Container(
          color: BleTheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _searchField()),
                  const SizedBox(width: 8),
                  // Auto-scroll toggle
                  _toolbarBtn(
                    icon: Icons.vertical_align_bottom_rounded,
                    active: _autoScroll,
                    tooltip: 'Auto-scroll',
                    onTap: () =>
                        setState(() => _autoScroll = !_autoScroll),
                  ),
                  const SizedBox(width: 6),
                  // Copy all
                  _toolbarBtn(
                    icon: Icons.copy_all_rounded,
                    active: false,
                    tooltip: 'Copy logs',
                    onTap: () async {
                      await Clipboard.setData(
                          ClipboardData(text: _exportText()));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: BleTheme.surfaceCard,
                            content: Text('Logs copied to clipboard',
                                style: TextStyle(
                                    color: BleTheme.textPrimary)),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                  // Clear
                  _toolbarBtn(
                    icon: Icons.delete_outline,
                    active: false,
                    tooltip: 'Clear logs',
                    onTap: () => widget.logService.clear(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _levelChip(null, 'ALL'),
                    const SizedBox(width: 6),
                    ...BleLogLevel.values.map(
                      (l) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _levelChip(l, l.name.toUpperCase()),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Stats bar ─────────────────────────────────────────
        Container(
          color: BleTheme.bg,
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          child: Row(
            children: [
              Text(
                '${entries.length} / ${widget.logService.entries.length} entries',
                style: const TextStyle(
                    color: BleTheme.textMuted, fontSize: 11),
              ),
              const Spacer(),
              _miniCount(BleLogLevel.error, BleTheme.accentRed),
              const SizedBox(width: 10),
              _miniCount(BleLogLevel.warning, BleTheme.accentOrange),
              const SizedBox(width: 10),
              _miniCount(BleLogLevel.success, BleTheme.accentGreen),
            ],
          ),
        ),

        // ── Log list ──────────────────────────────────────────
        Expanded(
          child: entries.isEmpty
              ? const Center(
                  child: Text('No log entries',
                      style: TextStyle(
                          color: BleTheme.textMuted, fontSize: 13)),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  itemCount: entries.length,
                  itemBuilder: (_, i) => _LogEntryRow(entry: entries[i]),
                ),
        ),
      ],
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchCtrl,
      onChanged: (v) => setState(() => _searchQuery = v),
      style:
          const TextStyle(color: BleTheme.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Search logs…',
        hintStyle:
            const TextStyle(color: BleTheme.textMuted, fontSize: 13),
        prefixIcon: const Icon(Icons.search,
            color: BleTheme.textMuted, size: 18),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close,
                    color: BleTheme.textMuted, size: 16),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
        filled: true,
        fillColor: BleTheme.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: BleTheme.surfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: BleTheme.surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: BleTheme.accent),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
    );
  }

  Widget _toolbarBtn({
    required IconData icon,
    required bool active,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: active ? BleTheme.accent.withValues(alpha: 0.15) : BleTheme.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? BleTheme.accent : BleTheme.surfaceBorder,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? BleTheme.accent : BleTheme.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _levelChip(BleLogLevel? level, String label) {
    final selected = _levelFilter == level;
    final color = level == null
        ? BleTheme.textSecondary
        : BleLogEntry(
                timestamp: DateTime.now(),
                level: level,
                tag: '',
                message: '')
            .levelColor;

    return GestureDetector(
      onTap: () => setState(() => _levelFilter = level),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.2) : BleTheme.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : BleTheme.surfaceBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : BleTheme.textMuted,
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _miniCount(BleLogLevel level, Color color) {
    final count =
        widget.logService.entries.where((e) => e.level == level).length;
    final label = BleLogEntry(
            timestamp: DateTime.now(), level: level, tag: '', message: '')
        .levelLabel
        .trim();
    return Row(
      children: [
        Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text('$label: $count',
            style: TextStyle(color: color, fontSize: 10)),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// LOG ENTRY ROW
// ══════════════════════════════════════════════════════════════

class _LogEntryRow extends StatelessWidget {
  final BleLogEntry entry;

  const _LogEntryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(
          text:
              '[${entry.timeStr}] [${entry.levelLabel}] [${entry.tag}] ${entry.message}',
        ));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: BleTheme.surfaceCard,
            content: Text('Log entry copied',
                style: TextStyle(
                    color: BleTheme.textPrimary, fontSize: 12)),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: entry.levelColor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(5),
          border: Border(
            left: BorderSide(color: entry.levelColor, width: 2.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.timeStr,
              style: const TextStyle(
                color: BleTheme.textMuted,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: entry.levelColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                entry.levelLabel,
                style: TextStyle(
                  color: entry.levelColor,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '[${entry.tag}]',
              style: const TextStyle(
                color: BleTheme.accent,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                entry.message,
                style: const TextStyle(
                  color: BleTheme.textPrimary,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
