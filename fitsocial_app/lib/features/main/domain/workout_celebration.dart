import 'workout_math.dart';

/// Everything the "Workout saved" screen shows, worked out by the save screen
/// before it hands over.
///
/// Carried as the route's `extra` rather than re-read on arrival: the screen
/// has to work offline, straight after a save that may still be queued, and
/// everything here is already in hand at that moment.
class WorkoutCelebration {
  const WorkoutCelebration({
    required this.title,
    required this.loggedAt,
    required this.workoutNumber,
    required this.weeklyStreak,
    required this.prs,
    required this.workoutData,
    this.backgroundPath,
    this.postId,
  });

  final String title;
  final DateTime loggedAt;

  /// "Workout #N": how many the user has logged, this one included.
  final int workoutNumber;

  /// Weeks in a row with a workout, this week included.
  final int weeklyStreak;

  final List<WorkoutPr> prs;

  /// The card's document, as the post carries it.
  final Map<String, dynamic> workoutData;

  /// The photo picked on the save screen, a local file.
  final String? backgroundPath;

  /// The post the workout was shared as. Null when it was kept private.
  final String? postId;
}
