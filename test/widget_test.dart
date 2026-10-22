// Basic smoke test for RFMonitor.
//
// This just verifies the app boots to its splash screen without throwing.
// Screens that depend on stored server profiles / live network calls are
// exercised manually, not here.

import 'package:flutter_test/flutter_test.dart';

import 'package:rfmonitor/main.dart';

void main() {
  testWidgets('App boots and shows the RFMonitor splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const RfMonitorApp());

    // Splash screen renders immediately; don't pumpAndSettle here since it
    // kicks off a real async bootstrap (reads secure storage) that we're
    // not mocking in this smoke test.
    await tester.pump();

    expect(find.text('RFMONITOR'), findsOneWidget);
    expect(find.text('by RFPROJECT'), findsOneWidget);
  });
}
