import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/content_repository.dart';
import '../domain/routine.dart';
import '../domain/workout_models.dart';

/// The exercises the user has made up, alphabetical. Searched alongside the
/// bundled library by the exercise picker.
final customExercisesProvider =
    FutureProvider.autoDispose<List<CustomExercise>>((ref) {
  return ref.watch(contentRepositoryProvider).getCustomExercises();
});

/// The id a custom exercise carries on logged entries.
///
/// Prefixed so it can never collide with a library slug: a user who makes up
/// "squat-barbell" must not have their history merged with the library's.
String customExerciseId(String documentId) => 'custom-$documentId';

/// The signed-in user's routines. Invalidated after every save, delete or
/// start, so the list and its "last used" chips follow.
final routinesProvider = FutureProvider.autoDispose<List<Routine>>((ref) {
  return ref.watch(contentRepositoryProvider).getRoutines();
});

/// [routinesProvider] grouped by folder — see [groupRoutines] for the order.
final routineFoldersProvider = Provider.autoDispose<
    AsyncValue<List<({String folder, List<Routine> routines})>>>((ref) {
  return ref.watch(routinesProvider).whenData(groupRoutines);
});
