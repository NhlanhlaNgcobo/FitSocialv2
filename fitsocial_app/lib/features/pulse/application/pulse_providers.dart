import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/reactions/fit_reaction.dart';
import '../../auth/application/app_session.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider, followingIdsProvider;
import '../../main/domain/app_models.dart' show Comment;
import '../data/pulse_repository.dart';
import '../domain/pulse_models.dart';

/// Every unexpired Pulse the signed-in user is allowed to see, live. Loose
/// segments — see [pulseTrayProvider] for the grouped form the UI renders.
///
/// The audience is the people they follow, plus themselves. A Pulse is a
/// 24-hour glimpse of someone's day, and it goes to the people who asked for
/// it — not to everyone holding an account.
final activePulsesProvider = StreamProvider<List<PulseSegment>>((ref) {
  // Re-subscribe on sign-in/out: the query requires an authenticated reader.
  ref.watch(appSessionProvider);

  final currentUserId = ref.watch(currentUserIdProvider);
  if (currentUserId == null) return Stream.value(const <PulseSegment>[]);

  // Treated as empty while it loads rather than holding the tray back: your
  // own ring appears immediately, and the rest arrive a beat later when the
  // follow graph lands.
  final following = ref.watch(followingIdsProvider).valueOrNull ?? const {};

  return ref
      .watch(pulseRepositoryProvider)
      .watchActivePulses({...following, currentUserId});
});

/// The signed-in user's per-author "last watched" cursors.
final pulseSeenMarkersProvider =
    StreamProvider<Map<String, DateTime>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const <String, DateTime>{});
  return ref.watch(pulseRepositoryProvider).watchSeenMarkers(userId);
});

/// The Pulse tray: one ring per author, ordered the way Instagram orders its
/// story tray — you first, then anything unseen, then the rest, newest first.
///
/// Seen markers are treated as empty while they load rather than holding the
/// whole tray back; the worst case is a ring that shows bright for a moment
/// before dimming, which beats an empty rail on every cold start.
final pulseTrayProvider = Provider<AsyncValue<List<PulseTrayEntry>>>((ref) {
  final segments = ref.watch(activePulsesProvider);
  final markers = ref.watch(pulseSeenMarkersProvider).valueOrNull;
  final currentUserId = ref.watch(currentUserIdProvider);

  return segments.whenData(
    (list) => buildPulseTray(
      segments: list,
      seenMarkers: markers ?? const <String, DateTime>{},
      currentUserId: currentUserId,
      now: DateTime.now(),
    ),
  );
});

/// One author's ring, or null when they have nothing live. Used by the viewer
/// to resolve the ring it was opened on.
final pulseTrayEntryProvider =
    Provider.family<PulseTrayEntry?, String>((ref, authorId) {
  final entries = ref.watch(pulseTrayProvider).valueOrNull;
  if (entries == null) return null;
  for (final entry in entries) {
    if (entry.authorId == authorId) return entry;
  }
  return null;
});

/// The live version of one segment, or null once it has expired or been
/// deleted.
///
/// The viewer plays from a snapshot of the tray so that marking Pulses seen
/// can't reshuffle the pages under someone's thumb. That snapshot also freezes
/// the reaction counts, which is wrong the moment anyone reacts — so the
/// counts are looked up here, live, by id, without disturbing the order.
final pulseSegmentProvider =
    Provider.family<PulseSegment?, String>((ref, pulseId) {
  final segments = ref.watch(activePulsesProvider).valueOrNull;
  if (segments == null) return null;
  for (final segment in segments) {
    if (segment.id == pulseId) return segment;
  }
  return null;
});

/// Who has watched a given Pulse. Only the author can read this.
final pulseViewersProvider =
    StreamProvider.family<List<PulseViewerRecord>, String>((ref, pulseId) {
  return ref.watch(pulseRepositoryProvider).watchViewers(pulseId);
});

/// The signed-in user's own reaction to a Pulse, null when they haven't given
/// one. Drives the selected state of the reaction bar.
final myFitReactionProvider =
    StreamProvider.family<FitReaction?, String>((ref, pulseId) {
  // Re-subscribed on sign-in/out: which document this reads is decided by who
  // is signed in, so the answer is wrong the moment that changes.
  ref.watch(appSessionProvider);
  return ref.watch(pulseRepositoryProvider).watchMyReaction(pulseId);
});

/// Everyone who reacted to a Pulse and what they picked.
///
/// Only watched while the breakdown sheet is open — the counts the bar draws
/// come off the Pulse document, which the tray is already streaming.
final pulseReactionsProvider =
    StreamProvider.family<List<FitReactionRecord>, String>((ref, pulseId) {
  return ref.watch(pulseRepositoryProvider).watchReactions(pulseId);
});

/// The conversation under a Pulse, oldest first.
final pulseCommentsProvider =
    StreamProvider.family<List<Comment>, String>((ref, pulseId) {
  return ref.watch(pulseRepositoryProvider).watchComments(pulseId);
});

/// Write-side actions. The tray is a live query, so none of these need to
/// invalidate anything — the streams carry the change back on their own.
class PulseActions {
  const PulseActions(this._ref);

  final Ref _ref;

  Future<PulseSegment> publish(PulseDraft draft) {
    final profile = _ref.read(appSessionProvider).profile;
    return _ref.read(pulseRepositoryProvider).publish(profile, draft);
  }

  /// Marks everything up to and including [segment] as watched.
  Future<void> markSeen(PulseSegment segment) {
    return _ref
        .read(pulseRepositoryProvider)
        .markSeen(segment.authorId, segment.createdAt);
  }

  Future<void> recordView(String pulseId) {
    final profile = _ref.read(appSessionProvider).profile;
    return _ref.read(pulseRepositoryProvider).recordView(pulseId, profile);
  }

  Future<void> delete(String pulseId) {
    return _ref.read(pulseRepositoryProvider).deletePulse(pulseId);
  }

  /// Sets or clears the signed-in user's reaction. Pass null to take it back.
  ///
  /// Nothing is invalidated afterwards: the reaction document and the Pulse's
  /// counts are both live queries, so the new face and the new number arrive on
  /// their own.
  Future<void> react(String pulseId, FitReaction? reaction) {
    final profile = _ref.read(appSessionProvider).profile;
    return _ref
        .read(pulseRepositoryProvider)
        .setReaction(pulseId, reaction, profile);
  }

  Future<Comment> comment(String pulseId, String text) {
    final profile = _ref.read(appSessionProvider).profile;
    return _ref
        .read(pulseRepositoryProvider)
        .addComment(pulseId, text, profile);
  }

  Future<void> deleteComment(String pulseId, String commentId) {
    return _ref
        .read(pulseRepositoryProvider)
        .deleteComment(pulseId, commentId);
  }
}

final pulseActionsProvider = Provider<PulseActions>((ref) {
  return PulseActions(ref);
});
