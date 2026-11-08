import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:csuatlasf/widgets/admin_shell.dart';

void main() {
  testWidgets('AdminSidebar renders without error with app theme', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          fontFamily: 'sans-serif',
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4338CA),
            brightness: Brightness.light,
          ),
        ),
        home: Scaffold(
          body: AdminSidebar(
            isCollapsed: false,
            activePage: 'Dashboard',
            onPageSelected: (_) {},
            onToggleCollapse: () {},
            badges: const {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  });
}
