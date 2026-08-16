import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/auth/data/user_profile_repository.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository_contract.dart';
import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';
import 'package:fitsocial_app/features/main/presentation/bmi_screen.dart';

class FakeProfiles implements UserProfileRepository {
  FakeProfiles({this.stored = const BodyMetrics()});

  final BodyMetrics stored;
  BodyMetrics? saved;

  @override
  Future<BodyMetrics> loadBodyMetrics() async => stored;

  @override
  Future<void> saveBodyMetrics(BodyMetrics metrics) async => saved = metrics;

  @override
  Future<UserProfileDraft?> loadCurrentProfile() async => null;

  @override
  Future<UserProfileDraft> saveProfile({
    required String displayName,
    required String handle,
    required String bio,
    required String location,
    String? avatarLocalPath,
    String pronouns = '',
    String links = '',
  }) async =>
      throw UnimplementedError();
}

Future<void> pumpCalculator(WidgetTester tester, FakeProfiles profiles) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProfileRepositoryProvider.overrideWithValue(profiles),
      ],
      child: const MaterialApp(home: BmiScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Finder fieldWithSuffix(String suffix) =>
    find.widgetWithText(TextField, suffix);

void main() {
  group('bmi calculator', () {
    testWidgets('computes as you type, before anything is saved',
        (tester) async {
      await pumpCalculator(tester, FakeProfiles());

      await tester.enterText(fieldWithSuffix('cm'), '175');
      await tester.enterText(fieldWithSuffix('kg'), '70');
      await tester.pump();

      expect(find.text('22.9'), findsOneWidget);
      expect(find.text('Healthy'), findsOneWidget);
    });

    testWidgets('invites input while the form is untouched', (tester) async {
      await pumpCalculator(tester, FakeProfiles());

      expect(find.text('Enter your height and weight'), findsOneWidget);
    });

    // The original bug, in miniature: a half-filled form used to fall back to
    // "enter your height and weight" — telling a user who had just typed their
    // height that they had typed nothing.
    testWidgets('names the missing field once one is filled', (tester) async {
      await pumpCalculator(tester, FakeProfiles());

      await tester.enterText(fieldWithSuffix('cm'), '175');
      await tester.pump();

      expect(find.text('Add your weight.'), findsOneWidget);
      expect(find.text('Enter your height and weight'), findsNothing);
    });

    // What the reported failure actually was. A decimal comma is what a
    // locale keyboard puts on the decimal key; it used to be filtered out,
    // turning 70,5 kg into 705 kg — out of range, so no BMI and no reason.
    testWidgets('accepts a decimal comma as a decimal point', (tester) async {
      await pumpCalculator(tester, FakeProfiles());

      await tester.enterText(fieldWithSuffix('cm'), '175');
      await tester.enterText(fieldWithSuffix('kg'), '70,5');
      await tester.pump();

      expect(find.text('23.0'), findsOneWidget);
      expect(find.text('Healthy'), findsOneWidget);
    });

    // The other way a filled form produced silence: height typed in metres.
    testWidgets('reads a height typed in metres', (tester) async {
      await pumpCalculator(tester, FakeProfiles());

      await tester.enterText(fieldWithSuffix('cm'), '1.75');
      await tester.enterText(fieldWithSuffix('kg'), '70');
      await tester.pump();

      expect(find.text('22.9'), findsOneWidget);
    });

    testWidgets('explains a figure it cannot use instead of going quiet',
        (tester) async {
      await pumpCalculator(tester, FakeProfiles());

      await tester.enterText(fieldWithSuffix('cm'), '175');
      await tester.enterText(fieldWithSuffix('kg'), '900');
      await tester.pump();

      expect(find.text('No BMI yet'), findsOneWidget);
      expect(find.textContaining('That weight looks off'), findsOneWidget);
    });

    testWidgets('seeds the fields from what was stored', (tester) async {
      await pumpCalculator(
        tester,
        FakeProfiles(stored: const BodyMetrics(heightCm: 180, weightKg: 95)),
      );

      expect(find.text('180'), findsOneWidget);
      expect(find.text('95'), findsOneWidget);
      // 95 / 1.8² = 29.3
      expect(find.text('29.3'), findsOneWidget);
      expect(find.text('Overweight'), findsOneWidget);
    });

    // The BMI must not move when only the units label does. This is the whole
    // risk of a two-unit form: the number on screen changes, the body does not.
    testWidgets('switching units converts the figures instead of reading them '
        'as the new unit', (tester) async {
      await pumpCalculator(tester, FakeProfiles());

      await tester.enterText(fieldWithSuffix('cm'), '175');
      await tester.enterText(fieldWithSuffix('kg'), '70');
      await tester.pump();
      expect(find.text('22.9'), findsOneWidget);

      await tester.tap(find.text('Imperial (ft/lb)'));
      await tester.pumpAndSettle();

      // 175 cm is 5 ft 8.9 in; 70 kg is 154.3 lb.
      expect(find.text('5'), findsOneWidget);
      expect(find.text('8.9'), findsOneWidget);
      expect(find.text('154.3'), findsOneWidget);
      // The point of the test: the same body, so the same BMI.
      expect(find.text('22.9'), findsOneWidget);

      // And back again, unchanged.
      await tester.tap(find.text('Metric (cm/kg)'));
      await tester.pumpAndSettle();

      expect(find.text('22.9'), findsOneWidget);
      expect(find.text('Healthy'), findsOneWidget);
    });

    testWidgets('saves metric figures even when entered in imperial',
        (tester) async {
      final profiles = FakeProfiles();
      await pumpCalculator(tester, profiles);

      await tester.tap(find.text('Imperial (ft/lb)'));
      await tester.pumpAndSettle();

      await tester.enterText(fieldWithSuffix('ft'), '5');
      await tester.enterText(fieldWithSuffix('in'), '9');
      await tester.enterText(fieldWithSuffix('lb'), '154');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Stored in metric, with the entry preference alongside it.
      expect(profiles.saved!.heightCm, closeTo(175.26, 0.01));
      expect(profiles.saved!.weightKg, closeTo(69.85, 0.01));
      expect(profiles.saved!.units, MeasurementUnits.imperial);
    });

    testWidgets('says what a healthy weight would be for the height',
        (tester) async {
      await pumpCalculator(
        tester,
        FakeProfiles(stored: const BodyMetrics(heightCm: 175, weightKg: 90)),
      );

      expect(
        find.textContaining('A healthy weight for your height is 57–77 kg'),
        findsOneWidget,
      );
    });

    testWidgets('carries the disclaimer', (tester) async {
      await pumpCalculator(tester, FakeProfiles());
      expect(find.textContaining('not a diagnosis'), findsOneWidget);
    });
  });
}
