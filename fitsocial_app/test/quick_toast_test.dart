import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/shared/widgets/quick_toast.dart';

/// A screen with one button under where the toast lands, so a test can prove
/// the pill does — or does not — swallow the tap meant for it.
Widget _host(void Function(BuildContext context) onTap, {VoidCallback? onHit}) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: onHit ?? () {},
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Builder(
            builder: (context) => Align(
              alignment: Alignment.topCenter,
              child: TextButton(
                onPressed: () => onTap(context),
                child: const Text('go'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  group('quick toast', () {
    testWidgets('retires itself without anyone dismissing it', (tester) async {
      await tester.pumpWidget(_host((c) => showQuickToast(c, 'Saved')));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Saved'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsNothing);
    });

    testWidgets('a failure stays up longer than an acknowledgement',
        (tester) async {
      await tester.pumpWidget(
        _host((c) => showQuickToast(c, 'Failed', tone: ToastTone.danger)),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      // Past the 1150ms an acknowledgement gets, and still readable.
      await tester.pump(const Duration(milliseconds: 1600));
      expect(find.text('Failed'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Failed'), findsNothing);
    });

    testWidgets('the action runs once and takes the toast with it',
        (tester) async {
      var undone = 0;
      await tester.pumpWidget(
        _host(
          (c) => showQuickToast(
            c,
            'Removed Toast',
            actionLabel: 'Undo',
            onAction: () => undone++,
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('UNDO'));
      await tester.pumpAndSettle();

      expect(undone, 1);
      expect(find.text('Removed Toast'), findsNothing);
    });

    testWidgets('a plain toast lets a tap through to the screen behind it',
        (tester) async {
      var behind = 0;
      await tester.pumpWidget(
        _host(
          (c) => showQuickToast(c, 'Saved'),
          onHit: () => behind++,
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      // Dead centre of the pill: without IgnorePointer this tap stops there.
      await tester.tapAt(tester.getCenter(find.text('Saved')));
      await tester.pumpAndSettle();

      expect(behind, 1);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });

    testWidgets('a second toast replaces the first rather than queueing',
        (tester) async {
      late BuildContext held;
      await tester.pumpWidget(
        _host((c) {
          held = c;
          showQuickToast(c, 'First');
        }),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      showQuickToast(held, 'Second');
      await tester.pumpAndSettle();

      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });
  });
}
