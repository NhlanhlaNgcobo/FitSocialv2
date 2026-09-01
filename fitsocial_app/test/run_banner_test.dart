import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/tracking/presentation/run_session_widgets.dart';

/// The weak-GPS banner used to describe a fix instead of carrying one: it told
/// the runner to go and set FitSocial to Unrestricted, several screens into
/// Settings, mid-run, out of breath. The same warning then came back the next
/// run, and the one after. A banner about something the runner can act on has
/// to put the action in reach.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(body: child),
      );

  testWidgets('a banner with nothing to do about it shows no action',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        const RunBanner(
          icon: Icons.motion_photos_paused_rounded,
          message: 'Auto-paused — start moving to resume',
          tone: RunBannerTone.brand,
        ),
      ),
    );

    expect(find.text('Auto-paused — start moving to resume'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('an action is offered as a button and runs when pressed',
      (tester) async {
    var taps = 0;

    await tester.pumpWidget(
      wrap(
        RunBanner(
          icon: Icons.satellite_alt_rounded,
          message: 'Weak GPS updates',
          tone: RunBannerTone.danger,
          actionLabel: 'Allow unrestricted battery',
          onAction: () => taps++,
        ),
      ),
    );

    await tester.tap(find.text('Allow unrestricted battery'));
    await tester.pump();

    expect(taps, 1);
  });

  test('half an action is rejected rather than rendered', () {
    // A label with no callback is a button that does nothing when a runner
    // presses it, which is worse than not offering one.
    expect(
      () => RunBanner(
        icon: Icons.satellite_alt_rounded,
        message: 'Weak GPS updates',
        tone: RunBannerTone.danger,
        actionLabel: 'Allow unrestricted battery',
      ),
      throwsAssertionError,
    );
  });
}
