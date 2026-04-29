import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' hide License;
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp show License;

import '../../ble_theme.dart';
import '../../services/ble_log_service.dart';
import '../../services/dfu_service.dart';
import '../../services/gatt_data_parser.dart';
import 'package:file_picker/file_picker.dart';

// ══════════════════════════════════════════════════════════════
// BLE INSPECTOR TAB
// Connect → Services → Characteristics → Read / Write / Notify
// ══════════════════════════════════════════════════════════════

class BleInspectorTab extends StatefulWidget {
  final BleLogService logService;
  final String initialRemoteId;

  const BleInspectorTab({
    super.key,
    required this.logService,
    required this.initialRemoteId,
  });

  @override
  State<BleInspectorTab> createState() => _BleInspectorTabState();
}

class _BleInspectorTabState extends State<BleInspectorTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _idCtrl = TextEditingController();

  BluetoothDevice? _device;
  bool _connecting = false;
  bool _connected = false;
  bool _manualDisconnect = false;
  List<BluetoothService> _services = [];
  StreamSubscription? _connStateSub;

  final Map<String, StreamSubscription> _notifySubs = {};
  final Map<String, List<int>> _charValues = {};
  final Map<String, TextEditingController> _writeCtrl = {};
  String _payloadFormat = 'HEX';
  bool _isRecording = false;
  final List<String> _macroSteps = [];
  DateTime? _lastActionTime;
  late final DfuService _dfuService;

  String get _cleanRemoteId {
    if (widget.initialRemoteId.contains('|')) {
      return widget.initialRemoteId.split('|').first;
    }
    return widget.initialRemoteId;
  }

  @override
  void initState() {
    super.initState();
    _dfuService = DfuService(widget.logService);
    final id = _cleanRemoteId;
    _idCtrl.text = id;
    if (id.isNotEmpty) {
      _connect();
    }
  }

  @override
  void didUpdateWidget(BleInspectorTab old) {
    super.didUpdateWidget(old);
    if (widget.initialRemoteId != old.initialRemoteId &&
        _cleanRemoteId.isNotEmpty) {
      _idCtrl.text = _cleanRemoteId;
      _connect();
    }
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _dfuService.dispose();
    for (final s in _notifySubs.values) {
      s.cancel();
    }
    for (final c in _writeCtrl.values) {
      c.dispose();
    }
    _connStateSub?.cancel();
    super.dispose();
  }

  // ── connect ────────────────────────────────────────────────

  String _friendlyError(dynamic e) {
    final s = e.toString().toLowerCase();
    if (s.contains('timeout')) return 'Device didn\'t respond. It may be sleeping or out of range.';
    if (s.contains('133') || s.contains('0x85')) return 'Device abruptly closed the connection. Hardware might be busy.';
    if (s.contains('not connectable')) return 'Device is locked and rejecting connections.';
    return 'Connection failed to establish.';
  }

  Future<void> _connect() async {
    final id = _idCtrl.text.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: BleTheme.accentOrange,
        content: Text('Enter a device MAC / Remote ID first.',
            style: TextStyle(color: Colors.white)),
      ));
      return;
    }

    if (_device != null && (_connected || _connecting)) {
      try {
        await _device!.disconnect();
      } catch (_) {}
    }

    setState(() {
      _connecting = true;
      _services = [];
      _connected = false;
      _manualDisconnect = false;
      _charValues.clear();
      _isRecording = false;
    });

    widget.logService.info('Connecting to $id…', tag: 'INSPECT');
    final stopwatch = Stopwatch()..start();

    try {
      // STOP SCAN before connecting to ensure radio resources are focused on connection
      await FlutterBluePlus.stopScan().catchError((_) {});
      
      _device = BluetoothDevice.fromId(id);

      _connStateSub?.cancel();
      _connStateSub = _device!.connectionState.listen((state) {
        final connected = state == BluetoothConnectionState.connected;
        if (mounted) setState(() => _connected = connected);
        widget.logService
            .info('Connection state: ${state.name}', tag: 'INSPECT');
        if (!connected && mounted) {
          setState(() => _services = []);
          if (!_connecting && !_manualDisconnect) {
             ScaffoldMessenger.of(context).clearSnackBars(); // Prevent queueing
             ScaffoldMessenger.of(context).showSnackBar(SnackBar(
               backgroundColor: BleTheme.accentRed.withValues(alpha: 0.9),
               content: const Text(
                   '⚠️ Device disconnected unexpectedly.',
                   style: TextStyle(color: Colors.white)),
             ));
          }
        }
      });

      try {
        await _device!.connect(autoConnect: false, timeout: const Duration(seconds: 15), license: fbp.License.free);
        
        // Request high connection priority on Android to prevent timeouts
        if (Theme.of(context).platform == TargetPlatform.android) {
          try {
            await _device!.requestConnectionPriority(connectionPriorityRequest: ConnectionPriority.high);
            widget.logService.info('Requested high connection priority', tag: 'SYS');
          } catch (_) {} // Ignore if not supported
        }
        
      } catch (e) {
        rethrow;
      }

      widget.logService.success('Connected to $id', tag: 'INSPECT');

      widget.logService.info('Discovering services…', tag: 'INSPECT');
      final services = await _device!.discoverServices();
      stopwatch.stop();
      
      widget.logService.success(
          'Found ${services.length} service(s) in ${stopwatch.elapsed.inMilliseconds / 1000}s', tag: 'INSPECT');

      if (mounted) {
        setState(() => _services = services);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BleTheme.accentGreen,
          content: Text('✅ Connected in ${stopwatch.elapsed.inMilliseconds / 1000}s',
              style: const TextStyle(color: Colors.white)),
        ));
      }
    } catch (e) {
      widget.logService.error('Connect failed: $e', tag: 'INSPECT');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BleTheme.accentRed.withValues(alpha: 0.9),
          content: Text('❌ ${_friendlyError(e)}',
              style: const TextStyle(color: Colors.white)),
        ));
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() async {
    _manualDisconnect = true;
    for (final s in _notifySubs.values) {
      s.cancel();
    }
    _notifySubs.clear();
    await _device?.disconnect().catchError((_) {});
    widget.logService.info('Disconnected', tag: 'INSPECT');
    if (mounted) {
      setState(() {
        _connected = false;
        _services = [];
        _charValues.clear();
        _isRecording = false;
      });
    }
  }

  // ── read ───────────────────────────────────────────────────

  Future<void> _readChar(BluetoothCharacteristic c) async {
    try {
      final value = await c.read();
      if (_isRecording) {
        _recordWait();
        _macroSteps.add('READ ${_fullUuid(c.uuid.toString())}');
      }
      widget.logService.info(
          'READ [${_fullUuid(c.uuid.toString())}] HEX: ${_bytesToHex(value)}',
          tag: 'INSPECT');
      setState(() => _charValues[c.uuid.toString()] = value);
    } catch (e) {
      widget.logService.error('Read failed: $e', tag: 'INSPECT');
    }
  }

  // ── write ──────────────────────────────────────────────────

  Future<void> _writeChar(
    BluetoothCharacteristic c,
    String hexStr, {
    bool? withResponse,
  }) async {
    try {
      final bytes = _hexToBytes(hexStr);
      if (bytes.isEmpty) {
        widget.logService.warning('Write aborted: empty byte string',
            tag: 'INSPECT');
        return;
      }
      
      bool withoutResp = !c.properties.write;
      if (withResponse != null) {
        withoutResp = !withResponse;
      }
      
      await c.write(
        bytes, 
        withoutResponse: withoutResp,
        allowLongWrite: !withoutResp, // Some devices require this for normal writes
      );
      if (_isRecording) {
        _recordWait();
        _macroSteps.add('WRITE ${_fullUuid(c.uuid.toString())} $hexStr');
      }
      widget.logService.success(
          'WRITE [${_fullUuid(c.uuid.toString())}] → ${_bytesToHex(bytes)}',
          tag: 'INSPECT');
          
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BleTheme.accentGreen,
          content: Text('✅ Successfully wrote: ${_bytesToHex(bytes)}',
              style: const TextStyle(color: Colors.white)),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      widget.logService.error('Write failed: $e', tag: 'INSPECT');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BleTheme.accentRed,
          content: Text('❌ Write failed: $e',
              style: const TextStyle(color: Colors.white)),
        ));
      }
    }
  }

  // ── notify ─────────────────────────────────────────────────

  Future<void> _toggleNotify(BluetoothCharacteristic c) async {
    final uuid = c.uuid.toString();
    if (_notifySubs.containsKey(uuid)) {
      await _notifySubs[uuid]?.cancel();
      _notifySubs.remove(uuid);
      await c.setNotifyValue(false).catchError((_) => false);
      widget.logService.info(
          'Notifications OFF [${_fullUuid(uuid)}]', tag: 'INSPECT');
    } else {
      await c.setNotifyValue(true);
      _notifySubs[uuid] = c.lastValueStream.listen((value) {
        final hex = _bytesToHex(value);
        widget.logService.debug(
            'NOTIFY [${_fullUuid(uuid)}] HEX: $hex',
            tag: 'NOTIFY');
        if (mounted) {
          setState(() => _charValues[uuid] = value);
        }
      });
      widget.logService.info(
          'Notifications ON [${_fullUuid(uuid)}]', tag: 'INSPECT');
    }
    if (mounted) setState(() {});
  }

  void _recordWait() {
    if (_lastActionTime != null) {
      final diff = DateTime.now().difference(_lastActionTime!).inMilliseconds;
      if (diff > 100) {
        _macroSteps.add('WAIT $diff');
      }
    }
    _lastActionTime = DateTime.now();
  }

  bool _mtuRequested = false;
  int _phyRequested = 1; // 1 = 1M, 2 = 2M

  void _showRssiGraph() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: BleTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('RSSI Graph', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const SizedBox(
              height: 200,
              child: Center(child: Text('Live RSSI Graphing coming in v1.1', style: TextStyle(color: BleTheme.textSecondary))),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showThroughput() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: BleTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Live Throughput', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const SizedBox(
              height: 200,
              child: Center(child: Text('Throughput Monitor coming in v1.1', style: TextStyle(color: BleTheme.textSecondary))),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showAdvancedSettings() {
    if (!_connected || _device == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: BleTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Advanced Link Settings', style: TextStyle(color: BleTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.sync_alt, size: 16),
                      label: Text(_mtuRequested ? 'MTU 512 (Req)' : 'Request MTU 512'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _mtuRequested ? BleTheme.accentGreen.withValues(alpha: 0.2) : BleTheme.surfaceCard, 
                        foregroundColor: _mtuRequested ? BleTheme.accentGreen : BleTheme.textPrimary,
                      ),
                      onPressed: () async {
                        try {
                          await _device!.requestMtu(512);
                          setSheetState(() => _mtuRequested = true);
                          setState(() {});
                          widget.logService.success('MTU requested: 512', tag: 'SYS');
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('MTU requested: 512', style: TextStyle(color: Colors.white)), backgroundColor: BleTheme.accentGreen));
                        } catch (e) {
                          widget.logService.error('MTU request failed: $e', tag: 'SYS');
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('MTU failed: $e', style: const TextStyle(color: Colors.white)), backgroundColor: BleTheme.accentRed));
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.speed, size: 16),
                      label: Text(_phyRequested == 2 ? 'PHY 2M (Req)' : 'Request PHY 2M'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _phyRequested == 2 ? BleTheme.accentGreen.withValues(alpha: 0.2) : BleTheme.surfaceCard, 
                        foregroundColor: _phyRequested == 2 ? BleTheme.accentGreen : BleTheme.textPrimary,
                      ),
                      onPressed: () async {
                        try {
                          int targetPhy = _phyRequested == 2 ? 1 : 2; // Toggle
                          await _device!.setPreferredPhy(txPhy: targetPhy, rxPhy: targetPhy, option: PhyCoding.noPreferred);
                          setSheetState(() => _phyRequested = targetPhy);
                          setState(() {});
                          widget.logService.success('PHY requested: ${targetPhy}M', tag: 'SYS');
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PHY requested: ${targetPhy}M', style: const TextStyle(color: Colors.white)), backgroundColor: BleTheme.accentGreen));
                        } catch (e) {
                          widget.logService.error('PHY request failed: $e', tag: 'SYS');
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PHY failed: $e', style: const TextStyle(color: Colors.white)), backgroundColor: BleTheme.accentRed));
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startDfu() async {
    if (!_connected || _device == null) return;
    
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      
      if (result == null || result.files.single.path == null) return;
      if (!mounted) return;
      
      final path = result.files.single.path!;
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _DfuDialog(dfuService: _dfuService, deviceId: _device!.remoteId.str, filePath: path),
      );
    } catch (e) {
      widget.logService.error('FilePicker error: $e', tag: 'DFU');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to open file picker: $e'), backgroundColor: BleTheme.accentRed));
      }
    }
  }

  void _showMacroSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: BleTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _MacroSheet(
        initialScript: _macroSteps.join('\n'),
        onPlay: (script) async {
          Navigator.pop(ctx);
          await _playMacro(script);
        },
      ),
    );
  }

  Future<void> _playMacro(String script) async {
    final lines = script.split('\n');
    widget.logService.info('▶️ Playing Macro (${lines.length} steps)', tag: 'MACRO');
    for (int i=0; i<lines.length; i++) {
      if (!mounted || !_connected) break;
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('//')) continue;
      
      final parts = line.split(' ');
      final cmd = parts[0].toUpperCase();
      
      try {
        if (cmd == 'WAIT') {
          final ms = int.parse(parts[1]);
          await Future.delayed(Duration(milliseconds: ms));
        } else if (cmd == 'READ') {
          final uuid = parts[1];
          final c = _findChar(uuid);
          if (c != null) {
            await _readChar(c);
          } else {
            widget.logService.error('Char not found: $uuid', tag: 'MACRO');
          }
        } else if (cmd == 'WRITE') {
          final uuid = parts[1];
          final hex = parts.sublist(2).join(' ');
          final c = _findChar(uuid);
          if (c != null) {
            await _writeChar(c, hex, withResponse: true); // Macros assume withResponse for safety
          } else {
            widget.logService.error('Char not found: $uuid', tag: 'MACRO');
          }
        }
      } catch (e) {
        widget.logService.error('Error on line ${i+1}: $line -> $e', tag: 'MACRO');
        break; 
      }
    }
    widget.logService.success('⏹️ Macro Finished', tag: 'MACRO');
  }

  BluetoothCharacteristic? _findChar(String uuid) {
    final target = uuid.toLowerCase();
    for (final s in _services) {
      for (final c in s.characteristics) {
        if (c.uuid.toString().toLowerCase() == target) return c;
      }
    }
    return null;
  }

  Widget _macroBtn({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(6),
          color: color.withValues(alpha: 0.1),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // ── UI ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildConnectBar(),
        if (_connected) _buildConnectionInfo(),
        Expanded(
          child: _services.isEmpty
              ? _buildEmptyState()
              : _buildServiceList(),
        ),
      ],
    );
  }

  Widget _buildConnectBar() {
    return Container(
      color: BleTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _idCtrl,
              style: BleTheme.mono.copyWith(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Device MAC / Remote ID',
                hintStyle: const TextStyle(
                    color: BleTheme.textMuted, fontSize: 13),
                prefixIcon: const Icon(Icons.bluetooth,
                    color: BleTheme.textMuted, size: 18),
                filled: true,
                fillColor: BleTheme.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: BleTheme.surfaceBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: BleTheme.surfaceBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: BleTheme.accent),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste_rounded,
                      color: BleTheme.textMuted, size: 18),
                  onPressed: () async {
                    final d = await Clipboard.getData('text/plain');
                    if (d?.text != null) {
                      _idCtrl.text = d!.text!.trim();
                    }
                  },
                  tooltip: 'Paste',
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _connecting
                ? const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: BleTheme.accent),
                  )
                : _connected
                    ? ElevatedButton(
                        onPressed: _disconnect,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: BleTheme.accentRed,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        child: const Text('DISCONNECT',
                            style: TextStyle(fontSize: 12)),
                      )
                    : ElevatedButton(
                        onPressed: _connect,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: BleTheme.accentGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        child: const Text('CONNECT',
                            style: TextStyle(fontSize: 12)),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionInfo() {
    return Container(
      color: BleTheme.accentGreen.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.circle, color: BleTheme.accentGreen, size: 10),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Connected  •  ${_services.length} service(s)',
                  style: const TextStyle(color: BleTheme.accentGreen, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              CopyChip(value: _idCtrl.text.trim()),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text('Format:', style: TextStyle(color: BleTheme.textMuted, fontSize: 11)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _payloadFormat,
                  dropdownColor: BleTheme.surfaceCard,
                  style: const TextStyle(color: BleTheme.accent, fontSize: 11, fontWeight: FontWeight.bold),
                  icon: const Icon(Icons.arrow_drop_down, color: BleTheme.accent, size: 16),
                  underline: const SizedBox(),
                  isDense: true,
                  onChanged: (v) {
                    if (v != null && mounted) setState(() => _payloadFormat = v);
                  },
                  items: const [
                    DropdownMenuItem(value: 'HEX', child: Text('HEX')),
                    DropdownMenuItem(value: 'ASCII', child: Text('ASCII')),
                    DropdownMenuItem(value: 'Int8', child: Text('Int8')),
                    DropdownMenuItem(value: 'Uint16', child: Text('Uint16 (LE)')),
                    DropdownMenuItem(value: 'Float32', child: Text('Float32 (LE)')),
                  ],
                ),
                const SizedBox(width: 16),
                _macroBtn(
                  icon: _isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
                  label: _isRecording ? 'Stop REC' : 'Record',
                  color: _isRecording ? BleTheme.accentRed : BleTheme.textSecondary,
                  onTap: () {
                    setState(() {
                      _isRecording = !_isRecording;
                      if (_isRecording) {
                        _macroSteps.clear();
                        _lastActionTime = DateTime.now();
                        widget.logService.info('⏺️ Recording started', tag: 'MACRO');
                      } else {
                        widget.logService.info('⏹️ Recording stopped (${_macroSteps.length} steps)', tag: 'MACRO');
                        if (_macroSteps.isNotEmpty) _showMacroSheet();
                      }
                    });
                  },
                ),
                const SizedBox(width: 8),
                _macroBtn(
                  icon: Icons.system_update_alt,
                  label: 'DFU Update',
                  color: Colors.blueAccent,
                  onTap: _startDfu,
                ),
                const SizedBox(width: 8),
                _macroBtn(
                  icon: Icons.settings_ethernet,
                  label: 'MTU/PHY',
                  color: BleTheme.accentOrange,
                  onTap: _showAdvancedSettings,
                ),
                const SizedBox(width: 8),
                _macroBtn(
                  icon: Icons.show_chart,
                  label: 'RSSI Graph',
                  color: BleTheme.accentSecondary,
                  onTap: _showRssiGraph,
                ),
                const SizedBox(width: 8),
                _macroBtn(
                  icon: Icons.speed,
                  label: 'Throughput',
                  color: const Color(0xFF00D4AA),
                  onTap: _showThroughput,
                ),
                const SizedBox(width: 8),
                _macroBtn(
                  icon: Icons.code_rounded,
                  label: 'Scripts',
                  color: BleTheme.accent,
                  onTap: _showMacroSheet,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _connected
                ? Icons.hourglass_empty_rounded
                : Icons.bluetooth_disabled,
            size: 64,
            color: BleTheme.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            _connecting
                ? 'Connecting and discovering services…'
                : _connected
                    ? 'No services found'
                    : 'Enter a MAC address and tap CONNECT\nor pick a device from the Scanner tab',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: BleTheme.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _services.length,
      itemBuilder: (_, i) => _ServiceTile(
        service: _services[i],
        charValues: _charValues,
        notifyActive: _notifySubs.keys.toSet(),
        writeCtrl: _writeCtrl,
        payloadFormat: _payloadFormat,
        onRead: _readChar,
        onWrite: _writeChar,
        onToggleNotify: _toggleNotify,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// DFU DIALOG
// ══════════════════════════════════════════════════════════════

class _DfuDialog extends StatefulWidget {
  final DfuService dfuService;
  final String deviceId;
  final String filePath;

  const _DfuDialog({required this.dfuService, required this.deviceId, required this.filePath});

  @override
  State<_DfuDialog> createState() => _DfuDialogState();
}

class _DfuDialogState extends State<_DfuDialog> {
  @override
  void initState() {
    super.initState();
    widget.dfuService.startDfu(widget.deviceId, widget.filePath);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: BleTheme.surfaceCard,
      title: const Text('Firmware Update (DFU)', style: TextStyle(color: BleTheme.textPrimary, fontSize: 16)),
      content: StreamBuilder<DfuState>(
        stream: widget.dfuService.updates,
        builder: (ctx, snap) {
          final state = widget.dfuService.state;
          final progress = widget.dfuService.progress;
          final error = widget.dfuService.error;

          if (state == DfuState.error) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error, color: BleTheme.accentRed, size: 48),
                const SizedBox(height: 16),
                Text('Update failed: $error', style: const TextStyle(color: BleTheme.accentRed)),
              ],
            );
          }

          if (state == DfuState.completed) {
            return const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: BleTheme.accentGreen, size: 48),
                SizedBox(height: 16),
                Text('Update completed successfully!', style: TextStyle(color: BleTheme.accentGreen)),
              ],
            );
          }

          if (state == DfuState.aborted) {
            return const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cancel, color: BleTheme.textMuted, size: 48),
                SizedBox(height: 16),
                Text('Update aborted.', style: TextStyle(color: BleTheme.textMuted)),
              ],
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(state.name.toUpperCase(), style: const TextStyle(color: BleTheme.accent, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: progress / 100, backgroundColor: BleTheme.surfaceBorder, color: BleTheme.accent),
              const SizedBox(height: 8),
              Text('$progress%', style: const TextStyle(color: BleTheme.textSecondary)),
            ],
          );
        },
      ),
      actions: [
        StreamBuilder<DfuState>(
          stream: widget.dfuService.updates,
          builder: (ctx, snap) {
            final state = widget.dfuService.state;
            final canAbort = state == DfuState.starting || state == DfuState.uploading || state == DfuState.validating;
            
            if (canAbort) {
              return TextButton(
                onPressed: () => widget.dfuService.abortDfu(),
                child: const Text('ABORT', style: TextStyle(color: BleTheme.accentRed)),
              );
            } else {
              return TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CLOSE', style: TextStyle(color: BleTheme.textPrimary)),
              );
            }
          },
        ),
      ],
    );
  }
}

