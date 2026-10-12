import 'dart:io';

import 'package:fitsocial_app/features/challenges/application/challenge_providers.dart';
import 'package:fitsocial_app/features/challenges/domain/challenge_points.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/milestone_guide.dart';
import 'package:fitsocial_app/features/main/presentation/achievements_screen.dart';
import 'package:fitsocial_app/features/main/presentation/milestones_guide_screen.dart';
import 'package:fitsocial_app/shared/widgets/milestone_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

PostMilestone milestone(String kind, String key) => PostMilestone(
      kind: kind,
      key: key,
      title: 'Title',
      subtitle: 'Subtitle',
      emoji: '🔥',
    );

void main() {
  group('how a milestone is earned', () {
    test('a streak names its length and what counts', () {
      final text = MilestoneGuide.howEarned(milestone('streak', 'streak_7'));
      expect(text, contains('7 days in a row'));
      expect(text, contains('workout, run or meal'));
    });

    test('a personal best says it needs history and a shared run', () {
      final text =
          MilestoneGuide.howEarned(milestone('personalBest', 'longest_run'));
      expect(text, contains('farther than any run'));
      expect(text, contains('3 earlier runs'));
      expect(text, contains('shared to the feed'));
    });

    test('the points badges explain where points come from', () {
      final text =
          MilestoneGuide.howEarned(milestone('badge', 'POINTS_CENTURY'));
      expect(text, contains('100 points'));
      expect(text, contains('logging a workout'));
      expect(text, contains('reaction'));
    });

    test('an unknown badge still says something', () {
      expect(
        MilestoneGuide.howEarned(milestone('badge', 'NOT_A_BADGE')),
        isNotEmpty,
      );
    });
  });

  test('the streak days are the ones the server posts at', () {
    // functions/milestones.js decides when a streak milestone is posted; the
    // guide only describes it. Read the server's list rather than trusting a
    // comment to keep the two in step.
    final source = File('functions/milestones.js').readAsStringSync();
    final match =
        RegExp(r'const STREAK_MILESTONES = \[([^\]]*)\]').firstMatch(source);
    expect(match, isNotNull);
    final serverDays =
        match!.group(1)!.split(',').map((s) => int.parse(s.trim())).toList();
    expect(MilestoneGuide.streakDays, serverDays);
  });

  test('everyday points list only what the server pays', () {
    final labels = MilestoneGuide.everydayPoints.map((w) => w.label).toList();
    expect(labels, hasLength(5));
    expect(labels.any((l) => l.contains('challenge')), isFalse);
    final workout = MilestoneGuide.everydayPoints
        .firstWhere((w) => w.label.startsWith('Log a workout'));
    expect(workout.points, 5);
    expect(workout.dailyCap, 2);
  });

  group('a points award gives its reason', () {
    PointsEntry entry(PointsEvent event,
            {int amount = 5, String? taskKey, double multiplier = 1}) =>
        PointsEntry(
          id: 'e',
          event: event,
          amount: amount,
          createdAt: DateTime(2026, 10, 12),
          taskKey: taskKey,
          multiplier: multiplier,
        );

    test('everyday awards', () {
      expect(entry(PointsEvent.workoutLogged).reason, 'Logged a workout');
      expect(entry(PointsEvent.likeReceived).reason, 'A reaction on your post');
    });

    test('a Pulse 75 task names the task', () {
      expect(
        entry(PointsEvent.task, taskKey: 'runWalk').reason,
        'Pulse 75 · Run / Walk',
      );
      expect(entry(PointsEvent.task).reason, 'Pulse 75 task');
    });

    test('a perfect day shows its streak multiplier', () {
      expect(
        entry(PointsEvent.dayCompleteBonus, multiplier: 1.5).reason,
        'Pulse 75 · Perfect day, streak ×1.5',
      );
      expect(
        entry(PointsEvent.dayCompleteBonus, multiplier: 2).reason,
        'Pulse 75 · Perfect day, streak ×2',
      );
      expect(
          entry(PointsEvent.dayCompleteBonus).reason, 'Pulse 75 · Perfect day');
    });

    test('a reversal says why it is negative', () {
      final reversal = entry(PointsEvent.reversal, amount: -5);
      expect(reversal.isReversal, isTrue);
      expect(reversal.reason, contains('no longer counts'));
    });
  });

  testWidgets('the milestone card explains itself on tap', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MilestoneCard(
            milestone: const PostMilestone(
              kind: 'badge',
              key: 'POINTS_CENTURY',
              title: 'Century',
              subtitle: 'Earned 100 points',
              emoji: '💯',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text("How it's earned"));
    await tester.pumpAndSettle();

    expect(find.text("HOW IT'S EARNED"), findsOneWidget);
    expect(find.textContaining('Points come from'), findsOneWidget);
    expect(find.text('All milestones and points'), findsOneWidget);
  });

  testWidgets('the guide lists the kinds, the points and every badge',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: MilestonesGuideScreen()),
    );

    expect(find.text('Streaks'), findsOneWidget);
    expect(find.text('Personal bests'), findsOneWidget);
    expect(find.text('Badges'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('HOW POINTS WORK'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Log a meal'), findsOneWidget);

    await tester.scrollUntilVisible(
        find.textContaining('Earned 100 points', findRichText: true), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Century', findRichText: true), findsOneWidget);
  });

  testWidgets('achievements shows where the points came from', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('me'),
          myPointsProvider.overrideWith((ref) => Stream.value(6)),
          myPointsHistoryProvider.overrideWith(
            (ref) => Stream.value([
              PointsEntry(
                id: 'a',
                event: PointsEvent.workoutLogged,
                amount: 5,
                createdAt: DateTime.now(),
              ),
              PointsEntry(
                id: 'b',
                event: PointsEvent.likeReceived,
                amount: 1,
                createdAt: DateTime.now(),
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: AchievementsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('How points work'), findsOneWidget);
    expect(find.text('RECENT POINTS'), findsOneWidget);
    expect(find.text('Logged a workout'), findsOneWidget);
    expect(find.text('+5'), findsOneWidget);
    expect(find.text('A reaction on your post'), findsOneWidget);
  });
}
