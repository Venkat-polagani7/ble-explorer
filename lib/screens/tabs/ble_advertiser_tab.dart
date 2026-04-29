import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import '../../ble_theme.dart';
import '../../services/ble_log_service.dart';
import '../../services/permission_service.dart';

class BleAdvertiserTab extends StatefulWidget {
  final BleLogService logService;

  const BleAdvertiserTab({super.key, required this.logService});

  @override
  State<BleAdvertiserTab> createState() => _BleAdvertiserTabState();
}

class _BleAdvertiserTabState extends State<BleAdvertiserTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();
  bool _isSupported = false;
  bool _isAdvertising = false;

  final TextEditingController _uuidCtrl = TextEditingController(text: '0000180F-0000-1000-8000-00805F9B34FB');
  final TextEditingController _manufacturerIdCtrl = TextEditingController(text: '0xFFFF');
  final TextEditingController _manufacturerDataCtrl = TextEditingController(text: '010203');

  @override
  void initState() {
    super.initState();
    _checkSupport();
    _blePeripheral.onPeripheralStateChanged?.listen((state) {
      if (mounted) {
        setState(() {
          _isAdvertising = state == PeripheralState.advertising;
        });
      }
    });
  }

  Future<void> _checkSupport() async {
    try {
      final isSupported = await _blePeripheral.isSupported;
      if (mounted) setState(() => _isSupported = isSupported);
    } catch (e) {
      widget.logService.error('Peripheral check failed: $e', tag: 'ADV');
    }
  }

  List<int> _hexToBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'[\s:]+'), '');
    if (clean.isEmpty || clean.length % 2 != 0) return [];
    final result = <int>[];
    for (int i = 0; i < clean.length - 1; i += 2) {
      result.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  Future<void> _toggleAdvertising() async {
    if (_isAdvertising) {
      try {
        await _blePeripheral.stop();
        widget.logService.info('Stopped advertising', tag: 'ADV');
      } catch (e) {
        widget.logService.error('Stop advertise failed: $e', tag: 'ADV');
      }
      return;
    }

    if (Platform.isAndroid && PermissionService.androidSdkInt >= 31) {
      final status = await Permission.bluetoothAdvertise.request();
      if (status.isPermanentlyDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Advertising permission permanently denied. Please enable in Settings.'),
            action: SnackBarAction(label: 'SETTINGS', onPressed: () => openAppSettings()),
            backgroundColor: BleTheme.accentRed,
            duration: const Duration(seconds: 5),
          ));
        }
        return;
      }
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Bluetooth Advertise permission is required.'),
            backgroundColor: BleTheme.accentRed,
          ));
        }
        return;
      }
    }

    try {
      final mIdStr = _manufacturerIdCtrl.text.replaceAll('0x', '').replaceAll('0X', '');
      final mId = int.tryParse(mIdStr, radix: 16) ?? 0xFFFF;
      
      final mDataBytes = _hexToBytes(_manufacturerDataCtrl.text);

      final advertiseData = AdvertiseData(
        serviceUuid: _uuidCtrl.text.trim(),
        manufacturerId: mId,
        manufacturerData: Uint8List.fromList(mDataBytes),
        includeDeviceName: false,
      );

      final advertiseSettings = AdvertiseSettings(
        advertiseMode: AdvertiseMode.advertiseModeLowLatency,
        txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
        connectable: true,
      );

      await _blePeripheral.start(
        advertiseData: advertiseData,
        advertiseSettings: advertiseSettings,
      );
      
      widget.logService.success('Started advertising UUID: ${_uuidCtrl.text.trim()}', tag: 'ADV');
    } catch (e) {
      widget.logService.error('Start advertise failed: $e', tag: 'ADV');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to advertise: $e'),
          backgroundColor: BleTheme.accentRed,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('GATT Advertiser', style: TextStyle(color: BleTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Simulate a peripheral by advertising custom service UUIDs and manufacturer data.', style: TextStyle(color: BleTheme.textSecondary, fontSize: 14)),
          const SizedBox(height: 24),
          
          if (!_isSupported)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: BleTheme.accentRed.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: BleTheme.accentRed.withValues(alpha: 0.3))),
              child: const Row(
                children: [
                  Icon(Icons.error_outline, color: BleTheme.accentRed),
                  SizedBox(width: 12),
                  Expanded(child: Text('Peripheral mode is not supported on this device hardware.', style: TextStyle(color: BleTheme.accentRed))),
                ],
              ),
            ),
            
          const SizedBox(height: 16),
          
          _buildInput('Service UUID', _uuidCtrl, 'e.g. 0000180F-0000-1000-8000...'),
          const SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(child: _buildInput('Manufacturer ID (Hex)', _manufacturerIdCtrl, 'e.g. FFFF')),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: _buildInput('Manufacturer Data (Hex)', _manufacturerDataCtrl, 'e.g. 01020304')),
            ],
          ),
          
          const Spacer(),
          
          ElevatedButton.icon(
            icon: Icon(_isAdvertising ? Icons.stop : Icons.cell_tower, size: 24),
            label: Text(_isAdvertising ? 'STOP ADVERTISING' : 'START ADVERTISING', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isAdvertising ? BleTheme.accentRed : BleTheme.accentGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _isSupported ? _toggleAdvertising : null,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController ctrl, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: BleTheme.textSecondary, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          style: const TextStyle(color: BleTheme.textPrimary, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: BleTheme.textMuted),
            filled: true,
            fillColor: BleTheme.surfaceCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: BleTheme.surfaceBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: BleTheme.surfaceBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: BleTheme.accent)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }
}
