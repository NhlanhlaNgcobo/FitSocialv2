/// Badges — the permanent half of the reward system.
///
/// Three hooks pull in different directions on purpose. Points accumulate and
/// never go down. Streaks are fragile and can vanish overnight. Badges are
/// permanent and cannot be taken back *at all* — not by elimination, not by a
/// lapsed subscription, not by quitting. Somebody who reached day 50 and then
/// lost it still reached day 50, and the case on their profile has to keep
/// saying so, or the app is punishing people for the part they did do.
library;

/// Which surface a badge belongs to. Drives grouping on the profile shelf.
enum BadgeGroup {
  pulse75('Pulse 75'),
  earlyWorm('Early Worm'),
  general('FitSocial');

  const BadgeGroup(this.label);

  final String label;
}

/// The badge catalogue.
///
/// [key] is what lands in Firestore, and it is never derived from the constant
/// name: renaming a constant would otherwise orphan every badge already
/// awarded, and a badge that vanishes from a profile is the one bug this system
/// cannot afford.
enum ChallengeBadge {
  // --- Pulse 75 ---------------------------------------------------------
  dayOne(
    key: 'PULSE_DAY_ONE',
    label: 'Day One',
    description: 'Completed the first day of Pulse 75.',
    group: BadgeGroup.pulse75,
  ),
  firstWeek(
    key: 'PULSE_FIRST_WEEK',
    label: 'First Week',
    description: 'Held a 7-day Pulse 75 streak.',
    group: BadgeGroup.pulse75,
  ),
  lockedIn(
    key: 'PULSE_LOCKED_IN',
    label: 'Locked In',
    description: 'Held a 21-day Pulse 75 streak.',
    group: BadgeGroup.pulse75,
  ),
  ironMonth(
    key: 'PULSE_IRON_MONTH',
    label: 'Iron Month',
    description: 'Held a 30-day Pulse 75 streak.',
    group: BadgeGroup.pulse75,
  ),
  halfway(
    key: 'PULSE_HALFWAY',
    label: 'Halfway',
    description: '38 completed days. Past the middle.',
    group: BadgeGroup.pulse75,
  ),
  theGrind(
    key: 'PULSE_THE_GRIND',
    label: 'The Grind',
    description: '50 completed days of Pulse 75.',
    group: BadgeGroup.pulse75,
  ),
  comeback(
    key: 'PULSE_COMEBACK',
    label: 'Comeback',
    description: 'Rebuilt a 14-day streak after losing one.',
    group: BadgeGroup.pulse75,
  ),
  finisher(
    key: 'PULSE_75_FINISHER',
    label: 'Pulse 75 Finisher',
    description: '75 of 75 days. Done.',
    group: BadgeGroup.pulse75,
    repeatable: true,
  ),
  flawless(
    key: 'PULSE_FLAWLESS',
    label: 'Flawless',
    description: '75 days without missing one.',
    group: BadgeGroup.pulse75,
    repeatable: true,
  ),

  // --- Early Worm -------------------------------------------------------
  earlyWorm(
    key: 'EARLY_WORM',
    label: 'Early Worm',
    description: 'Posted a Pulse before 6 AM.',
    group: BadgeGroup.earlyWorm,
  ),
  dawnPatrol(
    key: 'EARLY_WORM_DAWN_PATROL',
    label: 'Dawn Patrol',
    description: '7 mornings in a row.',
    group: BadgeGroup.earlyWorm,
  ),
  sunriseSociety(
    key: 'EARLY_WORM_SUNRISE',
    label: 'Sunrise Society',
    description: '30 mornings in a row.',
    group: BadgeGroup.earlyWorm,
  ),
  fourAmClub(
    key: 'EARLY_WORM_4AM_CLUB',
    label: 'The 4AM Club',
    description: '100 mornings in a row.',
    group: BadgeGroup.earlyWorm,
  ),

  // --- General ----------------------------------------------------------
  firstPulse(
    key: 'FIRST_PULSE',
    label: 'First Pulse',
    description: 'Published your first Pulse.',
    group: BadgeGroup.general,
  ),
  century(
    key: 'POINTS_CENTURY',
    label: 'Century',
    description: 'Earned 100 points.',
    group: BadgeGroup.general,
  ),
  pointMachine(
    key: 'POINTS_MACHINE',
    label: 'Point Machine',
    description: 'Earned 10,000 points.',
    group: BadgeGroup.general,
  ),
  supporter(
    key: 'SUPPORTER',
    label: 'Supporter',
    description: 'Gave 100 reactions.',
    group: BadgeGroup.general,
  );

  const ChallengeBadge({
    required this.key,
    required this.label,
    required this.description,
    required this.group,
    this.repeatable = false,
  });

