import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/material.dart';
import '../ble_theme.dart';
import '../services/ble_log_service.dart';
import 'tabs/ble_scanner_tab.dart';
import 'tabs/ble_guide_tab.dart';
import 'tabs/ble_inspector_tab.dart';
import 'tabs/ble_diagnostics_tab.dart';
import 'tabs/ble_advertiser_tab.dart';
import 'tabs/ble_log_tab.dart';

// ══════════════════════════════════════════════════════════════
// HOME SCREEN – Main scaffold with 4 tabs
// ══════════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late final TabController _tabCtrl;
  final BleLogService _logService = BleLogService();
  String? _diagRemoteId;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) setState(() {});
    });
    _checkBleAdapter();
  }

  Future<void> _checkBleAdapter() async {
    try {
      await FlutterBluePlus.adapterState.first;
      if (mounted) setState(() {});

      // Listen for adapter state changes
      FlutterBluePlus.adapterState.listen((s) {
        if (mounted) {
          setState(() {});
          if (s == BluetoothAdapterState.off) {
            _logService.warning('Bluetooth adapter turned OFF', tag: 'SYS');
            _showBleOffBanner();
          } else if (s == BluetoothAdapterState.on) {
            _logService.info('Bluetooth adapter turned ON', tag: 'SYS');
            ScaffoldMessenger.of(context).clearSnackBars();
          }
        }
      });
    } catch (e) {
      _logService.error('BLE adapter check failed: $e', tag: 'SYS');
    }
  }

  void _showBleOffBanner() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: BleTheme.accentRed.withValues(alpha: 0.9),
        content: const Row(
          children: [
            Icon(Icons.bluetooth_disabled, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text(
              'Bluetooth is off — please enable it',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        action: SnackBarAction(
          label: Platform.isAndroid ? 'Enable' : 'Settings',
          textColor: Colors.white,
          onPressed: () async {
            if (Platform.isAndroid) {
              try {
                // Native Android intent: gracefully asks "App wants to turn on Bluetooth"
                await FlutterBluePlus.turnOn();
              } catch (_) {}
            } else {
              // iOS strictly prohibits programmatic BT toggling. Native graceful fallback.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please enable Bluetooth via Control Center',
                      style: TextStyle(color: Colors.white)),
                  backgroundColor: Color(0xFF1E3A5F),
                  duration: Duration(seconds: 3),
                ),
              );
            }
          },
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _navigateToInspector(String remoteId) {
    setState(() {
      _diagRemoteId = '$remoteId|${DateTime.now().millisecondsSinceEpoch}';
    });
    _tabCtrl.animateTo(1);
  }

  void _navigateToDiagnostics(String remoteId) {
    setState(() {
      _diagRemoteId = remoteId;
    });
    _tabCtrl.animateTo(2);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BleTheme.bg,
      appBar: AppBar(
        backgroundColor: BleTheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [BleTheme.accent, BleTheme.accentSecondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.bluetooth_searching,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'BLE Explorer',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            // BLE adapter status indicator
            StreamBuilder<BluetoothAdapterState>(
              stream: FlutterBluePlus.adapterState,
              builder: (context, snap) {
                final state = snap.data ?? BluetoothAdapterState.unknown;
                final isOn = state == BluetoothAdapterState.on;
                return Tooltip(
                  message: 'BT: ${state.name}',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isOn
                          ? BleTheme.accentGreen.withValues(alpha: 0.15)
                          : BleTheme.accentRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isOn
                            ? BleTheme.accentGreen.withValues(alpha: 0.4)
                            : BleTheme.accentRed.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isOn ? Icons.bluetooth : Icons.bluetooth_disabled,
                          size: 14,
                          color: isOn
                              ? BleTheme.accentGreen
                              : BleTheme.accentRed,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isOn ? 'ON' : state.name.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            color: isOn
                                ? BleTheme.accentGreen
                                : BleTheme.accentRed,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.menu_book_outlined, color: BleTheme.textMuted),
              tooltip: 'BLE Guide',
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const Scaffold(
                  backgroundColor: BleTheme.bg,
                  body: SafeArea(child: BleGuideTab()),
                )));
              },
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: BleTheme.accent,
          indicatorWeight: 3,
          labelColor: BleTheme.accent,
          unselectedLabelColor: BleTheme.textMuted,
          labelStyle:
              const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          tabs: const [
            Tab(icon: Icon(Icons.radar, size: 20), text: 'Scanner'),
            Tab(icon: Icon(Icons.explore, size: 20), text: 'Inspector'),
            Tab(icon: Icon(Icons.bar_chart, size: 20), text: 'Diagnostics'),
            Tab(icon: Icon(Icons.cell_tower, size: 20), text: 'Advertiser'),
            Tab(icon: Icon(Icons.list_alt_rounded, size: 20), text: 'Logs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        physics: const NeverScrollableScrollPhysics(), // prevent swipe conflicts with BLE list
        children: [
          BleScannerTab(
            logService: _logService,
            onConnectTap: _navigateToInspector,
            onDiagnoseTap: _navigateToDiagnostics,
          ),
          BleInspectorTab(
            key: _diagRemoteId != null ? ValueKey('insp_$_diagRemoteId') : null,
            logService: _logService,
            initialRemoteId: _diagRemoteId ?? '',
          ),
          BleDiagnosticsTab(
            key: _diagRemoteId != null ? ValueKey('diag_$_diagRemoteId') : null,
            logService: _logService,
            initialDeviceId: _diagRemoteId,
          ),
          BleAdvertiserTab(logService: _logService),
          BleLogTab(logService: _logService),
        ],
      ),
    );
  }
}
