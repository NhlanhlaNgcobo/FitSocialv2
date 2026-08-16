/// Points — the app-wide engagement currency.
///
/// Points and streaks are separate systems and must stay separate. A Pulse 75
/// day is complete on a strict 7/7 and nothing else; points never decide it.
/// What points do is give a user credit for a 5/7 day, rank them across
/// challenges, and give a free user something to accumulate. Conflating the two
/// would turn the challenge into something you can buy your way through with
/// the two self-reported tasks.
library;

import 'challenge_task.dart';

/// What each Pulse 75 task pays when completed.
///
/// Automatic tasks pay more than manual ones, deliberately. Water and reading
/// are on the user's honour; a workout, a run, 12,000 steps and three logged
/// meals are not. Effort the app can verify is worth more than effort it has to
/// take on trust, and the gap is what stops the manual pair from being the
/// cheap route to a high score.
///
/// The seven sum to 70. With the day-complete bonus at its base rate that makes
/// a perfect day exactly 100, which is the point: 75 perfect days is 7,500, and
/// a user can do that arithmetic in their head.
const Map<ChallengeTask, int> taskPoints = {
  ChallengeTask.workout: 15,
  ChallengeTask.runWalk: 15,
  ChallengeTask.steps: 10,
  ChallengeTask.nutrition: 10,
  ChallengeTask.water: 5,
  ChallengeTask.reading: 5,
  ChallengeTask.pulse: 10,
};

/// The bonus for clearing all seven, before the streak multiplier.
const int dayCompleteBaseBonus = 30;

/// Paid once, on the day the 75th day completes.
const int finisherBonus = 500;

/// An Early Worm morning.
const int earlyWormPoints = 10;

/// Paid on every 7th consecutive Early Worm day.
const int earlyWormStreakBonus = 25;

/// How often the Early Worm streak bonus lands.
const int earlyWormStreakInterval = 7;

/// The multiplier on the day-complete bonus at a given streak.
///
/// The multiplier scales the *bonus* and never the task points. That cap is
/// the anti-gaming rule: at a 60-day streak a manual task is still worth 5,
/// so there is no point at which lying about water becomes lucrative.
///
/// [streak] is the streak the day itself produces — the value after this day's
/// increment. Completing your seventh day in a row pays at x1.5, not x1.0.
double streakMultiplier(int streak) {
  if (streak >= 50) return 2.5;
  if (streak >= 21) return 2.0;
  if (streak >= 7) return 1.5;
  return 1.0;
}

/// The day-complete bonus actually paid at [streak].
int dayCompleteBonus(int streak) =>
    (dayCompleteBaseBonus * streakMultiplier(streak)).round();

/// What the seven tasks pay between them, before any bonus. 70.
///
/// Exported rather than kept as an implementation detail of [perfectDayTotal]
/// because the detail screen lists all seven task values in a column and then
/// states what a perfect day is worth. A reader who adds that column gets 70,
/// so the screen has to be able to name the 70 and say where the rest came
/// from — otherwise the larger number reads as an error.
int get taskPointsTotal =>
    taskPoints.values.fold(0, (sum, value) => sum + value);

/// Everything a perfect day is worth at [streak] — the seven tasks plus the
/// bonus. 100 at the start, 145 in the last stretch.
int perfectDayTotal(int streak) => taskPointsTotal + dayCompleteBonus(streak);

/// What the ledger calls each kind of award.
///
/// Stored as strings, so the enum name is never what lands in Firestore —
/// [key] is. The Cloud Functions write these same strings; changing one here
/// without changing it there breaks every total.
enum PointsEvent {
  task('task'),
  dayCompleteBonus('day_complete_bonus'),
  finisher('finisher_bonus'),
  earlyWorm('early_worm'),
  earlyWormStreak('early_worm_streak'),
  pulsePublished('pulse_published'),
  workoutLogged('workout_logged'),
  mealLogged('meal_logged'),
  likeReceived('like_received'),
  commentGiven('comment_given'),
  challengeCompleted('challenge_completed'),
  reversal('reversal');

  const PointsEvent(this.key);

  final String key;

  static PointsEvent? byKey(String key) {
    for (final event in values) {
      if (event.key == key) return event;
    }
    return null;
  }
}

/// General engagement points, outside any challenge.
///
/// These exist so a free user still accumulates something. Each carries a daily
/// cap, because an uncapped point for a received like is an invitation to farm
/// them, and a leaderboard that rewards farming stops meaning anything.
class GeneralPointsRule {
  const GeneralPointsRule({
    required this.event,
    required this.points,
    required this.dailyCap,
  });

  final PointsEvent event;

  /// What one occurrence pays.
  final int points;

  /// How many occurrences pay per day. Null means uncapped — used only for
  /// one-time awards, which cap themselves.
  final int? dailyCap;

  /// The most this rule can pay in a single day.
  int? get dailyMaximum => dailyCap == null ? null : points * dailyCap!;
}

const List<GeneralPointsRule> generalPointsRules = [
  GeneralPointsRule(
    event: PointsEvent.pulsePublished,
    points: 5,
    dailyCap: 3,
  ),
  GeneralPointsRule(
    event: PointsEvent.workoutLogged,
    points: 5,
    dailyCap: 2,
  ),
  GeneralPointsRule(
    event: PointsEvent.mealLogged,
    points: 2,
    dailyCap: 3,
  ),
  GeneralPointsRule(
    event: PointsEvent.likeReceived,
    points: 1,
    dailyCap: 20,
  ),
  GeneralPointsRule(
    event: PointsEvent.commentGiven,
    points: 1,
    dailyCap: 10,
  ),
  GeneralPointsRule(
    event: PointsEvent.challengeCompleted,
    points: 50,
    dailyCap: null,
  ),
];

/// The minimum a logged workout must run to earn general points at all.
const int generalWorkoutMinimumMinutes = 20;

/// One row of the points ledger.
///
/// A ledger rather than a running total on the user document, and that is a
/// design decision worth keeping: a total can only ever be trusted as far as
/// every write that touched it. When a GPS activity is later flagged as a car
/// journey, a ledger lets exactly that award be reversed with a negative row,
/// leaving an audit trail. A mutable integer would have to be guessed at.
class PointsEntry {
  const PointsEntry({
    required this.id,
    required this.event,
    required this.amount,
    required this.createdAt,
    this.sourceId,
    this.multiplier = 1.0,
    this.dayKey,
    this.enrollmentId,
  });

  final String id;
  final PointsEvent event;

  /// Negative on a reversal. Everything else is additive — points already
  /// earned are never taken back by elimination.
  final int amount;

  final DateTime createdAt;

  /// What earned it: an activity id, a post id, a day key. The handle a
  /// reversal is found by.
  final String? sourceId;

  final double multiplier;
  final String? dayKey;
  final String? enrollmentId;

  bool get isReversal => amount < 0;
}