// ── helpers ────────────────────────────────────────────────

String _fullUuid(String uuid) {
  String u = uuid.toLowerCase();
  if (u.length == 4) return '0000$u-0000-1000-8000-00805f9b34fb';
  if (u.length == 8) return '$u-0000-1000-8000-00805f9b34fb';
  return u;
}

String _bytesToHex(List<int> b) =>
    b.map((v) => v.toRadixString(16).padLeft(2, '0')).join(' ').toUpperCase();

List<int> _hexToBytes(String hex) {
  final clean = hex.replaceAll(RegExp(r'[\s:]+'), '');
  if (clean.isEmpty || clean.length % 2 != 0) return [];
  final result = <int>[];
  for (int i = 0; i < clean.length - 1; i += 2) {
    result.add(int.parse(clean.substring(i, i + 2), radix: 16));
  }
  return result;
}

// ══════════════════════════════════════════════════════════════
// SERVICE TILE
// ══════════════════════════════════════════════════════════════
class _ServiceTile extends StatefulWidget {
  final BluetoothService service;
  final Map<String, List<int>> charValues;
  final Set<String> notifyActive;
  final Map<String, TextEditingController> writeCtrl;
  final String payloadFormat;
  final Future<void> Function(BluetoothCharacteristic) onRead;
  final Future<void> Function(BluetoothCharacteristic, String,
      {bool withResponse}) onWrite;
  final Future<void> Function(BluetoothCharacteristic) onToggleNotify;

