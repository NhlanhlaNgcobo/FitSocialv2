import 'dart:typed_data';

import '../../main/domain/app_models.dart';
import 'music_playback.dart';

/// The little the music island needs to know, and nothing else.
///
/// Deliberately much thinner than [MusicPlayerSnapshot]. This is watched for
/// the whole life of the app, so it carries only what a collapsed pill draws —
/// keeping shuffle, repeat, volume and device out of it means none of those
/// changing rebuilds an overlay sitting above every screen.
class MusicPresence {
  const MusicPresence({
    this.service,
    this.title = '',
    this.artist = '',
    this.isPlaying = false,
    this.albumArtUrl,
    this.albumArtBytes,
  });

  /// Nothing playing, or nothing connected. The island is not drawn.
  static const MusicPresence none = MusicPresence();

  static MusicPresence fromSnapshot(MusicPlayerSnapshot? snapshot) {
    final track = snapshot?.track;
    if (snapshot == null || track == null) return none;
    return MusicPresence(
      service: snapshot.service,
      title: track.title,
      artist: track.artist,
      isPlaying: snapshot.isPlaying,
      albumArtUrl: track.albumArtUrl,
      albumArtBytes: track.albumArtBytes,
    );
  }

  final MusicProviderService? service;
  final String title;
  final String artist;
  final bool isPlaying;
  final String? albumArtUrl;
  final Uint8List? albumArtBytes;

  /// Whether there is a track loaded at all — playing *or* paused.
  bool get hasTrack => service != null && title.isNotEmpty;

  /// Whether the island should be on screen.
  ///
  /// Playing only. A paused track is not music playing, so the pill goes —
  /// which means resuming happens from the Activity tab's player rather than
  /// from the bar. That is the deliberate trade: the island is a sign that
  /// something is playing, not a permanent transport control.
  bool get isLive => hasTrack && isPlaying;

  /// Whether this is a different piece of music, rather than the same one
  /// reported again with a new position or a resolved cover.
  ///
  /// The island rebuilds on every emission from a push stream that fires on
  /// each seek; without this the pill would repaint continuously while a track
  /// plays.
  bool isSameAs(MusicPresence other) =>
      other.service == service &&
      other.title == title &&
      other.artist == artist &&
      other.isPlaying == isPlaying &&
      other.albumArtUrl == albumArtUrl &&
      identical(other.albumArtBytes, albumArtBytes);
}
