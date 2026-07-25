import 'package:flutter_riverpod/flutter_riverpod.dart';

enum CreateCanvasDestination {
  workout,
  run,
  meal,
  post,
  photo,
}

extension CreateCanvasDestinationX on CreateCanvasDestination {
  String get label {
    switch (this) {
      case CreateCanvasDestination.workout:
        return 'Workout draft';
      case CreateCanvasDestination.run:
        return 'Run tracker';
      case CreateCanvasDestination.meal:
        return 'Meal draft';
      case CreateCanvasDestination.post:
        return 'Post draft';
      case CreateCanvasDestination.photo:
        return 'Photo meal draft';
    }
  }

  String get route {
    switch (this) {
      case CreateCanvasDestination.workout:
        return '/log-workout';
      case CreateCanvasDestination.run:
        return '/log-run';
      case CreateCanvasDestination.meal:
        return '/meal-review';
      case CreateCanvasDestination.post:
        return '/compose-post';
      case CreateCanvasDestination.photo:
        // Route to the upload screen that actually performs the AI meal
        // analysis (Firebase Storage upload + analyzeMeal Cloud Function).
        // The old /meal-camera screen was a stub that never called it.
        return '/meal-upload';
    }
  }
}

int _exerciseIdCounter = 0;

String _nextExerciseId() =>
    'exercise_${_exerciseIdCounter++}_${DateTime.now().microsecondsSinceEpoch}';

class ExerciseDraftEntry {
  ExerciseDraftEntry({
    String? id,
    this.name = '',
    this.sets = 3,
    this.reps = 10,
  }) : id = id ?? _nextExerciseId();

  final String id;
  final String name;
  final int sets;
  final int reps;

  ExerciseDraftEntry copyWith({String? name, int? sets, int? reps}) {
    return ExerciseDraftEntry(
      id: id,
      name: name ?? this.name,
      sets: sets ?? this.sets,
      reps: reps ?? this.reps,
    );
  }
}

class WorkoutDraftState {
  const WorkoutDraftState({
    this.title = '',
    this.duration = '',
    this.calories = '',
    this.exercises = const [],
    this.notes = '',
    this.shareToFeed = true,
  });

  final String title;
  final String duration;
  final String calories;
  final List<ExerciseDraftEntry> exercises;
  final String notes;
  final bool shareToFeed;

  bool get hasContent =>
      title.trim().isNotEmpty ||
      duration.trim().isNotEmpty ||
      calories.trim().isNotEmpty ||
      notes.trim().isNotEmpty ||
      exercises.any((exercise) => exercise.name.trim().isNotEmpty);

  WorkoutDraftState copyWith({
    String? title,
    String? duration,
    String? calories,
    List<ExerciseDraftEntry>? exercises,
    String? notes,
    bool? shareToFeed,
  }) {
    return WorkoutDraftState(
      title: title ?? this.title,
      duration: duration ?? this.duration,
      calories: calories ?? this.calories,
      exercises: exercises ?? this.exercises,
      notes: notes ?? this.notes,
      shareToFeed: shareToFeed ?? this.shareToFeed,
    );
  }
}

class RunDraftState {
  const RunDraftState({
    this.distanceKm = 0,
    this.hours = 0,
    this.minutes = 0,
    this.seconds = 0,
    this.shareToFeed = true,
  });

  final double distanceKm;
  final int hours;
  final int minutes;
  final int seconds;
  final bool shareToFeed;

  bool get hasContent =>
      distanceKm > 0 || hours > 0 || minutes > 0 || seconds > 0;

  RunDraftState copyWith({
    double? distanceKm,
    int? hours,
    int? minutes,
    int? seconds,
    bool? shareToFeed,
  }) {
    return RunDraftState(
      distanceKm: distanceKm ?? this.distanceKm,
      hours: hours ?? this.hours,
      minutes: minutes ?? this.minutes,
      seconds: seconds ?? this.seconds,
      shareToFeed: shareToFeed ?? this.shareToFeed,
    );
  }
}

class MealDraftState {
  const MealDraftState({
    this.name = '',
    this.calories = '',
    this.protein = '',
    this.carbs = '',
    this.fat = '',
    this.notes = '',
    this.shareToFeed = true,
    this.imageUrl,
  });

  final String name;
  final String calories;
  final String protein;
  final String carbs;
  final String fat;
  final String notes;
  final bool shareToFeed;

  /// Firebase Storage URL of the uploaded meal photo, when present.
  final String? imageUrl;

  bool get hasContent =>
      name.trim().isNotEmpty ||
      calories.trim().isNotEmpty ||
      protein.trim().isNotEmpty ||
      carbs.trim().isNotEmpty ||
      fat.trim().isNotEmpty ||
      notes.trim().isNotEmpty;

