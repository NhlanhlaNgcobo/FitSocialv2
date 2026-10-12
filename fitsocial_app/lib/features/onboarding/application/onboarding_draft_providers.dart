import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tracking/application/run_draft_providers.dart';
import '../data/fitness_profile_repository.dart';
import '../data/onboarding_draft_store.dart';
import 'onboarding_sync.dart';

/// Rooted where the run drafts are, so tests that override
/// [runStorageRootProvider] with a temp directory cover this too.
final onboardingDraftStoreProvider = Provider<OnboardingDraftStore>((ref) {
  if (kIsWeb) return MemoryOnboardingDraftStore();
  return FileOnboardingDraftStore(
    rootDirectory: ref.watch(runStorageRootProvider),
  );
});

final fitnessProfileRepositoryProvider = Provider<FitnessProfileRepository>(
  (ref) => FirestoreFitnessProfileRepository(),
);

final onboardingSyncProvider = Provider<OnboardingSync>((ref) {
  return DraftOnboardingSync(
    drafts: ref.watch(onboardingDraftStoreProvider),
    fitness: ref.watch(fitnessProfileRepositoryProvider),
  );
});
