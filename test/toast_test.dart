import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:csuatlasf/utils/app_utils.dart';

void main() {
  testWidgets('showTopToast does not crash when caller context is unmounted', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              AppUtils.showTopToast(context, 'Test message');
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Second Page'))),
              );
            },
            child: const Text('Go'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Go'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
  });
}
