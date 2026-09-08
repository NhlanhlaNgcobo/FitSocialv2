import '../../main/domain/activity_kind.dart';

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

/// Average speed for a ride, formatted the one way this app formats it.
///
/// Cyclists think in km/h, not in minutes per kilometre: a good ride reads as
/// "28.4 km/h", and the same ride as a pace reads "2:07 /km", which is a number
/// no cyclist has ever used to describe anything.
///
/// **The slash is load-bearing.** `RunSummaryCard.distanceFrom` picks the
/// distance out of a post's metric strip by taking the label that ends in "km"
/// and contains no "/" or ":" — so "28.4 km/h" is correctly passed over, and
/// "28.4 kmh" would be read as the distance and printed on the run card in
/// place of it. Do not tidy the slash away.
///
/// Returns the placeholder for a ride too short to have a meaningful speed, on
/// the same terms and for the same reason as [formatAveragePace].
String formatAverageSpeed({
  required double distanceKm,
  required Duration elapsed,
}) {
  final hours = elapsed.inSeconds / Duration.secondsPerHour;
  if (distanceKm <= 0.01 || hours <= 0) return '--.- km/h';
  return '${(distanceKm / hours).toStringAsFixed(1)} km/h';
}

/// The headline second metric for [kind]: a pace on foot, a speed on a bike.
String formatPaceOrSpeed({
  required ActivityKind kind,
  required double distanceKm,
  required Duration elapsed,
}) {
  return kind.descriptor.usesPace
      ? formatAveragePace(distanceKm: distanceKm, elapsed: elapsed)
      : formatAverageSpeed(distanceKm: distanceKm, elapsed: elapsed);
}
