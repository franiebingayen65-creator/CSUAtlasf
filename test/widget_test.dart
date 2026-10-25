import 'package:flutter_test/flutter_test.dart'; // Keep this

import 'package:csuatlasf/main.dart';

void main() {
  testWidgets('App renders login screen correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Email or Username'), findsOneWidget);
  });
}