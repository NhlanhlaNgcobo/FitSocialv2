import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../auth/application/app_session.dart';
import '../../main/application/activity_actions.dart';
import '../../main/domain/app_models.dart';
import '../data/run_checkpoint_store.dart';
import '../data/run_draft_store.dart';
import '../data/run_import_ledger.dart';
import '../data/run_import_preference.dart';
import '../domain/run_draft.dart';

/// Where both on-disk stores root themselves.
///
/// Documents, not cache: see [FileRunDraftStore]. Overridden in tests with a
/// temp directory so nothing here touches path_provider's platform channel.
final runStorageRootProvider = Provider<Future<Directory> Function()>((ref) {
  return getApplicationDocumentsDirectory;
});

/// The uid whose drafts we are looking at, or null when nobody is signed in.
///
/// Public because the import sync has to know there is somebody to file a run
/// for before it starts looking for one.
///
/// Read off FirebaseAuth with the session watched, exactly as
/// `backendReachabilityProvider` does — signing in as someone else has to
/// rebuild the stores onto their own directory rather than serving the
/// previous user's runs.
final runDraftOwnerProvider = Provider<String?>((ref) {
  ref.watch(appSessionProvider);
  try {
    return FirebaseAuth.instance.currentUser?.uid;
  } on FirebaseException {
    // No Firebase app — a widget test, or a surface that builds before
    // bootstrap. Nobody owns any drafts, which is the honest answer and keeps
    // a drafts list from taking its page down with it.
    return null;
  }
});

final runDraftStoreProvider = Provider<RunDraftStore>((ref) {
  final userId = ref.watch(runDraftOwnerProvider);
  if (kIsWeb || userId == null) return const NoopRunDraftStore();
  return FileRunDraftStore(
    rootDirectory: ref.watch(runStorageRootProvider),
    userId: userId,
  );
});

/// Filed beside the drafts and per-user for the same reasons they are.
final runImportLedgerProvider = Provider<RunImportLedger>((ref) {
  final userId = ref.watch(runDraftOwnerProvider);
  if (kIsWeb || userId == null) return const NoopRunImportLedger();
  return FileRunImportLedger(
    rootDirectory: ref.watch(runStorageRootProvider),
    userId: userId,
  );
});

final runImportPreferenceStoreProvider =
    Provider<RunImportPreferenceStore>((ref) {
  return const RunImportPreferenceStore();
});

/// Whether runs found in Health Connect may be filed as drafts.
///
/// Starts true and corrects itself once storage answers, rather than starting
/// false: true is the default, so an optimistic start is right nearly always,
/// and the one thing that could go wrong -- an import beginning a few hundred
/// milliseconds before a stored "off" arrives -- files a draft nobody sees sent
/// anywhere.
final runImportEnabledProvider =
    StateNotifierProvider<RunImportEnabledController, bool>((ref) {
  return RunImportEnabledController(
      ref.watch(runImportPreferenceStoreProvider));
});

class RunImportEnabledController extends StateNotifier<bool> {
  RunImportEnabledController(this._store) : super(true) {
    _load();
  }

  final RunImportPreferenceStore _store;

  Future<void> _load() async {
    final enabled = await _store.read();
    if (mounted) state = enabled;
  }

  /// Applies immediately and persists in the background — a switch must not
  /// wait on a keystore round trip to move.
  Future<void> set({required bool enabled}) async {
    if (enabled == state) return;
    state = enabled;
    await _store.write(enabled: enabled);
  }
}

final runCheckpointStoreProvider = Provider<RunCheckpointStore>((ref) {
  final userId = ref.watch(runDraftOwnerProvider);
  if (kIsWeb || userId == null) return const NoopRunCheckpointStore();
  return FileRunCheckpointStore(
    rootDirectory: ref.watch(runStorageRootProvider),
    userId: userId,
  );
});

/// The run the app died in the middle of, if there is one worth offering back.
///
/// A one-shot read rather than a stream: it is asked once, when the run screen
/// opens. Stale and too-short checkpoints are cleared here so the question is
/// never asked twice about the same dead run.
final recoverableRunProvider = FutureProvider<RunCheckpoint?>((ref) async {
  final store = ref.watch(runCheckpointStoreProvider);
  final checkpoint = await store.read();
  if (checkpoint == null) return null;
  if (checkpoint.isStale || !checkpoint.isWorthRecovering) {
    await store.clear();
    return null;
  }
  return checkpoint;
});

final runDraftsProvider =
    StateNotifierProvider<RunDraftController, AsyncValue<List<RunDraft>>>(
        (ref) {
  return RunDraftController(
    store: ref.watch(runDraftStoreProvider),
    ledger: ref.watch(runImportLedgerProvider),
    publish: ref.watch(activityActionsProvider).saveRun,
  );
});

/// What came of sending a draft up.
class RunPublishResult {
  const RunPublishResult({required this.save, required this.photoMissing});

