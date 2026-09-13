import '../../main/domain/app_models.dart';

/// The track someone was listening to, snapshotted onto their Pulse.
///
/// A snapshot rather than a pointer, for the same reason `SharedPostRef` is
/// one: the sticker is drawn on every frame of playback, and the people
/// watching may not have the sharer's music service connected at all. What was
/// playing is a fact about the moment the Pulse was made — it does not change
/// when the sharer skips to the next song.
class PulseMusic {
  const PulseMusic({
    required this.provider,
    required this.title,
    required this.artist,
    this.trackUri,
    this.albumArtUrl,
  });

  /// Null when the stored map has no title — a sticker that cannot name the
  /// song has nothing to say, and is better not drawn.
  static PulseMusic? fromMap(Object? value) {
    if (value is! Map) return null;

    final title = (value['title'] ?? '').toString().trim();
    if (title.isEmpty) return null;

    final providerName = (value['provider'] ?? '').toString();
    final provider = MusicProviderService.values
        .where((service) => service.name == providerName)
        .firstOrNull;

    return PulseMusic(
      // Falls back to Spotify rather than dropping the sticker: it is the only
      // service this app plays from, so an unreadable provider on a stored
      // track is far more likely to be a typo than a real fourth service.
      provider: provider ?? MusicProviderService.spotify,
      title: title,
      artist: (value['artist'] ?? '').toString().trim(),
      trackUri: _trimmedOrNull(value['trackUri']),
      albumArtUrl: _trimmedOrNull(value['albumArtUrl']),
    );
  }

  static String? _trimmedOrNull(Object? value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }

  final MusicProviderService provider;
  final String title;
  final String artist;

  /// `spotify:track:…`, when the transport reported one. Without it the
  /// sticker still names the song but cannot start it.
  final String? trackUri;

  /// An https cover-art URL.
  ///
  /// Only ever a URL some catalogue already hosts. Both the App Remote and the
  /// phone's media session report cover art as raw bytes, which no viewer's
  /// device can fetch — rather than re-hosting label artwork on our own
  /// Storage, the share screen looks a URL up by track id or by name, and a
  /// Pulse it finds nothing for simply draws the placeholder.
  final String? albumArtUrl;

  /// The same track with cover art attached, once a URL has been found for it.
  PulseMusic withAlbumArt(String url) => PulseMusic(
        provider: provider,
        title: title,
        artist: artist,
        trackUri: trackUri,
        albumArtUrl: url,
      );

  /// Whether a viewer could play this from their own account.
  bool get isPlayable =>
      trackUri != null && provider == MusicProviderService.spotify;

  /// "Artist · Spotify", dropping the artist when it is unknown.
  String get subtitle {
    final parts = <String>[
      if (artist.isNotEmpty) artist,
      provider.label,
    ];
    return parts.join(' · ');
  }

  Map<String, dynamic> toMap() => {
        'provider': provider.name,
        'title': title,
        'artist': artist,
        if (trackUri != null) 'trackUri': trackUri,
        if (albumArtUrl != null) 'albumArtUrl': albumArtUrl,
      };
}
