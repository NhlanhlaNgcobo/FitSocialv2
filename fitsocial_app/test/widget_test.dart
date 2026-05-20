// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fitsocial_app/app/app.dart';

void main() {
  testWidgets('renders the FitSocial shell', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: FitSocialApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Train. Fuel. Share. Grow.'), findsWidgets);
    expect(find.text('Get Started'), findsOneWidget);
  });
}
