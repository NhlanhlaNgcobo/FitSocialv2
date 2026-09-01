import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/tracking/presentation/finish_run_sheet.dart';

// The sheet is the only place the runner is told where their run is going, so
// what it says has to match what the caller is about to do with it.

void main() {
  /// Opens the sheet and hands back a getter for whatever it eventually
  /// returns, so a test can drive the sheet and then read the choice.
  Future<Future<FinishRunChoice?> Function()> openSheet(
    WidgetTester tester, {
    required bool saveToDrafts,
  }) async {
    FinishRunChoice? choice;
    var closed = false;

    // A phone-shaped surface rather than the 800x600 default: the sheet is a
    // scrolling column, and on a short viewport the share toggle sits below the
    // fold, where a tap cannot reach it.
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  choice = await showFinishRunSheet(
                    context: context,
                    route: const [],
                    distanceLabel: '5.20 km',
                    durationLabel: '28:14',
                    saveToDrafts: saveToDrafts,
                  );
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    return () async {
      expect(closed, isTrue, reason: 'the sheet never closed');
      return choice;
    };
  }

  /// Taps something inside the sheet, scrolling it into view first.
  ///
  /// The sheet is a scrolling column and the toggle and the button both sit
  /// below the fold on a phone-sized viewport, where a tap lands on nothing.
  Future<void> tapInSheet(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  group('online', () {
    testWidgets('offers to save and share', (tester) async {
      await openSheet(tester, saveToDrafts: false);

      expect(find.text('Save Run & Share'), findsOneWidget);
      expect(find.text('Save to Drafts'), findsNothing);
      expect(find.textContaining("You're offline"), findsNothing);
    });

    testWidgets('drops "& Share" when the toggle is off', (tester) async {
      await openSheet(tester, saveToDrafts: false);

      await tapInSheet(tester, find.text('Share to Feed'));

      expect(find.text('Save Run'), findsOneWidget);
      expect(find.text('Save Run & Share'), findsNothing);
    });
  });

  group('offline', () {
    testWidgets('says where the run is actually going', (tester) async {
      await openSheet(tester, saveToDrafts: true);

      expect(find.text('Save to Drafts'), findsOneWidget);
      expect(find.textContaining("You're offline"), findsOneWidget);
      // Sharing is not what this button does now, so it must not claim to.
      expect(find.text('Save Run & Share'), findsNothing);
    });

    // The label stays put whichever way the toggle is set: the choice is
    // recorded on the draft and honoured at publish time, not acted on here.
    testWidgets('keeps one label whichever way the toggle is set',
        (tester) async {
      await openSheet(tester, saveToDrafts: true);

      await tapInSheet(tester, find.text('Share to Feed'));

      expect(find.text('Save to Drafts'), findsOneWidget);
      expect(find.text('Save Run'), findsNothing);
    });

    testWidgets('still explains when the run will go out', (tester) async {
      await openSheet(tester, saveToDrafts: true);

      expect(
        find.textContaining('when you publish it'),
        findsOneWidget,
      );
    });
  });

  group('the choice that comes back', () {
    testWidgets('keeps sharing on when the runner left it on', (tester) async {
      final read = await openSheet(tester, saveToDrafts: true);

      await tapInSheet(tester, find.text('Save to Drafts'));

      expect((await read())!.shareToFeed, isTrue);
    });

    testWidgets('keeps sharing off when the runner turned it off',
        (tester) async {
      final read = await openSheet(tester, saveToDrafts: true);

      await tapInSheet(tester, find.text('Share to Feed'));
      await tapInSheet(tester, find.text('Save to Drafts'));

      expect((await read())!.shareToFeed, isFalse);
    });
  });

  // Every way out of this sheet saves: the clock was stopped before it opened,
  // so there is nothing to go back to.
  test('a dismissed sheet still saves and shares', () {
    expect(FinishRunChoice.dismissed.shareToFeed, isTrue);
    expect(FinishRunChoice.dismissed.backgroundImagePath, isNull);
  });
}
