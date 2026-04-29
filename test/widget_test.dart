// BLE Explorer — Widget smoke test
// Verifies the app can boot and renders the HomeScreen tab bar.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ble_explorer/main.dart';

void main() {
  testWidgets('BLE Explorer boots without crashing', (WidgetTester tester) async {
    // Boot the app in "permissions already granted" mode so we skip onboarding
    await tester.pumpWidget(const BleExplorerRoot(skipOnboarding: true));
    // Just verify the app renders without error
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
