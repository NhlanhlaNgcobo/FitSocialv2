import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../data/content_repository.dart';
import 'content_providers.dart';

/// Logs the user's repeating meals once their time has come today.
///
/// Sits around the shell beside [RunImportSync] and for the same reason: it is
/// the one widget alive on every tab, and opening the app or coming back to it
/// is when a meal that fell due in the meantime should appear.
///
/// The app does this rather than a scheduled function. A repeat only needs to
/// be in place by the time somebody looks, it works offline, and it keeps a
/// meal from being written for someone who has stopped using the app.
class MealRepeatSync extends ConsumerStatefulWidget {
  const MealRepeatSync({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<MealRepeatSync> createState() => _MealRepeatSyncState();
}

class _MealRepeatSyncState extends ConsumerState<MealRepeatSync>
    with WidgetsBindingObserver {
  /// A resume fires on every glance away and back; a repeat falls due at most
  /// a few times a day.
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
    if (state == AppLifecycleState.resumed) _sync();
  }

  Future<void> _sync() async {
    if (_isSyncing || !ref.read(bootstrapStatusProvider).canUseFirebase) {
      return;
    }
    final now = DateTime.now();
    if (_lastSyncAt != null && now.difference(_lastSyncAt!) < _minimumGap) {
      return;
    }
    _lastSyncAt = now;

    _isSyncing = true;
    try {
      final logged =
          await ref.read(contentRepositoryProvider).logDueMealRepeats(now);
      if (logged > 0 && mounted) {
        ref
          ..invalidate(loggedMealsProvider)
          ..invalidate(mealRepeatsProvider);
      }
    } catch (error) {
      // Silent, like the run import: the next resume tries again, and there
      // is nothing the user could do about it from wherever they are.
      debugPrint('Could not log repeating meals: $error');
    } finally {
      _isSyncing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