  /// The stored badge id.
  final String key;

  final String label;

  /// The line on the badge sheet — what the holder did, stated plainly.
  final String description;

  final BadgeGroup group;

  /// Whether a second run can earn it again. A repeatable badge is held once
  /// and carries a count, so a profile reads "Finisher x2" rather than showing
  /// the same art twice.
  final bool repeatable;

  static ChallengeBadge? byKey(String key) {
    for (final badge in values) {
      if (badge.key == key) return badge;
    }
    return null;
  }

  static List<ChallengeBadge> inGroup(BadgeGroup group) =>
      values.where((badge) => badge.group == group).toList(growable: false);

  /// Whether [facts] earn this badge.
  ///
  /// Every condition is a threshold on a number the server already maintains,
  /// which is what lets the same check run at finalisation and on a live event
  /// without either of them needing to reconstruct history.
  bool isEarnedBy(BadgeFacts facts) => switch (this) {
        dayOne => facts.pulseDaysCompleted >= 1,
        firstWeek => facts.pulseLongestStreak >= 7,
        lockedIn => facts.pulseLongestStreak >= 21,
        ironMonth => facts.pulseLongestStreak >= 30,
        halfway => facts.pulseDaysCompleted >= 38,
        theGrind => facts.pulseDaysCompleted >= 50,
        // A streak rebuilt to a fortnight *after* having lost one. The reset is
        // the condition, not incidental to it: this badge exists to say that
        // failing once and carrying on is worth marking.
        comeback => facts.pulseMissedDays > 0 && facts.pulseCurrentStreak >= 14,
        finisher => facts.pulseCompleted,
        flawless => facts.pulseCompleted && facts.pulseMissedDays == 0,
        earlyWorm => facts.earlyWormTotalDays >= 1,
        dawnPatrol => facts.earlyWormLongestStreak >= 7,
        sunriseSociety => facts.earlyWormLongestStreak >= 30,
        fourAmClub => facts.earlyWormLongestStreak >= 100,
        firstPulse => facts.pulsesPublished >= 1,
        century => facts.totalPoints >= 100,
        pointMachine => facts.totalPoints >= 10000,
        supporter => facts.reactionsGiven >= 100,
      };
}

/// Everything the award check needs to know, in one bag.
///
/// Deliberately flat numbers rather than the objects they came from. The Cloud
/// Function assembles the same set from Firestore, and a flat shape is what
/// keeps the two implementations checkable against each other.
class BadgeFacts {
  const BadgeFacts({
    this.pulseDaysCompleted = 0,
    this.pulseCurrentStreak = 0,
    this.pulseLongestStreak = 0,
    this.pulseMissedDays = 0,
    this.pulseCompleted = false,
    this.earlyWormLongestStreak = 0,
    this.earlyWormTotalDays = 0,
    this.totalPoints = 0,
    this.pulsesPublished = 0,
    this.reactionsGiven = 0,
  });

  /// Counters for the run being evaluated, not a lifetime total across runs.
  /// Two separate 40-day attempts do not add up to an 80-day badge.
  final int pulseDaysCompleted;
  final int pulseCurrentStreak;
  final int pulseLongestStreak;

  /// Missed days in this run. Zero is what Flawless is checking for.
  final int pulseMissedDays;

  final bool pulseCompleted;

  final int earlyWormLongestStreak;
  final int earlyWormTotalDays;

  final int totalPoints;
  final int pulsesPublished;
  final int reactionsGiven;

  /// Every badge these facts earn.
  List<ChallengeBadge> get earned => ChallengeBadge.values
      .where((badge) => badge.isEarnedBy(this))
      .toList(growable: false);

  /// The badges earned here that [held] does not already cover.
  ///
  /// Repeatable badges are excluded once held: a second Finisher is a count on
  /// the badge already awarded, not a new award, and the caller increments it
  /// separately when a run completes.
  List<ChallengeBadge> newlyEarned(Set<String> held) => earned
      .where((badge) => !held.contains(badge.key))
      .toList(growable: false);
}

/// A badge as awarded to somebody, read back for the profile shelf.
class UserBadge {
  const UserBadge({
    required this.badge,
    required this.awardedAt,
    this.count = 1,
    this.rarityPercent,
  });

  final ChallengeBadge badge;
  final DateTime awardedAt;

  /// How many times it has been earned. Only ever above one for a repeatable
  /// badge.
  final int count;

  /// The share of active users holding it, recomputed daily. Null until the
  /// aggregation has run — the shelf falls back to catalogue order rather than
  /// sorting on a number it does not have.
  final double? rarityPercent;

  /// "x2", or empty for a badge held once.
  String get countLabel => count > 1 ? 'x$count' : '';
}