  /// The save path's own answer, whose wording already distinguishes a post
  /// that reached the server from one still on its way.
  final ActivitySaveResult save;

  /// The run went out without the backdrop the runner picked for it.
  final bool photoMissing;
}

/// Holds the list of unsent runs and owns the two things that can happen to
/// one: it goes out, or it goes away.
class RunDraftController extends StateNotifier<AsyncValue<List<RunDraft>>> {
  RunDraftController({
    required RunDraftStore store,
    required RunImportLedger ledger,
    required Future<ActivitySaveResult> Function(RunLogDraft) publish,
  })  : _store = store,
        _ledger = ledger,
        _publish = publish,
        super(const AsyncValue.loading()) {
    _load();
  }

  final RunDraftStore _store;

  final RunImportLedger _ledger;

  /// The save call, injected rather than reached for through a Ref.
  ///
  /// `ContentRepository` is a wide abstract contract, and a widget test that
  /// only wants to know whether Post was pressed should not have to stub forty
  /// methods to find out.
  final Future<ActivitySaveResult> Function(RunLogDraft) _publish;

  /// Ids with a publish in flight, so a second tap on a row cannot save the
  /// same run twice.
  final Set<String> _publishing = {};

  bool isPublishing(String id) => _publishing.contains(id);

  Future<void> _load() async {
    try {
      final drafts = await _store.list();
      if (mounted) state = AsyncValue.data(drafts);
    } catch (error, stackTrace) {
      if (mounted) state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> refresh() => _load();

  /// Files a finished run that could not be uploaded.
  ///
  /// Throws if it cannot be written — the caller is the run screen, which has
  /// the run in memory still and must not navigate away on a failure.
  Future<RunDraft> saveFromRun(
    RunDraft draft, {
    String? sourcePhotoPath,
  }) async {
    final stored = await _store.save(draft, sourcePhotoPath: sourcePhotoPath);
    await _load();
    return stored;
  }

  /// The external ids this controller already has drafts for.
  ///
  /// Handed to the import alongside the ledger so a ledger that failed to write
  /// -- or was lost with the app's data -- still cannot produce a second draft
  /// for a session already sitting in the list.
  Set<String> get importedIds => {
        for (final draft in state.valueOrNull ?? const <RunDraft>[])
          if (draft.externalId case final id?) id,
      };

  /// Files a run found in Health Connect that FitSocial never saw happen.
  ///
  /// The ledger is stamped **after** the draft lands, and never rolled back.
  /// Those two facts are the whole design: stamping first would lose the run
  /// outright if the write failed, and clearing the stamp when the runner
  /// discards the draft would have the same unwanted run offered back every
  /// time the app opened for the next two days.
  Future<void> importDetected(RunDraft draft) async {
    await _store.save(draft);
    if (draft.externalId case final id?) {
      await _ledger.markHandled([id]);
    }
    await _load();
  }

  /// Sends [draft] up the ordinary save path and drops it from disk once it
  /// lands.
  ///
  /// The draft is converted straight back into the [RunLogDraft] the live run
  /// screen would have built, so publishing gets the run log, the post, the
  /// counters, the streak and every cache invalidation for free — there is
  /// exactly one way a run reaches Firestore in this app, and this is not a
  /// second one.
  Future<RunPublishResult> publish(RunDraft draft) async {
    if (!_publishing.add(draft.id)) {
      throw StateError('This run is already being posted.');
    }
    // Rebuilt so rows can show their own spinner and disable themselves.
    if (mounted) state = AsyncValue.data(state.valueOrNull ?? const []);

    try {
      // Stamped BEFORE the call goes out. If the process dies between the save
      // landing and the delete below, the draft comes back carrying this and
      // the list warns that it may already be on the feed — which is the only
      // honest thing to do, because saveRun is not idempotent and a blind
      // retry would post the run twice.
      await _store.markPublishAttempted(draft);

      // The photo may have been swept out from under us since the run was
      // saved. A missing one costs the backdrop, never the run.
      final photoPath = draft.photoPath;
      final hasPhoto = photoPath != null && await File(photoPath).exists();

      final result = await _publish(
        draft.toRunLogDraft(backgroundImagePath: hasPhoto ? photoPath : null),
      );

      await _store.delete(draft.id);
      await _load();
      return RunPublishResult(
        save: result,
        // The runner chose a backdrop and it did not go out with the run. Said
        // plainly rather than left for them to notice on the feed.
        photoMissing:
            (photoPath != null && !hasPhoto) || draft.photoUnavailable,
      );
    } finally {
      _publishing.remove(draft.id);
      if (mounted) state = AsyncValue.data(state.valueOrNull ?? const []);
    }
  }

  Future<void> discard(RunDraft draft) async {
    await _store.delete(draft.id);
    await _load();
  }
}