  const _ServiceTile({
    required this.service,
    required this.charValues,
    required this.notifyActive,
    required this.writeCtrl,
    required this.payloadFormat,
    required this.onRead,
    required this.onWrite,
    required this.onToggleNotify,
  });

  @override
  State<_ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends State<_ServiceTile> {
  bool _expanded = true;


  @override
  Widget build(BuildContext context) {
    final s = widget.service;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BleTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color:
                          BleTheme.accentSecondary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                        Icons.miscellaneous_services_rounded,
                        color: BleTheme.accentSecondary,
                        size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _gattServiceName(s.uuid.toString()) ??
                              'Unknown Service',
                          style: const TextStyle(
                            color: BleTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _fullUuid(s.uuid.toString()).toUpperCase(),
                                style: BleTheme.mono.copyWith(
                                    fontSize: 10,
                                    color: BleTheme.textMuted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            CopyChip(
                                value: _fullUuid(s.uuid.toString()).toUpperCase()),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${s.characteristics.length} char',
                          style: const TextStyle(
                              color: BleTheme.textMuted, fontSize: 11)),
                      const SizedBox(width: 4),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: BleTheme.textMuted,
                        size: 18,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            ...s.characteristics.map((c) => _CharacteristicTile(
                  char: c,
                  charValues: widget.charValues,
                  notifyActive: widget.notifyActive,
                  writeCtrl: widget.writeCtrl,
                  payloadFormat: widget.payloadFormat,
                  onRead: widget.onRead,
                  onWrite: widget.onWrite,
                  onToggleNotify: widget.onToggleNotify,
                )),
        ],
      ),
    );
  }

  String? _gattServiceName(String uuid) {
    // First try the GattDataParser which has a full Bluetooth SIG list
    final parsed = GattDataParser.serviceName(uuid);
    if (parsed != null) return parsed;
    // Fallback for custom UUIDs
    final id = uuid.length >= 8
        ? uuid.substring(4, 8).toUpperCase()
        : uuid.toUpperCase();
    const custom = {
      'FFF0': 'Custom (FFF0)',
      'FFE0': 'Custom (FFE0)',
    };
    return custom[id] ?? 'Unknown Service';
  }
}

