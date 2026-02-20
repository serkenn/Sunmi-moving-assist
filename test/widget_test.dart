// This is a basic Flutter widget test for the Sunmi Inventory App.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunmi_inventory_app/main.dart';

void main() {
  testWidgets('Sunmi Inventory App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SunmiInventoryApp());

    // Wait for the app to initialize
    await tester.pump();

    // Verify that our app title is displayed
    expect(find.text('Sunmi在庫管理'), findsOneWidget);

    // Verify that the main tabs are present
    expect(find.text('在庫'), findsOneWidget);
    expect(find.text('分析'), findsOneWidget);
    expect(find.text('引越'), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);

    // Verify that the scan button is present
    expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
  });
}
