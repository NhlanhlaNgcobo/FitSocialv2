import 'package:flutter/foundation.dart';

import 'app_models.dart';
import 'workout_models.dart';

/// A workout saved with "Only me", read back from its log so it can still be
/// posted later — the workout twin of `UnsharedRun`.
@immutable
class UnsharedWorkout {
  const UnsharedWorkout({
    required this.id,
    required this.loggedAt,
    required this.title,
    required this.durationMinutes,
    required this.calories,
    required this.exercises,
    this.caloriesEstimated = false,
    this.volumeKg,
    this.notes = '',
    this.imageUrl,
  });

  /// The `workouts/` document id.
  final String id;
  final DateTime loggedAt;
  final String title;
  final int durationMinutes;
  final int calories;
  final bool caloriesEstimated;
  final List<ExerciseEntry> exercises;
  final double? volumeKg;

  /// The description written when it was saved. Empty on a workout saved
  /// before private logs kept one.
  final String notes;

  /// The photo saved behind the card, already uploaded.
  final String? imageUrl;

  /// The workout as a draft, so the post made from it is built by exactly
  /// the same code as one shared when it was saved — the same card, the same
  /// labels, the same muscle map.
  WorkoutLogDraft toDraft({
    String? notes,
    List<TaggedUser> taggedUsers = const [],
    List<CustomExercise> customExercises = const [],
  }) =>
      WorkoutLogDraft(
        title: title,
        durationMinutes: durationMinutes,
        calories: calories,
        caloriesEstimated: caloriesEstimated,
        exercises: exercises,
        notes: notes ?? this.notes,
        shareToFeed: true,
        loggedAt: loggedAt,
        volumeKg: volumeKg,
        taggedUsers: taggedUsers,
        customExercises: customExercises,
      );
}

/// How the user left a private workout when they tapped Post.
@immutable
class UnsharedWorkoutShare {
  const UnsharedWorkoutShare({
    required this.workout,
    this.caption = '',
    this.backgroundImagePath,
    this.keepExistingImage = false,
    this.taggedUsers = const [],
    this.customExercises = const [],
  });

  final UnsharedWorkout workout;

  /// The post's caption. Blank falls back to "Logged n exercises.", as a
  /// workout shared when it was saved does.
  final String caption;

  /// A new photo picked in the editor, still to be uploaded. Wins over
  /// [keepExistingImage].
  final String? backgroundImagePath;

  /// Post with the photo already saved on the workout.
  final bool keepExistingImage;

  final List<TaggedUser> taggedUsers;

  /// So the post's muscle map credits the user's own exercises.
  final List<CustomExercise> customExercises;
}
