import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tracking/application/run_draft_providers.dart';
import '../data/onboarding_draft_store.dart';

/// Rooted where the run drafts are, so tests that override
/// [runStorageRootProvider] with a temp directory cover this too.
final onboardingDraftStoreProvider = Provider<OnboardingDraftStore>((ref) {
  if (kIsWeb) return MemoryOnboardingDraftStore();
  return FileOnboardingDraftStore(
    rootDirectory: ref.watch(runStorageRootProvider),
  );
});