// ══════════════════════════════════════════════════════════════
// CHARACTERISTIC TILE
// ══════════════════════════════════════════════════════════════
class _CharacteristicTile extends StatefulWidget {
  final BluetoothCharacteristic char;
  final Map<String, List<int>> charValues;
  final Set<String> notifyActive;
  final Map<String, TextEditingController> writeCtrl;
  final String payloadFormat;
  final Future<void> Function(BluetoothCharacteristic) onRead;
  final Future<void> Function(BluetoothCharacteristic, String,
      {bool withResponse}) onWrite;
  final Future<void> Function(BluetoothCharacteristic) onToggleNotify;

  const _CharacteristicTile({
    required this.char,
    required this.charValues,
    required this.notifyActive,
    required this.writeCtrl,
    required this.payloadFormat,
    required this.onRead,
    required this.onWrite,
    required this.onToggleNotify,
  });

  @override
  State<_CharacteristicTile> createState() => _CharacteristicTileState();
}

class _CharacteristicTileState extends State<_CharacteristicTile> {
  bool _loading = false;

  String get _uuid => widget.char.uuid.toString();
  String get _shortId => _fullUuid(_uuid).toUpperCase();

  Future<void> _action(Future<void> Function() fn) async {
    setState(() => _loading = true);
    await fn();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.char;
    final props = c.properties;
    final notifyOn = widget.notifyActive.contains(_uuid);
    final rawValue = widget.charValues[_uuid];
    String? displayValue;
    if (rawValue != null && rawValue.isNotEmpty) {
      if (widget.payloadFormat == 'HEX') {
        displayValue = rawValue.map((v) => v.toRadixString(16).padLeft(2, '0')).join(' ').toUpperCase();
      } else if (widget.payloadFormat == 'ASCII') {
        displayValue = String.fromCharCodes(rawValue.where((v) => v >= 32 && v < 127)).trim();
        if (displayValue.isEmpty) displayValue = '<non-printable ASCII>';
      } else if (widget.payloadFormat == 'Int8') {
        displayValue = rawValue.map((v) => v > 127 ? v - 256 : v).join(', ');
      } else if (widget.payloadFormat == 'Uint16') {
        if (rawValue.length >= 2) {
          final bd = ByteData.sublistView(Uint8List.fromList(rawValue));
          List<int> vals = [];
          for (int i=0; i<rawValue.length-1; i+=2) {
            vals.add(bd.getUint16(i, Endian.little));
          }
          displayValue = vals.join(', ');
        } else {
          displayValue = 'Insufficient bytes';
        }
      } else if (widget.payloadFormat == 'Float32') {
        if (rawValue.length >= 4) {
          final bd = ByteData.sublistView(Uint8List.fromList(rawValue));
          List<double> vals = [];
          for (int i=0; i<rawValue.length-3; i+=4) {
            vals.add(bd.getFloat32(i, Endian.little));
          }
          displayValue = vals.map((v) => v.toStringAsFixed(3)).join(', ');
        } else {
          displayValue = 'Insufficient bytes';
        }
      }
    }
    
    widget.writeCtrl.putIfAbsent(_uuid, () => TextEditingController());

    return Container(
      margin: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
      decoration: BoxDecoration(
        color: BleTheme.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: notifyOn
              ? BleTheme.accentGreen.withValues(alpha: 0.4)
              : BleTheme.surfaceBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune,
                    size: 14, color: BleTheme.accentOrange),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _gattCharName(_uuid) ?? _shortId,
                    style: const TextStyle(
                      color: BleTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                CopyChip(value: _fullUuid(_uuid).toUpperCase()),
              ],
            ),
            const SizedBox(height: 4),
            Text(_fullUuid(_uuid).toUpperCase(),
                style: BleTheme.mono
                    .copyWith(fontSize: 10, color: BleTheme.textMuted)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (props.read) _propBadge('READ', BleTheme.accent),
                if (props.write)
                  _propBadge('WRITE', BleTheme.accentOrange),
                if (props.writeWithoutResponse)
                  _propBadge('WRITE NR', Colors.deepOrange),
                if (props.notify)
                  _propBadge('NOTIFY', BleTheme.accentGreen),
                if (props.indicate)
                  _propBadge('INDICATE', BleTheme.accentGreen),
                if (props.broadcast)
                  _propBadge('BROADCAST', BleTheme.textMuted),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (props.read)
                  _iconBtn(
                    icon: Icons.download_rounded,
                    label: 'Read',
                    color: BleTheme.accent,
                    loading: _loading,
                    onTap: () => _action(() => widget.onRead(c)),
                  ),
                if (props.notify || props.indicate) ...[
                  const SizedBox(width: 6),
                  _iconBtn(
                    icon: notifyOn
                        ? Icons.notifications_active
                        : Icons.notifications_none,
                    label: notifyOn ? 'Notif ON' : 'Notify',
                    color: notifyOn
                        ? BleTheme.accentGreen
                        : BleTheme.textSecondary,
                    loading: false,
                    onTap: () =>
                        _action(() => widget.onToggleNotify(c)),
                  ),
                ],
              ],
            ),
            if (props.write || props.writeWithoutResponse) ...[
              const SizedBox(height: 10),
              const Divider(height: 1, color: BleTheme.surfaceBorder),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: widget.writeCtrl[_uuid],
                      style: BleTheme.mono.copyWith(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'HEX e.g. 01 02 0A',
                        hintStyle: const TextStyle(
                            color: BleTheme.textMuted, fontSize: 12),
                        filled: true,
                        fillColor: BleTheme.surfaceCard,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(
                              color: BleTheme.surfaceBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(
                              color: BleTheme.surfaceBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(
                              color: BleTheme.accentOrange),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (props.write)
                    _iconBtn(
                      icon: Icons.upload_rounded,
                      label: 'Write',
                      color: BleTheme.accentOrange,
                      loading: _loading,
                      onTap: () => _action(() => widget.onWrite(
                            c,
                            widget.writeCtrl[_uuid]!.text,
                            withResponse: true,
                          )),
                    ),
                  if (props.writeWithoutResponse) ...[
                    const SizedBox(width: 6),
                    _iconBtn(
                      icon: Icons.upload_file_rounded,
                      label: 'No Resp',
                      color: Colors.deepOrange,
                      loading: _loading,
                      onTap: () => _action(() => widget.onWrite(
                            c,
                            widget.writeCtrl[_uuid]!.text,
                            withResponse: false,
                          )),
                    ),
                  ],
                ],
              ),
            ],
            if (displayValue != null && displayValue.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: BleTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: BleTheme.surfaceBorder),
                ),
                child: SelectableText(displayValue,
                    style: BleTheme.mono.copyWith(fontSize: 12)),
              ),
              // Show parsed human-readable value if available
              Builder(builder: (context) {
                if (rawValue == null) return const SizedBox.shrink();
                final parsed = GattDataParser.parse(_uuid, rawValue);
                if (parsed == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 12, color: Color(0xFF00D4AA)),
                      const SizedBox(width: 6),
                      Text(parsed,
                          style: const TextStyle(
                              color: Color(0xFF00D4AA),
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _propBadge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.bold)),
      );

  Widget _iconBtn({
    required IconData icon,
    required String label,
    required Color color,
    required bool loading,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: loading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: color),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 13, color: color),
                    const SizedBox(width: 4),
                    Text(label,
                        style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
        ),
      );

  String? _gattCharName(String uuid) {
    final id = uuid.length >= 8
        ? uuid.substring(4, 8).toUpperCase()
        : uuid.toUpperCase();
    const map = {
      '2A00': 'Device Name',
      '2A01': 'Appearance',
      '2A04': 'Preferred Connection Parameters',
      '2A05': 'Service Changed',
      '2A19': 'Battery Level',
      '2A24': 'Model Number',
      '2A25': 'Serial Number',
      '2A26': 'Firmware Revision',
      '2A27': 'Hardware Revision',
      '2A28': 'Software Revision',
      '2A29': 'Manufacturer Name',
      '2A37': 'Heart Rate Measurement',
      '2A38': 'Body Sensor Location',
    };
    return map[id];
  }
}

