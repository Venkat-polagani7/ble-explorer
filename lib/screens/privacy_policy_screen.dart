import 'package:flutter/material.dart';
import '../ble_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BleTheme.bg,
      appBar: AppBar(
        backgroundColor: BleTheme.surface,
        title: const Text('Privacy Policy',
            style: TextStyle(color: BleTheme.textPrimary, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: BleTheme.textPrimary),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header('BLE Explorer – Privacy Policy'),
            //const Text('Effective Date: April 28, 2025', style: TextStyle(color: BleTheme.textMuted, fontSize: 13)),
            const SizedBox(height: 24),
            _section(
              'Overview',
              'BLE Explorer is a professional Bluetooth Low Energy (BLE) diagnostic tool. '
              'We are committed to your privacy. This policy explains what data we access, '
              'what we do with it, and your rights.',
            ),
            _section(
              '1. Data We Do NOT Collect',
              '• We do not collect, store, or transmit any personal information.\n'
              '• We do not track your location.\n'
              '• We do not share any data with third parties.\n'
              '• We do not use any advertising SDKs or analytics that track users.',
            ),
            _section(
              '2. Bluetooth & Location Permissions',
              'BLE Explorer requests the following permissions solely to enable core functionality:\n\n'
              '• BLUETOOTH_SCAN — Required to discover nearby Bluetooth devices.\n'
              '• BLUETOOTH_CONNECT — Required to connect and communicate with Bluetooth devices.\n'
              '• BLUETOOTH_ADVERTISE — Required only when using the GATT Advertiser feature.\n'
              '• ACCESS_FINE_LOCATION — Required on Android 11 and below by the OS for BLE scanning. '
              'We never record, store, or use your GPS location.\n\n'
              'All Bluetooth operations happen entirely on-device. No device data, names, or MAC addresses '
              'are ever sent to external servers.',
            ),
            _section(
              '3. Data Minimization',
              'BLE Explorer is built on a data-minimization principle. '
              'The app only processes data that is absolutely required for the feature you are actively using. '
              'No background data collection occurs. '
              'Scan results and logs exist only in memory and are cleared when the app is closed.',
            ),
            _section(
              '4. Data Storage',
              'All data generated during app use (logs, scan results, diagnostic reports) '
              'is stored exclusively on your local device. If you export an Excel (.xlsx) report, '
              'it is saved to your device or shared via a system share sheet — we never upload it to any server.',
            ),
            _section(
              '5. Children\'s Privacy',
              'BLE Explorer is not directed to children under 13. We do not knowingly collect '
              'any information from children.',
            ),
            _section(
              '6. Changes to This Policy',
              'We may update this Privacy Policy as the app evolves. Any changes will be posted '
              'here with an updated effective date. Continued use of the app means you accept '
              'the revised policy.',
            ),
            _section(
              '7. Contact Us',
              'If you have any questions or concerns about this Privacy Policy, '
              'please contact us at:\n\nsupport@bleexplorer.app',
            ),
            const SizedBox(height: 40),
            const Center(
              child: Text('BLE Explorer v1.0.0 · All rights reserved',
                  style: TextStyle(color: BleTheme.textMuted, fontSize: 12)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: const TextStyle(
                color: BleTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.3)),
      );


  Widget _section(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: BleTheme.accent,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: BleTheme.surfaceCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: BleTheme.surfaceBorder),
              ),
              child: Text(body,
                  style: const TextStyle(
                      color: BleTheme.textSecondary, fontSize: 13, height: 1.7)),
            ),
          ],
        ),
      );
}
