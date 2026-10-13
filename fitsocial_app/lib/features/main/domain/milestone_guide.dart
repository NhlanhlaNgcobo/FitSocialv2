import '../../challenges/domain/challenge_badges.dart';
import '../../challenges/domain/challenge_points.dart';
import 'app_models.dart';

/// What milestones are and how each one is earned, in words.
///
/// Testers saw a milestone in their feed and could not tell what it was or why
/// they had it. The card said *what* — "Century, Earned 100 points" — and
/// nothing anywhere said how points are earned. This is that missing half,
/// written once and read by the milestone card's sheet, the guide screen and
/// the Achievements page, so the three can never explain the same thing two
/// different ways.
abstract final class MilestoneGuide {
  /// Streak lengths that earn a milestone post. MUST MATCH
  /// `STREAK_MILESTONES` in functions/milestones.js, which decides them.
  static const streakDays = [
    3, 7, 14, 21, 30, 50, 75, 100, 150, 200, 250, 300, 365, //
  ];

  /// Earlier runs needed before a run can be a personal best. Matches
  /// `MIN_PRIOR_RUNS` in functions/milestones.js.
  static const minPriorRuns = 3;

  /// The shortest run whose pace can stand as a best. Matches `PACE_MIN_KM`.
  static const paceMinKm = 5;

  /// What counts towards a streak — the writes that advance `currentStreak`.
  static const streakActivity = 'a workout, run or meal, or posted';

  /// "3, 7, 14, 21, 30, 50, 75, 100, 150, 200, 250, 300 and 365 days".
  static String get streakDaysLabel {
    final days = streakDays.map((d) => '$d').toList();
    return '${days.sublist(0, days.length - 1).join(', ')} and ${days.last} '
        'days';
  }

  /// How [milestone] was earned, as one or two sentences.
  static String howEarned(PostMilestone milestone) {
    if (milestone.isStreak) {
      final days = int.tryParse(milestone.key.replaceFirst('streak_', ''));
      final run = days == null ? 'several days' : '$days days';
      return 'Logged $streakActivity, on $run in a row. Streak milestones '
          'land at $streakDaysLabel, then every 100 days after that.';
    }
    if (milestone.isPersonalBest) {
      const rule = 'Personal bests count once there are at least '
          '$minPriorRuns earlier runs to beat, and only for runs shared to '
          'the feed.';
      return switch (milestone.key) {
        'longest_run' => 'A run farther than any run logged before it. $rule',
        'fastest_5k_pace' => 'The quickest pace per km yet on a run of '
            '$paceMinKm km or more. $rule',
        _ => rule,
      };
    }

    final badge = ChallengeBadge.byKey(milestone.key);
    if (badge == null) {
      return 'A badge, awarded automatically when its goal is reached.';
    }
    final earned = 'A badge: ${_sentence(badge.description)}';
    return switch (badge) {
      ChallengeBadge.century ||
      ChallengeBadge.pointMachine =>
        '$earned ${pointsSummary()}',
      _ => earned,
    };
  }

  /// One paragraph on where points come from, built from the same rule table
  /// the server pays from.
  static String pointsSummary() {
    String rule(PointsEvent event) => generalPointsRules
        .where((r) => r.event == event)
        .map((r) => '${r.points}')
        .first;
    return 'Points come from logging a workout of '
        '$generalWorkoutMinimumMinutes+ minutes (${rule(PointsEvent.workoutLogged)}), '
        'a meal (${rule(PointsEvent.mealLogged)}) or a Pulse '
        '(${rule(PointsEvent.pulsePublished)}), from every reaction on your '
        'posts (${rule(PointsEvent.likeReceived)}) and every comment you '
        'leave on a Pulse (${rule(PointsEvent.commentGiven)}), each up to a '
        'daily limit, plus Pulse 75 and Early Worm.';
  }

  /// The everyday ways to earn points, as rows for a table.
  ///
  /// Only the rules the server actually pays. `challengeCompleted` is in the
  /// client's table but not in functions/challenges.js `GENERAL_RULES`, so it
  /// is left off rather than promised.
  static List<PointsWay> get everydayPoints => [
        for (final rule in generalPointsRules)
          if (_everydayLabels[rule.event] case final label?)
            PointsWay(
              label: label,
              points: rule.points,
              dailyCap: rule.dailyCap,
            ),
      ];

  static const _everydayLabels = {
    PointsEvent.workoutLogged:
        'Log a workout of $generalWorkoutMinimumMinutes+ minutes',
    PointsEvent.mealLogged: 'Log a meal',
    PointsEvent.pulsePublished: 'Post a Pulse',
    PointsEvent.likeReceived: 'Get a reaction on a post',
    PointsEvent.commentGiven: 'Comment on a Pulse',
  };

  static String _sentence(String text) {
    if (text.isEmpty) return text;
    return text[0].toLowerCase() + text.substring(1);
  }
}

/// One way to earn points, as the guide's table shows it.
class PointsWay {
  const PointsWay({
    required this.label,
    required this.points,
    required this.dailyCap,
  });

  final String label;
  final int points;

  /// How many a day pay. Null for no limit.
  final int? dailyCap;
}
