import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/muscle_heat.dart';
import 'content_providers.dart';
import 'workout_library_providers.dart';
import 'workout_preferences.dart';

/// What the workouts in [range] did to each muscle group, recomputed from the
/// logged exercises — so workouts saved before `muscleSets` existed count too.
final muscleWindowStatsProvider = FutureProvider.autoDispose
    .family<MuscleWindowStats, MuscleRange>((ref, range) async {
  final history = await ref.watch(workoutHistoryItemsProvider.future);
  // A custom list that failed to load costs those exercises their credit,
  // not the whole map.
  final custom = await ref
      .watch(customExercisesProvider.future)
      .catchError((Object _) => const <Never>[]);
  final includeWarmups =
      ref.watch(workoutPreferencesProvider).includeWarmupsInStats;
  return MuscleWindowStats.fromHistory(
    history,
    range: range,
    today: DateTime.now(),
    custom: custom,
    includeWarmups: includeWarmups,
  );
});
