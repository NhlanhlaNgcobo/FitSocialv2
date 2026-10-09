import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/app_session.dart';
import '../../auth/domain/auth_models.dart';
import '../data/content_repository.dart';
import '../data/content_repository_contract.dart';
import '../domain/app_models.dart';
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
      // And the log screen's repeat chips, so the session just saved is
      // offered as a template the next time it opens.
      ..invalidate(recentWorkoutsProvider)
      // And the history live PRs are measured against.
      ..invalidate(workoutHistoryProvider)
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
