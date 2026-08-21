import 'dart:async';

import 'package:flutter/services.dart';

import '../../main/domain/app_models.dart';
import '../domain/music_playback.dart';

/// Why a media-session command could not be served.
///
/// Each of these is an ordinary outcome the user can act on, not a bug: the
/// permission has not been granted yet, or nothing is playing to control.
enum MediaSessionBlock {
  /// Notification access has not been granted, so Android will not hand over
  /// the list of active sessions. Fixed by the user in system settings.
  noPermission,

  /// Permission is granted but no music app has a session open. Fixed by the
  /// user pressing play in their music app.
  noSession,

  /// The session rejected the command, or died between reading and sending.
  failed,

  /// The platform channel is not there at all — an iOS build, or a test with
  /// no mock registered. Never surfaced as an error to the user; the music UI
  /// simply stays hidden.
  unsupported,
}

extension MediaSessionBlockMessage on MediaSessionBlock {
  String get message {
    switch (this) {
      case MediaSessionBlock.noPermission:
        return 'FitSocial needs notification access to show and control your '
            'music. You can turn it on in Settings.';
      case MediaSessionBlock.noSession:
        return 'Nothing is playing. Start a song in your music app and it will '
            'show up here.';
      case MediaSessionBlock.failed:
        return 'Your music app would not take that command.';
      case MediaSessionBlock.unsupported:
        return 'Music controls are not available on this device.';
    }
  }
}

class MediaSessionException implements Exception {
  const MediaSessionException(this.block, [this.detail]);

  final MediaSessionBlock block;

  /// The platform's own words, when it gave any. Appended rather than
  /// substituted, so nothing gets swallowed.
  final String? detail;

  String get message {
    final extra = detail;
    if (extra == null || extra.isEmpty) return block.message;
    return '${block.message} ($extra)';
  }

  @override
  String toString() => message;
}

/// What the phone is playing, plus whether we are allowed to look.
///
/// The two travel together because the UI has to tell them apart: no snapshot
/// *because permission is missing* asks the user for something, while no
/// snapshot *with permission granted* just means nothing is playing and should
/// say nothing at all.
class MediaSessionState {
  const MediaSessionState({required this.hasPermission, this.snapshot});

  static const denied = MediaSessionState(hasPermission: false);
  static const idle = MediaSessionState(hasPermission: true);

  final bool hasPermission;
  final MusicPlayerSnapshot? snapshot;

  bool get hasTrack => snapshot?.track != null;
}

