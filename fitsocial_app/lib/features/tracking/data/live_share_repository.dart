import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../../auth/domain/auth_models.dart';
import '../../main/domain/activity_kind.dart';
import '../domain/live_activity_share.dart';
import 'firestore_live_share_repository.dart';

/// Where a shared activity is written to and watched from.
///
/// Small on purpose. Four calls cover the whole life of a share: open it,
/// keep it current, close it, and — from the other end of the link — watch it.
abstract class LiveShareRepository {
  /// Opens a new share and returns its id, which is the secret in the link.
  ///
  /// [profile] is the sharer's own, used for the name and photo the viewer
  /// sees; the repository falls back to the stored profile when it is missing
  /// a display name, the way every other author stamp in the app does.
  Future<String> begin({
    required ActivityKind kind,
    required DateTime startedAt,
    required UserProfileDraft? profile,
  });

  /// Writes the latest numbers and position onto an open share.
  Future<void> update(String shareId, LiveShareSnapshot snapshot);

  /// Marks the share finished, with its final numbers. The document stays
  /// readable — somebody who opens the link afterwards sees the completed
  /// route rather than a blank — until it expires.
  Future<void> end(String shareId, LiveShareSnapshot snapshot);

  /// Removes the share outright. For "stop sharing" mid-activity, where the
  /// point is that the link should show nothing at all.
  Future<void> discard(String shareId);

  /// The share behind a link, as it changes. Emits null when there is no such
  /// document — a mistyped id, or one that has been discarded.
  Stream<LiveActivityShare?> watch(String shareId);
}

final liveShareRepositoryProvider = Provider<LiveShareRepository>((ref) {
  final status = ref.watch(bootstrapStatusProvider);
  if (status.canUseFirebase) {
    return FirestoreLiveShareRepository(FirebaseFirestore.instance);
  }
  return const UnconfiguredLiveShareRepository();
});

/// Stand-in for a build with no Firebase behind it. A share cannot be started
/// — there is nowhere to put it — and says so, rather than handing out a link
/// that leads nowhere.
class UnconfiguredLiveShareRepository implements LiveShareRepository {
  const UnconfiguredLiveShareRepository();

  @override
  Future<String> begin({
    required ActivityKind kind,
    required DateTime startedAt,
    required UserProfileDraft? profile,
  }) {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> update(String shareId, LiveShareSnapshot snapshot) async {}

  @override
  Future<void> end(String shareId, LiveShareSnapshot snapshot) async {}

  @override
  Future<void> discard(String shareId) async {}

  @override
  Stream<LiveActivityShare?> watch(String shareId) => Stream.value(null);
}

const _firebaseSetupMessage =
    'Firebase is not configured. Run flutterfire configure to generate lib/firebase_options.dart.';
