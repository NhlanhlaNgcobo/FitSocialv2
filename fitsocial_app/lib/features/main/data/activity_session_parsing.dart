/// Reading sessions back out of what older records happened to store.
///
/// Before the `runs` and `workouts` collections existed, a session survived
/// only as the post it was shared as — and a post records its numbers as
/// display strings ("45 min", "5.02 km", "28:14"), because that is what the
/// feed renders. These functions turn those strings back into numbers, and
/// merge the result with the real logs without counting anything twice.
///
/// Pure and Firestore-free so the parsing rules can be tested directly.
library;

import '../domain/progress_models.dart';

/// Minutes out of a "45 min" label. Zero when it does not parse — a guessed
/// number would quietly corrupt every total it feeds.
int minutesFromDurationLabel(String? label) {
  if (label == null) return 0;
  final digits = RegExp(r'\d+').firstMatch(label)?.group(0);
  return digits == null ? 0 : int.tryParse(digits) ?? 0;
}

/// kcal out of a "320 kcal" label.
///
/// Zero for the "0 kcal" every workout carried before calories were captured,
/// which is the honest reading: nothing was recorded.
int kcalFromLabel(String? label) => minutesFromDurationLabel(label);

/// The first "5.02 km" metric as a number, or null when none of them is one.
double? distanceFromMetricLabels(List<String> labels) {
  final pattern = RegExp(r'^([\d.]+)\s*km$', caseSensitive: false);
  for (final label in labels) {
    final match = pattern.firstMatch(label.trim());
    if (match != null) return double.tryParse(match.group(1)!);
  }
  return null;
}

/// The first "28:14" or "1:05:22" metric as a duration.
///
/// Anchored at both ends so a pace like "5:37 /km" — which sits in the same
/// metric strip and looks almost identical — is not read as an elapsed time.
Duration? durationFromMetricLabels(List<String> labels) {
  final pattern = RegExp(r'^(?:(\d+):)?(\d{1,2}):(\d{2})$');
  for (final label in labels) {
    final match = pattern.firstMatch(label.trim());
    if (match == null) continue;
    return Duration(
      hours: int.tryParse(match.group(1) ?? '0') ?? 0,
      minutes: int.tryParse(match.group(2)!) ?? 0,
      seconds: int.tryParse(match.group(3)!) ?? 0,
    );
  }
  return null;
}

/// [logged] plus whichever of [fromPosts] is not already one of them, newest
/// first.
///
/// A session that was logged *and* shared exists twice — once in its
/// collection, once as a post — and must be counted once. The postId written
/// when a log is shared answers that exactly.
///
/// The fallback covers the narrow window of logs written before that id was
/// recorded: same kind, same day, same length is the same session. It can only
/// confuse two sessions of identical duration on one day, and it only ever
/// runs against logs that say they were shared but cannot say where.
List<ActivitySession> mergeSessions({
  required List<ActivitySession> logged,
  required List<ActivitySession> fromPosts,
}) {
  final linked = logged.map((session) => session.postId).nonNulls.toSet();

  bool alreadyLogged(ActivitySession candidate) {
    if (candidate.postId != null && linked.contains(candidate.postId)) {
      return true;
    }
    return logged.any(
      (session) =>
          session.postId == null &&
          session.sharedToFeed &&
          session.kind == candidate.kind &&
          session.day == candidate.day &&
          (session.duration - candidate.duration).abs() <=
              const Duration(minutes: 1),
    );
  }

  return <ActivitySession>[
    ...logged,
    ...fromPosts.where((session) => !alreadyLogged(session)),
  ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
}
