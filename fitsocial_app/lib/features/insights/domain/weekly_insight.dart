/// One finished week's Weekly Insight, as functions/insights.js stores it at
/// `users/{uid}/insights/{weekId}`.
///
/// The server has already validated everything in here against the output
/// contract and the safety rules; this class only reads it. A document that is
/// not `ready` carries no content, and the app shows nothing for it (or the
/// "not enough data yet" line for [InsightStatus.insufficient]).
library;

enum InsightStatus {
  ready,
  insufficient,
  generating,
  failed;

  static InsightStatus fromKey(Object? key) => switch (key) {
    'ready' => ready,
    'insufficient' => insufficient,
    'generating' => generating,
    _ => failed,
  };
}

enum TrendDirection {
  up,
  down,
  flat;

  static TrendDirection? fromKey(Object? key) => switch (key) {
    'up' => up,
    'down' => down,
    'flat' => flat,
    _ => null,
  };
}

class InsightTrend {
  const InsightTrend({
    required this.metric,
    required this.direction,
    required this.note,
  });

  /// `steps`, `active_minutes`, `sessions`, `streak`, `meals_logged` or
  /// `heart_rate`.
  final String metric;
  final TrendDirection direction;
  final String note;

  String get metricLabel => switch (metric) {
    'steps' => 'Steps',
    'active_minutes' => 'Active minutes',
    'sessions' => 'Sessions',
    'streak' => 'Streak',
    'meals_logged' => 'Meals logged',
    'heart_rate' => 'Heart rate',
    _ => metric,
  };
}

/// How a user rated an insight. The keys match the rules' allowed list.
enum InsightRating {
  veryHelpful('very_helpful', 'Very helpful'),
  somewhatHelpful('somewhat_helpful', 'Somewhat'),
  unhelpful('unhelpful', 'Not helpful'),
  offensive('offensive', 'Offensive');

  const InsightRating(this.key, this.label);

  final String key;
  final String label;

  static InsightRating? fromKey(Object? key) {
    for (final rating in values) {
      if (rating.key == key) return rating;
    }
    return null;
  }
}

class WeeklyInsight {
  const WeeklyInsight({
    required this.weekId,
    required this.status,
    this.headline = '',
    this.summary = '',
    this.wins = const [],
    this.trends = const [],
    this.suggestion = '',
    this.partialWeek = false,
    this.wellbeingNote = false,
  });

  final String weekId;
  final InsightStatus status;
  final String headline;
  final String summary;
  final List<String> wins;
  final List<InsightTrend> trends;
  final String suggestion;

  /// True when only part of the week had data, so the app can say so.
  final bool partialWeek;

  /// Set by the server when the week's meal logging looked like very low
  /// intake. Shows [kWellbeingNote]; the insight itself never mentions food
  /// amounts either way.
  final bool wellbeingNote;

  /// Ready and with something to show. Anything else draws no insight.
  bool get hasContent =>
      status == InsightStatus.ready &&
      headline.isNotEmpty &&
      summary.isNotEmpty;

  static WeeklyInsight fromMap(String weekId, Map<String, dynamic> data) {
    final status = InsightStatus.fromKey(data['status']);
    final wellbeingNote = data['wellbeingNote'] == true;
    final content = data['insight'];
    if (status != InsightStatus.ready || content is! Map) {
      return WeeklyInsight(
        weekId: weekId,
        // Ready with no content is a broken document: shown as nothing.
        status: status == InsightStatus.ready ? InsightStatus.failed : status,
        wellbeingNote: wellbeingNote,
      );
    }

    String text(Object? value) => value is String ? value.trim() : '';
    final wins = <String>[
      for (final win in (content['wins'] as List?) ?? const [])
        if (text(win).isNotEmpty) text(win),
    ];
    final trends = <InsightTrend>[];
    for (final raw in (content['trends'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final direction = TrendDirection.fromKey(raw['direction']);
      final note = text(raw['note']);
      final metric = text(raw['metric']);
      if (direction == null || note.isEmpty || metric.isEmpty) continue;
      trends.add(
        InsightTrend(metric: metric, direction: direction, note: note),
      );
    }

    return WeeklyInsight(
      weekId: weekId,
      status: status,
      headline: text(content['headline']),
      summary: text(content['summary']),
      wins: wins,
      trends: trends,
      suggestion: text(content['suggestion']),
      partialWeek: content['dataQuality'] == 'partial',
      wellbeingNote: wellbeingNote,
    );
  }
}

/// Shown when [WeeklyInsight.wellbeingNote] is set.
///
/// Wording signed off by Bear on 2026-10-02, as spec section 7.1 requires.
/// Change it only with the same sign-off.
const String kWellbeingNote =
    'Looking after yourself matters more than any number in this app. '
    'If anything about food or eating is worrying you, a doctor or a '
    'registered dietitian can help.';
