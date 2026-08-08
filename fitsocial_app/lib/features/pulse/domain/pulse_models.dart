import 'package:flutter/material.dart';

import '../../../shared/identity/profile_identity.dart';

/// Timing rules for Pulse playback and expiry.
///
/// These mirror Instagram Stories: a still frame holds for 5 seconds, a video
/// plays for its own length, and the whole thing disappears after a day.
abstract final class PulseTiming {
  /// How long a photo or text Pulse stays on screen before auto-advancing.
  static const Duration frameDuration = Duration(seconds: 5);

  /// Longest video a single Pulse may carry. Anything longer is rejected at
  /// compose time rather than silently truncated during playback.
  static const Duration maxVideoDuration = Duration(seconds: 60);

  /// Floor on a segment's display time, so a corrupt or zero-length video
  /// can't produce a segment that ends the instant it starts.
  static const Duration minSegmentDuration = Duration(seconds: 1);

  /// How long a Pulse lives before it expires.
  static const Duration lifetime = Duration(hours: 24);
}

enum PulseMediaType {
  photo,
  video,
  text;

  /// Stored form. Kept explicit rather than using `name` so a rename of the
  /// enum can never silently change what is already in Firestore.
  String get key {
    switch (this) {
      case PulseMediaType.photo:
        return 'photo';
      case PulseMediaType.video:
        return 'video';
      case PulseMediaType.text:
        return 'text';
    }
  }

  static PulseMediaType fromKey(String? value) {
    switch (value) {
      case 'video':
        return PulseMediaType.video;
      case 'text':
        return PulseMediaType.text;
      case 'photo':
      default:
        return PulseMediaType.photo;
    }
  }
}

/// A background for a text Pulse.
///
/// Only [key] is persisted — the colours live in the app so the palette can be
/// restyled without rewriting stored documents.
class PulseGradient {
  const PulseGradient(this.key, this.label, this.colors);

  final String key;
  final String label;
  final List<Color> colors;

  static const ember =
      PulseGradient('ember', 'Ember', [Color(0xFFFF8A3D), Color(0xFFD33F00)]);
  static const midnight = PulseGradient(
      'midnight', 'Midnight', [Color(0xFF2B3A67), Color(0xFF0B0F1F)]);
  static const forest =
      PulseGradient('forest', 'Forest', [Color(0xFF1F8A4C), Color(0xFF06301A)]);
  static const blood =
      PulseGradient('blood', 'Blood', [Color(0xFFB3123C), Color(0xFF3A0111)]);
  static const violet =
      PulseGradient('violet', 'Violet', [Color(0xFF7B2FF7), Color(0xFF2B0A57)]);
  static const graphite = PulseGradient(
      'graphite', 'Graphite', [Color(0xFF3A3A3A), Color(0xFF0B0B0B)]);
  static const ice =
      PulseGradient('ice', 'Ice', [Color(0xFF3AA9C9), Color(0xFF0B2E3A)]);

  /// Order is the order of swatches in the composer.
  static const all = <PulseGradient>[
    ember,
    midnight,
    forest,
    blood,
    violet,
    graphite,
    ice,
  ];

  /// Falls back to [ember] for an unknown key, so a document written by a
  /// newer build with a palette this one doesn't have still renders.
  static PulseGradient fromKey(String? key) {
    for (final gradient in all) {
      if (gradient.key == key) return gradient;
    }
    return ember;
  }

  LinearGradient get linear => LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

/// One frame of a Pulse — a photo, a video, or a written card.
class PulseSegment {
  const PulseSegment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.type,
    required this.createdAt,
    required this.expiresAt,
    this.authorAvatarUrl,
    this.mediaUrl,
    this.text = '',
    this.gradientKey = 'ember',
    this.viewCount = 0,
    this.videoDuration,
    this.aspectRatio,
  });

  final String id;
  final String authorId;

  /// Author's public name and photo as they were at publish time,
  /// denormalised the same way posts do it so the tray renders from the
  /// documents it already streams instead of one profile read per author.
  final String authorName;
  final String? authorAvatarUrl;

  final PulseMediaType type;

  /// Firebase Storage URL of the photo or video. Null on a text Pulse.
  final String? mediaUrl;

  /// The written message on a text Pulse, or the caption laid over a photo or
  /// video. Empty when there is none.
  final String text;

  /// Background palette for a text Pulse, and the tint behind a still that is
  /// letterboxed. See [PulseGradient].
  final String gradientKey;

  final DateTime createdAt;

  /// When this Pulse stops being visible. Written by the client as
  /// `createdAt + lifetime` so the value can be both TTL-swept server-side and
  /// filtered client-side.
  final DateTime expiresAt;

  final int viewCount;

  /// Real length of the video, recorded at compose time so the progress bar
  /// can be sized before the player has loaded.
  final Duration? videoDuration;

  /// width / height of the media, for fitting it without distortion.
  final double? aspectRatio;

  PulseGradient get gradient => PulseGradient.fromKey(gradientKey);

  bool get hasMedia => (mediaUrl ?? '').isNotEmpty;

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  /// How long this segment holds the screen.
  ///
  /// Stills get a fixed beat; a video runs for its own length, floored so a
  /// broken duration can't produce an instant skip and capped so a document
  /// claiming an hour-long video can't strand the viewer.
  Duration get displayDuration {
    if (type != PulseMediaType.video) return PulseTiming.frameDuration;
    final duration = videoDuration;
    if (duration == null || duration < PulseTiming.minSegmentDuration) {
      return PulseTiming.frameDuration;
    }
    return duration > PulseTiming.maxVideoDuration
        ? PulseTiming.maxVideoDuration
        : duration;
  }
}

