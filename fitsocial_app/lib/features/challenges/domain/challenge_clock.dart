/// The clock a challenge is judged by.
///
/// Every rule in the challenge system turns on one question: which day did that
/// happen on? The answer is never UTC. A user who trains at 22:00 in
/// Johannesburg has trained on *their* Tuesday, and a server that files it
/// under Wednesday has taken their streak away over a timezone.
///
/// So the whole module works in the user's local wall clock, and this class is
/// the only place that conversion happens.
library;

/// A user's local clock, expressed as a fixed offset from UTC.
///
/// Offset minutes rather than an IANA zone id, for a practical reason: Flutter
/// has no timezone database, `DateTime.timeZoneName` yields an abbreviation
/// ("SAST") rather than a zone id, and pulling in a full tz package to serve
/// one number is not worth the weight. The client knows its own offset exactly
/// and re-stamps it on every write, so the stored value is never more than one
/// app-open stale.
///
/// The cost of that choice is honest and small: in a zone that observes DST,
/// the two days around a transition are judged against the previous offset
/// until the app is next opened. South Africa — the launch market — has no DST
/// at all. If the app later ships somewhere that does, this is the class to
/// replace, and nothing above it has to change.
class ChallengeClock {
  const ChallengeClock({required this.utcOffsetMinutes});

  /// The clock of the device this is running on, right now.
  factory ChallengeClock.ofDevice([DateTime? now]) {
    return ChallengeClock(
      utcOffsetMinutes: (now ?? DateTime.now()).timeZoneOffset.inMinutes,
    );
  }

  /// Minutes east of UTC. Johannesburg is +120.
  final int utcOffsetMinutes;

  /// The hour a day stops accepting activity — 02:00 the following morning.
  ///
  /// Not midnight, deliberately. Late-night training is normal, and somebody
  /// who finishes at 23:50 and gets the log saved at 00:10 has trained on the
  /// day they think they have. Two hours is wide enough to cover that and
  /// narrow enough that nobody is filling in yesterday over breakfast.
  static const int finalisationHour = 2;

  /// The window that credits an Early Worm post: 04:00:00 to 05:59:59 local.
  static const int earlyWormStartHour = 4;
  static const int earlyWormEndHour = 6; // exclusive

  /// [instant] as the user's wall clock.
  ///
  /// The returned value carries local *field* values (year, hour, …) while
  /// being flagged UTC, because there is no way to build a DateTime in an
  /// arbitrary zone. Read its fields; never compare it to `DateTime.now()`.
  DateTime wallClock(DateTime instant) =>
      instant.toUtc().add(Duration(minutes: utcOffsetMinutes));

  /// The instant at which the user's wall clock reads [local].
  DateTime instantOf(DateTime local) => DateTime.utc(
        local.year,
        local.month,
        local.day,
        local.hour,
        local.minute,
        local.second,
        local.millisecond,
      ).subtract(Duration(minutes: utcOffsetMinutes));

  /// Which challenge day [instant] falls on, as `YYYY-MM-DD`.
  ///
  /// The calendar day of the user's wall clock, with no shifting: an activity
  /// belongs to the date it happened on. The 02:00 grace is about when the day
  /// *locks*, not about which day owns the activity — conflating the two is how
  /// a 00:30 workout ends up credited to the wrong date.
  String dayKeyOf(DateTime instant) => formatDayKey(wallClock(instant));

  /// Today's day key.
  String today([DateTime? now]) => dayKeyOf(now ?? DateTime.now());

  /// When [dayKey] stops accepting activity: 02:00 local the morning after.
  DateTime finalisesAt(String dayKey) {
    final day = parseDayKey(dayKey);
    return instantOf(
      DateTime.utc(day.year, day.month, day.day + 1, finalisationHour),
    );
  }

  /// Whether [dayKey] can still be changed. A finalised day is immutable.
  bool isOpen(String dayKey, [DateTime? now]) =>
      (now ?? DateTime.now()).isBefore(finalisesAt(dayKey));

  /// Whether [instant] lands in the Early Worm window, 04:00–05:59 local.
  ///
  /// The boundaries are the point of the challenge, so they are exact: 04:00:00
  /// counts, 05:59:59 counts, 06:00:00 does not.
  bool isEarlyWorm(DateTime instant) {
    final hour = wallClock(instant).hour;
    return hour >= earlyWormStartHour && hour < earlyWormEndHour;
  }

  /// The day key [steps] days after [dayKey]. Negative walks backwards.
  static String addDays(String dayKey, int days) {
    final day = parseDayKey(dayKey);
    return formatDayKey(DateTime.utc(day.year, day.month, day.day + days));
  }

  /// How many days [to] is after [from]. Negative when it is before.
  static int daysBetween(String from, String to) =>
      parseDayKey(to).difference(parseDayKey(from)).inDays;

  /// The day keys from [from] to [to], inclusive at both ends.
  static List<String> dayKeysBetween(String from, String to) {
    final span = daysBetween(from, to);
    if (span < 0) return const [];
    return List.generate(span + 1, (index) => addDays(from, index));
  }
}

/// `YYYY-MM-DD` for a wall-clock date. The sortable form, so a string compare
/// on two day keys is also a date compare.
String formatDayKey(DateTime local) {
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}-$month-$day';
}

/// A day key back to a date, at UTC midnight. Throws on anything malformed —
/// a bad day key is a bug, and silently returning "today" would hide it.
DateTime parseDayKey(String dayKey) {
  final parts = dayKey.split('-');
  if (parts.length != 3) {
    throw FormatException('Not a day key: $dayKey');
  }
  return DateTime.utc(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}
