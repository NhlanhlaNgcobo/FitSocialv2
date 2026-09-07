/// Average pace for a run, formatted the one way this app formats it.
///
/// Lives on its own because two things now produce a finished run: the live
/// GPS engine, and a session imported from Health Connect. A recorded run and
/// an imported one showing pace in two slightly different shapes would read as
/// a bug in whichever the user saw second.
///
/// Returns the placeholder for a run too short to have a meaningful pace. The
/// 0.01 km floor is deliberately below the 0.05 km a run has to reach to be
/// saved at all — this is guarding the division, not judging the run.
String formatAveragePace({
  required double distanceKm,
  required Duration elapsed,
}) {
  final minutes = elapsed.inSeconds / 60.0;
  if (distanceKm <= 0.01 || minutes <= 0) return '--:-- /km';
  final pace = minutes / distanceKm;
  final mins = pace.floor();
  final secs = ((pace - mins) * 60).round().toString().padLeft(2, '0');
  return '$mins:$secs /km';
}
