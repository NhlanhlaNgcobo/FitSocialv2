import 'dart:typed_data';

import '../../main/domain/app_models.dart';

/// What the repeat button cycles through. Mirrors Spotify's three states:
/// off -> repeat the whole context (playlist/album) -> repeat one track.
enum MusicRepeatMode { off, context, track }

extension MusicRepeatModeX on MusicRepeatMode {
  /// The value Spotify's `PUT /me/player/repeat` expects.
  String get apiValue {
    switch (this) {
      case MusicRepeatMode.off:
        return 'off';
      case MusicRepeatMode.context:
        return 'context';
      case MusicRepeatMode.track:
        return 'track';
    }
  }

  MusicRepeatMode get next {
    switch (this) {
      case MusicRepeatMode.off:
        return MusicRepeatMode.context;
      case MusicRepeatMode.context:
        return MusicRepeatMode.track;
      case MusicRepeatMode.track:
        return MusicRepeatMode.off;
    }
  }

  static MusicRepeatMode fromApi(String? value) {
    switch (value) {
      case 'context':
        return MusicRepeatMode.context;
      case 'track':
        return MusicRepeatMode.track;
      default:
        return MusicRepeatMode.off;
    }
  }
}

/// The track currently loaded in the remote player.
class NowPlayingTrack {
  const NowPlayingTrack({
    required this.title,
    required this.artist,
    required this.duration,
    required this.position,
    this.uri,
    this.albumArtUrl,
    this.albumArtUri,
    this.albumArtBytes,
  });

  final String title;
  final String artist;

  /// The track's own `spotify:track:…` URI.
  ///
  /// The only stable way to name this piece of music — title and artist are
  /// what a person reads, but two songs can share both. Null on a snapshot
  /// from a source that did not report one, which is why anything built from
  /// it has to cope with its absence.
  final String? uri;
  final Duration duration;
  final Duration position;

  /// An ordinary https cover-art URL.
  ///
  /// What the Web API returns directly. On the App Remote path it is looked up
  /// afterwards from the track's URI, because this is the only form of the
  /// artwork that can leave this device — a Pulse, or a friend's presence row,
  /// needs a URL their phone can fetch, not bytes sitting in our memory.
  final String? albumArtUrl;

  /// A `spotify:image:…` reference, which is what App Remote returns instead.
  /// No HTTP client can fetch it — only the SDK can turn it into bytes, which
  /// then arrive as [albumArtBytes].
  final String? albumArtUri;

  /// Cover art already decoded to bytes, resolved from [albumArtUri].
  final Uint8List? albumArtBytes;

  double get progress {
    if (duration.inMilliseconds <= 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Whether [other] is a different piece of music, rather than the same one
  /// reported again at a new position. Used to decide when cover art has to be
  /// re-fetched and when an in-flight seek is stale.
  bool isSameTrackAs(NowPlayingTrack? other) =>
      other != null && other.title == title && other.artist == artist;

  NowPlayingTrack copyWith({
    Duration? position,
    Uint8List? albumArtBytes,
    String? albumArtUrl,
  }) {
    return NowPlayingTrack(
      // Carried through explicitly, like every other field here: this is
      // called once a second to advance the position and again when artwork
      // resolves, so anything left out would be erased a beat after it
      // arrived.
      uri: uri,
      title: title,
      artist: artist,
      duration: duration,
      position: position ?? this.position,
      albumArtUrl: albumArtUrl ?? this.albumArtUrl,
      albumArtUri: albumArtUri,
      albumArtBytes: albumArtBytes ?? this.albumArtBytes,
    );
  }
}

/// A snapshot of a provider's remote player.
///
/// [track] is null when the service is connected but nothing is loaded — the
/// player UI shows its idle state rather than disappearing, so the transport
/// controls stay where the user left them.
class MusicPlayerSnapshot {
  const MusicPlayerSnapshot({
    required this.service,
    this.track,
    this.isPlaying = false,
    this.shuffleEnabled = false,
    this.repeatMode = MusicRepeatMode.off,
    this.deviceName,
    this.volumePercent,
    this.supportsVolume = false,
  });

  final MusicProviderService service;
  final NowPlayingTrack? track;
  final bool isPlaying;
  final bool shuffleEnabled;
  final MusicRepeatMode repeatMode;

  /// The speaker/phone/desktop Spotify is currently playing through, if any.
  final String? deviceName;

  /// Output volume, 0-100. Null when the active device doesn't report one.
  final int? volumePercent;

  /// Whether the active device will accept a volume change. Reporting a level
  /// and accepting a new one are separate capabilities on Spotify Connect.
  final bool supportsVolume;

  bool get hasTrack => track != null;

  /// True only when there is a level to show *and* a device that will act on
  /// it — the slider is hidden rather than shown dead otherwise.
  bool get canSetVolume => supportsVolume && volumePercent != null;

  MusicPlayerSnapshot copyWith({
    NowPlayingTrack? track,
    bool? isPlaying,
    bool? shuffleEnabled,
    MusicRepeatMode? repeatMode,
    String? deviceName,
    int? volumePercent,
    bool? supportsVolume,
    bool clearTrack = false,
  }) {
    return MusicPlayerSnapshot(
      service: service,
      track: clearTrack ? null : (track ?? this.track),
      isPlaying: isPlaying ?? this.isPlaying,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      repeatMode: repeatMode ?? this.repeatMode,
      deviceName: deviceName ?? this.deviceName,
      volumePercent: volumePercent ?? this.volumePercent,
      supportsVolume: supportsVolume ?? this.supportsVolume,
    );
  }
}
