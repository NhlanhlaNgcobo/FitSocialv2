import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main/data/content_repository.dart';
import '../../main/domain/progress_models.dart';
import '../domain/imported_run.dart';
import 'run_draft_providers.dart';
import 'tracking_providers.dart';

/// Notices runs recorded somewhere other than FitSocial and files them as
/// drafts.
///
/// Sits around the shell for the same reason [DailyStepsSync] does: it is the
/// one widget alive on every tab. Unlike that one there is no timer — a run
/// does not finish while the user is looking at the app. The two moments that
/// matter are opening it and coming back to it, which is exactly when somebody
/// who has just stopped running reaches for their phone.
///
/// Nothing here prompts for anything, and nothing here reaches the network in
/// the sending direction. A found run becomes a file on disk and a card on
/// Create; it stays there until the runner taps Post.
class RunImportSync extends ConsumerStatefulWidget {
  const RunImportSync({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<RunImportSync> createState() => _RunImportSyncState();
}

class _RunImportSyncState extends ConsumerState<RunImportSync>
    with WidgetsBindingObserver {
  /// A resume fires every time the user glances at another app and comes back.
  /// Reading the platform store on each of those would be a real cost for a
  /// question whose answer changes at most a couple of times a day.
  static const Duration _minimumGap = Duration(minutes: 1);

  DateTime? _lastSyncAt;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only the returning edge, unlike the step sync. Going away is when a step
    // count is most at risk of being lost; a finished run is already sitting in
    // Health Connect and will still be there whenever the app is next opened.
    if (state == AppLifecycleState.resumed) _sync();
  }

  Future<void> _sync() async {
    // Nowhere durable to file a draft on web, and no platform store to read.
    if (kIsWeb || _isSyncing) return;

    final now = DateTime.now();
    if (_lastSyncAt != null && now.difference(_lastSyncAt!) < _minimumGap) {
      return;
    }
    // Stamped before the work rather than after it, so a sync that fails backs
    // off like one that succeeded instead of retrying on every resume.
    _lastSyncAt = now;

    if (!ref.read(runImportEnabledProvider)) return;
    // Signed out, the draft store is a no-op that throws on save. There is also
    // nobody to file a run for.
    if (ref.read(runDraftOwnerProvider) == null) return;

    _isSyncing = true;
    try {
      // Only a definite refusal stops us. HealthKit never discloses read grants
      // — it answers null forever — and treating that as "no" would disable
      // this on iOS outright. An unauthorised read there returns nothing, which
      // is the same outcome without the false gate. Nothing is ever *requested*
      // here: a permission dialog that appears because the app was opened, with
      // no action behind it, is the kind of prompt people deny on reflex.
      if (await ref.read(healthServiceProvider).hasPermissions() == false) {
        return;
      }

      // Ahead of the import and allowed to throw: these are the windows that
      // stop a run the user recorded *with* FitSocial being imported a second
      // time from the copy Samsung Health made of the same outing. Importing
      // without them would be worse than not importing at all, so a failed read
      // aborts rather than proceeding unguarded.
      final knownRuns = await _knownRunWindows();

      final controller = ref.read(runDraftsProvider.notifier);
      final handled = <String>{
        ...await ref.read(runImportLedgerProvider).handled(),
        ...controller.importedIds,
      };

      final drafts = await ref.read(runImportServiceProvider).collect(
            handled: handled,
            knownRuns: knownRuns,
            now: now,
          );

      for (final draft in drafts) {
        if (!mounted) return;
        await controller.importDetected(draft);
      }
    } catch (error) {
      // Silent by design. The promise is that runs turn up on their own; a
      // failure means one did not, and there is nothing the runner could do
      // about it from here. The next resume tries again.
      debugPrint('Could not import runs from the health store: $error');
    } finally {
      _isSyncing = false;
    }
  }

  /// When each run the user already has happened.
  ///
  /// Read from the repository rather than through `activitySessionsProvider`,
  /// which is autoDispose: reading its future from here creates it with no
  /// listener and disposes it again mid-flight.
  Future<List<RunWindow>> _knownRunWindows() async {
    final sessions =
        await ref.read(contentRepositoryProvider).getActivitySessions();
    return [
      for (final session in sessions)
        // Every GPS kind, so that a hike recorded here still blocks the same
        // hike arriving later from Health Connect.
        if (session.kind.isGps)
          RunWindow(
            start: session.startedAt,
            end: session.startedAt.add(session.duration),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
