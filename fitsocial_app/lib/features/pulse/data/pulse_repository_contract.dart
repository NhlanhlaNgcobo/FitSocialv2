import '../../auth/domain/auth_models.dart';
import '../domain/pulse_models.dart';

/// Storage and retrieval for Pulses — FitSocial's 24-hour ephemeral posts.
abstract class PulseRepository {
  /// Every Pulse that has not expired yet, across all authors.
  ///
  /// Emits loose segments rather than grouped rings: grouping needs the
  /// viewer's seen markers, which arrive on their own stream, so the two are
  /// joined a layer up by [buildPulseTray].
  Stream<List<PulseSegment>> watchActivePulses();

  /// The viewer's "last watched" cursor per author, keyed by author id.
  ///
  /// One document per author rather than per Pulse: that is what makes the
  /// unseen ring a single cheap read instead of a lookup per segment.
  Stream<Map<String, DateTime>> watchSeenMarkers(String userId);

  /// Uploads any media on [draft] and creates the Pulse document.
  ///
  /// [profile] supplies the public author name and photo, following the same
  /// rule as posts: attribution comes from the user's profile and never from
  /// their auth credentials.
  Future<PulseSegment> publish(UserProfileDraft? profile, PulseDraft draft);

  /// Advances the viewer's cursor for [authorId] to [lastSeenAt], dimming that
  /// ring. Never moves the cursor backwards.
  Future<void> markSeen(String authorId, DateTime lastSeenAt);

  /// Records that the signed-in user watched [pulseId] and bumps its view
  /// count. A no-op on repeat views and on the author's own Pulse.
  Future<void> recordView(String pulseId, UserProfileDraft? profile);

  /// Removes a Pulse the caller authored, along with its view records and its
  /// uploaded media. Throws if the caller is not the author.
  Future<void> deletePulse(String pulseId);

  /// Who has watched [pulseId], most recent first. Readable by the author only.
  Stream<List<PulseViewerRecord>> watchViewers(String pulseId);
}
