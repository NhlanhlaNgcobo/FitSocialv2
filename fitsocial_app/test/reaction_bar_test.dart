import 'package:fitsocial_app/shared/reactions/fit_reaction.dart';
import 'package:fitsocial_app/shared/widgets/reaction_bar.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mounts the bar and records what it reports back.
///
/// [changes] collects every [ReactionBar.onChanged], including the nulls
/// that mean "taken back", so a test can tell "reported nothing" from
/// "reported a clear".
Future<void> _pumpBar(
  WidgetTester tester, {
  required List<FitReaction?> changes,
  required List<bool> trayVisibility,
  FitReaction? selected,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ReactionBar(
            selected: selected,
            onChanged: changes.add,
            onTrayVisibilityChanged: trayVisibility.add,
          ),
        ),
      ),
    ),
  );
}

/// The reaction as drawn in the open tray.
///
/// Last, not first: the pill draws one too — the reaction already held, or
/// the dimmed default — and the tray is inserted into the overlay after it.
Finder _trayReaction(FitReaction reaction) => find.text(reaction.emoji).last;

/// Presses the pill, holds past the long-press threshold so the tray opens,
/// and hands back the live gesture to aim with.
Future<TestGesture> _openTray(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(ReactionBar)),
  );
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  // Let the reveal settle so the reactions are where they will stay.
  await tester.pumpAndSettle();
  return gesture;
}

void main() {
  group('ReactionBar taps', () {
    testWidgets('a bare tap gives the default reaction', (tester) async {
      final changes = <FitReaction?>[];
      await _pumpBar(tester, changes: changes, trayVisibility: []);

      await tester.tap(find.byType(ReactionBar));
      await tester.pump();

      expect(changes, [FitReaction.defaultReaction]);
    });

    testWidgets('tapping while holding a reaction takes it back',
        (tester) async {
      final changes = <FitReaction?>[];
      await _pumpBar(
        tester,
        changes: changes,
        trayVisibility: [],
        selected: FitReaction.fire,
      );

      await tester.tap(find.byType(ReactionBar));
      await tester.pump();

      // Not "give the default" — the second tap is an undo, whichever
      // reaction you are holding.
      expect(changes, [null]);
    });
  });

  group('ReactionBar tray', () {
    testWidgets('holding opens all seven reactions and reports the tray is up',
        (tester) async {
      final visibility = <bool>[];
      await _pumpBar(tester, changes: [], trayVisibility: visibility);

      final gesture = await _openTray(tester);

      for (final reaction in FitReaction.all) {
        expect(
          find.text(reaction.emoji),
          findsWidgets,
          reason: '${reaction.label} should be in the tray',
        );
      }
      // The host has to know, or the Pulse advances out from under the tray.
      expect(visibility, [true]);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(visibility, [true, false]);
    });

    testWidgets('sliding onto a reaction and lifting picks it', (tester) async {
      final changes = <FitReaction?>[];
      await _pumpBar(tester, changes: changes, trayVisibility: []);

      final gesture = await _openTray(tester);
      await gesture.moveTo(
        tester.getCenter(_trayReaction(FitReaction.champion)),
      );
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();

      // One gesture start to finish: press, slide, lift. Never a second tap.
      expect(changes, [FitReaction.champion]);
    });

    testWidgets('lifting away from the row picks nothing', (tester) async {
      final changes = <FitReaction?>[];
      await _pumpBar(tester, changes: changes, trayVisibility: []);

      final gesture = await _openTray(tester);
      final tray = tester.getCenter(_trayReaction(FitReaction.champion));
      // Well below the row — the way someone backs out of a tray they opened
      // by accident.
      await gesture.moveTo(tray + const Offset(0, 240));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(changes, isEmpty);
    });

    testWidgets('lifting on the reaction already held reports nothing',
        (tester) async {
      final changes = <FitReaction?>[];
      await _pumpBar(
        tester,
        changes: changes,
        trayVisibility: [],
        selected: FitReaction.champion,
      );

      final gesture = await _openTray(tester);
      await gesture.moveTo(
        tester.getCenter(_trayReaction(FitReaction.champion)),
      );
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();

      // Re-picking what you already have is not an event, so it must not cost
      // a write.
      expect(changes, isEmpty);
    });

    testWidgets('the tray is taken down when the bar goes away',
        (tester) async {
      await _pumpBar(tester, changes: [], trayVisibility: []);

      final gesture = await _openTray(tester);
      expect(find.text(FitReaction.rocket.emoji), findsOneWidget);

      // Playback ending, or the viewer being closed, while a finger is still
      // down: the overlay entry must not outlive the widget that inserted it.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pumpAndSettle();

      expect(find.text(FitReaction.rocket.emoji), findsNothing);
      await gesture.up();
    });
  });
}
