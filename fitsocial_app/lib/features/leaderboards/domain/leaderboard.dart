/// Friends leaderboards: the people you follow, ordered on one figure.
///
/// The figures come from `leaderboardEntries/{uid}_{periodId}`
/// (functions/leaderboard.js), which is the server's projection of a week's or
/// month's stats down to the four numbers a board may rank. Those documents are
/// readable by the people who follow their owner and nobody else, so a board is
/// built from the viewer's own following list: the query names the entries it
/// wants, and the rules check every one it returns.
///
/// Three rules decide what a board says, and all three are here rather than in
/// the widget, because all three are the kind of thing that has to be testable:
///
///  * **Nobody appears at zero.** An entry exists when at least one of its four
///    figures is above zero, but a board shows one figure at a time. Somebody
///    with three sessions and no step sync belongs on the sessions board and
///    not on the steps board, where a 0 would read as a week spent sitting down.
///  * **Equal figures share a rank.** Two people on 40,000 steps are both
///    second, and the next person is fourth. Within a shared rank the order is
///    fixed -- more active days first, then user id -- so a board never
///    reshuffles between refreshes. That is the same final fallback the activity
///    challenge ranking uses, for the same reason.
///  * **You are always on your own board.** Past the cap the top of the board is
///    cut, but the viewer's own row is kept and shown at its real rank. A
///    leaderboard that cannot tell you where you came is not worth opening.
///
/// Nothing here knows about Firestore, which is what lets the ranking be tested
/// against hand-written rows.
library;

/// How many rows a board shows.
///
/// Fifty is well past the point anybody scrolls, and it is also the ceiling on
/// how many entry documents one board reads -- see
/// `FirestoreLeaderboardRepository` for why that number matters.
const kLeaderboardLimit = 50;

/// What a board ranks on.
enum LeaderboardMetric {
  steps('Steps', 'steps', ''),
  activeMinutes('Active minutes', 'activeMinutes', 'min'),
  sessions('Sessions', 'sessions', ''),
  streak('Best streak', 'streak', 'days');

  const LeaderboardMetric(this.label, this.field, this.unit);

  /// What the chip says.
  final String label;

  /// The field on the entry document. A fixed string: renaming the enum value
  /// must not change what is read out of Firestore.
  final String field;

  final String unit;
}

/// A week's board or a month's.
enum LeaderboardScope {
  week('This week', 'week'),
  month('This month', 'month');

  const LeaderboardScope(this.label, this.key);

  final String label;

  /// What the entry document's `scope` says, and what analytics reports.
  final String key;
}

/// One person's figures for one period, as the board needs them.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.userId,
    this.steps = 0,
    this.activeMinutes = 0,
    this.sessions = 0,
    this.streak = 0,
    this.activeDays = 0,
  });

  /// Reads an entry document. Absent or unreadable figures count as zero, which
  /// keeps an entry written by an older build from crashing a newer board.
  factory LeaderboardEntry.fromMap(String userId, Map<String, dynamic> data) {
    int read(String field) {
      final value = data[field];
      return value is num && value.isFinite && value > 0 ? value.round() : 0;
    }

    return LeaderboardEntry(
      userId: userId,
      steps: read('steps'),
      activeMinutes: read('activeMinutes'),
      sessions: read('sessions'),
      streak: read('streak'),
      activeDays: read('activeDays'),
    );
  }

  final String userId;
  final int steps;
  final int activeMinutes;
  final int sessions;
  final int streak;

  /// How many days of the period had a session. Shown as the one line of
  /// context under a name, and the first tiebreak between equal figures.
  final int activeDays;

  int valueOf(LeaderboardMetric metric) => switch (metric) {
        LeaderboardMetric.steps => steps,
        LeaderboardMetric.activeMinutes => activeMinutes,
        LeaderboardMetric.sessions => sessions,
        LeaderboardMetric.streak => streak,
      };
}

/// One line of a board.
///
/// Carries no name or face. Who a uid belongs to is `userProfileProvider`'s
/// answer, looked up by the row widget and cached across every screen that asks
/// — the same way the challenge board does it, rather than this feature keeping
/// a second copy of the profile cache.
class LeaderboardPlace {
  const LeaderboardPlace({
    required this.rank,
    required this.entry,
    required this.value,
    required this.isViewer,
  });

  /// Where this row came, counting from 1. Shared with anyone on the same
  /// figure.
  final int rank;

  final LeaderboardEntry entry;

  /// The figure for the metric the board is showing.
  final int value;

  /// Whether this is the person looking at the board.
  final bool isViewer;

  String get userId => entry.userId;
}

/// A board, ready to draw.
class LeaderboardBoard {
  const LeaderboardBoard({
    required this.metric,
    required this.rows,
    this.viewerRow,
  });

  static const empty = LeaderboardBoard(
    metric: LeaderboardMetric.steps,
    rows: <LeaderboardPlace>[],
  );

  final LeaderboardMetric metric;

  /// The top [kLeaderboardLimit] rows, best first.
  final List<LeaderboardPlace> rows;

  /// The viewer's own row when it fell outside [rows] — shown under them, so
  /// the board always answers "and where am I?". Null when the viewer is
  /// already in [rows], or has nothing on this board.
  final LeaderboardPlace? viewerRow;

  bool get isEmpty => rows.isEmpty;
}

/// Orders [entries] on [metric] and hands back a board.
///
/// [viewerId] is the person looking, who is ranked among everybody else — their
/// own entry is in [entries] like any other.
LeaderboardBoard buildBoard({
  required Iterable<LeaderboardEntry> entries,
  required LeaderboardMetric metric,
  required String? viewerId,
  int limit = kLeaderboardLimit,
}) {
  final ranked = entries.where((entry) => entry.valueOf(metric) > 0).toList()
    ..sort((a, b) {
      final byValue = b.valueOf(metric).compareTo(a.valueOf(metric));
      if (byValue != 0) return byValue;
      // Steadier first, then an arbitrary but fixed order. Arbitrary is the
      // point: it never changes, so two tied rows do not swap places every time
      // the board is opened.
      final byDays = b.activeDays.compareTo(a.activeDays);
      if (byDays != 0) return byDays;
      return a.userId.compareTo(b.userId);
    });

  final rows = <LeaderboardPlace>[];
  var rank = 0;
  int? previousValue;
  for (var i = 0; i < ranked.length; i++) {
    final entry = ranked[i];
    final value = entry.valueOf(metric);
    // Competition ranking: equal figures share a rank, and the rank after a
    // shared one skips the places it used up.
    if (value != previousValue) {
      rank = i + 1;
      previousValue = value;
    }
    rows.add(
      LeaderboardPlace(
        rank: rank,
        entry: entry,
        value: value,
        isViewer: entry.userId == viewerId,
      ),
    );
  }

  final top = rows.take(limit).toList(growable: false);
  final viewerRow = top.any((row) => row.isViewer)
      ? null
      : rows.where((row) => row.isViewer).firstOrNull;

  return LeaderboardBoard(metric: metric, rows: top, viewerRow: viewerRow);
}
