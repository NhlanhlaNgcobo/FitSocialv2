import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/fitness_profile_repository.dart';
import '../data/onboarding_draft_store.dart';
import '../domain/fitness_profile.dart';

/// Moves the onboarding answers from the phone into the new account.
///
/// The order is the whole point (spec §5.3):
///
/// 1. [afterSignUp] writes `private/fitness`, right after the account is
///    created and before the session moves on to "Claim your name".
/// 2. The profile write on that screen carries [pendingWeeklyGoalDays].
/// 3. [afterProfileSaved] clears the draft.
///
/// The profile document existing is what lets the user into `/home`, so the
/// goal has to be on file before it — otherwise home renders a frame with no
/// goal. None of these may block sign-up: a fitness profile that failed to
/// write degrades to defaults, and [retryPending] tries again next launch.
abstract interface class OnboardingSync {
  /// Called once an account with no profile is signed in — a sign-up, or a
  /// sign-up that was abandoned before "Claim your name".
  Future<void> afterSignUp(String uid);

  /// The days-a-week answer to write onto the profile, or null.
  Future<int?> pendingWeeklyGoalDays(String uid);

  Future<void> afterProfileSaved(String uid);

  /// Finishes a flush a previous launch started and did not complete.
  Future<void> retryPending(String uid);

  /// The user backed out of "Claim your name" and is being signed out. The
  /// answers stay, unclaimed, so whichever account they sign in with next
  /// gets them — including a different Google account.
  Future<void> abandon(String uid);
}

/// For sessions with no onboarding behind them — tests, mostly.
class NoopOnboardingSync implements OnboardingSync {
  const NoopOnboardingSync();

  @override
  Future<void> afterSignUp(String uid) async {}

  @override
  Future<int?> pendingWeeklyGoalDays(String uid) async => null;

  @override
  Future<void> afterProfileSaved(String uid) async {}

  @override
  Future<void> retryPending(String uid) async {}

  @override
  Future<void> abandon(String uid) async {}
}

class DraftOnboardingSync implements OnboardingSync {
  DraftOnboardingSync({
    required OnboardingDraftStore drafts,
    required FitnessProfileRepository fitness,
    this.writeTimeout = const Duration(seconds: 10),
  })  : _drafts = drafts,
        _fitness = fitness;

  final OnboardingDraftStore _drafts;
  final FitnessProfileRepository _fitness;

  /// How long a Firestore write may hold up sign-up.
  ///
  /// Offline, a write's future does not complete until the server has it, so
  /// awaiting it bare would leave the user on a spinner. The write itself is
  /// not cancelled by the timeout — Firestore keeps it queued and sends it
  /// when the connection is back — it is only no longer waited on, and the
  /// draft stays unmarked so the next launch checks again.
  final Duration writeTimeout;

  @override
  Future<void> afterSignUp(String uid) async {
    try {
      final draft = await _drafts.read();
      if (draft == null || draft.isEmpty) return;
      // A draft that already belongs to another account is left alone: that
      // person's flush is still waiting for them to come back.
      if (draft.ownerUid != null && draft.ownerUid != uid) return;

      final claimed = draft.copyWith(ownerUid: uid);
      await _drafts.save(claimed);
      await _writeFitness(uid, claimed);
    } catch (error) {
      debugPrint('Onboarding flush, fitness step, failed: $error');
    }
  }

  @override
  Future<int?> pendingWeeklyGoalDays(String uid) async {
    try {
      final draft = await _drafts.read();
      if (draft == null || draft.ownerUid != uid) return null;
      return draft.weeklyGoalDays;
    } catch (error) {
      debugPrint('Could not read the onboarding draft: $error');
      return null;
    }
  }

  @override
  Future<void> afterProfileSaved(String uid) async {
    try {
      final draft = await _drafts.read();
      if (draft == null || draft.ownerUid != uid) return;
      // The fitness write failed at sign-up. One more try now; if this fails
      // too the draft stays for the next launch, and the user goes on in with
      // the defaults meanwhile.
      if (!draft.fitnessSaved && !await _writeFitness(uid, draft)) return;
      await _drafts.clear();
    } catch (error) {
      debugPrint('Onboarding flush, clear step, failed: $error');
    }
  }

  @override
  Future<void> retryPending(String uid) async {
    try {
      final draft = await _drafts.read();
      // Only a draft this account claimed at sign-up. An unclaimed one is
      // answers made before logging in to an existing account — those wait
      // for "Finish your plan" rather than being written behind the user's
      // back.
      if (draft == null || draft.ownerUid != uid) return;
      if (draft.fitnessSaved || await _writeFitness(uid, draft)) {
        await _drafts.clear();
      }
    } catch (error) {
      debugPrint('Onboarding flush retry failed: $error');
    }
  }

  @override
  Future<void> abandon(String uid) async {
    try {
      final draft = await _drafts.read();
      if (draft == null || draft.ownerUid != uid) return;
      // fitnessSaved goes too: it was true of the account being left, not of
      // the one coming next.
      await _drafts.save(draft.copyWith(clearOwner: true, fitnessSaved: false));
    } catch (error) {
      debugPrint('Could not release the onboarding draft: $error');
    }
  }

  /// Writes the fitness profile unless the account already has one, and marks
  /// the draft. True when the account now has a profile on the server.
  Future<bool> _writeFitness(String uid, OnboardingDraft draft) async {
    try {
      // Never overwrite. A profile already there was written by an earlier
      // launch of this flush or chosen by the user since, and either way it
      // is newer than these answers.
      final existing = await _fitness.load(uid).timeout(writeTimeout);
      if (existing == null) {
        await _fitness
            .save(uid, draft.toFitnessProfile())
            .timeout(writeTimeout);
      }
      await _drafts.save(draft.copyWith(fitnessSaved: true));
      return true;
    } on TimeoutException {
      debugPrint('Fitness profile write is still pending; will check again.');
      return false;
    } catch (error) {
      debugPrint('Fitness profile write failed: $error');
      return false;
    }
  }
}
