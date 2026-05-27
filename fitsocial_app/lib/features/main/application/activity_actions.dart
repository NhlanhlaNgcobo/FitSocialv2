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
      ..invalidate(summaryMetricsProvider)
      ..invalidate(progressMetricsProvider)
      ..invalidate(profileStatsProvider)
      ..invalidate(storyItemsProvider);
    return result;
  }
}

final activityActionsProvider = Provider<ActivityActions>((ref) {
  return ActivityActions(ref);
});