/// One author's live Pulses, as shown by a single ring in the tray.
class PulseTrayEntry {
  const PulseTrayEntry({
    required this.authorId,
    required this.authorName,
    required this.segments,
    required this.isOwn,
    required this.hasUnseen,
    required this.firstUnseenIndex,
    this.authorAvatarUrl,
  });

  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;

  /// Oldest first — the order they play in.
  final List<PulseSegment> segments;

  /// Whether this is the signed-in user's own ring, which gets the add button
  /// and the viewer counts.
  final bool isOwn;

  /// Whether anything here is newer than the viewer's last look. Drives the
  /// bright vs. dimmed ring.
  final bool hasUnseen;

  /// Where playback starts — Instagram resumes at the first unseen frame
  /// rather than replaying from the top.
  final int firstUnseenIndex;

  DateTime get latestAt => segments.last.createdAt;

  /// Label for the tray: the user's own ring always reads the same, everyone
  /// else is shown by first name so the rail stays narrow.
  String get displayLabel {
    if (isOwn) return 'Pulse';
    final first = authorName.trim().split(' ').first;
    return first.isEmpty ? authorName : first;
  }
}

/// Someone who has watched a Pulse, for the author's viewer list.
class PulseViewerRecord {
  const PulseViewerRecord({
    required this.userId,
    required this.name,
    required this.viewedAt,
    this.avatarUrl,
  });

  final String userId;
  final String name;
  final DateTime viewedAt;
  final String? avatarUrl;
}

/// What the composer hands to the repository.
class PulseDraft {
  const PulseDraft({
    required this.type,
    this.localFilePath,
    this.text = '',
    this.gradientKey = 'ember',
    this.videoDuration,
    this.aspectRatio,
  });

  final PulseMediaType type;

  /// Path to the photo or video on the device. Null on a text Pulse, which
  /// uploads nothing.
  final String? localFilePath;

  final String text;
  final String gradientKey;
  final Duration? videoDuration;
  final double? aspectRatio;

  bool get isPublishable {
    if (type == PulseMediaType.text) return text.trim().isNotEmpty;
    return (localFilePath ?? '').isNotEmpty;
  }
}

/// Groups loose segments into the per-author rings the tray renders.
///
/// Pure and time-injected so the ordering rules can be tested without a clock
/// or a network. Mirrors Instagram's tray ranking without the ML: your own
/// ring leads, then anything unseen, then everything already watched — each
/// band newest first.
List<PulseTrayEntry> buildPulseTray({
  required List<PulseSegment> segments,
  required Map<String, DateTime> seenMarkers,
  required String? currentUserId,
  required DateTime now,
}) {
  final byAuthor = <String, List<PulseSegment>>{};
  for (final segment in segments) {
    // Expiry is enforced here as well as by the server's TTL sweep. The sweep
    // is not prompt — Firestore only guarantees deletion within 24h of the
    // expiry time — so without this filter a viewer would keep seeing Pulses
    // that are already a day stale.
    if (segment.isExpiredAt(now)) continue;
    byAuthor.putIfAbsent(segment.authorId, () => <PulseSegment>[]).add(segment);
  }

  final entries = <PulseTrayEntry>[];
  for (final group in byAuthor.entries) {
    final ordered = group.value.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final lastSeenAt = seenMarkers[group.key];

    var firstUnseenIndex = ordered.indexWhere(
      (segment) => lastSeenAt == null || segment.createdAt.isAfter(lastSeenAt),
    );
    final hasUnseen = firstUnseenIndex != -1;
    // Nothing new: a deliberate re-open replays the whole ring from the start.
    if (!hasUnseen) firstUnseenIndex = 0;

    final newest = ordered.last;
    entries.add(
      PulseTrayEntry(
        authorId: group.key,
        authorName: newest.authorName,
        authorAvatarUrl: newest.authorAvatarUrl,
        segments: ordered,
        isOwn: currentUserId != null && group.key == currentUserId,
        hasUnseen: hasUnseen,
        firstUnseenIndex: firstUnseenIndex,
      ),
    );
  }

  entries.sort((a, b) {
    if (a.isOwn != b.isOwn) return a.isOwn ? -1 : 1;
    if (a.hasUnseen != b.hasUnseen) return a.hasUnseen ? -1 : 1;
    return b.latestAt.compareTo(a.latestAt);
  });
  return entries;
}

/// Monogram shown in a ring when someone has no profile photo, empty when
/// there is no real name to build one from — see [avatarInitials].
String pulseInitials(String name) => avatarInitials(name);

/// Compact age label for the Pulse header — "now", "42m", "6h".
///
/// Never needs a day unit: nothing here outlives [PulseTiming.lifetime].
String pulseAgeLabel(DateTime createdAt, DateTime now) {
  final elapsed = now.difference(createdAt);
  if (elapsed.inMinutes < 1) return 'now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m';
  return '${elapsed.inHours}h';
}
