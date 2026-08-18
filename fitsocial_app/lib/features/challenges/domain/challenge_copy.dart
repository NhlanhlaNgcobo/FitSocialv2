/// Every string the challenge system shows.
///
/// One file rather than literals scattered through widgets, because this copy
/// is a product decision that will be tuned, and tuning it should not mean
/// hunting through fifteen build methods.
///
/// The tone is deliberate and it is not decoration. Short sentences. Full stops
/// rather than exclamation marks. No congratulating somebody for doing what
/// they said they would do — state the achievement instead. Never apologise to
/// a user for their own missed day, and never use the word "journey". The user
/// chose a hard thing; the copy treats them as capable of hearing about it.
library;

import 'challenge_models.dart';
import 'challenge_task.dart';

class ChallengeCopy {
  const ChallengeCopy._();

  // --- Identity ---------------------------------------------------------

  static const String pulse75Title = 'PULSE 75';
  static const String pulse75Tagline = '7 TASKS. EVERY DAY. 75 DAYS.';
  static const String pulse75Blurb =
      'The hardest challenge in FitSocial. Seven tasks, every day, for '
      '75 days. All seven or the day does not count.';
  static const String pulse75FailureRule =
      'Miss three days in a row and you are ELIMINATED. There is no restart.';

  static const String earlyWormTitle = 'EARLY WORM';
  static const String earlyWormTagline = 'POST BEFORE 6 AM.';
  static const String earlyWormBlurb =
      'Always on, free for everyone. Post a Pulse between 4 and 6 in the '
      'morning and the day counts. Miss one and the streak goes back to zero.';
  static const String earlyWormFailureRule =
      'No elimination. Nothing to join. Just do not miss a morning.';

  // --- Enrollment -------------------------------------------------------

  static const String enterPulse75 = 'ENTER PULSE 75';
  static const String openTracker = 'OPEN TRACKER';
  static const String enrolled = "YOU'RE IN. Day 1 starts now.";
  static const String quitPulse75 = 'QUIT PULSE 75';
  static const String quitConfirmTitle = 'Quit Pulse 75?';
  static const String quitConfirmBody =
      'Your record stays. Your run ends here, and starting again means '
      'starting at day 1.';

  /// What the enrollment sheet says before the user commits. Everything that
  /// can end their run is stated here, before they enter — being eliminated by
  /// a rule nobody mentioned is how you lose somebody for good.
  static const String enrollmentTerms =
      'All seven tasks, before midnight, in your own timezone. Six of seven '
      'is an incomplete day. Three incomplete days in a row and the run is '
      'over.';

  // --- Status -----------------------------------------------------------

  static const String atRiskTitle = 'ONE DAY MISSED';
  static const String dangerTitle = 'TWO DAYS MISSED';
  static const String eliminatedTitle = 'ELIMINATED';
  static const String completedTitle = 'PULSE 75 COMPLETE';

  static String atRiskBody(int missesRemaining) =>
      'Your streak is back to zero. $missesRemaining more missed '
      '${missesRemaining == 1 ? 'day' : 'days'} and you are out.';

  static const String dangerBody =
      'Complete tomorrow or you are eliminated from Pulse 75.';

  static const String eliminatedBody =
      'Three days missed in a row. Your record stands and your badges stay.';

  static const String runItBack = 'RUN IT BACK';
  static const String shareIt = 'SHARE IT';

  /// The line on the completion card. 525 is 75 days of seven tasks.
  static String completionCard(int days) =>
      'I COMPLETED PULSE 75 — $days DAYS • ${days * ChallengeTask.values.length} TASKS • 0 EXCUSES';

  // --- Tracker ----------------------------------------------------------

  static const String todayHeading = 'TODAY';
  static const String currentStreak = 'CURRENT STREAK';
  static const String bestStreak = 'BEST STREAK';
  static const String challengeProgress = 'CHALLENGE PROGRESS';
  static const String pointsThisChallenge = 'POINTS THIS CHALLENGE';
  static const String manualTaskNote = 'You track this one yourself.';

  /// Shown when a tap on water or reading did not reach the server.
  ///
  /// Said out loud rather than swallowed. These two counters are the only ones
  /// the user moves by hand, so a tap that quietly goes nowhere reads as the
  /// tracker being broken — which is exactly how it read to the tester who
  /// found the rule that was refusing every one of these writes.
  static const String manualTaskFailed =
      "Couldn't save that. Check your connection and tap again.";
  static const String automaticTaskNote =
      'Read from your logs. It cannot be ticked by hand.';

  /// The day's headline: "DAY 24 — 5 / 7".
  static String dayHeadline(int dayNumber, String tasksLabel) =>
      'DAY $dayNumber — $tasksLabel';

  /// What a finalised day locking means, said once on the tracker.
  static const String cutoffNote =
      'The day closes at midnight. Logs still land until 2 AM, so a late '
      'session counts.';

  // --- Notifications ----------------------------------------------------

  static String morningNudge(int dayNumber) =>
      'PULSE 75 — DAY $dayNumber. Your seven tasks are waiting.';

  /// The evening warning, naming only what is actually outstanding.
  ///
  /// A reminder about a task finished four hours ago is how a useful nudge
  /// turns into the notification a user switches off, so the caller passes the
  /// outstanding list and nothing else is ever mentioned.
  static String outstandingNudge(int dayNumber, List<TaskProgress> outstanding) {
    if (outstanding.isEmpty) {
      return 'PULSE 75 — DAY $dayNumber is done. All seven.';
    }
    final parts = outstanding
        .map((task) => '${task.task.label} ${task.remainingLabel}')
        .join('   ');
    final count = outstanding.length;
    return 'PULSE 75 — DAY $dayNumber. $count '
        '${count == 1 ? 'task' : 'tasks'} left: $parts';
  }

  static String finalHours(List<TaskProgress> outstanding) {
    final parts = outstanding
        .map((task) => '${task.task.label} ${task.remainingLabel}')
        .join('   ');
    return 'FINAL HOURS. Your streak is at risk: $parts';
  }

  // --- Status lines -----------------------------------------------------

  /// The one-line state the strip and the leaderboard row show.
  static String statusLine(ChallengeEnrollment enrollment) {
    final progress = enrollment.progress;
    return switch (progress.status) {
      EnrollmentStatus.completed => completedTitle,
      EnrollmentStatus.eliminated => eliminatedTitle,
      EnrollmentStatus.abandoned => 'LEFT PULSE 75',
      EnrollmentStatus.danger => dangerTitle,
      EnrollmentStatus.atRisk => atRiskTitle,
      EnrollmentStatus.active => 'PULSE 75 — ${enrollment.dayLabel()}',
    };
  }

  /// The recruitment line where a strip would otherwise be empty. One
  /// challenge, stated flatly — the hub is a tap away for anyone curious.
  static const String noActiveChallenge = 'NO CHALLENGE RUNNING.';
  static const String recruit = 'Seven tasks. Every day. 75 days.';
}