  MealDraftState copyWith({
    String? name,
    String? calories,
    String? protein,
    String? carbs,
    String? fat,
    String? notes,
    bool? shareToFeed,
    String? imageUrl,
  }) {
    return MealDraftState(
      name: name ?? this.name,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
      notes: notes ?? this.notes,
      shareToFeed: shareToFeed ?? this.shareToFeed,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}

class PostComposerDraftState {
  const PostComposerDraftState({
    this.caption = '',
  });

  final String caption;

  bool get hasContent => caption.trim().isNotEmpty;

  PostComposerDraftState copyWith({String? caption}) {
    return PostComposerDraftState(caption: caption ?? this.caption);
  }
}

class CreateFlowState {
  const CreateFlowState({
    this.activeDestination,
    this.workoutDraft = const WorkoutDraftState(),
    this.runDraft = const RunDraftState(),
    this.mealDraft = const MealDraftState(),
    this.postDraft = const PostComposerDraftState(),
    this.mealPhotoAnalysisPending = false,
    this.lastCompletedMessage,
  });

  final CreateCanvasDestination? activeDestination;
  final WorkoutDraftState workoutDraft;
  final RunDraftState runDraft;
  final MealDraftState mealDraft;
  final PostComposerDraftState postDraft;
  final bool mealPhotoAnalysisPending;
  final String? lastCompletedMessage;

  bool get hasDraft =>
      workoutDraft.hasContent ||
      runDraft.hasContent ||
      mealDraft.hasContent ||
      postDraft.hasContent;

  CreateFlowState copyWith({
    CreateCanvasDestination? activeDestination,
    bool clearActiveDestination = false,
    WorkoutDraftState? workoutDraft,
    RunDraftState? runDraft,
    MealDraftState? mealDraft,
    PostComposerDraftState? postDraft,
    bool? mealPhotoAnalysisPending,
    String? lastCompletedMessage,
    bool clearLastCompletedMessage = false,
  }) {
    return CreateFlowState(
      activeDestination: clearActiveDestination
          ? null
          : activeDestination ?? this.activeDestination,
      workoutDraft: workoutDraft ?? this.workoutDraft,
      runDraft: runDraft ?? this.runDraft,
      mealDraft: mealDraft ?? this.mealDraft,
      postDraft: postDraft ?? this.postDraft,
      mealPhotoAnalysisPending:
          mealPhotoAnalysisPending ?? this.mealPhotoAnalysisPending,
      lastCompletedMessage: clearLastCompletedMessage
          ? null
          : lastCompletedMessage ?? this.lastCompletedMessage,
    );
  }
}

class CreateFlowController extends StateNotifier<CreateFlowState> {
  CreateFlowController() : super(const CreateFlowState());

  void begin(CreateCanvasDestination destination) {
    state = state.copyWith(
      activeDestination: destination,
      clearLastCompletedMessage: true,
    );
  }

  void updateWorkout(WorkoutDraftState draft) {
    state = state.copyWith(workoutDraft: draft);
  }

  void updateRun(RunDraftState draft) {
    state = state.copyWith(runDraft: draft);
  }

  void updateMeal(MealDraftState draft) {
    state = state.copyWith(mealDraft: draft);
  }

  void updatePost(PostComposerDraftState draft) {
    state = state.copyWith(postDraft: draft);
  }

  void markMealPhotoPending() {
    state = state.copyWith(
      activeDestination: CreateCanvasDestination.photo,
      mealPhotoAnalysisPending: true,
      clearLastCompletedMessage: true,
    );
  }

  void completeWorkout(String message) {
    state = state.copyWith(
      clearActiveDestination: true,
      workoutDraft: const WorkoutDraftState(),
      lastCompletedMessage: message,
    );
  }

  void completeRun(String message) {
    state = state.copyWith(
      clearActiveDestination: true,
      runDraft: const RunDraftState(),
      lastCompletedMessage: message,
    );
  }

  void completeMeal(String message) {
    state = state.copyWith(
      clearActiveDestination: true,
      mealDraft: const MealDraftState(),
      mealPhotoAnalysisPending: false,
      lastCompletedMessage: message,
    );
  }

  void completePost(String message) {
    state = state.copyWith(
      clearActiveDestination: true,
      postDraft: const PostComposerDraftState(),
      lastCompletedMessage: message,
    );
  }

  void clearDrafts() {
    state = const CreateFlowState();
  }
}

final createFlowControllerProvider =
    StateNotifierProvider<CreateFlowController, CreateFlowState>((ref) {
  return CreateFlowController();
});
