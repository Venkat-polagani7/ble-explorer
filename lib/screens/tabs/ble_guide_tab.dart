import 'package:flutter/material.dart';
import '../../ble_theme.dart';
import '../privacy_policy_screen.dart';

class BleGuideTab extends StatefulWidget {
  const BleGuideTab({super.key});

  @override
  State<BleGuideTab> createState() => _BleGuideTabState();
}

class _BleGuideTabState extends State<BleGuideTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Widget _section(String title, IconData icon, List<String> points) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BleTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: BleTheme.accent, size: 24),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(color: BleTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: BleTheme.surfaceBorder),
          const SizedBox(height: 12),
          ...points.map((p) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•', style: TextStyle(color: BleTheme.accentSecondary, fontSize: 18, height: 1)),
                const SizedBox(width: 8),
                Expanded(child: Text(p, style: const TextStyle(color: BleTheme.textSecondary, fontSize: 14))),
              ],
            ),
          )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: BleTheme.bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'BLE Explorer Guide',
                style: TextStyle(color: BleTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w800),
              ),
            ),
            _section('1. Scanner', Icons.radar, [
              'Discovers nearby BLE devices in real-time.',
              'Use the Toolbar to Filter by Name, MAC Address, or specific Service UUIDs.',
              'Tap "Sort By" to organize devices by Discovery Time, Signal Strength (RSSI), or Name.',
              'Tap the "Connect" icon on any device to instantly navigate to the Inspector.',
            ]),
            _section('2. Inspector', Icons.explore, [
              'Your main hub for interacting with a connected device.',
              'Browse all discovered GATT Services and Characteristics.',
              'Perform Read, Write, and Subscribe (Notify) operations on characteristics.',
              'Tap "DFU Update" to flash new firmware (Nordic DFU) directly from your phone.',
              'Tap "MTU/PHY" to negotiate connection parameters for faster data throughput.',
            ]),
            _section('3. Diagnostics', Icons.bar_chart, [
              'A stress-testing tool to analyze connection reliability.',
              'Enter a device MAC address to run automated, repeated connection attempts.',
              'It logs success rates, average connection durations, and GATT errors.',
              'Tap the Share icon to export a detailed Excel (.xlsx) report of the test results.',
            ]),
            _section('4. Advertiser (Peripheral Mode)', Icons.cell_tower, [
              'Turns your phone into a simulated BLE device (GATT Server).',
              'Define custom Service UUIDs and Hex Manufacturer Data to broadcast.',
              'Useful for testing other BLE central apps or hardware without needing physical IoT devices.',
            ]),
            _section('5. Logs', Icons.list_alt_rounded, [
              'A centralized, real-time event monitor.',
              'Tracks connection statuses, GATT errors, payloads, and system events.',
              'Use the top filters to isolate INFO, SUCCESS, ERROR, or WARNING logs.',
            ]),
            const SizedBox(height: 16),
            // Privacy Policy & About section
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BleTheme.cardDecoration,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline, color: BleTheme.accent, size: 22),
                      SizedBox(width: 10),
                      Text('About & Legal', style: TextStyle(color: BleTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: BleTheme.surfaceBorder),
                  const SizedBox(height: 12),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.shield_outlined, color: BleTheme.accentSecondary, size: 20),
                    title: const Text('Privacy Policy', style: TextStyle(color: BleTheme.textSecondary, fontSize: 14)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: BleTheme.textMuted),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                    ),
                  ),
                  const Divider(height: 1, color: BleTheme.surfaceBorder),
                  const SizedBox(height: 8),
                  const Text('All BLE data processed on-device. Nothing is uploaded.', style: TextStyle(color: BleTheme.textMuted, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 40),
            const Center(
              child: Text('App Version 1.0.0 (Production)', 
                style: TextStyle(color: BleTheme.textMuted, fontSize: 12)),
            )
          ],
        ),
      ),
    );
  }
}