/// Playback control through Android's media session, with no account attached.
///
/// This drives whatever music app the user already has playing — Spotify,
/// YouTube Music, a podcast app, a local-files player — by reading the media
/// session it publishes to the system and sending transport commands back to
/// it. There is no OAuth, no client ID, no rate limit and no allowlist, which
/// is the entire reason it exists: every one of those is a per-user gate, and
/// this has to work for every user who installs the app.
///
/// The trade is that it is a remote control, not a player. It can pause, skip
/// and seek what is playing; it cannot start a particular song, because
/// Android only exposes sessions that some other app has already opened. The
/// music library UI has nothing to feed it.
///
/// Android only. On any other platform every method reports
/// [MediaSessionBlock.unsupported] and [states] stays empty, so callers get a
/// quiet no rather than a crash.
class MediaSessionService {
  MediaSessionService({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _method = methodChannel ?? const MethodChannel(_methodChannelName),
        _events = eventChannel ?? const EventChannel(_eventChannelName);

  static const _methodChannelName = 'com.fitsocial.fitsocial_app/media_session';
  static const _eventChannelName =
      'com.fitsocial.fitsocial_app/media_session/events';

  final MethodChannel _method;
  final EventChannel _events;

  /// Cover art for the track currently playing.
  ///
  /// The native side sends bytes only when the track changes — artwork is
  /// hundreds of KB and sessions emit on every seek tick, so re-sending it
  /// each time would push megabytes a second across the channel. Holding the
  /// last one here is what lets those position-only updates keep their cover.
  Uint8List? _art;

  /// The last state seen, replayed to whoever subscribes next.
  ///
  /// Sessions only emit on *change*, so a widget that starts listening while a
  /// song is already playing would otherwise sit blank until the user next
  /// pressed a button.
  MediaSessionState? _last;

  /// The one subscription to the platform channel, fanned out to everyone.
  Stream<MediaSessionState>? _upstream;

  /// Live state, mapped into the app's own model.
  ///
  /// Push-based and shared: a single subscription to the platform channel is
  /// fanned out to every listener, because opening the event channel twice
  /// leaves one of the two receiving nothing.
  ///
  /// Returns a *fresh* stream each call, wrapped around that shared broadcast.
  /// The music island and the player card both watch this at once, and the
  /// replay below has to happen per subscriber — a single cached stream would
  /// hand the second caller a stream that has already been listened to.
  Stream<MediaSessionState> states() {
    return _replaying(
      _upstream ??= _events.receiveBroadcastStream().map(_decode).handleError(
        (Object error) {
          // A dropped channel invalidates the cache — whatever was playing is
          // no longer something we can claim to know.
          _last = null;
          _art = null;
        },
        test: (error) => error is MissingPluginException,
      ).asBroadcastStream(),
    );
  }

  /// Hands the newest known state to a subscriber before the live ones.
  ///
  /// Sessions emit only on change, so a widget that starts watching while a
  /// song is already playing would otherwise sit blank until the user next
  /// pressed a button — which is precisely how a music island comes to look
  /// like it never works.
  Stream<MediaSessionState> _replaying(
    Stream<MediaSessionState> upstream,
  ) async* {
    final cached = _last;
    if (cached != null) yield cached;
    yield* upstream;
  }

  /// Re-reads the current state.
  ///
  /// Worth calling when the app returns to the foreground: the user may have
  /// granted notification access while they were away, and Android delivers no
  /// callback for that.
  Future<MediaSessionState> refresh() async {
    try {
      final raw = await _method.invokeMethod<Map<Object?, Object?>>('refresh');
      return _decode(raw);
    } on MissingPluginException {
      return MediaSessionState.denied;
    } on PlatformException {
      return MediaSessionState.denied;
    }
  }

  Future<bool> hasPermission() async {
    try {
      return await _method.invokeMethod<bool>('hasPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the system screen where notification access is granted.
  ///
  /// This permission has no runtime dialog — it can only be switched on by the
  /// user, by hand, in Settings. Returns false when the screen could not be
  /// opened at all, which some OEM builds do.
  Future<bool> openPermissionSettings() async {
    try {
      return await _method.invokeMethod<bool>('openPermissionSettings') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  // --- Transport ---

  Future<void> play() => _send('play');

  Future<void> pause() => _send('pause');

  Future<void> skipNext() => _send('skipNext');

  Future<void> skipPrevious() => _send('skipPrevious');

  Future<void> seek(Duration position) =>
      _send('seek', {'positionMs': position.inMilliseconds});

  // No setShuffle or setRepeat, deliberately.
  //
  // android.media.session.MediaController exposes neither a getter nor a
  // setter for either one — they exist only on androidx's
  // MediaControllerCompat, which would mean pulling in androidx.media and
  // rebuilding every controller through MediaSessionCompat.Token. Snapshots
  // report canSetShuffleRepeat: false so the buttons can be disabled instead.

  Future<void> setVolume(int percent) =>
      _send('setVolume', {'percent': percent.clamp(0, 100)});

  Future<void> _send(String method, [Map<String, Object?>? args]) async {
    try {
      await _method.invokeMethod<void>(method, args);
    } on MissingPluginException {
      throw const MediaSessionException(MediaSessionBlock.unsupported);
    } on PlatformException catch (e) {
      throw MediaSessionException(_blockFor(e.code), e.message);
    }
  }

  static MediaSessionBlock _blockFor(String code) {
    switch (code) {
      case 'no_permission':
        return MediaSessionBlock.noPermission;
      case 'no_session':
        return MediaSessionBlock.noSession;
      default:
        return MediaSessionBlock.failed;
    }
  }

  // --- Mapping ---

  /// The three services with their own branding, matched by package name.
  ///
  /// Everything else reports as [MusicProviderService.device]. The point is
  /// purely cosmetic — a session from the Spotify app gets Spotify's colours
  /// and mark rather than a grey note — and nothing downstream may treat a
  /// match here as an account being connected, because none is.
  static const _knownApps = <String, MusicProviderService>{
    'com.spotify.music': MusicProviderService.spotify,
    'com.google.android.apps.youtube.music': MusicProviderService.youtubeMusic,
    'com.apple.android.music': MusicProviderService.appleMusic,
  };

  MediaSessionState _decode(Object? raw) {
    if (raw is! Map) return MediaSessionState.denied;
    final map = raw.map((key, value) => MapEntry(key.toString(), value));

    final granted = map['hasPermission'] == true;
    if (!granted) {
      _art = null;
      _last = MediaSessionState.denied;
      return _last!;
    }
    if (map['hasTrack'] != true) {
      _art = null;
      _last = MediaSessionState.idle;
      return _last!;
    }

    // Absent bytes mean "unchanged" rather than "no artwork" — the flag is
    // what tells the two apart, and without honouring it every position tick
    // would blank the cover.
    if (map['albumArtChanged'] == true) {
      final bytes = map['albumArt'];
      _art = bytes is Uint8List ? bytes : null;
    }

    final package = (map['appPackage'] ?? '').toString();
    final title = (map['title'] ?? '').toString();
    final artist = (map['artist'] ?? '').toString();

    final snapshot = MusicPlayerSnapshot(
      service: _knownApps[package] ?? MusicProviderService.device,
      sourceAppName: (map['appName'] ?? '').toString().isEmpty
          ? null
          : map['appName'].toString(),
      track: NowPlayingTrack(
        // A media session publishes no stable id, so the track has no URI to
        // carry. Anything that needs to name this song across devices — a
        // Pulse sticker, say — has only the title and artist to go on.
        title: title,
        artist: artist,
        duration: _millis(map['durationMs']),
        position: _millis(map['positionMs']),
        albumArtBytes: _art,
      ),
      isPlaying: map['isPlaying'] == true,
      // Always the resting values: the platform has no way to tell us
      // otherwise, so reporting anything else would be invention.
      shuffleEnabled: false,
      repeatMode: MusicRepeatMode.off,
      canSetShuffleRepeat: false,
      deviceName: 'This phone',
      volumePercent:
          map['volumePercent'] is int ? map['volumePercent'] as int : null,
      supportsVolume: map['supportsVolume'] == true,
      // Absent keys default to allowed, matching the field defaults: a session
      // that publishes no action mask is far more likely to be terse than to
      // genuinely refuse every button.
      canSkipNext: map['canSkipNext'] != false,
      canSkipPrevious: map['canSkipPrevious'] != false,
      canSeek: map['canSeek'] != false,
    );

    _last = MediaSessionState(hasPermission: true, snapshot: snapshot);
    return _last!;
  }

  static Duration _millis(Object? value) {
    if (value is int) return Duration(milliseconds: value < 0 ? 0 : value);
    if (value is num) return Duration(milliseconds: value.toInt().abs());
    return Duration.zero;
  }
}
