import 'package:flutter_test/flutter_test.dart'; // Keep this

import 'package:csuatlasf/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // CHANGED: Replaced CampusPulseApp() with MyApp()
    await tester.pumpWidget(const MyApp());

    expect(find.text('LOG IN'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
  });
}