import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:lottie/lottie.dart';

import '../../ble_theme.dart';
import '../../services/ble_log_service.dart';

// ══════════════════════════════════════════════════════════════
// SCANNER TAB – nRF Connect-style BLE scanner
// ══════════════════════════════════════════════════════════════

class BleScannerTab extends StatefulWidget {
  final BleLogService logService;
  final void Function(String remoteId) onConnectTap;
  final void Function(String remoteId) onDiagnoseTap;

  const BleScannerTab({
    super.key,
    required this.logService,
    required this.onConnectTap,
    required this.onDiagnoseTap,
  });

  @override
  State<BleScannerTab> createState() => _BleScannerTabState();
}

class _BleScannerTabState extends State<BleScannerTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  bool _isScanning = false;
  bool _filterDuplicates = true;
  int _scanTimeout = 10;
  String _nameFilter = '';
  int? _rssiFilter;
  AndroidScanMode _scanMode = AndroidScanMode.lowLatency;

  final Map<String, ScanResult> _results = {};
  final Map<String, int> _seenCount = {};

  StreamSubscription? _scanSub;
  StreamSubscription? _isScanSub;

  final TextEditingController _nameFilterCtrl = TextEditingController();
  final TextEditingController _rssiCtrl = TextEditingController();
  final TextEditingController _serviceUuidCtrl = TextEditingController();
  bool _showFilters = false;
  String _sortBy = 'time';
  final Map<String, DateTime> _discoveryTime = {};

  @override
  void initState() {
    super.initState();
    _isScanSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (mounted) setState(() => _isScanning = scanning);
    });

    // Auto-start scan similar to nRF Connect when opened, but ONLY if BT is on!
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final state = await FlutterBluePlus.adapterState.first;
      if (state == BluetoothAdapterState.on && mounted) {
        _startScan();
      } else {
        // If it's OFF, wait asynchronously for the user to turn it ON via Control Center/Settings, then trigger scan!
        FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .then((_) {
          if (mounted && !_isScanning) _startScan();
        });
      }
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _isScanSub?.cancel();
    _nameFilterCtrl.dispose();
    _rssiCtrl.dispose();
    _serviceUuidCtrl.dispose();
    // Stop scan if running when tab is disposed
    FlutterBluePlus.stopScan().catchError((_) {});
    super.dispose();
  }

  Future<void> _startScan() async {
    _results.clear();
    _seenCount.clear();
    _discoveryTime.clear();
    widget.logService
        .info('Scan started (timeout: ${_scanTimeout}s)', tag: 'SCAN');

    try {
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();

      _scanSub = FlutterBluePlus.onScanResults.listen((results) {
        for (final r in results) {
          final id = r.device.remoteId.toString();
          _seenCount[id] = (_seenCount[id] ?? 0) + 1;
          _discoveryTime.putIfAbsent(id, () => DateTime.now());

          if (_rssiFilter != null && r.rssi < _rssiFilter!) continue;

          final name = r.device.platformName.isNotEmpty
              ? r.device.platformName
              : r.advertisementData.advName;

          if (_nameFilter.isNotEmpty &&
              !name.toLowerCase().contains(_nameFilter.toLowerCase()) &&
              !id.toLowerCase().contains(_nameFilter.toLowerCase())) {
            continue;
          }

          final targetUuid = _serviceUuidCtrl.text.trim().toLowerCase();
          if (targetUuid.isNotEmpty) {
            final hasUuid = r.advertisementData.serviceUuids
                .any((u) => u.toString().toLowerCase().contains(targetUuid));
            if (!hasUuid) continue; // Filter out if it doesn't have the target UUID
          }

          _results[id] = r;
          widget.logService.debug(
            'Found: ${name.isNotEmpty ? name : id}  RSSI: ${r.rssi} dBm',
            tag: 'SCAN',
          );
        }
        if (mounted) setState(() {});
      });

      await FlutterBluePlus.startScan(
        timeout: Duration(seconds: _scanTimeout),
        continuousUpdates: !_filterDuplicates,
        androidScanMode: _scanMode,
        //withServices: [Guid('5d321206')]
      );
    } catch (e) {
      widget.logService.error('Scan failed: $e', tag: 'SCAN');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BleTheme.accentRed.withValues(alpha: 0.9),
          content: Text('Scan error: $e',
              style: const TextStyle(color: Colors.white)),
        ));
      }
    }
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
    widget.logService.info(
      'Scan stopped. Found ${_results.length} device(s).',
      tag: 'SCAN',
    );
  }

  List<ScanResult> get _sorted {
    final list = _results.values.toList();
    switch (_sortBy) {
      case 'name':
        list.sort((a, b) => _deviceName(a).compareTo(_deviceName(b)));
        break;
      case 'time':
        list.sort((a, b) => (_discoveryTime[a.device.remoteId.toString()] ?? DateTime.now())
            .compareTo(_discoveryTime[b.device.remoteId.toString()] ?? DateTime.now()));
        break;
      case 'rssi':
      default:
        list.sort((a, b) => b.rssi.compareTo(a.rssi));
    }
    return list;
  }

  String _deviceName(ScanResult r) {
    if (r.device.platformName.isNotEmpty) return r.device.platformName;
    if (r.device.advName.isNotEmpty) return r.device.advName;
    if (r.advertisementData.advName.isNotEmpty) {
      return r.advertisementData.advName;
    }
    return 'Unknown Device';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildToolbar(),
        if (_showFilters) _buildFilters(),
        _buildStatsBar(),
        Expanded(child: _buildDeviceList()),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      color: BleTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _isScanning
              ? ElevatedButton.icon(
            onPressed: _stopScan,
            icon: const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
            label: const Text('STOP'),
            style: ElevatedButton.styleFrom(
              backgroundColor: BleTheme.accentRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          )
              : StreamBuilder<BluetoothAdapterState>(
            stream: FlutterBluePlus.adapterState,
            builder: (context, snap) {
              final isOn = snap.data == BluetoothAdapterState.on;
              return ElevatedButton.icon(
                onPressed: isOn ? _startScan : null,
                icon: const Icon(Icons.radar, size: 18),
                label: const Text('SCAN'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: BleTheme.accent,
                  disabledBackgroundColor: BleTheme.surfaceBorder,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: BleTheme.textMuted,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: () =>
                setState(() {
                  _results.clear();
                  _seenCount.clear();
                }),
            icon: const Icon(Icons.delete_sweep_rounded,
                color: BleTheme.textSecondary),
            tooltip: 'Clear results',
          ),
          const Spacer(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, color: BleTheme.textSecondary),
            tooltip: 'Sort By',
            onSelected: (val) => setState(() => _sortBy = val),
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'time',
                  child: Text('Time Discovered${_sortBy == 'time' ? ' (✓)' : ''}')),
              PopupMenuItem(
                  value: 'rssi',
                  child: Text('Signal Strength${_sortBy == 'rssi' ? ' (✓)' : ''}')),
              PopupMenuItem(
                  value: 'name',
                  child: Text('Name${_sortBy == 'name' ? ' (✓)' : ''}')),
            ],
          ),
          IconButton(
            onPressed: () => setState(() => _showFilters = !_showFilters),
            icon: Icon(Icons.tune_rounded,
                color:
                _showFilters ? BleTheme.accent : BleTheme.textSecondary),
            tooltip: 'Filters',
          ),
        ],
      ),
    );
  }



  Widget _buildFilters() {
    return Container(
      color: BleTheme.surfaceCard,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _filterTextField(
                    controller: _serviceUuidCtrl,
                    hint: 'Service UUID (e.g. FFF0)',
                    icon: Icons.vpn_key_rounded,
                    onChanged: (v) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                _timeoutChips(),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _filterTextField(
                    controller: _nameFilterCtrl,
                    hint: 'Filter by name or MAC',
                    icon: Icons.search,
                    onChanged: (v) => setState(() => _nameFilter = v),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('Dupes', style: TextStyle(color: BleTheme.textSecondary, fontSize: 11)),
                Switch(
                  value: !_filterDuplicates,
                  onChanged: (v) => setState(() => _filterDuplicates = !v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.signal_cellular_alt_rounded, color: BleTheme.textMuted, size: 16),
                const SizedBox(width: 8),
                Text('Min RSSI: ${_rssiFilter ?? "Any"}', style: const TextStyle(color: BleTheme.textSecondary, fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _rssiFilter?.toDouble() ?? -100.0,
                    min: -100,
                    max: 0,
                    divisions: 100,
                    activeColor: BleTheme.accent,
                    inactiveColor: BleTheme.surfaceBorder,
                    onChanged: (v) {
                      setState(() {
                        _rssiFilter = v.round();
                        if (_rssiFilter == -100) _rssiFilter = null;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.speed_rounded, color: BleTheme.textMuted, size: 16),
                const SizedBox(width: 8),
                const Text('Mode:', style: TextStyle(color: BleTheme.textSecondary, fontSize: 12)),
                const SizedBox(width: 8),
                Expanded(
                  child: SegmentedButton<AndroidScanMode>(
                    style: SegmentedButton.styleFrom(
                      backgroundColor: BleTheme.bg,
                      selectedBackgroundColor: BleTheme.accent.withValues(alpha: 0.2),
                      foregroundColor: BleTheme.textSecondary,
                      selectedForegroundColor: BleTheme.accent,
                      side: const BorderSide(color: BleTheme.surfaceBorder),
                      textStyle: const TextStyle(fontSize: 10),
                      padding: EdgeInsets.zero,
                    ),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: AndroidScanMode.lowPower, label: Text('Low Power')),
                      ButtonSegment(value: AndroidScanMode.balanced, label: Text('Balanced')),
                      ButtonSegment(value: AndroidScanMode.lowLatency, label: Text('Latency')),
                    ],
                    selected: {_scanMode},
                    onSelectionChanged: (Set<AndroidScanMode> set) {
                      setState(() => _scanMode = set.first);
                      if (_isScanning) _startScan(); // restart with new mode
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _nameFilterCtrl.clear();
                      _serviceUuidCtrl.clear();
                      _nameFilter = '';
                      _rssiFilter = null;
                      _scanTimeout = 10;
                    });
                  },
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                  label: const Text('Clear All'),
                  style: TextButton.styleFrom(
                    foregroundColor: BleTheme.accentRed,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() => _showFilters = false);
                    _startScan();
                  },
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Apply & Scan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BleTheme.accentGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required ValueChanged<String> onChanged,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: keyboardType,
      style: const TextStyle(color: BleTheme.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: BleTheme.textMuted, fontSize: 13),
        prefixIcon: Icon(icon, color: BleTheme.textMuted, size: 18),
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

  Widget _timeoutChips() {
    return Row(
      children: [10, 30, 60].map((sec) {
        final selected = _scanTimeout == sec;
        return GestureDetector(
          onTap: () => setState(() => _scanTimeout = sec),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? BleTheme.accent.withValues(alpha: 0.2)
                  : BleTheme.bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected ? BleTheme.accent : BleTheme.surfaceBorder,
              ),
            ),
            child: Text(
              '${sec}s',
              style: TextStyle(
                fontSize: 12,
                color: selected ? BleTheme.accent : BleTheme.textSecondary,
                fontWeight:
                selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStatsBar() {
    return Container(
      color: BleTheme.bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Text(
            '${_sorted.length} device${_sorted.length == 1 ? '' : 's'} found',
            style: const TextStyle(
                color: BleTheme.textSecondary, fontSize: 12),
          ),
          if (_isScanning) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: BleTheme.accent),
            ),
            const SizedBox(width: 4),
            const Text('Scanning…',
                style: TextStyle(color: BleTheme.accent, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return StreamBuilder<BluetoothAdapterState>(
        stream: FlutterBluePlus.adapterState,
        builder: (context, snap) {
          final isOn = snap.data == BluetoothAdapterState.on;

          if (!isOn && !_isScanning && _sorted.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bluetooth_disabled, size: 64,
                      color: BleTheme.textMuted),
                  SizedBox(height: 16),
                  Text('Scan did not start.',
                      style: TextStyle(color: BleTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text('Permissions missing or Bluetooth is OFF.',
                      style: TextStyle(
                          color: BleTheme.textSecondary, fontSize: 14)),
                ],
              ),
            );
          }

          if (_sorted.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isScanning ? Icons.radar : Icons.bluetooth_disabled,
                    size: 64,
                    color: BleTheme.textMuted,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isScanning
                        ? 'Scanning for devices…'
                        : 'Tap SCAN to start discovery',
                    style: const TextStyle(
                        color: BleTheme.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _sorted.length,
            itemBuilder: (context, index) =>
                _DeviceCard(
                  result: _sorted[index],
                  seenCount:
                  _seenCount[_sorted[index].device.remoteId.toString()] ?? 1,
                  onConnectTap: widget.onConnectTap,
                  onDiagnoseTap: widget.onDiagnoseTap,
                  logService: widget.logService,
                ),
          );
        }
    );
  }
}

// ══════════════════════════════════════════════════════════════
// DEVICE CARD
// ══════════════════════════════════════════════════════════════
class _DeviceCard extends StatefulWidget {
  final ScanResult result;
  final int seenCount;
  final void Function(String) onConnectTap;
  final void Function(String) onDiagnoseTap;
  final BleLogService logService;

  const _DeviceCard({
    required this.result,
    required this.seenCount,
    required this.onConnectTap,
    required this.onDiagnoseTap,
    required this.logService,
  });

  @override
  State<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<_DeviceCard> with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _animCtrl;
  late final Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _expandAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _animCtrl.forward();
    } else {
      _animCtrl.reverse();
    }
  }

  String get _name {
    final r = widget.result;
    if (r.device.platformName.isNotEmpty) return r.device.platformName;
    if (r.device.advName.isNotEmpty) return r.device.advName;
    if (r.advertisementData.advName.isNotEmpty) return r.advertisementData.advName;
    return 'Unknown Device';
  }

  String get _remoteId => widget.result.device.remoteId.toString();
  bool get _isUnknown => _name == 'Unknown Device';



  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final adv = r.advertisementData;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: BleTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _expanded ? BleTheme.accent.withValues(alpha: 0.5) : BleTheme.surfaceBorder,
          width: _expanded ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Lottie.asset('assets/lottie/bluetooth_lottie.json', width: 20, height: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _name,
                          style: TextStyle(
                            color: _isUnknown ? BleTheme.textSecondary : BleTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              _remoteId,
                              style: const TextStyle(
                                color: BleTheme.textSecondary,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 6),
                            CopyChip(value: _remoteId, label: 'COPY'),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 4,
                          children: [
                            if (adv.txPowerLevel != null)
                              _badge(
                                'TX ${adv.txPowerLevel} dBm',
                                BleTheme.textMuted,
                                'Transmit Power: Base signal strength at 1 meter. Used for proximity calculation.',
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              StreamBuilder<BluetoothConnectionState>(
                                stream: widget.result.device.connectionState,
                                builder: (context, snap) {
                                  final connected = snap.data == BluetoothConnectionState.connected;
                                  return _actionBtn(
                                    icon: connected ? Icons.bluetooth_connected : Icons.flash_on_rounded,
                                    label: connected ? 'Connected' : 'Connect',
                                    color: connected ? BleTheme.accentGreen : BleTheme.accent,
                                    onTap: () => widget.onConnectTap(_remoteId),
                                    compact: true,
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              _actionBtn(
                                icon: Icons.bug_report_outlined,
                                label: 'Diagnose',
                                color: BleTheme.accentOrange,
                                onTap: () => widget.onDiagnoseTap(_remoteId),
                                compact: true,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      RssiWidget(rssi: r.rssi),
                      const SizedBox(height: 4),
                      RotationTransition(
                        turns: Tween(begin: 0.0, end: 0.5).animate(_expandAnim),
                        child: const Icon(Icons.keyboard_arrow_down, color: BleTheme.textMuted, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SizeTransition(
            sizeFactor: _expandAnim,
            child: Column(
              children: [
                const Divider(height: 1, color: BleTheme.surfaceBorder),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel('Advertisement Data'),
                      const SizedBox(height: 8),
                      if (adv.serviceUuids.isNotEmpty)
                        _advRow('Service UUIDs', adv.serviceUuids.map((u) => u.toString()).join('\n')),
                      if (adv.serviceData.isNotEmpty)
                        ...adv.serviceData.entries.map((e) => _advRow('Service Data [${e.key}]', _bytesToHex(e.value))),
                      if (adv.manufacturerData.isNotEmpty)
                        ...adv.manufacturerData.entries.map((e) => _advRow('Mfr [0x${e.key.toRadixString(16).toUpperCase().padLeft(4, '0')}]', _bytesToHex(e.value))),
                      
                      const SizedBox(height: 14),
                      _sectionLabel('Raw Advertisement Packet (Hex Dump)'),
                      const SizedBox(height: 8),
                      _rawAdvHexBlock(adv),

                      if (adv.serviceUuids.isEmpty && adv.serviceData.isEmpty && adv.manufacturerData.isEmpty)
                        const Text(
                          'No advertisement data',
                          style: TextStyle(color: BleTheme.textMuted, fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rawAdvHexBlock(AdvertisementData adv) {
    final List<int> rawBytes = [];
    adv.serviceData.forEach((uuid, bytes) {
      rawBytes.addAll(bytes);
    });
    adv.manufacturerData.forEach((id, bytes) {
      rawBytes.addAll([id & 0xFF, (id >> 8) & 0xFF]);
      rawBytes.addAll(bytes);
    });
    
    final hexString = rawBytes.isEmpty ? 'No raw data available' : _bytesToHex(rawBytes);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BleTheme.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BleTheme.surfaceBorder),
      ),
      child: SelectableText(
        hexString,
        style: BleTheme.mono.copyWith(fontSize: 12, color: BleTheme.textPrimary),
      ),
    );
  }

  Widget _badge(String label, Color color, [String? tooltip]) {
    final b = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10)),
    );
    if (tooltip == null) return b;
    return Tooltip(
      message: tooltip,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(10),
      textStyle: const TextStyle(color: Colors.white, fontSize: 11),
      decoration: BoxDecoration(
        color: BleTheme.surfaceCard.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: BleTheme.surfaceBorder),
      ),
      child: b,
    );
  }

  Widget _sectionLabel(String label) => Row(
    children: [
      Container(
        width: 3,
        height: 14,
        decoration: BoxDecoration(color: BleTheme.accent, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(
          color: BleTheme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    ],
  );

  Widget _advRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(color: BleTheme.textMuted, fontSize: 11)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(value, style: BleTheme.mono.copyWith(fontSize: 11)),
        ),
      ],
    ),
  );

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool compact = false,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 6 : 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
}
