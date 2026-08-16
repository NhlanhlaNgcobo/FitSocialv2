import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/presentation/achievements_screen.dart';

void main() {
  group('achievements screen', () {
    // The streak-and-goals dashboard that used to live here is still out for
    // redesign. What replaced the construction placeholder is the half that has
    // real data behind it: the points total and the badge case, both written by
    // the server.
    testWidgets('shows the points total and an empty badge case',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [currentUserIdProvider.overrideWithValue('me')],
          child: const MaterialApp(home: AchievementsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TOTAL POINTS'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('BADGES'), findsOneWidget);
      expect(find.text('No badges yet.'), findsOneWidget);

      // The removed dashboard has not quietly come back.
      expect(find.text('Page under construction'), findsNothing);
      expect(find.text('Goals'), findsNothing);
    });

    testWidgets('says nothing about Early Worm before the first morning',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [currentUserIdProvider.overrideWithValue('me')],
          child: const MaterialApp(home: AchievementsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('EARLY WORM'), findsNothing);
    });
  });
}
