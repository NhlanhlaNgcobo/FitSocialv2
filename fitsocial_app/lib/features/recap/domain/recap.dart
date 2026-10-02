/// Recap Cards (Build 11, F5): a shareable image of a finished week, a
/// challenge result, or a badge.
///
/// A card is plain data plus the sharer's choices. Nothing goes on the image
/// that [RecapOptions] has not let through, and the defaults keep the
/// sensitive figure -- heart rate -- off. Challenge cards carry only the
/// sharer's own place and the number of people in it, never anybody else's
/// name or figure.
library;

enum RecapKind {
  week('week'),
  challenge('challenge'),
  achievement('achievement');

  const RecapKind(this.key);

  /// For analytics.
  final String key;
}

/// One figure on a card.
class RecapStat {
  const RecapStat({
    required this.label,
    required this.value,
    this.sensitive = false,
  });

  final String label;
  final String value;

  /// A health figure, shown only when the sharer turns it on.
  final bool sensitive;
}

/// What the sharer chose to put on the image.
class RecapOptions {
  const RecapOptions({
    this.showName = true,
    this.showNumbers = true,
    this.showHeartRate = false,
  });

  final bool showName;
  final bool showNumbers;

  /// Off by default, per the spec: heart rate is health data.
  final bool showHeartRate;

  RecapOptions copyWith({
    bool? showName,
    bool? showNumbers,
    bool? showHeartRate,
  }) =>
      RecapOptions(
        showName: showName ?? this.showName,
        showNumbers: showNumbers ?? this.showNumbers,
        showHeartRate: showHeartRate ?? this.showHeartRate,
      );
}

class RecapCardData {
  const RecapCardData({
    required this.kind,
    required this.eyebrow,
    required this.headline,
    this.hero,
    this.subline,
    this.stats = const [],
    this.displayName,
  });

  final RecapKind kind;

  /// The small line on top: "WEEK OF 21 SEP", "CHALLENGE RESULT".
  final String eyebrow;
  final String headline;

  /// The one big figure, when the card has one: "#2", a badge's icon text.
  /// Counts as a number, so it goes when numbers are hidden.
  final String? hero;

  /// A line under the headline: "of 6 people", a badge's description.
  final String? subline;
  final List<RecapStat> stats;

  /// The sharer's own public name, when known.
  final String? displayName;

  bool get hasSensitiveStats => stats.any((stat) => stat.sensitive);

  /// The figures [options] lets onto the image.
  List<RecapStat> statsFor(RecapOptions options) {
    if (!options.showNumbers) return const [];
    return [
      for (final stat in stats)
        if (!stat.sensitive || options.showHeartRate) stat,
    ];
  }

  String? nameFor(RecapOptions options) {
    final name = displayName?.trim();
    return options.showName && name != null && name.isNotEmpty ? name : null;
  }
}

/// `61,000` for 61000.
String formatRecapNumber(num value) {
  final digits = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

const _months = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];

/// "WEEK OF 21 SEP" for a week starting on [startDayKey] (`YYYY-MM-DD`).
String weekEyebrow(String startDayKey) {
  final month = int.parse(startDayKey.substring(5, 7));
  final day = int.parse(startDayKey.substring(8, 10));
  return 'WEEK OF $day ${_months[month - 1]}';
}

/// A finished week's card, from its `weeklyStats` document and the number of
/// weekly goals completed in it. Null when the week had nothing in it -- an
/// empty card is not worth sharing.
RecapCardData? weekRecapFrom(
  Map<String, dynamic>? stats, {
  required int goalsHit,
  String? displayName,
}) {
  if (stats == null) return null;
  int read(String key) => (stats[key] as num?)?.round() ?? 0;
  if (read('daysWithData') == 0) return null;

  final startDayKey = stats['startDayKey'];
  final heartRate = (stats['avgHeartRate'] as num?)?.round();
  return RecapCardData(
    kind: RecapKind.week,
    eyebrow: startDayKey is String && startDayKey.length == 10
        ? weekEyebrow(startDayKey)
        : 'MY WEEK',
    headline: 'My week',
    stats: [
      // Steps net of anything typed in by hand, like every ranked figure.
      if (read('daysWithSteps') > 0)
        RecapStat(
          label: 'Steps',
          value: formatRecapNumber(
            stats['rankableSteps'] is num
                ? read('rankableSteps')
                : read('steps'),
          ),
        ),
      RecapStat(
          label: 'Active minutes',
          value: formatRecapNumber(read('activeMinutes'))),
      RecapStat(label: 'Sessions', value: '${read('sessions')}'),
      RecapStat(label: 'Best streak', value: '${read('longestStreak')} days'),
      if (goalsHit > 0) RecapStat(label: 'Goals hit', value: '$goalsHit'),
      if (heartRate != null && heartRate > 0)
        RecapStat(
            label: 'Avg heart rate', value: '$heartRate bpm', sensitive: true),
    ],
    displayName: displayName,
  );
}

/// A finished challenge's card: the sharer's own place out of how many, and
/// their own result. Nobody else's name or figure, by construction -- there
/// is no parameter to put one in.
RecapCardData challengeRecap({
  required String title,
  required int finalRank,
  required int participantCount,
  required String result,
  String? displayName,
}) {
  final people =
      '$participantCount ${participantCount == 1 ? 'person' : 'people'}';
  return RecapCardData(
    kind: RecapKind.challenge,
    eyebrow: 'CHALLENGE RESULT',
    headline: title,
    hero: '#$finalRank',
    subline: 'Finished #$finalRank of $people',
    stats: [
      if (result.trim().isNotEmpty)
        RecapStat(label: 'My result', value: result.trim())
    ],
    displayName: displayName,
  );
}

/// An unlocked badge's card.
RecapCardData achievementRecap({
  required String label,
  required String description,
  int count = 1,
  String? displayName,
}) {
  return RecapCardData(
    kind: RecapKind.achievement,
    eyebrow: 'ACHIEVEMENT UNLOCKED',
    headline: label,
    subline: description,
    stats: [if (count > 1) RecapStat(label: 'Times earned', value: '$count')],
    displayName: displayName,
  );
}
