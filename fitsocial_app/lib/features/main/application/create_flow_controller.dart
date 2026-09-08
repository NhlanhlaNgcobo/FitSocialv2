import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/activity_kind.dart';
import '../domain/app_models.dart';

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
        // Covers runs, hikes and rides — the tracker is one flow with a
        // three-way choice inside it, not three entries on the Create page.
        return 'Activity tracker';
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
        // The upload screen performs the real AI meal analysis (Firebase
        // Storage upload + analyzeMeal Cloud Function).
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
    this.activityKind = ActivityKind.run,
  });

  final double distanceKm;
  final int hours;
  final int minutes;
  final int seconds;
  final bool shareToFeed;

  /// Which activity the tracker is set to. Carried on the draft so that
  /// resuming a half-entered hike comes back as a hike rather than silently
  /// becoming a run.
  final ActivityKind activityKind;

  bool get hasContent =>
      distanceKm > 0 || hours > 0 || minutes > 0 || seconds > 0;

  RunDraftState copyWith({
    double? distanceKm,
    int? hours,
    int? minutes,
    int? seconds,
    bool? shareToFeed,
    ActivityKind? activityKind,
  }) {
    return RunDraftState(
      distanceKm: distanceKm ?? this.distanceKm,
      hours: hours ?? this.hours,
      minutes: minutes ?? this.minutes,
      seconds: seconds ?? this.seconds,
      shareToFeed: shareToFeed ?? this.shareToFeed,
      activityKind: activityKind ?? this.activityKind,
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
    this.items = const [],
    this.confidence,
    this.databaseCoverage,
  });

  /// Builds a draft from an analyzeMeal response.
  ///
  /// The totals are taken from the items rather than the response's own total
  /// fields when items are present: the two agree by construction server-side,
  /// and deriving here keeps them agreeing after the user edits a portion.
  factory MealDraftState.fromAnalysis(
    Map<String, dynamic> analysis, {
    String? imageUrl,
  }) {
    final items = MealFoodItem.listFrom(analysis['foodItems']);
    final totals = MacroTotals.of(items);
    String field(String key, int derived) {
      if (items.isNotEmpty) return derived.toString();
      final raw = (analysis[key] ?? '').toString().trim();
      return raw;
    }

    return MealDraftState(
      name: (analysis['name'] ?? '').toString(),
      calories: field('calories', totals.calories),
      protein: field('protein', totals.protein),
      carbs: field('carbs', totals.carbs),
      fat: field('fat', totals.fat),
      notes: (analysis['notes'] ?? '').toString(),
      imageUrl: imageUrl,
      items: items,
      confidence: (analysis['confidence'] as Object?)?.toString(),
      databaseCoverage: (analysis['databaseCoverage'] as num?)?.toDouble(),
    );
  }

  final String name;
  final String calories;
  final String protein;
  final String carbs;
  final String fat;
  final String notes;
  final bool shareToFeed;

  /// Firebase Storage URL of the uploaded meal photo, when present.
  final String? imageUrl;

  /// The analysed breakdown behind the totals. Empty for a hand-typed meal.
  final List<MealFoodItem> items;

  /// The analyzer's own confidence: 'low', 'medium' or 'high'.
  final String? confidence;

  /// Fraction of the items that resolved against the nutrition database, 0-1.
  /// Null when the meal was never analysed.
  final double? databaseCoverage;

  bool get hasContent =>
      name.trim().isNotEmpty ||
      calories.trim().isNotEmpty ||
      protein.trim().isNotEmpty ||
      carbs.trim().isNotEmpty ||
      fat.trim().isNotEmpty ||
      notes.trim().isNotEmpty;

  /// Whether this draft has already been through the analyzer — an uploaded
  /// photo, an itemised breakdown, or macros on the form.
  ///
  /// This is what separates a meal worth returning to the review screen from
  /// a photo flow that never got past the picker. Resuming an analyzed meal at
  /// the picker would discard the analysis and cost another vision call to
  /// recreate it.
  bool get isAnalyzed =>
      imageUrl != null ||
      items.isNotEmpty ||
      calories.trim().isNotEmpty ||
      protein.trim().isNotEmpty ||
      carbs.trim().isNotEmpty ||
      fat.trim().isNotEmpty;

  MealDraftState copyWith({
    String? name,
    String? calories,
    String? protein,
    String? carbs,
    String? fat,
    String? notes,
    bool? shareToFeed,
    String? imageUrl,
    List<MealFoodItem>? items,
    String? confidence,
    double? databaseCoverage,
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
      items: items ?? this.items,
      confidence: confidence ?? this.confidence,
      databaseCoverage: databaseCoverage ?? this.databaseCoverage,
    );
  }
}

class PostComposerDraftState {
  const PostComposerDraftState({
    this.caption = '',
    this.activity = '',
  });

  final String caption;

  /// Optional activity subtitle shown under the author's name in the feed.
  final String activity;

  bool get hasContent =>
      caption.trim().isNotEmpty || activity.trim().isNotEmpty;

  PostComposerDraftState copyWith({String? caption, String? activity}) {
    return PostComposerDraftState(
      caption: caption ?? this.caption,
      activity: activity ?? this.activity,
    );
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

  /// Which canvas the resume card should reopen.
  ///
  /// [activeDestination] is normally set, but a draft can outlive it (the app
  /// was restarted, or a flow was entered from a shortcut), so fall back to
  /// whichever draft actually holds content.
  CreateCanvasDestination get resumeDestination =>
      activeDestination ??
      (workoutDraft.hasContent
          ? CreateCanvasDestination.workout
          : runDraft.hasContent
              ? CreateCanvasDestination.run
              : mealDraft.hasContent
                  ? CreateCanvasDestination.meal
                  : CreateCanvasDestination.post);

  /// Where resuming should actually land — not always the destination's own
  /// route.
  ///
  /// The photo canvas owns the picker, but once its meal has been analyzed the
  /// work lives on the review screen. Sending the user back to the picker
  /// would silently throw away the analysis they already paid for.
  String get resumeRoute {
    // A run entered by hand has no live tracking session to return to.
    if (activeDestination == null &&
        runDraft.hasContent &&
        !workoutDraft.hasContent) {
      return '/log-run-manual';
    }

    final destination = resumeDestination;
    final isMealFlow = destination == CreateCanvasDestination.photo ||
        destination == CreateCanvasDestination.meal;
    if (isMealFlow && mealDraft.isAnalyzed) {
      return CreateCanvasDestination.meal.route;
    }
    return destination.route;
  }

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
