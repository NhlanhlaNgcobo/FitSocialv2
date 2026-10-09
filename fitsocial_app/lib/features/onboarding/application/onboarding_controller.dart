import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/onboarding_draft_store.dart';
import '../domain/fitness_profile.dart';
import 'onboarding_draft_providers.dart';

/// The answers to onboarding Steps 1–2 while they are being given.
///
/// Every change is written straight to the draft store, not just held here:
/// the user leaves the app mid-flow by design (Google's consent screen), and
/// a back press must restore what they picked, both of which outlive this
/// notifier's memory.
final onboardingControllerProvider =
    StateNotifierProvider<OnboardingController, OnboardingDraft>((ref) {
  return OnboardingController(ref.watch(onboardingDraftStoreProvider));
});

class OnboardingController extends StateNotifier<OnboardingDraft> {
  OnboardingController(this._store) : super(const OnboardingDraft()) {
    _load();
  }

  final OnboardingDraftStore _store;

  /// Set by the first change, so a load that lands late cannot overwrite an
  /// answer the user already gave.
  bool _touched = false;

  Future<void> _load() async {
    final saved = await _store.read();
    if (saved != null && mounted && !_touched) state = saved;
  }

  void selectGoal(TrainingGoal goal) =>
      _update(state.copyWith(primaryGoal: goal));

  void _update(OnboardingDraft next) {
    _touched = true;
    state = next;
    // Not awaited: a tap must not wait on the disk. Failure costs the answer
    // surviving a process death, never the answer on screen.
    _store.save(next).catchError((Object error) {
      debugPrint('Could not save the onboarding draft: $error');
    });
  }
}
