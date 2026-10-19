import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/app_session.dart';
import '../../auth/domain/auth_models.dart';
import '../data/content_repository.dart';
import '../data/content_repository_contract.dart';
import '../domain/app_models.dart';
import '../domain/activity_kind.dart';
import '../domain/unshared_run.dart';
import '../domain/unshared_workout.dart';
import 'content_providers.dart';

class ActivityActions {
  ActivityActions(this._ref);

  final Ref _ref;

  Future<ActivitySaveResult> saveWorkout(WorkoutLogDraft draft) {
    return _saveAndRefresh(
      (repository, profile) => repository.saveWorkout(profile, draft),
    );
  }

  Future<ActivitySaveResult> saveRun(RunLogDraft draft) {
    return _saveAndRefresh(
      (repository, profile) => repository.saveRun(profile, draft),
    );
  }

  /// Posts a run that was saved without sharing, from the "Not shared" list.
  Future<ActivitySaveResult> shareUnsharedRun(UnsharedRunShare share) {
    return _saveAndRefresh(
      (repository, profile) => repository.shareUnsharedRun(profile, share),
    );
  }

  /// Deletes a run from the "Not shared" list. It has no post, so the log is
  /// the whole of it.
  Future<void> deleteUnsharedRun(UnsharedRun run) async {
    await _ref
        .read(contentRepositoryProvider)
        .deleteActivitySession(run.id, run.kind);
    _ref
      ..invalidate(unsharedRunsProvider)
      ..invalidate(activitySessionsProvider)
      ..invalidate(progressMetricsProvider);
  }

  /// Posts a workout from the "Not shared" list.
  Future<ActivitySaveResult> shareUnsharedWorkout(UnsharedWorkoutShare share) {
    return _saveAndRefresh(
      (repository, profile) => repository.shareUnsharedWorkout(profile, share),
    );
  }

  /// Deletes a workout from the "Not shared" list. It has no post, so the log
  /// is the whole of it.
  Future<void> deleteUnsharedWorkout(UnsharedWorkout workout) async {
    await _ref
        .read(contentRepositoryProvider)
        .deleteActivitySession(workout.id, ActivityKind.workout);
    _ref
      ..invalidate(unsharedWorkoutsProvider)
      ..invalidate(activitySessionsProvider)
      ..invalidate(progressMetricsProvider)
      ..invalidate(workoutHistoryProvider)
      ..invalidate(workoutHistoryItemsProvider)
      ..invalidate(recentWorkoutsProvider);
  }

  Future<ActivitySaveResult> saveMeal(MealLogDraft draft) {
    return _saveAndRefresh(
      (repository, profile) => repository.saveMeal(profile, draft),
    );
  }

  Future<ActivitySaveResult> sharePost(PostDraft draft) {
    return _saveAndRefresh(
      (repository, profile) => repository.sharePost(profile, draft),
    );
  }

  Future<ActivitySaveResult> createPoll(PollDraft draft) {
    return _saveAndRefresh(
      (repository, profile) => repository.createPoll(profile, draft),
    );
  }

  Future<ActivitySaveResult> createMeetup(MeetupDraft draft) {
    return _saveAndRefresh(
      (repository, profile) => repository.createMeetup(profile, draft),
    );
  }

  Future<ActivitySaveResult> _saveAndRefresh(
    Future<ActivitySaveResult> Function(
      ContentRepository repository,
      UserProfileDraft? profile,
    ) save,
  ) async {
    final profile = _ref.read(appSessionProvider).profile;
    final repository = _ref.read(contentRepositoryProvider);
    final result = await save(repository, profile);
    _ref
      ..invalidate(feedPostsProvider)
      ..invalidate(progressMetricsProvider)
      ..invalidate(profileStatsProvider)
      ..invalidate(achievementsProvider)
      // Family providers: invalidating the family clears every keyed instance,
      // so the author's profile grids pick the new post up.
      ..invalidate(userPostsProvider)
      ..invalidate(userMediaPostsProvider)
      // Likewise the training log every Progress view is derived from —
      // without this the square for today keeps the value it was first built
      // with and a run logged mid-session never lights up.
      ..invalidate(activitySessionsProvider)
      // And the profile's "Not shared" list, which a private run joins and a
      // run posted from it leaves.
      ..invalidate(unsharedRunsProvider)
      ..invalidate(unsharedWorkoutsProvider)
      // And the log screen's repeat chips, so the session just saved is
      // offered as a template the next time it opens.
      ..invalidate(recentWorkoutsProvider)
      // And the history live PRs are measured against.
      ..invalidate(workoutHistoryProvider)
      ..invalidate(workoutHistoryItemsProvider)
      // And the meal history, so a meal logged from the tracking page appears
      // in today's totals rather than after a restart.
      ..invalidate(loggedMealsProvider)
      // And the day's question, whose card counts the answers and says
      // whether this user has given one.
      ..invalidate(promptAnswersProvider);
    return result;
  }
}

final activityActionsProvider = Provider<ActivityActions>((ref) {
  return ActivityActions(ref);
});
