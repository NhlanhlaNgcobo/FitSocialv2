import '../../../shared/reactions/fit_reaction.dart';
import '../../auth/domain/auth_models.dart';
import '../../main/domain/app_models.dart' show Comment;
import '../domain/pulse_models.dart';

/// Storage and retrieval for Pulses — FitSocial's 24-hour ephemeral posts.
abstract class PulseRepository {
  /// Every unexpired Pulse by any of [authorIds].
  ///
  /// The audience is passed in rather than derived here: a Pulse is only for
  /// the people its author lets see it, and that list lives in the follow
  /// graph, which is not this repository's to read. Callers pass the people
  /// the viewer follows, plus the viewer — you always see your own.
  ///
  /// Emits loose segments rather than grouped rings: grouping needs the
  /// viewer's seen markers, which arrive on their own stream, so the two are
  /// joined a layer up by [buildPulseTray].
  Stream<List<PulseSegment>> watchActivePulses(Set<String> authorIds);

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

  /// The signed-in user's own reaction to [pulseId], or null if they haven't
  /// picked one.
  ///
  /// A single-document stream rather than a slice of [watchReactions]: the
  /// reaction bar needs this on every frame of playback, and one document is
  /// what it costs. The public counts ride on the Pulse document itself.
  Stream<FitReaction?> watchMyReaction(String pulseId);

  /// Sets, changes, or clears the signed-in user's reaction to [pulseId].
  ///
  /// A person holds at most one reaction per Pulse — this is Facebook's rule,
  /// and it is what makes the counts mean something. Passing null takes the
  /// reaction back. Repeating the reaction already held is a no-op, so a double
  /// tap can't double-count.
  ///
  /// [profile] supplies the public name and photo shown in the reactor list,
  /// following the same rule as everything else here: attribution comes from
  /// the user's profile and never from their auth credentials.
  Future<void> setReaction(
    String pulseId,
    FitReaction? reaction,
    UserProfileDraft? profile,
  );

  /// Everyone who reacted to [pulseId] and what they picked, most recent
  /// first. Streamed only when the breakdown is opened — the summary the bar
  /// draws comes off the Pulse document instead.
  Stream<List<FitReactionRecord>> watchReactions(String pulseId);

  /// Comments on [pulseId], oldest first — the order they read in.
  ///
  /// Visible to the same people the Pulse is: a comment is part of the
  /// conversation around it, not a private note to the author.
  Stream<List<Comment>> watchComments(String pulseId);

  /// Adds a comment to [pulseId] as the signed-in user.
  Future<Comment> addComment(
    String pulseId,
    String text,
    UserProfileDraft? profile,
  );

  /// Removes a comment. Allowed to the person who wrote it and to the author
  /// of the Pulse it sits under, who is the one moderating their own thread.
  Future<void> deleteComment(String pulseId, String commentId);
}