// ══════════════════════════════════════════════════════════════
// MACRO SCRIPT SHEET
// ══════════════════════════════════════════════════════════════
class _MacroSheet extends StatefulWidget {
  final String initialScript;
  final Future<void> Function(String script) onPlay;

  const _MacroSheet({required this.initialScript, required this.onPlay});

  @override
  State<_MacroSheet> createState() => _MacroSheetState();
}

class _MacroSheetState extends State<_MacroSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialScript);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20, 
        bottom: MediaQuery.of(context).viewInsets.bottom + 20
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Macro Script Engine', style: TextStyle(color: BleTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: BleTheme.textMuted)),
            ],
          ),
          const Text('Write a sequence of commands to automate interactions. Supported commands:\nWAIT <ms>\nREAD <uuid>\nWRITE <uuid> <hex_payload>', style: TextStyle(color: BleTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _ctrl,
              maxLines: null,
              expands: true,
              style: BleTheme.mono.copyWith(fontSize: 12, color: BleTheme.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: BleTheme.bg,
                hintText: '// Example:\n// WAIT 500\n// WRITE FFF1 01 00\n// READ FFF2',
                hintStyle: const TextStyle(color: BleTheme.textMuted),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: BleTheme.surfaceBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: BleTheme.accent)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => widget.onPlay(_ctrl.text),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('PLAY MACRO'),
              style: ElevatedButton.styleFrom(
                backgroundColor: BleTheme.accentGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
