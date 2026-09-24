import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/safety/application/panic_controller.dart';
import 'package:fitsocial_app/features/safety/presentation/panic_screen.dart';
import 'package:fitsocial_app/features/safety/presentation/pin_pad.dart';
import 'package:fitsocial_app/features/safety/presentation/safety_widgets.dart';

void main() {
  group('PinPad', () {
    Future<List<String>> pump(WidgetTester tester) async {
      final entered = <String>[];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: SingleChildScrollView(child: PinPad(onComplete: entered.add)),
        ),
      ));
      return entered;
    }

    testWidgets('hands over four digits and clears itself', (tester) async {
      final entered = await pump(tester);
      for (final d in ['1', '2', '3', '4']) {
        await tester.tap(find.text(d));
      }
      await tester.pump();
      expect(entered, ['1234']);

      for (final d in ['9', '8', '7', '6']) {
        await tester.tap(find.text(d));
      }
      await tester.pump();
      expect(entered, ['1234', '9876']);
    });

    testWidgets('delete removes the last digit', (tester) async {
      final entered = await pump(tester);
      await tester.tap(find.text('1'));
      await tester.tap(find.text('2'));
      await tester.tap(find.bySemanticsLabel('Delete'));
      for (final d in ['5', '6', '7']) {
        await tester.tap(find.text(d));
      }
      await tester.pump();
      expect(entered, ['1567']);
    });
  });

  group('delivery wording never claims receipt', () {
    test('counts who the alert is addressed to', () {
      const state = PanicState(
        phase: PanicPhase.active,
        delivery: PanicDelivery.sent,
        alertedContacts: 2,
      );
      expect(deliveryLine(state), 'Alerting 2 contacts');
      expect(deliveryLine(state).toLowerCase(), isNot(contains('notified')));
    });

    test('one contact reads in the singular', () {
      expect(
        deliveryLine(const PanicState(
          delivery: PanicDelivery.sent,
          alertedContacts: 1,
        )),
        'Alerting 1 contact',
      );
    });

    test('zero contacts says it stayed on the phone', () {
      expect(
        deliveryLine(const PanicState(
          delivery: PanicDelivery.sent,
          alertedContacts: 0,
        )),
        contains('recorded on this phone only'),
      );
    });

    test('offline says it is waiting, not sent', () {
      final line = deliveryLine(const PanicState(
        delivery: PanicDelivery.queued,
        alertedContacts: 2,
      ));
      expect(line, contains('Waiting for signal'));
      expect(line, isNot(contains('Alerting')));
    });

    test('a failed write says so', () {
      expect(
        deliveryLine(const PanicState(delivery: PanicDelivery.failed)),
        contains("Couldn't send"),
      );
    });
  });

  test('position age reads in plain words', () {
    final now = DateTime(2026, 9, 24, 18);
    expect(agoLabel(now.subtract(const Duration(seconds: 2)), now), 'just now');
    expect(
      agoLabel(now.subtract(const Duration(seconds: 40)), now),
      '40 seconds ago',
    );
    expect(
      agoLabel(now.subtract(const Duration(minutes: 1)), now),
      '1 minute ago',
    );
    expect(
      agoLabel(now.subtract(const Duration(minutes: 14)), now),
      '14 minutes ago',
    );
  });
}
